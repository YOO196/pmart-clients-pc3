import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:meta/meta.dart';

import 'problem.dart';
import 'request_options.dart';

/// 화면·Repository 가 다루는 연동 실패. dio 예외를 그대로 위로 올리지 않는다.
///
/// 핵심 규칙: 변경 요청의 타임아웃·연결 끊김·5xx·UNKNOWN_RESULT 는 [UnknownResultFailure] 다.
/// "실패"로 확정하지 말고 짝 조회(ResultResolver)로 해소한다.
@immutable
sealed class PmartFailure implements Exception {
  const PmartFailure({this.requestId});

  /// 응답 헤더 `X-Request-Id`(없으면 Problem.requestId). 오류 화면에 표시한다.
  final String? requestId;

  static PmartFailure fromDioException(DioException e) {
    if (e.error is PmartFailure) return e.error! as PmartFailure;

    final mutation = isMutation(e.requestOptions);
    final response = e.response;
    final requestId = response?.headers.value('x-request-id');

    if (e.type == DioExceptionType.cancel) {
      return CancelledFailure(requestId: requestId);
    }

    // 2xx 를 받았는데 생성 모델로 읽지 못했다(필수 필드 누락·형식 불일치).
    // 변경 요청이면 서버는 반영했을 수 있으므로 결과 불명으로 다룬다.
    final httpStatus = response?.statusCode;
    if (e.type == DioExceptionType.unknown &&
        httpStatus != null &&
        httpStatus >= 200 &&
        httpStatus < 300) {
      return mutation
          ? UnknownResultFailure(requestId: requestId, httpStatus: httpStatus)
          : ContractViolationFailure(e.error, requestId: requestId);
    }

    if (response != null) {
      final problem = _parseProblem(response);
      if (problem != null) {
        if (mutation && problem.isUnknownResult) {
          return UnknownResultFailure(
            problem: problem,
            requestId: requestId ?? problem.requestId,
          );
        }
        return ProblemFailure(
          problem,
          requestId: requestId ?? problem.requestId,
        );
      }
      final status = response.statusCode ?? 0;
      if (mutation && status >= 500) {
        return UnknownResultFailure(requestId: requestId, httpStatus: status);
      }
      return UnexpectedResponseFailure(status, requestId: requestId);
    }

    // 응답이 없다: 타임아웃·연결 오류. 변경 요청이면 서버 반영 여부를 알 수 없다.
    if (mutation) {
      return UnknownResultFailure(requestId: requestId, transport: e.type);
    }
    return NetworkFailure(e.type, requestId: requestId);
  }

  static Problem? _parseProblem(Response<dynamic> response) {
    final contentType = response.headers.value(Headers.contentTypeHeader) ?? '';
    if (!contentType.contains('json')) return null;
    final data = response.data;
    final Object? decoded = switch (data) {
      final String s when s.isNotEmpty => _tryDecode(s),
      _ => data,
    };
    if (decoded is! Map<String, dynamic>) return null;
    if (!contentType.contains('problem+json') && decoded['code'] == null) {
      return null;
    }
    return Problem.fromJson(decoded, httpStatus: response.statusCode ?? 0);
  }

  static Object? _tryDecode(String s) {
    try {
      return jsonDecode(s);
    } on FormatException {
      return null;
    }
  }
}

/// 서버가 Problem 으로 확정 응답한 오류. [problem.code] 로 분기한다.
final class ProblemFailure extends PmartFailure {
  const ProblemFailure(this.problem, {super.requestId});

  final Problem problem;

  @override
  String toString() => 'ProblemFailure(${problem.status} ${problem.code})';
}

/// 변경 요청의 결과를 알 수 없음. 같은 키로 짝 조회한다. 사용자에게 재실행을 허용하지 않는다.
final class UnknownResultFailure extends PmartFailure {
  const UnknownResultFailure({
    super.requestId,
    this.problem,
    this.httpStatus,
    this.transport,
  });

  final Problem? problem;
  final int? httpStatus;
  final DioExceptionType? transport;

  @override
  String toString() =>
      'UnknownResultFailure(${problem?.code ?? httpStatus ?? transport})';
}

/// 조회 요청의 네트워크 실패. 화면은 ERROR 로 그린다(빈 목록·0으로 바꾸지 않음).
final class NetworkFailure extends PmartFailure {
  const NetworkFailure(this.type, {super.requestId});

  final DioExceptionType type;

  @override
  String toString() => 'NetworkFailure($type)';
}

/// Problem 형식이 아닌 오류 응답(게이트웨이 HTML 등).
final class UnexpectedResponseFailure extends PmartFailure {
  const UnexpectedResponseFailure(this.httpStatus, {super.requestId});

  final int httpStatus;

  @override
  String toString() => 'UnexpectedResponseFailure($httpStatus)';
}

/// 응답이 계약과 다르다(필수 값 누락·형식 불일치). 빈 값·0으로 메우지 않고 오류로 그린다.
///
/// Repository 가 생성 DTO 를 domain 모델로 바꿀 때 핵심 필드가 없으면 직접 던진다.
final class ContractViolationFailure extends PmartFailure {
  const ContractViolationFailure(this.cause, {super.requestId});

  /// 원인(역직렬화 예외 또는 설명 문자열). 개인정보를 넣지 않는다.
  final Object? cause;

  @override
  String toString() => 'ContractViolationFailure($cause)';
}

/// 호출 측이 취소함.
final class CancelledFailure extends PmartFailure {
  const CancelledFailure({super.requestId});
}

/// 세션 만료(토큰 갱신 실패·재사용 감지). 로그인 화면으로 보낸다.
final class SessionExpiredFailure extends PmartFailure {
  const SessionExpiredFailure({super.requestId});
}

/// dio 호출을 감싸 [PmartFailure] 로 바꾼다.
Future<T> pmartGuard<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on DioException catch (e) {
    throw PmartFailure.fromDioException(e);
  }
}
