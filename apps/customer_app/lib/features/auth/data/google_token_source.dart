import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../domain/auth.dart';
import 'auth_repository.dart';

/// Google 서버(웹) 클라이언트 ID. Android Google Sign-In 은 이 값을 줘야 ID 토큰을 주고, 토큰의 `aud` 가 이 값이다.
/// 비밀값이 아니다(백엔드 handoff 2026-10-30 고객 Google 로그인 §2, ADR-0019). client secret 은 앱에 두지 않는다.
const googleServerClientId = String.fromEnvironment(
  'PMART_GOOGLE_SERVER_CLIENT_ID',
  defaultValue: '293585219605-p6akml03k4lpi01agvgah41g2imo1aes.apps.googleusercontent.com',
);

/// [시험 전용] 서버 인가 코드(authorizeServer) 실기기 시험. 기본 꺼짐, 출시 빌드에서는 켜도 동작하지 않는다.
/// `--dart-define=PMART_GOOGLE_SERVER_AUTH_TEST=true` 로 켠다. ADR-0025 결정 뒤 지운다.
const googleServerAuthCodeTest = bool.fromEnvironment(
  'PMART_GOOGLE_SERVER_AUTH_TEST',
);

/// Google 설정 오류(Android OAuth 클라이언트 미등록·패키지 이름/SHA-1 불일치 = DEVELOPER_ERROR 등).
final class SocialProviderMisconfigured implements Exception {
  const SocialProviderMisconfigured();
}

/// Google Sign-In 결과 코드 → 앱 처리. 취소는 null(서버를 부르지 않고 실패 횟수에도 넣지 않는다).
SocialCredential? googleSignInFailure(GoogleSignInExceptionCode code) =>
    switch (code) {
      GoogleSignInExceptionCode.canceled ||
      GoogleSignInExceptionCode.interrupted => null,
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        throw const SocialProviderMisconfigured(),
      _ => throw const SocialProviderDown(),
    };

/// 실제 Google 계정 선택 창 → ID 토큰. 토큰 값은 로그·오류 문구에 남기지 않는다.
/// (GoogleSignInAuthentication.toString 은 토큰을 찍으므로 그 객체를 문자열로 바꾸지 않는다.)
final class GoogleSocialTokenSource implements SocialTokenSource {
  GoogleSocialTokenSource({
    GoogleSignIn? signIn,
    this.serverClientId = googleServerClientId,
  }) : _signIn = signIn ?? GoogleSignIn.instance;

  final GoogleSignIn _signIn;
  final String serverClientId;
  Future<void>? _initialized;

  @override
  Future<SocialCredential?> obtain(SocialProvider provider) async {
    // 서버는 Google 만 지원한다(ADR-0019). 화면도 Google 버튼만 보인다.
    if (provider != SocialProvider.google) throw const SocialProviderDown();
    try {
      await (_initialized ??= _signIn.initialize(
        serverClientId: serverClientId,
      ));
      final account = await _signIn.authenticate();
      if (googleServerAuthCodeTest && !kReleaseMode) {
        await _probeServerAuthCode(account);
      }
      final idToken = account.authentication.idToken;
      // serverClientId 가 맞으면 ID 토큰이 온다. 없으면 설정 문제다.
      if (idToken == null || idToken.isEmpty) {
        throw const SocialProviderMisconfigured();
      }
      return SocialCredential(idToken, accountLabel: account.email);
    } on GoogleSignInException catch (e) {
      return googleSignInFailure(e.code);
    }
  }

  /// 조용한 재로그인: 계정 선택 창 없이 지난번 계정으로 ID 토큰을 받는다(google_sign_in 7 `attemptLightweightAuthentication`).
  /// 세션이 끝났을 때 먼저 시도하고, 안 되면 호출자가 로그인 화면으로 안내한다. 실패는 null 로 돌려 던지지 않는다.
  @override
  Future<SocialCredential?> obtainSilently(SocialProvider provider) async {
    if (provider != SocialProvider.google) return null;
    try {
      await (_initialized ??= _signIn.initialize(
        serverClientId: serverClientId,
      ));
      final account = await _signIn.attemptLightweightAuthentication();
      final idToken = account?.authentication.idToken;
      if (account == null || idToken == null || idToken.isEmpty) return null;
      return SocialCredential(idToken, accountLabel: account.email);
    } on GoogleSignInException {
      return null;
    } on Object {
      return null;
    }
  }

  /// [시험 전용] 서버 인가 코드가 나오는지 확인한다(백엔드 handoff 2026-10-31 서버 인가 코드 시험, ADR-0025 초안).
  /// 코드 값은 남기지 않고 null 여부·길이만 찍는다. 서버에는 보내지 않는다.
  /// GoogleSignInServerAuthorization.toString 은 코드를 찍으므로 그 객체를 문자열로 바꾸지 않는다.
  /// 결과와 상관없이 로그인은 지금처럼 ID 토큰으로 계속한다.
  Future<void> _probeServerAuthCode(GoogleSignInAccount account) async {
    try {
      final server = await account.authorizationClient
          .authorizeServer(const ['openid', 'email', 'profile']);
      final code = server?.serverAuthCode;
      debugPrint(
        '[server-auth-test] serverAuthCode='
        '${code == null ? 'null' : 'present(length=${code.length})'}',
      );
    } on GoogleSignInException catch (e) {
      debugPrint('[server-auth-test] exception code=${e.code.name}');
    } catch (e) {
      debugPrint('[server-auth-test] unexpected ${e.runtimeType}');
    }
  }

  /// 다음 로그인 때 계정을 다시 고를 수 있게 Google 쪽 선택을 지운다(앱 로그아웃 시).
  Future<void> signOut() async {
    if (_initialized == null) return;
    await _signIn.signOut();
  }
}
