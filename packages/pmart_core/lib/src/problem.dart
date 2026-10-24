import 'package:meta/meta.dart';

/// RFC 9457 Problem + PMart 확장 멤버 (`_common.yaml` ErrorResponse).
///
/// 분기는 [code] 로만 한다. [title]/[detail] 문자열로 분기하지 않는다.
@immutable
final class Problem {
  const Problem({
    required this.status,
    required this.code,
    this.type = 'about:blank',
    this.title,
    this.detail,
    this.instance,
    this.traceId,
    this.requestId,
    this.retryable = false,
    this.details = const [],
    this.raw = const {},
  });

  factory Problem.fromJson(
    Map<String, dynamic> json, {
    required int httpStatus,
  }) => Problem(
    status: (json['status'] as int?) ?? httpStatus,
    code: (json['code'] as String?) ?? ProblemCode.unknown,
    type: (json['type'] as String?) ?? 'about:blank',
    title: json['title'] as String?,
    detail: json['detail'] as String?,
    instance: json['instance'] as String?,
    traceId: json['traceId'] as String?,
    requestId: json['requestId'] as String?,
    retryable: (json['retryable'] as bool?) ?? false,
    details: [
      for (final d in (json['details'] as List<dynamic>? ?? const []))
        if (d is Map<String, dynamic>)
          ProblemDetail(
            field: d['field'] as String?,
            reason: d['reason'] as String?,
          ),
    ],
    raw: json,
  );

  final int status;
  final String code;
  final String type;
  final String? title;
  final String? detail;
  final String? instance;
  final String? traceId;
  final String? requestId;
  final bool retryable;
  final List<ProblemDetail> details;

  /// 서비스별 확장 필드(예: cartVersion, limit)를 읽기 위한 원본.
  final Map<String, dynamic> raw;

  /// 결과가 불명인 오류인지. 실패로 확정하지 말고 짝 조회로 해소한다.
  bool get isUnknownResult =>
      code == ProblemCode.unknownResult ||
      code == ProblemCode.dependencyUnavailable;
}

@immutable
final class ProblemDetail {
  const ProblemDetail({this.field, this.reason});

  final String? field;
  final String? reason;
}

/// `_common.yaml` ErrorCode + 게이트웨이 코드.
///
/// 서비스별 코드(예: SKU_NOT_SALEABLE)는 문자열 그대로 온다.
abstract final class ProblemCode {
  static const validationFailed = 'VALIDATION_FAILED';
  static const forbidden = 'FORBIDDEN';
  static const notFound = 'NOT_FOUND';
  static const invalidState = 'INVALID_STATE';
  static const versionConflict = 'VERSION_CONFLICT';
  static const idempotencyConflict = 'IDEMPOTENCY_CONFLICT';
  static const configRequired = 'CONFIG_REQUIRED';
  static const insufficientStock = 'INSUFFICIENT_STOCK';
  static const capacityExceeded = 'CAPACITY_EXCEEDED';
  static const dependencyUnavailable = 'DEPENDENCY_UNAVAILABLE';
  static const unknownResult = 'UNKNOWN_RESULT';
  static const unsupportedAction = 'UNSUPPORTED_ACTION';
  static const approvalRequired = 'APPROVAL_REQUIRED';
  static const evidenceRequired = 'EVIDENCE_REQUIRED';
  static const staleVersion = 'STALE_VERSION';
  static const domainRejected = 'DOMAIN_REJECTED';
  static const partialApplied = 'PARTIAL_APPLIED';

  /// 게이트웨이 처리율 제한(429). `_common.yaml` enum 에는 없다.
  static const rateLimited = 'RATE_LIMITED';

  /// Problem 본문이 없거나 code 가 비어 있을 때 클라이언트가 붙이는 값.
  static const unknown = 'CLIENT_UNKNOWN_PROBLEM';
}
