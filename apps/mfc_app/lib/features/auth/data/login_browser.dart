import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../domain/employee_auth.dart';

/// 로그인 화면을 브라우저로 열고, 앱으로 돌아온 주소를 돌려준다.
///
/// WebView 를 쓰지 않는다 — Keycloak 비밀번호 입력을 앱이 볼 수 없어야 한다(백엔드 handoff 2026-11-13 §1).
abstract interface class LoginBrowser {
  /// [url] 을 열고 [callbackScheme] 으로 돌아온 주소를 돌려준다.
  /// 사용자가 창을 닫으면 [LoginFailure]([LoginError.cancelled]).
  Future<Uri> open(Uri url, {required String callbackScheme});
}

/// Chrome Custom Tab + 딥링크(`AndroidManifest.xml` 의 CallbackActivity 가 `pmart-mfc://` 를 받는다).
final class CustomTabLoginBrowser implements LoginBrowser {
  const CustomTabLoginBrowser();

  @override
  Future<Uri> open(Uri url, {required String callbackScheme}) async {
    try {
      final result = await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: callbackScheme,
      );
      return Uri.parse(result);
    } on PlatformException catch (e) {
      // 창을 닫으면 CANCELED. 그 밖(브라우저 없음 등)은 일시 오류로 안내한다. 주소는 남기지 않는다.
      throw LoginFailure(
        e.code == 'CANCELED' ? LoginError.cancelled : LoginError.temporary,
      );
    }
  }
}
