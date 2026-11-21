import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_appauth/flutter_appauth.dart' hide Prompt;
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:pmart_core/pmart_core.dart'
    show
        IdempotencyKey,
        PmartFailure,
        ProblemCode,
        ProblemFailure,
        UnknownResultFailure;

import '../domain/auth.dart';
import 'auth_repository.dart';
import 'google_token_source.dart' show SocialProviderMisconfigured;

/// 카카오 로그인 요청의 prompt(백엔드 요청 2026-11-21 "로그인 버튼마다 계정 고르기·다시 로그인").
/// `login` — 카카오계정에 로그인돼 있어도 매번 로그인 화면을 띄워 다른 계정으로 바꿀 수 있게(OIDC `prompt=login`).
/// 동의 화면은 처음 가입 때만 뜬다(이미 동의한 계정이면 다시 묻지 않는다).
const kakaoLoginPrompts = [Prompt.login];

Future<OAuthToken> _kakaoAccountLogin() =>
    UserApi.instance.loginWithKakaoAccount(prompts: kakaoLoginPrompts);

Future<void> _kakaoLogout() async {
  await UserApi.instance.logout();
}

/// 카카오 로그인(BR-65): 카카오계정 로그인 화면으로 로그인해 **OIDC ID 토큰**을 `providerToken` 으로 넘긴다
/// (서버가 카카오 JWKS 로 검증 — Google 과 같은 방식, ADR-0055). 콘솔에서 OpenID Connect 를 켜야 ID 토큰이 온다
/// (사용자 2026-11-19 활성화). 토큰은 로그에 남기지 않는다.
/// 2026-11-21 백엔드 요청: 카카오톡 앱 자동 로그인(바로 들어가 계정을 못 바꿈) 대신 카카오계정 로그인 화면 + [kakaoLoginPrompts].
final class KakaoSocialTokenSource implements SocialTokenSource {
  const KakaoSocialTokenSource({
    this.login = _kakaoAccountLogin,
    this.logout = _kakaoLogout,
  });

  /// 카카오계정 로그인 화면(시험에서 바꿔 끼운다).
  final Future<OAuthToken> Function() login;

  /// 카카오 SDK 로그아웃 — 이 기기에 저장된 카카오 토큰을 지운다(시험에서 바꿔 끼운다).
  final Future<void> Function() logout;

  @override
  Future<SocialCredential?> obtain(
    SocialProvider provider, {
    bool withdrawal = false,
  }) async {
    if (provider != SocialProvider.kakao) throw const SocialProviderDown();
    try {
      final token = await login();
      final idToken = token.idToken;
      // OIDC 가 꺼져 있으면 ID 토큰이 없다 — 서버가 검증할 수 없어 설정 문제로 알린다.
      if (idToken == null || idToken.isEmpty) {
        throw const SocialProviderMisconfigured();
      }
      return SocialCredential(idToken);
    } on KakaoAuthException catch (e) {
      if (e.error == AuthErrorCause.accessDenied) return null; // 동의 화면에서 취소
      throw const SocialProviderDown();
    } on KakaoClientException catch (e) {
      if (e.reason == ClientErrorCause.cancelled) return null;
      throw const SocialProviderDown();
    } on PlatformException catch (e) {
      // 로그인 화면에서 뒤로 — SDK 가 CANCELED 로 준다.
      if (e.code == 'CANCELED') return null;
      throw const SocialProviderDown();
    }
  }

  /// 카카오 SDK 가 저장한 토큰으로 조용한 재로그인은 하지 않는다(ID 토큰은 새로 로그인할 때만 온다) — 다시 로그인 화면으로.
  @override
  Future<SocialCredential?> obtainSilently(SocialProvider provider) async =>
      null;

  /// 앱 로그아웃·탈퇴 때 카카오 SDK `logout()`(백엔드 요청 2026-11-21 R2). 앱 연결 끊기는 서버가 한다
  /// (탈퇴 반영 뒤 Admin 키) — 앱은 끊지 않는다. 실패(오프라인 등)는 흐름을 막지 않는다.
  @override
  Future<void> forget(SocialProvider provider, {bool revoke = false}) async {
    if (provider != SocialProvider.kakao) return;
    try {
      await logout();
    } on Object {
      // 이 기기 토큰 정리 실패 — 다음 로그인은 prompt=login 이라 그대로 로그인 화면이 뜬다.
    }
  }
}

