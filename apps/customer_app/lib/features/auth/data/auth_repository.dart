import 'package:dio/dio.dart';
import 'package:pmart_api_auth/pmart_api_auth.dart' as auth;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../domain/auth.dart';

/// 제공자 SDK 에서 인가 코드·ID 토큰(과 표시용 계정 이름)을 받는다. 고객이 취소하면 null.
///
/// 실제 SDK(카카오 등)는 앱 키 결정 뒤 붙인다(`[결정 필요]` 카카오 키). 토큰은 로그에 남기지 않는다.
abstract interface class SocialTokenSource {
  /// 제공자 장애면 [SocialProviderDown] 을 던진다.
  /// [withdrawal] = 회원 탈퇴·철회 재인증(auth 0.11.0 BR-74) — 네이버는 서버가 교환 뒤 앱 연결을 끊는다.
  Future<SocialCredential?> obtain(
    SocialProvider provider, {
    bool withdrawal = false,
  });

  /// 조용한 재로그인(화면 없이). 세션이 끝났을 때 먼저 시도한다(백엔드 요청 2026-11-02 세션 만료 §3-2).
  /// 못 받으면 null — 던지지 않는다.
  Future<SocialCredential?> obtainSilently(SocialProvider provider);

  /// 이 기기의 제공자 로그인 흔적을 지운다(앱 로그아웃 — 다음에 계정을 다시 고르게).
  /// [revoke] 면 제공자와의 앱 연결(정보 제공 동의)까지 끊는다 — 탈퇴가 받아들여진 뒤, 다시 가입할 때 동의 화면이 다시 뜨게
  /// (백엔드 요청 2026-11-21 request-google-revoke-on-withdrawal — 카카오·네이버는 서버가 끊고 구글만 앱이 끊는다).
  /// 실패는 던지지 않는다(로그아웃·탈퇴 흐름을 막지 않는다). 토큰·이메일을 로그에 남기지 않는다.
  Future<void> forget(SocialProvider provider, {bool revoke = false});

  /// 제공자 동의는 했지만 우리 가입(약관 동의·휴대폰 확인)을 끝내지 않고 그만뒀다 — 다음 로그인 때 제공자 동의 화면이
  /// 다시 뜨게 제공자와의 앱 연결을 끊는다(사용자 2026-11-21 "아직 동의만 하고 가입한 것도 아닌데 왜 못 물어").
  /// 앱이 끊을 수 있는 제공자만(카카오 SDK `unlink`, 구글 `disconnect`). 네이버는 앱에 토큰이 없어 서버 몫(BR-79).
  /// 실패는 던지지 않는다. 토큰을 로그에 남기지 않는다.
  Future<void> abandonSignup(SocialProvider provider);
}

final class SocialProviderDown implements Exception {
  const SocialProviderDown();
}

abstract interface class AuthRepository {
  /// `POST /auth/social-logins`. 같은 [key] 재전송은 원인증 결과를 돌려준다.
  /// [profileImageUrl] 은 네이버만(auth 0.8.0·0.10.1 — 교환 응답으로 받은 사진 주소, 서버가 `*.pstatic.net` 만 쓴다).
  /// 동의 완료·휴대폰 확인("보냈어요")에도 같은 값을 다시 보낸다(회원 정보가 넘어가는 시점이 셋).
  Future<LoginOutcome> login(
    SocialProvider provider,
    String providerToken, {
    required LoginPurpose purpose,
    required IdempotencyKey key,
    String? profileImageUrl,
  });

  /// `GET /auth/social-logins/{authRequestId}`.
  Future<LoginOutcome> lookup(String authRequestId);

  /// 네이버 인가 코드 → ID 토큰(`POST /auth/naver-token-exchanges`, auth 0.10.0 — BR-69). 서버가 client secret 으로
  /// 대신 교환한다. 같은 [key] 재전송은 처음 결과를 준다(코드를 두 번 교환하지 않음). 실패는 [PmartFailure]
  /// (401 PROVIDER_REJECTED·503 PROVIDER_UNAVAILABLE·422 CONFIG_REQUIRED). 코드·verifier·토큰은 로그 금지.
  Future<NaverExchange> exchangeNaverCode({
    required String authorizationCode,
    required String codeVerifier,
    required String redirectUri,
    required IdempotencyKey key,
    bool withdrawal = false,
  });

