import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PKCE(RFC 7636). 티켓은 로그인을 시작한 code_verifier 로만 토큰으로 바뀐다.
/// verifier 는 메모리에만 두고 로그·저장소에 남기지 않는다.
abstract final class Pkce {
  /// 무작위 32바이트 → base64url 43자(계약 43~128자, `[A-Za-z0-9-._~]`).
  static String newVerifier([Random? random]) {
    final r = random ?? Random.secure();
    final bytes = List<int>.generate(32, (_) => r.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// S256: `BASE64URL(SHA-256(ASCII(verifier)))`, 패딩 없음.
  static String challenge(String verifier) => base64UrlEncode(
    sha256.convert(ascii.encode(verifier)).bytes,
  ).replaceAll('=', '');
}
