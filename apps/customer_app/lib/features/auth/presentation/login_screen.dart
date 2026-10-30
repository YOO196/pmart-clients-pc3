import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../data/auth_repository.dart' show consentTypeOf;
import '../domain/auth.dart';

import 'package:pmart_core/pmart_core.dart' show PmartEnv;

import '../../../shared/providers.dart' show envProvider;
import 'auth_controller.dart';

/// SCR-AUTH-001·CONSENT-001. 로그인되면 `true` 로 돌아간다. 취소·실패는 원래 화면을 그대로 둔다.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.purpose = LoginPurpose.general});

  final LoginPurpose purpose;

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

  String _consentLabel(AppLocalizations l10n, String item) =>
      switch (consentTypeOf(item)) {
        'TERMS_OF_SERVICE' => l10n.consentTerms,
        'PRIVACY_POLICY' => l10n.consentPrivacy,
        'AGE_OVER_14' => l10n.consentAge14,
        _ => item,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = loginFlowProvider(widget.purpose);
    final flow = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    ref.listen(provider, (_, next) {
      if (next case LoginSettled(outcome: LoginMember())) {
        if (context.canPop()) context.pop(true);
      }
      if (next case LoginSettled(outcome: LoginCancelled())) {
        // 고객 취소는 오류가 아니다. 원래 화면으로 돌아간다.
        if (context.canPop()) context.pop(false);
      }
    });

    final busy = flow is LoginWorking;
    final workingProvider = flow is LoginWorking ? flow.provider : null;
    final outcome = switch (flow) {
      LoginSettled(:final outcome) => outcome,
      _ => null,
    };

    if (outcome case LoginNeedsConsent(
      :final authRequestId,
      :final requiredConsents,
    )) {
      final allAgreed = requiredConsents.every(_agreed.contains);
      return Scaffold(
        appBar: AppBar(title: Text(l10n.consentTitle)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l10n.consentBody),
            for (final c in requiredConsents)
              CheckboxListTile(
                key: ValueKey('consent-$c'),
                value: _agreed.contains(c),
                title: Text(l10n.consentRequired(_consentLabel(l10n, c))),
                onChanged: busy
                    ? null
                    : (v) => setState(
                        () => (v ?? false) ? _agreed.add(c) : _agreed.remove(c),
                      ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('consent-submit'),
              onPressed: (allAgreed && !busy)
                  ? () => controller.submitConsents(
                      authRequestId,
                      requiredConsents,
                    )
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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.loginTitle)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            widget.purpose == LoginPurpose.checkout
                ? l10n.loginForCheckout
                : l10n.loginBody,
          ),
          if (ref.watch(envProvider) == PmartEnv.mock) ...[
            const SizedBox(height: 8),
            Text(
              l10n.loginMockNotice,
              key: const ValueKey('login-mock-notice'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 24),
          if (message != null) ...[
            Text(
              message,
              key: const ValueKey('login-message'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
            for (final p in ref.watch(loginProvidersProvider))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.tonal(
                  key: ValueKey('login-${p.name}'),
                  // 제한 중에는 다시 누를 수 없다(남은 시간은 서버 값).
                  onPressed: (busy || outcome is LoginRestricted)
                      ? null
                      : () => controller.start(p),
                  child: workingProvider == p
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_providerLabel(l10n, p)),
                ),
              ),
        ],
      ),
    );
  }
}