  /// 저장된 세션의 계정(`GET /auth/sessions/current`. 401 이면 인터셉터가 refresh 회전 후 다시 보낸다).
  /// 세션이 끝났거나 고객 세션이 아니면 null(토큰은 인터셉터가 지운다).
  /// 서버에 닿지 못했으면(연결 오류·타임아웃·결과 불명·5xx) [PmartFailure] 를 던진다 — 세션이 끝난 게 아니다.
  Future<String?> currentAccountId();

  /// 동의 대기(AUTH_CONSENT)를 끝낸다 — `POST /auth/social-logins/{id}/completions`(auth 0.2.0, CU-1).
  /// 토큰이 없는 단계라 [providerToken](로그인한 그 계정의 ID 토큰)으로 서버가 본인을 다시 확인한다.
  /// [consents] 는 필수(모두 동의)와 선택(고객이 고른 값 — 끈 것도 false)을 모두 담는다.
  /// 같은 [key] 재전송(응답 유실)은 새 토큰을 준다.
  Future<LoginOutcome> completeWithConsents(
    String authRequestId, {
    required String providerToken,
    required List<ConsentDecision> consents,
    required IdempotencyKey key,
    String? profileImageUrl,
  });

  /// 휴대폰 확인 시작(auth 0.6.0) — `POST /auth/social-logins/{id}/identity-verifications`.
  /// 실패는 [PmartFailure](400 PHONE_NOT_SUPPORTED·429 TOO_MANY_VERIFICATIONS·403 등).
  Future<IdentityStart> startIdentity(
    String authRequestId, {
    required String providerToken,
    required String phone,
    required IdempotencyKey key,
  });

  /// "보냈어요" — `…/{verificationId}/confirmations`. 회원이면 [LoginMember], 아직이면 [LoginNeedsIdentity]
  /// (status PENDING·FAILED·EXPIRED), 이미 가입·탈퇴 번호면 [LoginNeedsIdentity.conflict].
  Future<LoginOutcome> confirmIdentity(
    String authRequestId,
    String verificationId, {
    required String providerToken,
    required IdempotencyKey key,
    String? profileImageUrl,
  });
}

