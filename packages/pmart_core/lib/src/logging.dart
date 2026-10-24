import 'package:dio/dio.dart';

/// 요청 로그. 본문과 쿼리 값, 민감 헤더는 남기지 않는다.
///
/// 남기는 것: 메서드, 경로, 상태 코드, 소요 시간, `X-Request-Id`, Problem code.
final class PmartLogInterceptor extends Interceptor {
  PmartLogInterceptor(this.log);

  /// 로그 출력 함수. 앱이 debugPrint·로거를 넘긴다. 크래시 리포트로 보내지 않는다.
  final void Function(String line) log;

  static const _startedAt = 'pmart.log.startedAt';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startedAt] = DateTime.now();
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    log(_line(response.requestOptions, response.statusCode, response.headers));
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    final data = response?.data;
    final code = data is Map ? data['code'] : null;
    log(
      '${_line(err.requestOptions, response?.statusCode, response?.headers)}'
      '${code is String ? ' code=$code' : ''}'
      '${response == null ? ' ${err.type.name}' : ''}',
    );
    handler.next(err);
  }

  String _line(RequestOptions o, int? status, Headers? headers) {
    final started = o.extra[_startedAt];
    final ms = started is DateTime
        ? DateTime.now().difference(started).inMilliseconds
        : null;
    final requestId = headers?.value('x-request-id');
    return '${o.method} ${redactPath(o.uri)} -> ${status ?? '-'}'
        '${ms == null ? '' : ' ${ms}ms'}'
        '${requestId == null ? '' : ' rid=$requestId'}';
  }
}

/// 쿼리 값을 가린다(주소·전화번호 검색어가 들어갈 수 있다).
String redactPath(Uri uri) {
  if (uri.queryParameters.isEmpty) return uri.path;
  final keys = uri.queryParameters.keys.map((k) => '$k=***').join('&');
  return '${uri.path}?$keys';
}

/// 헤더를 로그·오류 보고에 쓸 때 가린다.
Map<String, Object?> redactHeaders(Map<String, Object?> headers) => {
  for (final e in headers.entries)
    e.key: _sensitiveHeaders.contains(e.key.toLowerCase()) ? '***' : e.value,
};

const _sensitiveHeaders = {
  'authorization',
  'cookie',
  'set-cookie',
  'x-device-id',
  'idempotency-key',
};
