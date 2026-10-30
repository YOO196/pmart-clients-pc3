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
///
/// 주체마다 따로 둔다(고객 앱: 회원 토큰과 비회원 장바구니 토큰은 [refreshKey] 가 다르다).
final class TokenStore {
  TokenStore(this._store, {this.refreshKey = defaultRefreshKey});

  static const defaultRefreshKey = 'pmart.refreshToken';

  /// refresh token 을 두는 보안 저장소 키.
  final String refreshKey;

  final SecureKeyValueStore _store;
  String? _accessToken;

  String? get accessToken => _accessToken;

  Future<String?> readRefreshToken() => _store.read(refreshKey);

  Future<void> save(AuthTokens tokens) async {
    _accessToken = tokens.accessToken;
    await _store.write(refreshKey, tokens.refreshToken);
  }

  Future<void> clear() async {
    _accessToken = null;
    await _store.delete(refreshKey);
  }
}

/// refresh token 으로 새 토큰을 받는다(`POST /auth/tokens`, 회전).
///
/// 갱신이 거절되면(재사용 감지 등) null 을 돌려준다. 네트워크 오류는 예외로 던진다.
typedef TokenRefresher = Future<AuthTokens?> Function(String refreshToken);