/// 네이버 Client ID(공개 값, 빌드 때 `.secrets` 에서 dart-define 으로). 비면 네이버 버튼은 설정 문제로 알린다.
const naverClientId = String.fromEnvironment('NAVER_CLIENT_ID');

/// 네이버 `redirect_uri` = 콘솔 Callback URL(BR-66, auth 0.5.0). 네이버 콘솔이 앱 주소를 받지 않고 도메인이 없어
/// LAN 게이트웨이 중계 주소를 쓴다 — 서버가 받은 쿼리 그대로 `com.pmart.customer://oauth/naver` 로 302 하면
/// flutter_appauth 가 이어 받는다(build.gradle `appAuthRedirectScheme`). 사내 와이파이에서만 닿는다.
/// 토큰 교환의 redirect_uri 도 이 값 그대로. 다른 주소는 `--dart-define=PMART_NAVER_REDIRECT_URL=…`.
const naverRedirectUrl = String.fromEnvironment(
  'PMART_NAVER_REDIRECT_URL',
  defaultValue:
      'http://192.168.0.40:8080/api/v1/auth/oauth-callbacks/naver/customer',
);

/// 네이버 OIDC 공개 설정(https://nid.naver.com/.well-known/openid-configuration, 2026-11-19 확인).
const _naverOidc = AuthorizationServiceConfiguration(
  authorizationEndpoint: 'https://nid.naver.com/oauth2/authorize',
  tokenEndpoint: 'https://nid.naver.com/oauth2/token',
);

/// 네이버 인가 요청으로 받은 것(메모리에만 — 로그 금지).
typedef NaverAuthorization = ({String code, String codeVerifier});

/// 네이버 인가 화면을 띄워 코드를 받는다. 고객이 닫으면 null. 실패는 [PlatformException].
typedef NaverAuthorize = Future<NaverAuthorization?> Function(String clientId);

/// 서버가 인가 코드를 ID 토큰으로 바꾼다(`POST /auth/naver-token-exchanges`, auth 0.10.0).
typedef NaverCodeExchange = Future<NaverExchange> Function({
  required String authorizationCode,
  required String codeVerifier,
  required String redirectUri,
  required IdempotencyKey key,
  bool withdrawal,
});

/// 네이버 인가 요청(`nid.naver.com/oauth2/authorize`)에 덧붙이는 값(사용자 2026-11-20).
/// `auth_type=reauthenticate` — 브라우저에 네이버 로그인이 남아 있어도 아이디·비밀번호를 매번 다시 받는다(사용자 2026-11-20).
/// (앞서 쓴 `reprompt` 는 전에 거부한 항목만 다시 묻는 값이라 바로 로그인됐다.) 정보 제공 동의 화면을 다시 띄우는 것은
/// 인가 요청 값으로는 안 되고 네이버 쪽 연결을 끊어야 한다 — 서버 요청 BR-74.
/// 서버의 코드 교환과는 상관없다 — 인가 요청에만 붙는다.
const naverAuthorizeExtra = {'auth_type': 'reauthenticate'};

Future<NaverAuthorization?> _authorizeWithAppAuth(String clientId) async {
  try {
    final r = await const FlutterAppAuth().authorize(
      AuthorizationRequest(
        clientId,
        naverRedirectUrl,
        scopes: const ['openid'],
        serviceConfiguration: _naverOidc,
        additionalParameters: naverAuthorizeExtra,
      ),
    );
    final code = r.authorizationCode;
    final verifier = r.codeVerifier;
    if (code == null || code.isEmpty || verifier == null || verifier.isEmpty) {
      throw const SocialProviderDown();
    }
    return (code: code, codeVerifier: verifier);
  } on FlutterAppAuthUserCancelledException {
    return null; // 고객이 로그인 화면을 닫음
  }
}

