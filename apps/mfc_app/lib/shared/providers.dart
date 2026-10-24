import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

/// `X-Source-System` (값 확정은 BR-08).
const sourceSystem = 'mfc-app';

final envProvider = Provider<PmartEnv>((_) => PmartEnv.fromDefine());

final secureStoreProvider = Provider<SecureKeyValueStore>(
  (_) => FlutterSecureKeyValueStore(),
);

final tokenStoreProvider = Provider<TokenStore>(
  (ref) => TokenStore(ref.watch(secureStoreProvider)),
);

/// 토큰 갱신(`POST /auth/tokens`)이 `X-Device-Id` 를 요구하므로 모든 앱이 보낸다.
final deviceIdProvider = Provider<DeviceIdProvider>(
  (ref) => DeviceIdProvider(ref.watch(secureStoreProvider)),
);

/// 실서버(local) 연동용 Dio. 목 모드에서는 만들지 않는다.
final dioProvider = Provider<Dio>((ref) {
  final env = ref.watch(envProvider);
  if (env == PmartEnv.mock) {
    throw StateError('목 모드는 네트워크를 쓰지 않는다. Repository 목 구현을 써야 한다.');
  }
  return createPmartDio(
    baseUrl: apiBaseUrl(
      env,
      androidEmulator: const bool.fromEnvironment('PMART_ANDROID_EMULATOR'),
    ),
    sourceSystem: sourceSystem,
    tokens: ref.watch(tokenStoreProvider),
    deviceId: ref.watch(deviceIdProvider),
    // BR-02: 라이더·점원 로그인 API 가 계약에 없어 토큰을 받을 수 없다.
    // 갱신은 항상 세션 만료로 끝난다. 계약 반영 후 customer_app 의 authRefresher 와 같은 방식으로 바꾼다.
    refresher: (_) async => null,
    log: kDebugMode ? debugPrint : null,
  );
});
