import 'dart:async';

import 'package:dio/dio.dart';

import 'auth_tokens.dart';
import 'device_id.dart';
import 'failure.dart';
import 'idempotency.dart';
import 'problem.dart';
import 'request_options.dart';

typedef Delay = Future<void> Function(Duration);

Future<void> _realDelay(Duration d) => Future<void>.delayed(d);

/// 공통 요청 헤더.
///
/// - 변경 요청에 멱등 키가 없으면 보내지 않고 거절한다(클라이언트 결함).
/// - `traceparent` 는 게이트웨이가 발급하므로 보내지 않는다.
final class PmartHeadersInterceptor extends Interceptor {
  PmartHeadersInterceptor({
    required this.sourceSystem,
    required this.tokens,
    this.deviceId,
  });

  /// `X-Source-System` 값(예: customer-app). 목록 확정은 BR-08.
  final String sourceSystem;
  final TokenStore tokens;

  /// 고객 앱만 보낸다(소셜 로그인·비회원 장바구니/배송지).
  final DeviceIdProvider? deviceId;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final headers = options.headers;
    headers['X-Source-System'] = sourceSystem;
    // 호출 쪽이 정한 Accept(예: SSE 의 text/event-stream)는 덮지 않는다.
    if (headers['Accept'] == null && headers['accept'] == null) {
      headers['Accept'] = 'application/json, application/problem+json';
    }

    if (isMutation(options)) {
      final key = options.extra[PmartExtra.idempotencyKey];
      if (key is! IdempotencyKey) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.unknown,
            error: StateError(
              '변경 요청에 Idempotency-Key 가 없다: ${options.method} ${options.path}',
            ),
          ),
        );
        return;
      }
      headers['Idempotency-Key'] = key.value;
    }

    final expected = options.extra[PmartExtra.expectedVersion];
    if (expected is int) headers['X-Expected-Version'] = '$expected';

    final device = deviceId;
    if (device != null) headers['X-Device-Id'] = await device.get();

    final access = tokens.accessToken;
    if (options.extra[PmartExtra.public] != true && access != null) {
      headers['Authorization'] = 'Bearer $access';
    }
    handler.next(options);
  }
}

/// 401 → 토큰 갱신 1회(single-flight) → 같은 요청 재전송(같은 멱등 키).
///
/// 갱신이 거절되면 토큰을 지우고 [onSessionExpired] 를 부른 뒤 [SessionExpiredFailure] 로 끝낸다.
final class PmartAuthInterceptor extends Interceptor {
  PmartAuthInterceptor({
    required this.dio,
    required this.tokens,
    required this.refresher,
    this.onSessionExpired,
  });

  final Dio dio;
  final TokenStore tokens;
  final TokenRefresher refresher;
  final void Function()? onSessionExpired;

  Future<bool>? _refreshing;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final unauthorized = err.response?.statusCode == 401;
    if (!unauthorized ||
        options.extra[PmartExtra.public] == true ||
        options.extra[PmartExtra.retriedAfterRefresh] == true) {
      handler.next(err);
      return;
    }

    // 이 요청을 보낸 뒤 다른 요청이 이미 갱신했으면 다시 갱신하지 않는다.
    // (회전된 refresh token 을 또 쓰면 서버가 재사용으로 보고 세션을 폐기한다.)
    final current = tokens.accessToken;
    final sentWith = options.headers['Authorization'];
    final alreadyRefreshed =
        _refreshing == null && current != null && sentWith != 'Bearer $current';

    final bool refreshed;
    try {
      refreshed =
          alreadyRefreshed ||
          await (_refreshing ??= _refresh().whenComplete(
            () => _refreshing = null,
          ));
    } on Object {
      // 갱신 요청 자체가 네트워크 오류: 세션 만료로 단정하지 않고 원래 오류를 넘긴다.
      handler.next(err);
      return;
    }

    if (!refreshed) {
      handler.reject(
        DioException(
          requestOptions: options,
          response: err.response,
          type: DioExceptionType.badResponse,
          error: SessionExpiredFailure(
            requestId: err.response?.headers.value('x-request-id'),
          ),
        ),
      );
      return;
    }