/// 실서버 구현(auth-service).
final class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(Dio dio, this._deviceId)
    : _logins = auth.PmartApiAuth(dio: dio).getLoginsApi(),
      _tokens = auth.PmartApiAuth(dio: dio).getTokensApi();

  final auth.LoginsApi _logins;
  final auth.TokensApi _tokens;
  final DeviceIdProvider _deviceId;

  Map<String, dynamic> _publicCommand(IdempotencyKey key) => {
    ...?commandOptions(key).extra,
    PmartExtra.public: true,
  };

  @override
  Future<LoginOutcome> login(
    SocialProvider provider,
    String providerToken, {
    required LoginPurpose purpose,
    required IdempotencyKey key,
    String? profileImageUrl,
  }) => _guard(
    () async => (await _logins.socialLogin(
      idempotencyKey: key.value,
      xSourceSystem: sourceSystem,
      xDeviceId: await _deviceId.get(),
      socialLoginRequest: auth.SocialLoginRequest(
        provider: switch (provider) {
          SocialProvider.kakao => auth.Provider.KAKAO,
          SocialProvider.naver => auth.Provider.NAVER,
          SocialProvider.apple => auth.Provider.APPLE,
          SocialProvider.google => auth.Provider.GOOGLE,
        },
        providerToken: providerToken,
        profileImageUrl: profileImageUrl,
        purpose: switch (purpose) {
          LoginPurpose.general => auth.SocialLoginRequestPurposeEnum.GENERAL,
          LoginPurpose.checkout => auth.SocialLoginRequestPurposeEnum.CHECKOUT,
        },
      ),
      extra: _publicCommand(key),
    )).data,
  );

  @override
  Future<LoginOutcome> lookup(String authRequestId) => _guard(
    () async => (await _logins.getSocialLogin(
      authRequestId: authRequestId,
      xDeviceId: await _deviceId.get(),
      extra: {PmartExtra.public: true},
    )).data,
  );

  @override
  Future<NaverExchange> exchangeNaverCode({
    required String authorizationCode,
    required String codeVerifier,
    required String redirectUri,
    required IdempotencyKey key,
    bool withdrawal = false,
  }) async {
    final res = await pmartGuard(
      () => _logins.exchangeNaverCode(
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        exchangeNaverCodeRequest: auth.ExchangeNaverCodeRequest(
          authorizationCode: authorizationCode,
          codeVerifier: codeVerifier,
          redirectUri: redirectUri,
          // 탈퇴 재인증이면 서버가 교환 뒤 네이버 앱 연결을 끊는다(auth 0.11.0, BR-74).
          purpose: withdrawal
              ? auth.ExchangeNaverCodeRequestPurposeEnum.WITHDRAWAL
              : auth.ExchangeNaverCodeRequestPurposeEnum.LOGIN,
        ),
        extra: _publicCommand(key),
      ),
    );
    // 본문이 없으면 교환됐는지 모른다 — 같은 키로 다시 물을 수 있게 결과 불명으로.
    final body = res.data ?? (throw UnknownResultFailure(requestId: key.value));
    return (
      idToken: body.idToken,
      // 없으면 null(빠지지 않고 null 로 온다 — 같게 다룬다)
      profileImageUrl: switch (body.profileImageUrl?.trim()) {
        null || '' => null,
        final u => u,
      },
    );
  }

  @override
  Future<String?> currentAccountId() async {
    try {
      final session = await pmartGuard(
        () async => (await _tokens.getCurrentSession()).data,
      );
      return session?.principalType == auth.SessionPrincipalTypeEnum.CUSTOMER
          ? session?.principalId
          : null;
    } on SessionExpiredFailure {
      return null;
    } on ProblemFailure catch (f) {
      // 서버가 답했다: 4xx 는 세션 없음, 5xx·429 는 지금 확인할 수 없음
      if (f.problem.status >= 500 || f.problem.status == 429) rethrow;
      return null;
    }
  }

  @override
  Future<LoginOutcome> completeWithConsents(
    String authRequestId, {
    required String providerToken,
    required List<ConsentDecision> consents,
    required IdempotencyKey key,
    String? profileImageUrl,
  }) => _guard(
    // BR-20 회신(2026-11-17): 동의는 completions 본문으로 보낸다 — customer `/me/consent-changes` 를 먼저 부르지 않는다.
    () async => (await _logins.completeSocialLogin(
      authRequestId: authRequestId,
      idempotencyKey: key.value,
      xSourceSystem: sourceSystem,
      xDeviceId: await _deviceId.get(),
      completeSocialLoginRequest: auth.CompleteSocialLoginRequest(
        providerToken: providerToken,
        profileImageUrl: profileImageUrl,
        consents: [
          for (final c in consents)
            auth.CompleteSocialLoginRequestConsentsInner(
              consentType: c.type,
              version: c.version,
              agreed: c.agreed,
            ),
        ],
      ),
      extra: _publicCommand(key),
    )).data,
  );

  @override
  Future<IdentityStart> startIdentity(
    String authRequestId, {
    required String providerToken,
    required String phone,
    required IdempotencyKey key,
  }) async {
    final res = await pmartGuard(
      () async => (await _logins.startSocialLoginIdentityVerification(
        authRequestId: authRequestId,
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        xDeviceId: await _deviceId.get(),
        startSocialLoginIdentityVerificationRequest:
            auth.StartSocialLoginIdentityVerificationRequest(
              providerToken: providerToken,
              phone: phone,
            ),
        extra: _publicCommand(key),
      )).data,
    );
    final s = res ?? (throw UnknownResultFailure(requestId: key.value));
    return IdentityStart(
      verificationId: s.verificationId,
      sendTo: s.sendTo,
      text: s.text,
      expiresAt: s.expiresAt,
      phoneMasked: s.phoneMasked,
    );
  }

  @override
  Future<LoginOutcome> confirmIdentity(
    String authRequestId,
    String verificationId, {
    required String providerToken,
    required IdempotencyKey key,
    String? profileImageUrl,
  }) => _guard(
    () async => (await _logins.confirmSocialLoginIdentityVerification(
      authRequestId: authRequestId,
      verificationId: verificationId,
      idempotencyKey: key.value,
      xSourceSystem: sourceSystem,
      xDeviceId: await _deviceId.get(),
      confirmSocialLoginIdentityVerificationRequest:
          auth.ConfirmSocialLoginIdentityVerificationRequest(
            providerToken: providerToken,
            profileImageUrl: profileImageUrl,
          ),
      extra: _publicCommand(key),
    )).data,
    authRequestId: authRequestId,
  );

  Future<LoginOutcome> _guard(
    Future<auth.AuthResult?> Function() call, {
    String? authRequestId,
  }) async {
    try {
      final result = await pmartGuard(call);
      if (result == null) return const LoginUnknown();
      return authResultToOutcome(result);
    } on PmartFailure catch (f) {
      // 이미 가입·탈퇴 번호(409) — 휴대폰 확인 화면에 안내를 띄운다(R3·R4).
      if (authRequestId != null) {
        if (identityConflictOf(f) case final c?) {
          return LoginNeedsIdentity(authRequestId: authRequestId, conflict: c);
        }
      }
      return authFailureToOutcome(f);
    }
  }
}

