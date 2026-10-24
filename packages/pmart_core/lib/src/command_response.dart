import 'package:meta/meta.dart';

/// `_common.yaml` CommandStatus.
///
/// ACCEPTED 는 접수일 뿐 업무 성공이 아니다. UNKNOWN_RESULT 는 원결과 조회로만 해소한다.
enum CommandStatus {
  accepted('ACCEPTED'),
  applied('APPLIED'),
  rejected('REJECTED'),
  unknownResult('UNKNOWN_RESULT');

  const CommandStatus(this.wire);

  final String wire;

  /// 서버가 결과를 확정했는지. 화면에 "완료/거절"로 확정 표시해도 되는 경우만 true.
  bool get isFinal => this == applied || this == rejected;

  static CommandStatus parse(String wire) => values.firstWhere(
    (s) => s.wire == wire,
    orElse: () => throw FormatException('알 수 없는 CommandStatus: $wire'),
  );
}

/// `_common.yaml` CommandResponse.
@immutable
final class CommandResponse {
  const CommandResponse({
    required this.status,
    required this.requestId,
    this.resultId,
    this.appliedQty,
    this.version,
    this.retryable,
    this.nextAction,
    this.occurredAt,
    this.raw = const {},
  });

  factory CommandResponse.fromJson(Map<String, dynamic> json) =>
      CommandResponse(
        status: CommandStatus.parse(json['status'] as String),
        requestId: json['requestId'] as String,
        resultId: json['resultId'] as String?,
        appliedQty: json['appliedQty'] as int?,
        version: json['version'] as int?,
        retryable: json['retryable'] as bool?,
        nextAction: json['nextAction'] as String?,
        occurredAt: switch (json['occurredAt']) {
          final String s => DateTime.parse(s),
          _ => null,
        },
        raw: json,
      );

  final CommandStatus status;
  final String requestId;
  final String? resultId;
  final int? appliedQty;
  final int? version;
  final bool? retryable;

  /// 예: QUERY_RESULT, RE_QUOTE, WAIT_FENCE. 서비스마다 값이 늘 수 있어 문자열로 둔다.
  final String? nextAction;
  final DateTime? occurredAt;

  /// 서비스별 확장 필드(예: cartVersion)를 읽기 위한 원본.
  final Map<String, dynamic> raw;
}
