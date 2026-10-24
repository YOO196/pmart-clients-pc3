import 'package:meta/meta.dart';

import 'storage.dart';

@immutable
final class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;

  /// 토큰 값을 로그에 남기지 않는다.
  @override
  String toString() => 'AuthTokens(***)';
}

/// 토큰 보관. access token 은 메모리에만, refresh token 은 보안 저장소에 둔다.
final class TokenStore {
  TokenStore(this._store);

  static const _refreshKey = 'pmart.refreshToken';

  final SecureKeyValueStore _store;
  String? _accessToken;

  String? get accessToken => _accessToken;

  Future<String?> readRefreshToken() => _store.read(_refreshKey);

  Future<void> save(AuthTokens tokens) async {
    _accessToken = tokens.accessToken;
    await _store.write(_refreshKey, tokens.refreshToken);
  }

  Future<void> clear() async {
    _accessToken = null;
    await _store.delete(_refreshKey);
  }
}

/// refresh token 으로 새 토큰을 받는다(`POST /auth/tokens`, 회전).
///
/// 갱신이 거절되면(재사용 감지 등) null 을 돌려준다. 네트워크 오류는 예외로 던진다.
typedef TokenRefresher = Future<AuthTokens?> Function(String refreshToken);
