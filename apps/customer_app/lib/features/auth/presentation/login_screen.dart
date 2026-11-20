import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart'
    show PmartLineIcon, PmartLineIcons, keepWords;

import '../../../l10n/gen/app_localizations.dart';
import '../data/auth_repository.dart' show consentTypeOf;
import '../domain/auth.dart';

import 'package:pmart_core/pmart_core.dart' show PmartEnv, ProblemCode;

import '../../../shared/providers.dart' show envProvider;
import '../../start/presentation/start_controller.dart'
    show leaveApp, startFlagsProvider;
import 'auth_controller.dart';
import 'identity_view.dart';

/// SCR-AUTH-001·CONSENT-001. 로그인되면 `true` 로 돌아간다. 취소·실패는 원래 화면을 그대로 둔다.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
    super.key,
    this.purpose = LoginPurpose.general,
    this.entry = false,
  });

  final LoginPurpose purpose;

  /// 처음 실행 단계(레퍼런스 2-3 "로그인 필요(둘러보기 = 비회원)"). 뒤로 가기 대신 아래 "둘러보기".
  final bool entry;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _agreed = <String>{};

  String _providerLabel(AppLocalizations l10n, SocialProvider p) => switch (p) {
    SocialProvider.kakao => l10n.loginKakao,
    SocialProvider.naver => l10n.loginNaver,
    SocialProvider.apple => l10n.loginApple,
    SocialProvider.google => l10n.loginGoogle,
  };

  String _providerShort(AppLocalizations l10n, SocialProvider p) => switch (p) {
    SocialProvider.kakao => l10n.loginKakaoShort,
    SocialProvider.naver => l10n.loginNaverShort,
    SocialProvider.apple => l10n.loginAppleShort,
    SocialProvider.google => l10n.loginGoogleShort,
  };

  String _consentLabel(AppLocalizations l10n, String item) =>
      switch (consentTypeOf(item)) {
        'TERMS_OF_SERVICE' => l10n.consentTerms,
        'PRIVACY_POLICY' => l10n.consentPrivacy,
        'AGE_OVER_14' => l10n.consentAge14,
        'MARKETING' => l10n.consentMarketing,
        // 모르는 항목은 서버 코드 그대로(지어내지 않는다)
        _ => consentTypeOf(item),
      };

  /// 이 동의 대기에 대해 고객이 고른 선택 항목(기본 해제). 동의 대기가 바뀌면 비운다.
  String? _consentFor;

  /// 새로 가입한 계정은 내 정보(이름·휴대폰 번호)부터 받는다(소셜 로그인이 번호를 주지 않음). 끝나면 원래 화면으로.
  Future<void> _afterLogin({required bool newAccount}) async {
    if (widget.entry) {
      await ref.read(startFlagsProvider.notifier).completeEntry();
      if (!mounted) return;
    }
    if (newAccount) await context.push<bool>('/me/info?from=signup');
    if (!mounted) return;
    if (widget.entry) {
      // 처음 실행 단계: 다음 단계(주소 또는 홈)는 라우터가 정한다.
      context.go('/');
      return;
    }
    if (context.canPop()) context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = loginFlowProvider(widget.purpose);
    final flow = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    ref.listen(provider, (_, next) {
      if (next case LoginSettled(outcome: LoginMember(:final newAccount))) {
        _afterLogin(newAccount: newAccount);
      }
      if (next case LoginSettled(outcome: LoginCancelled())) {
        // 고객 취소는 오류가 아니다. 원래 화면으로 돌아간다(처음 실행 단계는 이 화면에 남는다).
        if (!widget.entry && context.canPop()) context.pop(false);
      }
    });

    final busy = flow is LoginWorking;
    final workingProvider = flow is LoginWorking ? flow.provider : null;
    final outcome = switch (flow) {
      LoginSettled(:final outcome) => outcome,
      _ => null,
    };

    // 휴대폰 확인(AUTH_IDENTITY — auth 0.6.0, BR-64 회신): 동의 다음, 회원 전 단계.
    if (outcome case final LoginNeedsIdentity waiting) {
      return IdentityView(
        waiting: waiting,
        purpose: widget.purpose,
        providerLabel: (p) => _providerShort(l10n, p),
        onClose: () {
          if (context.canPop()) {
            context.pop(false);
          } else {
            ref.invalidate(provider);
          }
        },
      );
    }

    if (outcome case final LoginNeedsConsent waiting) {
      if (_consentFor != waiting.authRequestId) {
        _consentFor = waiting.authRequestId;
        _agreed.clear();
      }
      final allAgreed = waiting.requiredConsents.every(_agreed.contains);
      Widget box(String c, String title) => CheckboxListTile(
        key: ValueKey('consent-$c'),
        value: _agreed.contains(c),
        title: Text(title),
        onChanged: busy
            ? null
            : (v) => setState(
                () => (v ?? false) ? _agreed.add(c) : _agreed.remove(c),
              ),
      );
      final error = switch (waiting.lastError) {
        null => null,
        AuthProblemCode.requiredConsentMissing => l10n.consentMissing,
        ProblemCode.unknownResult => l10n.consentUnknown,
        _ => l10n.loginRejected,
      };
      return Scaffold(
        appBar: AppBar(title: Text(l10n.consentTitle)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 기존 회원(newAccount=false)은 약관이 바뀌어 다시 묻는 것이다.
            Text(
              waiting.newAccount ? l10n.consentBody : l10n.consentReconsentBody,
              key: const ValueKey('consent-body'),
            ),
            for (final c in waiting.requiredConsents)
              box(c, l10n.consentRequired(_consentLabel(l10n, c))),
            for (final c in waiting.optionalConsents)
              box(c, l10n.consentOptional(_consentLabel(l10n, c))),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error,
                key: const ValueKey('consent-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('consent-submit'),
              onPressed: (allAgreed && !busy)
                  ? () => controller.submitConsents(waiting, [
                      for (final c in waiting.requiredConsents)
                        ConsentDecision(c, agreed: true),
                      // 선택 항목은 끈 것도 false 로 보낸다(거부로 기록돼 다시 묻지 않는다)
                      for (final c in waiting.optionalConsents)
                        ConsentDecision(c, agreed: _agreed.contains(c)),
                    ])
                  : null,
              child: Text(l10n.consentSubmit),
            ),
          ],
        ),
      );
    }

    final message = switch (outcome) {
      LoginRestricted(:final retryAfterSeconds) => switch (retryAfterSeconds) {
        final int s => l10n.loginRestrictedFor((s / 60).ceil()),
        null => l10n.loginRestricted,
      },
      LoginProviderUnavailable() => l10n.loginProviderDown,
      LoginRejected(:final code) => switch (code) {
        AuthProblemCode.providerRejected => l10n.loginProviderRejected,
        // 동의 완료가 막혔다(다른 기기·계정, 이미 끝남, 그 사이 약관 버전이 바뀜) — 처음부터
        AuthProblemCode.forbidden ||
        AuthProblemCode.invalidState ||
        AuthProblemCode.consentVersionOutdated => l10n.loginConsentRestart,
        AuthProblemCode.accountNotAvailable ||
        AuthProblemCode.accountNotPurchasable => l10n.loginAccountUnavailable,
        AuthProblemCode.configRequired ||
        AuthProblemCode.providerConfiguration => l10n.loginConfigRequired,
        AuthProblemCode.unsupported => l10n.loginUnsupported,
        _ => l10n.loginRejected,
      },
      LoginUnknown() => l10n.loginUnknown,
      _ => null,
    };
    final theme = Theme.of(context);
    // 레퍼런스 2-3: 가운데 로고, 아래 동그란 소셜 단추 가로 한 줄(지름 약 53dp + 이름), 맨 아래 회색 "둘러보기"
    Widget round(SocialProvider p) {
      final (bg, fg, glyph, border) = switch (p) {
        SocialProvider.kakao => (
          const Color(0xFFFEE500),
          const Color(0xFF191600),
          null,
          false,
        ),
        SocialProvider.naver => (
          const Color(0xFF03C75A),
          Colors.white,
          'N',
          false,
        ),
        SocialProvider.apple => (Colors.black, Colors.white, '', false),
        SocialProvider.google => (
          Colors.white,
          const Color(0xFF4285F4),
          'G',
          true,
        ),
      };
      final working = workingProvider == p;
      return Semantics(
        button: true,
        label: _providerLabel(l10n, p),
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: bg,
              shape: CircleBorder(
                side: border
                    ? BorderSide(color: theme.colorScheme.outlineVariant)
                    : BorderSide.none,
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey('login-${p.name}'),
                // 제한 중에는 다시 누를 수 없다(남은 시간은 서버 값).
                onTap: (busy || outcome is LoginRestricted)
                    ? null
                    : () => controller.start(p),
                child: SizedBox.square(
                  dimension: 53,
                  child: Center(
                    child: working
                        ? SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: fg,
                            ),
                          )
                        : glyph == null
                        // 카카오: 말풍선
                        ? CustomPaint(
                            size: const Size(24, 22),
                            painter: _BubblePainter(fg),
                          )
                        : Text(
                            glyph,
                            style: TextStyle(
                              color: fg,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _providerShort(l10n, p),
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
            ),
          ],
        ),
      );
    }

    final body = LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: ConstrainedBox(
          // 폭도 화면 전체로 — 본문이 좁으면(실기기: 목 안내 문장 없음) 왼쪽에 붙던 것(사용자 2026-11-20)
          constraints: BoxConstraints(
            minHeight: c.maxHeight,
            minWidth: c.maxWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  l10n.appTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.primary,
                  ),
                ),
                if (widget.purpose == LoginPurpose.checkout) ...[
                  const SizedBox(height: 12),
                  Text(
                    keepWords(l10n.loginForCheckout),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 64),
                if (message != null) ...[
                  Text(
                    message,
                    key: const ValueKey('login-message'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: 12),
                ],
                if (outcome is LoginUnknown)
                  OutlinedButton(
                    key: const ValueKey('login-check-again'),
                    onPressed: busy ? null : controller.checkAgain,
                    child: Text(l10n.loginCheckAgain),
                  )
                else
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final p in ref.watch(loginProvidersProvider))
                        round(p),
                    ],
                  ),
                if (widget.entry) ...[
                  const SizedBox(height: 40),
                  TextButton(
                    key: const ValueKey('login-browse'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.onSurfaceVariant,
                      textStyle: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                      ),
                    ),
                    onPressed: busy
                        ? null
                        : () => ref
                              .read(startFlagsProvider.notifier)
                              .completeEntry(),
                    child: Text(l10n.loginBrowse),
                  ),
                ],
                if (ref.watch(envProvider) == PmartEnv.mock) ...[
                  const SizedBox(height: 24),
                  Text(
                    keepWords(l10n.loginMockNotice),
                    key: const ValueKey('login-mock-notice'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (widget.entry) {
      return PopScope(
        canPop: false,
        // 처음 실행의 로그인/둘러보기 — 돌아갈 곳이 없어 뒤로는 앱을 나간다.
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) leaveApp();
        },
        child: Scaffold(
          key: const ValueKey('start-entry'),
          body: SafeArea(child: body),
        ),
      );
    }
    // 레퍼런스 2-2(우리집 추가 → 로그인): 제목 없이 왼쪽 위 ✕
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('login-close'),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const PmartLineIcon(PmartLineIcons.close, size: 24),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: body,
    );
  }
}

/// 카카오 말풍선(둥근 말풍선 + 아래 꼬리).
class _BubblePainter extends CustomPainter {
  const _BubblePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final w = size.width;
    final h = size.height;
    canvas.drawOval(Rect.fromLTWH(0, 0, w, h * 0.8), p);
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.28, h * 0.6)
        ..lineTo(w * 0.22, h)
        ..lineTo(w * 0.5, h * 0.72)
        ..close(),
      p,
    );
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.color != color;
}
