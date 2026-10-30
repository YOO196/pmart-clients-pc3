import 'package:google_sign_in/google_sign_in.dart';

import '../domain/auth.dart';
import 'auth_repository.dart';

/// Google 서버(웹) 클라이언트 ID. Android Google Sign-In 은 이 값을 줘야 ID 토큰을 주고, 토큰의 `aud` 가 이 값이다.
/// 비밀값이 아니다(백엔드 handoff 2026-10-30 고객 Google 로그인 §2, ADR-0019). client secret 은 앱에 두지 않는다.
const googleServerClientId = String.fromEnvironment(
  'PMART_GOOGLE_SERVER_CLIENT_ID',
  defaultValue: '293585219605-p6akml03k4lpi01agvgah41g2imo1aes.apps.googleusercontent.com',
);

/// Google 설정 오류(Android OAuth 클라이언트 미등록·패키지 이름/SHA-1 불일치 = DEVELOPER_ERROR 등).
final class SocialProviderMisconfigured implements Exception {
  const SocialProviderMisconfigured();
}

/// Google Sign-In 결과 코드 → 앱 처리. 취소는 null(서버를 부르지 않고 실패 횟수에도 넣지 않는다).
String? googleSignInFailure(GoogleSignInExceptionCode code) => switch (code) {
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
  Future<String?> obtain(SocialProvider provider) async {
    // 서버는 Google 만 지원한다(ADR-0019). 화면도 Google 버튼만 보인다.
    if (provider != SocialProvider.google) throw const SocialProviderDown();
    try {
      await (_initialized ??= _signIn.initialize(
        serverClientId: serverClientId,
      ));
      final account = await _signIn.authenticate();
      final idToken = account.authentication.idToken;
      // serverClientId 가 맞으면 ID 토큰이 온다. 없으면 설정 문제다.
      if (idToken == null || idToken.isEmpty) {
        throw const SocialProviderMisconfigured();
      }
      return idToken;
    } on GoogleSignInException catch (e) {
      return googleSignInFailure(e.code);
    }
  }

  /// 다음 로그인 때 계정을 다시 고를 수 있게 Google 쪽 선택을 지운다(앱 로그아웃 시).
  Future<void> signOut() async {
    if (_initialized == null) return;
    await _signIn.signOut();
  }
}
