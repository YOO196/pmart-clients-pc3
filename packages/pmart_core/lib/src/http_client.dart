import 'package:dio/dio.dart';

import 'auth_tokens.dart';
import 'device_id.dart';
import 'interceptors.dart';
import 'logging.dart';

/// PMart 규약이 적용된 Dio 를 만든다. 생성된 API 클라이언트(pmart_api)는 이 Dio 를 받아 쓴다.
///
/// 인터셉터 순서: 헤더 → 로그 → 401 갱신 → 429/retryable 재시도.
Dio createPmartDio({
  required String baseUrl,
  required String sourceSystem,
  required TokenStore tokens,
  required TokenRefresher refresher,
  DeviceIdProvider? deviceId,
  void Function()? onSessionExpired,
  void Function(String line)? log,
  Duration connectTimeout = const Duration(seconds: 5),
  Duration receiveTimeout = const Duration(seconds: 15),
  HttpClientAdapter? adapter,
  Delay? delay,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    ),
  );
  if (adapter != null) dio.httpClientAdapter = adapter;
  dio.interceptors.addAll([
    PmartHeadersInterceptor(
      sourceSystem: sourceSystem,
      tokens: tokens,
      deviceId: deviceId,
    ),
    if (log != null) PmartLogInterceptor(log),
    PmartAuthInterceptor(
      dio: dio,
      tokens: tokens,
      refresher: refresher,
      onSessionExpired: onSessionExpired,
    ),
    PmartRetryInterceptor(dio: dio, delay: delay),
  ]);
  return dio;
}