/// 네이버 로그인(BR-65·BR-69, auth 0.10.0·ADR-0078): OpenID Connect 인가 코드 + PKCE(scope `openid`).
/// 네이버 토큰 엔드포인트는 client secret 없는 교환을 받지 않아(`invalid_client`), 앱은 **인가 코드까지만** 받고
/// 서버가 secret 으로 교환해 준 **id_token** 을 `providerToken` 으로 쓴다. secret 은 앱에 두지 않는다.
/// 코드·verifier·토큰은 로그에 남기지 않는다.
final class NaverSocialTokenSource implements SocialTokenSource {
  const NaverSocialTokenSource({
    required this.exchange,
    this.clientId = naverClientId,
    this.authorize = _authorizeWithAppAuth,
  });

  final NaverCodeExchange exchange;
  final String clientId;
  final NaverAuthorize authorize;

  @override
  Future<SocialCredential?> obtain(
    SocialProvider provider, {
    bool withdrawal = false,
  }) async {
    if (provider != SocialProvider.naver) throw const SocialProviderDown();
    if (clientId.isEmpty) throw const SocialProviderMisconfigured();
    final NaverAuthorization? granted;
    try {
      granted = await authorize(clientId);
    } on PlatformException {
      // 콘솔에 Callback URL 이 없거나 네이버가 거절 — 상세는 화면에 쓰지 않는다.
      throw const SocialProviderDown();
    }
    if (granted == null) return null;
    // 인가 코드는 한 번만 쓸 수 있다 — 결과를 모르면 같은 키로 한 번 더(서버가 두 번 교환하지 않는다).
    final key = IdempotencyKey.generate();
    Future<NaverExchange> once() => exchange(
      authorizationCode: granted!.code,
      codeVerifier: granted.codeVerifier,
      redirectUri: naverRedirectUrl,
      key: key,
      // 탈퇴 재인증이면 서버가 교환 뒤 네이버 앱 연결을 끊는다(auth 0.11.0, BR-74).
      withdrawal: withdrawal,
    );
    try {
      NaverExchange r;
      try {
        r = await once();
      } on UnknownResultFailure {
        r = await once();
      }
      return SocialCredential(r.idToken, profileImageUrl: r.profileImageUrl);
    } on ProblemFailure catch (f) {
      // 서버에 네이버 secret 이 없다 — 설정 문제로 알린다.
      if (f.problem.code == ProblemCode.configRequired) {
        throw const SocialProviderMisconfigured();
      }
      throw const SocialProviderDown();
    } on PmartFailure {
      throw const SocialProviderDown();
    }
  }

  @override
  Future<SocialCredential?> obtainSilently(SocialProvider provider) async =>
      null;

  /// 네이버 앱 연결은 서버가 끊는다(탈퇴 재인증 교환 때, BR-74). 네이버 로그인은 앱에 토큰을 남기지 않고(인가 코드만)
  /// 인가 요청마다 [naverAuthorizeExtra] 로 다시 로그인하게 해 — 앱은 할 일 없음.
  @override
  Future<void> forget(SocialProvider provider, {bool revoke = false}) async {}
}

/// 제공자마다 맞는 SDK 로 보낸다.
final class RoutingSocialTokenSource implements SocialTokenSource {
  const RoutingSocialTokenSource({
    required this.google,
    this.kakao = const KakaoSocialTokenSource(),
    required this.naver,
  });

  final SocialTokenSource google;
  final SocialTokenSource kakao;
  final SocialTokenSource naver;

  SocialTokenSource _of(SocialProvider p) => switch (p) {
    SocialProvider.kakao => kakao,
    SocialProvider.naver => naver,
    _ => google,
  };

  @override
  Future<SocialCredential?> obtain(
    SocialProvider provider, {
    bool withdrawal = false,
  }) => _of(provider).obtain(provider, withdrawal: withdrawal);

  @override
  Future<SocialCredential?> obtainSilently(SocialProvider provider) =>
      _of(provider).obtainSilently(provider);

  @override
  Future<void> forget(SocialProvider provider, {bool revoke = false}) =>
      _of(provider).forget(provider, revoke: revoke);
}
