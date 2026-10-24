import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart';
import '../data/auth_repository.dart';
import '../data/mock_auth_repository.dart';
import '../domain/auth.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockAuthRepository(),
    PmartEnv.local => ApiAuthRepository(
      ref.watch(dioProvider),
      ref.watch(deviceIdProvider),
    ),
  },
);

final socialTokenSourceProvider = Provider<SocialTokenSource>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockSocialTokenSource(),
    // 실제 제공자 SDK 는 앱 키 결정 뒤 붙인다. 그 전까지 local 도 목 제공자를 쓴다.
    PmartEnv.local => MockSocialTokenSource(),
  },
);

/// 결과 불명 로그인의 같은 키 재전송 횟수.
final loginResolveAttemptsProvider = Provider<int>((_) => 2);

/// 앱의 로그인 상태. 시작은 비회원이다(저장된 세션 복원은 `GET /auth/sessions/current` 로 붙인다).
final sessionProvider = NotifierProvider<SessionController, Session>(
  SessionController.new,
);

class SessionController extends Notifier<Session> {
  @override
  Session build() => const GuestSession();

  Future<void> signIn(LoginMember member) async {
    await ref.read(tokenStoreProvider).save(member.tokens);
    state = MemberSession(member.accountId);
  }

  Future<void> signOut() async {
    await ref.read(tokenStoreProvider).clear();
    state = const GuestSession();
  }
}

/// 로그인 화면의 진행 상태.
@immutable
sealed class LoginFlow {
  const LoginFlow();
}

final class LoginIdle extends LoginFlow {
  const LoginIdle();
}

final class LoginWorking extends LoginFlow {
  const LoginWorking(this.provider);

  final SocialProvider provider;
}

/// 직전 시도의 결과(동의 대기·제한·불명·실패·취소·완료).
final class LoginSettled extends LoginFlow {
  const LoginSettled(this.outcome);

  final LoginOutcome outcome;
}

final loginFlowProvider = NotifierProvider.autoDispose
    .family<LoginFlowController, LoginFlow, LoginPurpose>(
      LoginFlowController.new,
    );

class LoginFlowController extends Notifier<LoginFlow> {
  LoginFlowController(this.purpose);

  final LoginPurpose purpose;

  /// 결과 불명인 로그인의 키·제공자·제공자 토큰. 다시 확인은 같은 키로 재전송한다.
  ({IdempotencyKey key, SocialProvider provider, String token})? _unknown;

  @override
  LoginFlow build() => const LoginIdle();

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  bool get busy => state is LoginWorking;

  Future<void> start(SocialProvider provider) async {
    if (busy) return;
    state = LoginWorking(provider);
    final String? token;
    try {
      token = await ref.read(socialTokenSourceProvider).obtain(provider);
    } on SocialProviderDown {
      return _settle(const LoginProviderUnavailable());
    }
    if (!ref.mounted) return;
    if (token == null) return _settle(const LoginCancelled());
    final key = IdempotencyKey.generate();
    final outcome = await _repo.login(
      provider,
      token,
      purpose: purpose,
      key: key,
    );
    if (!ref.mounted) return;
    if (outcome is LoginUnknown) {
      _unknown = (key: key, provider: provider, token: token);
      return _resolve(
        outcome,
        attempts: ref.read(loginResolveAttemptsProvider),
      );
    }
    await _settle(outcome);
  }

  /// "다시 확인". 같은 키로만 재전송한다(새 로그인 시도가 아니다).
  Future<void> checkAgain() async {
    final unknown = _unknown;
    if (unknown == null || busy) return;
    state = LoginWorking(unknown.provider);
    await _resolve(const LoginUnknown(), attempts: 1);
  }

  Future<void> _resolve(LoginUnknown first, {required int attempts}) async {
    final unknown = _unknown!;
    LoginOutcome outcome = first;
    for (var i = 0; i < attempts && outcome is LoginUnknown; i++) {
      final id = outcome.authRequestId;
      outcome = id != null
          ? await _repo.lookup(id)
          : await _repo.login(
              unknown.provider,
              unknown.token,
              purpose: purpose,
              key: unknown.key,
            );
      if (!ref.mounted) return;
    }
    if (outcome is! LoginUnknown) _unknown = null;
    await _settle(outcome);
  }

  Future<void> submitConsents(
    String authRequestId,
    List<String> consents,
  ) async {
    if (busy) return;
    final previous = state;
    state = LoginWorking(
      previous is LoginWorking ? previous.provider : SocialProvider.naver,
    );
    final outcome = await _repo.completeWithConsents(
      authRequestId,
      consents,
      key: IdempotencyKey.generate(),
    );
    if (!ref.mounted) return;
    // 동의가 거절되면 동의 화면을 유지한다.
    if (outcome is LoginRejected && previous is LoginSettled) {
      state = previous;
      return;
    }
    await _settle(outcome);
  }

  Future<void> _settle(LoginOutcome outcome) async {
    if (outcome is LoginMember) {
      await ref.read(sessionProvider.notifier).signIn(outcome);
    }
    if (ref.mounted) state = LoginSettled(outcome);
  }
}
