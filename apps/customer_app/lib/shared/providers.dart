import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_api_auth/pmart_api_auth.dart' as auth;
import 'package:pmart_core/pmart_core.dart';

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

/// 실서버(local) 연동용 Dio. 목 모드에서는 만들지 않는다.
final dioProvider = Provider<Dio>((ref) {
  final env = ref.watch(envProvider);
  if (env == PmartEnv.mock) {
    throw StateError('목 모드는 네트워크를 쓰지 않는다. Repository 목 구현을 써야 한다.');
  }
  final baseUrl = apiBaseUrl(
    env,
    androidEmulator: const bool.fromEnvironment('PMART_ANDROID_EMULATOR'),
  );
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
