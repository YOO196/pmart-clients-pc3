import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_api_auth/pmart_api_auth.dart' as auth;
import 'package:pmart_core/pmart_core.dart';

import '../features/cart/data/guest_session.dart';

/// `X-Source-System` (값 확정은 BR-08).
const sourceSystem = 'customer-app';

final envProvider = Provider<PmartEnv>((_) => PmartEnv.fromDefine());

final secureStoreProvider = Provider<SecureKeyValueStore>(
  (_) => FlutterSecureKeyValueStore(),
);

final tokenStoreProvider = Provider<TokenStore>(
  (ref) => TokenStore(ref.watch(secureStoreProvider)),
);

final deviceIdProvider = Provider<DeviceIdProvider>(
  (ref) => DeviceIdProvider(ref.watch(secureStoreProvider)),
);

/// 비회원 장바구니 토큰(typ=GUEST). 회원 토큰과 저장 키가 다르다.
final guestTokenStoreProvider = Provider<TokenStore>(
  (ref) =>
      TokenStore(ref.watch(secureStoreProvider), refreshKey: guestRefreshKey),
);

/// 실서버(local) 게이트웨이 주소. 목 모드에서는 만들지 않는다.
final apiBaseUrlProvider = Provider<String>((ref) {
  final env = ref.watch(envProvider);
  if (env == PmartEnv.mock) {
    throw StateError('목 모드는 네트워크를 쓰지 않는다. Repository 목 구현을 써야 한다.');
  }
  return apiBaseUrl(
    env,
    androidEmulator: const bool.fromEnvironment('PMART_ANDROID_EMULATOR'),
  );
});

/// 비회원 장바구니용 Dio. 비회원 토큰은 장바구니(/carts/**)에서만 통하므로(그 밖은 403) 다른 API 에 쓰지 않는다.
/// 첫 요청 때 비회원 세션이 없으면 만든다([GuestSessionInterceptor]).
final guestDioProvider = Provider<Dio>((ref) {
  final baseUrl = ref.watch(apiBaseUrlProvider);
  final deviceId = ref.watch(deviceIdProvider);
  final tokens = ref.watch(guestTokenStoreProvider);
  final dio = createPmartDio(
    baseUrl: baseUrl,
    sourceSystem: sourceSystem,
    tokens: tokens,
    deviceId: deviceId,
    refresher: authRefresher(baseUrl: baseUrl, deviceId: deviceId),
    log: kDebugMode ? debugPrint : null,
  );
  dio.interceptors.insert(
    0,
    GuestSessionInterceptor(
      tokens: tokens,
      start: guestSessionStarter(
        baseUrl: baseUrl,
        sourceSystem: sourceSystem,
        deviceId: deviceId,
      ),
    ),
  );
  return dio;
});

/// 실서버(local) 연동용 Dio(회원 토큰). 목 모드에서는 만들지 않는다.
final dioProvider = Provider<Dio>((ref) {
  final baseUrl = ref.watch(apiBaseUrlProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return createPmartDio(
    baseUrl: baseUrl,
    sourceSystem: sourceSystem,
    tokens: ref.watch(tokenStoreProvider),
    deviceId: deviceId,
    refresher: authRefresher(baseUrl: baseUrl, deviceId: deviceId),
    log: kDebugMode ? debugPrint : null,
  );
});

/// `POST /auth/tokens` 로 토큰을 회전한다.
///
/// 인증 인터셉터를 거치지 않는 별도 Dio 를 쓴다(갱신 요청이 다시 갱신을 부르지 않게).
/// 401(TOKEN_INVALID·TOKEN_REUSED)이면 세션이 폐기된 것이므로 null 을 돌려준다.
TokenRefresher authRefresher({
  required String baseUrl,
  required DeviceIdProvider deviceId,
  HttpClientAdapter? adapter,
}) {
  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  if (adapter != null) dio.httpClientAdapter = adapter;
  final tokens = auth.PmartApiAuth(dio: dio).getTokensApi();
  return (refreshToken) async {
    try {
      final res = await tokens.refreshTokens(
        idempotencyKey: IdempotencyKey.generate().value,
        xSourceSystem: sourceSystem,
        xDeviceId: await deviceId.get(),
        refreshTokensRequest: auth.RefreshTokensRequest(
          refreshToken: refreshToken,
        ),
      );
      final pair = res.data;
      if (pair == null) {
        throw const ContractViolationFailure('TokenPair 본문 없음');
      }
      return AuthTokens(
        accessToken: pair.accessToken,
        refreshToken: pair.refreshToken,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) return null;
      throw PmartFailure.fromDioException(e);
    }
  };
}

/// 서버가 주는 이미지 주소는 게이트웨이 상대 경로다(`/api/v1/content-images/{imageId}`, 계약 Image.url).
/// 실서버는 게이트웨이 출처(scheme://host:port)를 붙인다. 목은 완전한 주소를 쓰므로 null.
final imageOriginProvider = Provider<String?>(
  (ref) => ref.watch(envProvider) == PmartEnv.mock
      ? null
      : Uri.parse(ref.watch(apiBaseUrlProvider)).origin,
);

/// 이미지 주소를 그릴 수 있는 완전한 주소로 바꾼다. 출처를 모르는 상대 경로는 null(자리표시).
String? resolveImageUrl(String? url, String? origin) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  if (origin == null || !url.startsWith('/')) return null;
  return '$origin$url';
}
