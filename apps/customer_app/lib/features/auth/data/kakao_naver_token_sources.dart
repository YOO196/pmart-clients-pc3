import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_appauth/flutter_appauth.dart';
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

/// 카카오 로그인(BR-65): 카카오톡이 있으면 카카오톡, 없으면 카카오계정(웹)으로 로그인해 **OIDC ID 토큰**을
/// `providerToken` 으로 넘긴다(서버가 카카오 JWKS 로 검증 — Google 과 같은 방식, ADR-0055). 콘솔에서 OpenID Connect 를
/// 켜야 ID 토큰이 온다(사용자 2026-11-19 활성화). 토큰은 로그에 남기지 않는다.
final class KakaoSocialTokenSource implements SocialTokenSource {
  const KakaoSocialTokenSource();

  @override
  Future<SocialCredential?> obtain(SocialProvider provider) async {
    if (provider != SocialProvider.kakao) throw const SocialProviderDown();
    try {
      final token = await isKakaoTalkInstalled()
          ? await UserApi.instance.loginWithKakaoTalk()
          : await UserApi.instance.loginWithKakaoAccount();
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
      // 카카오톡 로그인 화면에서 뒤로 — SDK 가 CANCELED 로 준다.
      if (e.code == 'CANCELED') return null;
      throw const SocialProviderDown();
    }
  }

  /// 카카오 SDK 가 저장한 토큰으로 조용한 재로그인은 하지 않는다(ID 토큰은 새로 로그인할 때만 온다) — 다시 로그인 화면으로.
  @override
  Future<SocialCredential?> obtainSilently(SocialProvider provider) async =>
      null;
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
});

/// 네이버 인가 요청(`nid.naver.com/oauth2/authorize`)에 덧붙이는 값(사용자 2026-11-20).
/// `auth_type=reprompt` — 전에 동의했더라도 네이버의 정보 제공 동의 화면을 다시 띄운다(가입을 끝내지 않고 나갔다
/// 다시 올 때 네이버 쪽 동의가 조용히 넘어가지 않게). 서버의 코드 교환과는 상관없다 — 인가 요청에만 붙는다.
const naverAuthorizeExtra = {'auth_type': 'reprompt'};

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
  Future<SocialCredential?> obtain(SocialProvider provider) async {
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
  Future<SocialCredential?> obtain(SocialProvider provider) =>
      _of(provider).obtain(provider);

  @override
  Future<SocialCredential?> obtainSilently(SocialProvider provider) =>
      _of(provider).obtainSilently(provider);
}
