import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart';
import '../data/auth_repository.dart';
import '../data/google_token_source.dart';
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
    // 실서버는 Google 만 지원한다(ADR-0019). 카카오·네이버 SDK 는 서버 지원 뒤 붙인다.
    PmartEnv.local => GoogleSocialTokenSource(),
  },
);

/// 로그인 화면에 보일 제공자. 실서버는 지원하는 제공자만(나머지는 501 이라 버튼을 숨긴다).
final loginProvidersProvider = Provider<List<SocialProvider>>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => loginProviders,
    PmartEnv.local => serverLoginProviders,
  },
);

/// 결과 불명 로그인의 같은 키 재전송 횟수.
final loginResolveAttemptsProvider = Provider<int>((_) => 2);

/// 앱 시작 때 한 번: 저장된 refresh token 이 있으면 세션을 되살린다. 실패하면 비회원으로 둔다.
final sessionRestoreProvider = FutureProvider<void>(
  (ref) => ref.read(sessionProvider.notifier).restore(),
);

/// 앱의 로그인 상태. 시작은 비회원이고, [sessionRestoreProvider] 가 저장된 세션을 확인한다.
final sessionProvider = NotifierProvider<SessionController, Session>(
  SessionController.new,
);

class SessionController extends Notifier<Session> {
  @override
  Session build() => const GuestSession();

  Future<void> signIn(
    LoginMember member, {
    SocialProvider? provider,
    String? accountLabel,
  }) async {
    await ref.read(tokenStoreProvider).save(member.tokens);
    state = MemberSession(
      member.accountId,
      provider: provider,
      accountLabel: accountLabel,
    );
  }

  /// 저장된 refresh token 이 있을 때만 서버에 세션을 묻는다(`GET /auth/sessions/current`).
  /// 서버가 확인한 계정만 회원으로 보인다. 그 사이 직접 로그인했으면 덮지 않는다.
  Future<void> restore() async {
    final tokens = ref.read(tokenStoreProvider);
    if (await tokens.readRefreshToken() == null) return;
    final accountId = await ref.read(authRepositoryProvider).currentAccountId();
    if (!ref.mounted || accountId == null || state is MemberSession) return;
    state = MemberSession(accountId);
  }

  Future<void> signOut() async {
    await ref.read(tokenStoreProvider).clear();
    final source = ref.read(socialTokenSourceProvider);
    if (source is GoogleSocialTokenSource) {
      try {
        await source.signOut();
      } on Object {
        // Google 쪽 선택 해제 실패는 앱 로그아웃을 막지 않는다.
      }
    }
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

  /// 결과 불명인 로그인의 키·제공자·제공자 자격. 다시 확인은 같은 키로 재전송한다.
  ({IdempotencyKey key, SocialProvider provider, SocialCredential credential})?
  _unknown;

  /// 이번 로그인 시도의 제공자·계정 표시(회원이 되면 세션에 붙인다).
  ({SocialProvider provider, String? label})? _who;

  @override
  LoginFlow build() => const LoginIdle();

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  bool get busy => state is LoginWorking;

  Future<void> start(SocialProvider provider) async {
    if (busy) return;
    state = LoginWorking(provider);
    final SocialCredential? credential;
    try {
      credential = await ref.read(socialTokenSourceProvider).obtain(provider);
    } on SocialProviderDown {
      return _settle(const LoginProviderUnavailable());
    } on SocialProviderMisconfigured {
      return _settle(
        const LoginRejected(AuthProblemCode.providerConfiguration),
      );
    }
    if (!ref.mounted) return;
    if (credential == null) return _settle(const LoginCancelled());
    _who = (provider: provider, label: credential.accountLabel);
    final key = IdempotencyKey.generate();
    final outcome = await _repo.login(
      provider,
      credential.token,
      purpose: purpose,
      key: key,
    );
    if (!ref.mounted) return;
    if (outcome is LoginUnknown) {
      _unknown = (key: key, provider: provider, credential: credential);
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
              unknown.credential.token,
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
      await ref
          .read(sessionProvider.notifier)
          .signIn(outcome, provider: _who?.provider, accountLabel: _who?.label);
    }
    if (ref.mounted) state = LoginSettled(outcome);
  }
}
