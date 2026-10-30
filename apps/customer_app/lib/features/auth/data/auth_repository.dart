import 'package:dio/dio.dart';
import 'package:pmart_api_auth/pmart_api_auth.dart' as auth;
import 'package:pmart_api_customer/pmart_api_customer.dart' as customer;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../domain/auth.dart';

/// 제공자 SDK 에서 인가 코드·ID 토큰을 받는다. 고객이 취소하면 null.
///
/// 실제 SDK(카카오 등)는 앱 키 결정 뒤 붙인다(`[결정 필요]` 카카오 키). 토큰은 로그에 남기지 않는다.
abstract interface class SocialTokenSource {
  /// 제공자 장애면 [SocialProviderDown] 을 던진다.
  Future<String?> obtain(SocialProvider provider);
}

final class SocialProviderDown implements Exception {
  const SocialProviderDown();
}

abstract interface class AuthRepository {
  /// `POST /auth/social-logins`. 같은 [key] 재전송은 원인증 결과를 돌려준다.
  Future<LoginOutcome> login(
    SocialProvider provider,
    String providerToken, {
    required LoginPurpose purpose,
    required IdempotencyKey key,
  });

  /// `GET /auth/social-logins/{authRequestId}`.
  Future<LoginOutcome> lookup(String authRequestId);

  /// 저장된 세션의 계정(`GET /auth/sessions/current`. 401 이면 인터셉터가 refresh 회전 후 다시 보낸다).
  /// 세션이 끝났으면 null(토큰은 인터셉터가 지운다). 네트워크 오류도 null — 토큰은 두고 비회원으로 시작한다.
  Future<String?> currentAccountId();

  /// 필수 동의 반영 후 인증 완료.
  Future<LoginOutcome> completeWithConsents(
    String authRequestId,
    List<String> consents, {
    required IdempotencyKey key,
  });
}

/// 실서버 구현(auth-service, 동의는 customer-service).
final class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(Dio dio, this._deviceId)
    : _logins = auth.PmartApiAuth(dio: dio).getLoginsApi(),
      _tokens = auth.PmartApiAuth(dio: dio).getTokensApi(),
      _consents = customer.PmartApiCustomer(dio: dio).getConsentsApi();

  final auth.LoginsApi _logins;
  final auth.TokensApi _tokens;
  final customer.ConsentsApi _consents;
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
  Future<String?> currentAccountId() async {
    try {
      final session = await pmartGuard(
        () async => (await _tokens.getCurrentSession()).data,
      );
      return session?.principalType == auth.SessionPrincipalTypeEnum.CUSTOMER
          ? session?.principalId
          : null;
    } on PmartFailure {
      return null;
    }
  }

  @override
  Future<LoginOutcome> completeWithConsents(
    String authRequestId,
    List<String> consents, {
    required IdempotencyKey key,
  }) => _guard(() async {
    // BR-20: AUTH_CONSENT 에는 토큰이 없는데 동의 변경(`/me/consent-changes`)은 인증 경로다.
    // 회신 전까지 계약 그대로 호출한다(실서버에서는 401 이 날 수 있다). 목에서만 끝까지 동작한다.
    final consentKey = IdempotencyKey('${key.value}-consent');
    final change = await _consents.changeMyConsents(
      idempotencyKey: consentKey.value,
      xSourceSystem: sourceSystem,
      changeMyConsentsRequest: customer.ChangeMyConsentsRequest(
        changes: [
          for (final c in consents)
            customer.ChangeMyConsentsRequestChangesInner(
              consentType: customer.ConsentType.values.firstWhere(
                (t) => t.value == consentTypeOf(c),
                orElse: () => throw ContractViolationFailure('동의 항목 $c'),
              ),
              version: consentVersionOf(c),
              agreed: true,
            ),
        ],
      ),
      extra: commandOptions(consentKey).extra,
    );
    final requestId = change.data?.requestId ?? consentKey.value;
    return (await _logins.completeSocialLogin(
      authRequestId: authRequestId,
      idempotencyKey: key.value,
      xSourceSystem: sourceSystem,
      xDeviceId: await _deviceId.get(),
      completeSocialLoginRequest: auth.CompleteSocialLoginRequest(
        consentChangeRequestId: requestId,
      ),
      extra: _publicCommand(key),
    )).data;
  });

  Future<LoginOutcome> _guard(Future<auth.AuthResult?> Function() call) async {
    try {
      final result = await pmartGuard(call);
      if (result == null) return const LoginUnknown();
      return authResultToOutcome(result);
    } on PmartFailure catch (f) {
      return authFailureToOutcome(f);
    }
  }
}

/// 동의 항목 문자열 `TYPE[:version]` 에서 유형. 형식은 BR-20 에서 확인 중.
String consentTypeOf(String item) => item.split(':').first;

String consentVersionOf(String item) {
  final parts = item.split(':');
  return parts.length > 1 ? parts.sublist(1).join(':') : '';
}

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