    options.extra[PmartExtra.retriedAfterRefresh] = true;
    try {
      handler.resolve(await dio.fetch<dynamic>(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Future<bool> _refresh() async {
    final refreshToken = await tokens.readRefreshToken();
    if (refreshToken == null) {
      await _expire();
      return false;
    }
    final next = await refresher(refreshToken);
    if (next == null) {
      await _expire();
      return false;
    }
    await tokens.save(next);
    return true;
  }

  Future<void> _expire() async {
    await tokens.clear();
    onSessionExpired?.call();
  }
}

/// 자동 재시도는 두 경우만:
/// - 429: `Retry-After` 만큼 기다린 뒤 같은 요청(같은 멱등 키)
/// - Problem `retryable=true`: 지수 백오프
///
/// 타임아웃·연결 오류는 재시도하지 않는다. 변경 요청이면 결과 불명으로 넘겨 짝 조회한다.
final class PmartRetryInterceptor extends Interceptor {
  PmartRetryInterceptor({
    required this.dio,
    this.maxAttempts = 3,
    this.baseBackoff = const Duration(milliseconds: 500),
    this.maxWait = const Duration(seconds: 30),
    Delay? delay,
    DateTime Function()? now,
  }) : _delay = delay ?? _realDelay,
       _now = now ?? DateTime.now;

  final Dio dio;

  /// 최초 요청을 뺀 재시도 횟수 상한.
  final int maxAttempts;
  final Duration baseBackoff;

  /// `Retry-After` 가 이보다 길면 기다리지 않고 오류로 넘긴다(화면이 안내).
  final Duration maxWait;
  final Delay _delay;
  final DateTime Function() _now;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final attempt = (options.extra[PmartExtra.attempt] as int?) ?? 0;
    final wait = _waitFor(err, attempt);
    if (wait == null || attempt >= maxAttempts) {
      handler.next(err);
      return;
    }
    // 변경 요청은 멱등 키가 있을 때만 재전송한다(헤더 인터셉터가 이미 보장).
    if (isMutation(options) &&
        options.extra[PmartExtra.idempotencyKey] is! IdempotencyKey) {
      handler.next(err);
      return;
    }

    await _delay(wait);
    options.extra[PmartExtra.attempt] = attempt + 1;
    try {
      handler.resolve(await dio.fetch<dynamic>(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Duration? _waitFor(DioException err, int attempt) {
    final response = err.response;
    if (response == null) return null;

    if (response.statusCode == 429) {
      final retryAfter = parseRetryAfter(
        response.headers.value('retry-after'),
        now: _now(),
      );
      final wait = retryAfter ?? _backoff(attempt);
      return wait > maxWait ? null : wait;
    }

    final failure = PmartFailure.fromDioException(err);
    final problem = switch (failure) {
      ProblemFailure(:final problem) => problem,
      // 변경 요청의 결과 불명은 재전송하지 않고 짝 조회로 넘긴다.
      UnknownResultFailure() => null,
      _ => null,
    };
    if (problem != null &&
        problem.retryable &&
        problem.code != ProblemCode.idempotencyConflict) {
      return _backoff(attempt);
    }
    return null;
  }

  Duration _backoff(int attempt) => baseBackoff * (1 << attempt);
}

/// `Retry-After`: 초(delta-seconds) 또는 HTTP-date.
Duration? parseRetryAfter(String? value, {required DateTime now}) {
  if (value == null) return null;
  final trimmed = value.trim();
  final seconds = int.tryParse(trimmed);
  if (seconds != null) return seconds < 0 ? null : Duration(seconds: seconds);
  try {
    final at = HttpDateParser.parse(trimmed);
    final diff = at.difference(now.toUtc());
    return diff.isNegative ? Duration.zero : diff;
  } on FormatException {
    return null;
  }
}

/// RFC 7231 IMF-fixdate(예: `Sun, 06 Nov 1994 08:49:37 GMT`)만 받는다.
abstract final class HttpDateParser {
  static const _months = {
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6, //
    'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
  };

  static DateTime parse(String value) {
    final m = RegExp(
      r'^[A-Za-z]{3}, (\d{2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
    ).firstMatch(value);
    final month = m == null ? null : _months[m.group(2)];
    if (m == null || month == null) {
      throw FormatException('HTTP-date 형식이 아니다', value);
    }
    return DateTime.utc(
      int.parse(m.group(3)!),
      month,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  }
}
