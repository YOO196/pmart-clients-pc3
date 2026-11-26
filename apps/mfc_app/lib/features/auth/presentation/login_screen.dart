import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../data/auth_repository.dart' show TemporaryPasswordLogin;
import '../domain/employee_auth.dart';
import 'auth_controller.dart';

String loginErrorText(AppLocalizations l10n, LoginError e) => switch (e) {
  LoginError.notRegistered => l10n.loginErrorNotRegistered,
  LoginError.accountNotAvailable => l10n.loginErrorAccountNotAvailable,
  LoginError.cancelled => l10n.loginErrorCancelled,
  LoginError.temporary => l10n.loginErrorTemporary,
  LoginError.ticketInvalid => l10n.loginErrorTicketInvalid,
  LoginError.network => l10n.loginErrorNetwork,
  LoginError.badCredentials => l10n.loginErrorBadCredentials,
  LoginError.unknown => l10n.loginErrorUnknown,
};

/// 직원 로그인. 버튼 하나 — 아이디·비밀번호는 Keycloak 화면(Custom Tab)에서 넣는다. 앱은 비밀번호를 받지 않는다.
/// 목 앱도 같은 화면이다(사용자 2026-11-17 "목 앱도 실서버 앱처럼 똑같이") — 버튼을 누르면 Keycloak 화면 자리에
/// 앱 안 시험용 로그인 화면([MockSignInPage])이 열린다.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _busy = false;
  LoginError? _error;

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (ref.read(authRepositoryProvider) is TemporaryPasswordLogin) {
        final done = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const MockSignInPage(),
          ),
        );
        // 실서버에서 Custom Tab 을 닫은 것과 같다.
        if (done != true) throw const LoginFailure(LoginError.cancelled);
      } else {
        await ref.read(authControllerProvider.notifier).login();
      }
      // 성공하면 라우터가 메인으로 보낸다.
    } on LoginFailure catch (e) {
      if (mounted) setState(() => _error = e.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider);
    final ended = auth is AuthSignedOut ? auth.ended : null;
    final scheme = theme.colorScheme;
    // 배치는 다른 앱의 로그인을 따랐다: 고객앱(큰 브랜드 이름 + 한 줄 설명 + 버튼), 백오피스 직원 로그인(카드 안에 버튼·안내·참고 문구).
    return Scaffold(
      resizeToAvoidBottomInset: false,
      // 기기 설정에서 왔으면 뒤로, 세션이 끝나 바로 왔으면 기기 설정으로 가는 버튼.
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: context.canPop()
            ? const BackButton()
            : IconButton(
                key: const ValueKey('login-setup'),
                tooltip: l10n.setupBack,
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => context.go('/setup'),
              ),
      ),
      // 화면 위쪽 = 앱 로고·이름·한 줄 설명, 아래쪽 = 큰 로그인 단추(엄지가 닿는 자리)와 짧은 안내.
      // 예전엔 창고 아이콘 + 카드 안 버튼 + 긴 문장(두세 줄)이라 허술해 보였다(사용자 2026-11-20). 로그인 동작은 그대로.
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // 폰·PDA 폭에서는 꽉 차고, 태블릿·브라우저에서는 늘어지지 않는다.
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 앱 아이콘과 같은 로고(tool/icon/pick_pda_icon.png 에서 만든 assets/images/pick_pda_logo.png).
                        ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Image.asset(
                            'assets/images/pick_pda_logo.png',
                            key: const ValueKey('login-logo'),
                            width: 112,
                            height: 112,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          l10n.homeTitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.loginSubtitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 세션이 끝나서 나온 경우의 안내(지금 누른 로그인의 오류가 있으면 그것을 먼저 보인다)
                  if (ended != null && _error == null)
                    _Notice(
                      key: const ValueKey('session-ended'),
                      text: switch (ended) {
                        SessionEnd.accountBlocked => l10n.sessionEndedBlocked,
                        SessionEnd.expired => l10n.sessionEndedExpired,
                      },
                    ),
                  if (_error != null)
                    _Notice(
                      key: const ValueKey('login-error'),
                      text: loginErrorText(l10n, _error!),
                      error: true,
                    ),
                  // 장갑을 끼고도 누를 수 있게 크게.
                  FilledButton.icon(
                    key: const ValueKey('employee-login'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(60),
                    ),
                    onPressed: _busy ? null : _login,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login, size: 24),
                    label: Text(
                      _busy ? l10n.loginInProgress : l10n.loginButton,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.loginNote,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 목 앱 전용 — 실서버의 Keycloak 로그인 화면(Custom Tab) 자리에 여는 시험용 로그인 화면.
/// 계약에 없는 임시 화면이라 서버로 보내는 것이 없다. 비밀번호는 이 칸에만 있고 로그·오류 문구에 남기지 않는다.
/// 성공하면 `true` 로 닫힌다. 아이디·비밀번호가 틀리면 Keycloak 처럼 이 화면에서 알리고 머문다.
class MockSignInPage extends ConsumerStatefulWidget {
  const MockSignInPage({super.key});

  @override
  ConsumerState<MockSignInPage> createState() => _MockSignInPageState();
}

class _MockSignInPageState extends ConsumerState<MockSignInPage> {
  final _loginId = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _busy = false;
  bool _bad = false;

  @override
  void dispose() {
    _loginId.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _ready =>
      _loginId.text.trim().isNotEmpty && _password.text.isNotEmpty;

  Future<void> _submit() async {
    if (!_ready || _busy) return;
    setState(() {
      _busy = true;
      _bad = false;
    });
    var closing = false;
    try {
      await ref
          .read(authControllerProvider.notifier)
          .loginWithPassword(
            loginId: _loginId.text.trim().toLowerCase(),
            password: _password.text,
          );
      // 키보드를 먼저 내리고 닫는다 — 열린 채 닫으면 다음 화면(메인)의 아래 줄이 키보드 높이만큼 떴다가 내려앉았다.
      // 비밀번호는 닫히는 화면에서 지우지 않는다(지우면 닫히는 동안 "빈 칸·로그인 꺼짐"이 실패처럼 비쳤다,
      // 에뮬레이터 확인 2026-11-20). 화면이 닫히면 입력칸째 사라진다.
      if (mounted) {
        closing = true;
        FocusScope.of(context).unfocus();
        Navigator.of(context).pop(true);
      }
    } on LoginFailure {
      if (mounted) {
        _password.clear();
        setState(() => _bad = true);
      }
    } finally {
      if (mounted && !closing) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('mock-signin-close'),
          tooltip: l10n.cancel,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: Text(l10n.loginTitle),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (_bad)
              _Notice(
                key: const ValueKey('login-error'),
                text: l10n.loginErrorBadCredentials,
                error: true,
              ),
            TextField(
              key: const ValueKey('login-id'),
              controller: _loginId,
              enabled: !_busy,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              // 갤럭시 키보드가 첫 글자를 대문자로 바꾸지 않게 — 영문·숫자 키보드(사용자 2026-11-26 "시험 계정 안 돌아가는데")
              keyboardType: TextInputType.visiblePassword,
              textCapitalization: TextCapitalization.none,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
              maxLength: 64,
              decoration: InputDecoration(
                labelText: l10n.loginIdLabel,
                hintText: l10n.loginIdHint,
                prefixIcon: const Icon(Icons.badge_outlined),
                border: const OutlineInputBorder(),
                counterText: '',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('login-password'),
              controller: _password,
              enabled: !_busy,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              maxLength: 128,
              decoration: InputDecoration(
                labelText: l10n.loginPasswordLabel,
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                counterText: '',
                suffixIcon: IconButton(
                  key: const ValueKey('login-password-toggle'),
                  tooltip: _showPassword
                      ? l10n.loginPasswordHide
                      : l10n.loginPasswordShow,
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('mock-signin-submit'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(60),
                textStyle: theme.textTheme.titleMedium,
              ),
              onPressed: _busy || !_ready ? null : _submit,
              child: Text(l10n.loginSubmit),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.loginTemporaryNote,
              key: const ValueKey('login-temporary-note'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.text, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: error ? scheme.errorContainer : scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            text,
            style: TextStyle(
              color: error
                  ? scheme.onErrorContainer
                  : scheme.onSecondaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}

/// 앱을 켠 직후 세션을 되살리는 동안.
class StartingScreen extends StatelessWidget {
  const StartingScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    resizeToAvoidBottomInset: false,
    body: Center(child: CircularProgressIndicator()),
  );
}