/// 동의 항목 문자열 `TYPE:version`(BR-20 회신)에서 유형.
String consentTypeOf(String item) => ConsentDecision(item, agreed: true).type;

LoginOutcome authResultToOutcome(auth.AuthResult r) => switch (r.state) {
  auth.AuthState.AUTH_MEMBER => switch ((r.accountId, r.tokens)) {
    (final String accountId, final auth.TokenPair t) => LoginMember(
      accountId: accountId,
      tokens: AuthTokens(
        accessToken: t.accessToken,
        refreshToken: t.refreshToken,
      ),
      newAccount: r.newAccount ?? false,
      cartMergeConfirm:
          r.nextAction == auth.AuthResultNextActionEnum.CART_MERGE_CONFIRM,
    ),
    // 회원이라는데 토큰·계정이 없으면 계약 위반이다. 로그인됐다고 보이지 않는다.
    _ => throw const ContractViolationFailure('AUTH_MEMBER 인데 토큰 없음'),
  },
  auth.AuthState.AUTH_CONSENT => LoginNeedsConsent(
    authRequestId: r.authRequestId,
    requiredConsents: r.requiredConsents ?? const [],
    optionalConsents: r.optionalConsents ?? const [],
    // 계약: 동의 화면에서 나갔던 가입은 다음 로그인도 newAccount=true. 값이 없으면 신규로 본다.
    newAccount: r.newAccount ?? true,
  ),
  // 휴대폰 확인 대기(auth 0.6.0). 확인 결과(identityVerification)가 실려 오면 그 상태를 함께.
  auth.AuthState.AUTH_IDENTITY => LoginNeedsIdentity(
    authRequestId: r.authRequestId,
    newAccount: r.newAccount ?? true,
    status: r.identityVerification?.state.value,
    remainingAttempts: r.identityVerification?.remainingAttempts,
  ),
  auth.AuthState.AUTH_RESTRICTED => LoginRestricted(
    retryAfterSeconds: r.retryAfterSeconds,
  ),
  auth.AuthState.AUTH_UNKNOWN ||
  auth.AuthState.AUTH_PENDING => LoginUnknown(authRequestId: r.authRequestId),
  auth.AuthState.AUTH_GUEST => const LoginRejected('AUTH_GUEST'),
};

LoginOutcome authFailureToOutcome(PmartFailure f) => switch (f) {
  ProblemFailure(:final problem)
      when problem.code == AuthProblemCode.restricted =>
    LoginRestricted(
      retryAfterSeconds: problem.raw['retryAfterSeconds'] as int?,
    ),
  ProblemFailure(:final problem) => LoginRejected(problem.code),
  UnknownResultFailure(:final problem)
      when problem?.code == AuthProblemCode.providerUnavailable =>
    const LoginProviderUnavailable(),
  // 501 은 "지원하지 않음"이 확정된 응답이다. 변경 요청의 5xx 라도 결과 불명으로 두지 않는다.
  UnknownResultFailure(:final problem)
      when problem?.code == AuthProblemCode.unsupported =>
    const LoginRejected(AuthProblemCode.unsupported),
  UnknownResultFailure() => const LoginUnknown(),
  _ => throw f,
};

/// 409 IDENTITY_ALREADY_REGISTERED·IDENTITY_REJOIN_BLOCKED 의 details(field·reason 쌍)를 읽는다. 그 밖이면 null.
IdentityConflict? identityConflictOf(PmartFailure f) {
  if (f is! ProblemFailure) return null;
  final code = f.problem.code;
  if (code != 'IDENTITY_ALREADY_REGISTERED' &&
      code != 'IDENTITY_REJOIN_BLOCKED') {
    return null;
  }
  final d = {for (final x in f.problem.details) x.field: x.reason};
  return IdentityConflict(
    code: code,
    provider: switch (d['provider']) {
      'KAKAO' => SocialProvider.kakao,
      'NAVER' => SocialProvider.naver,
      'GOOGLE' => SocialProvider.google,
      'APPLE' => SocialProvider.apple,
      _ => null,
    },
    joinedAt: DateTime.tryParse(d['joinedAt'] ?? ''),
    emailMasked: d['emailMasked'],
    rejoinAvailableAt: DateTime.tryParse(d['rejoinAvailableAt'] ?? ''),
  );
}
