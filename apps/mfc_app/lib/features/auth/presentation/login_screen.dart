import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers.dart';
import '../domain/employee_auth.dart';
import 'auth_controller.dart';

String loginErrorText(AppLocalizations l10n, LoginError e) => switch (e) {
  LoginError.notRegistered => l10n.loginErrorNotRegistered,
  LoginError.accountNotAvailable => l10n.loginErrorAccountNotAvailable,
  LoginError.cancelled => l10n.loginErrorCancelled,
  LoginError.temporary => l10n.loginErrorTemporary,
  LoginError.ticketInvalid => l10n.loginErrorTicketInvalid,
  LoginError.network => l10n.loginErrorNetwork,
  LoginError.unknown => l10n.loginErrorUnknown,
};

/// 직원 로그인. 버튼 하나 — 아이디·비밀번호는 Keycloak 화면(Custom Tab)에서 넣는다. 앱은 비밀번호를 받지 않는다.
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
      await ref.read(authControllerProvider.notifier).login();
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
    final mock = ref.watch(envProvider) == PmartEnv.mock;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeTitle),
        actions: [
          if (mock)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(label: Text(l10n.mockModeBadge)),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text(
                l10n.loginTitle,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // 세션이 끝나서 나온 경우의 안내(지금 누른 로그인의 오류가 있으면 그것을 먼저 보인다)
              if (ended != null && _error == null)
                _Notice(
                  key: const ValueKey('session-ended'),
                  text: ended == SessionEnd.accountBlocked
                      ? l10n.sessionEndedBlocked
                      : l10n.sessionEndedExpired,
                ),
              if (_error != null)
                _Notice(
                  key: const ValueKey('login-error'),
                  text: loginErrorText(l10n, _error!),
                  error: true,
                ),
              FilledButton.icon(
                key: const ValueKey('employee-login'),
                onPressed: _busy ? null : _login,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(_busy ? l10n.loginInProgress : l10n.loginButton),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.loginNote,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 2),
            ],
          ),
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
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
