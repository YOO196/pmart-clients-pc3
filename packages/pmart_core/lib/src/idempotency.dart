import 'package:uuid/uuid.dart';

/// 사용자 행위 1회에 대응하는 멱등 키.
///
/// - 새 클릭(새 행위) → [IdempotencyKey.generate] 로 새 키
/// - 재전송·재시도 → 같은 인스턴스를 다시 넘긴다
///
/// 계약상 이 값이 곧 `requestId` 이며 짝 조회 경로(`…/{requestId}`)의 키가 된다.
final class IdempotencyKey {
  IdempotencyKey(this.value) {
    if (value.isEmpty || value.length > maxLength) {
      throw ArgumentError.value(value, 'value', '1~$maxLength 자');
    }
  }

  factory IdempotencyKey.generate() => IdempotencyKey(_uuid.v4());

  /// `_common.yaml` IdempotencyKey: maxLength 128.
  static const maxLength = 128;
  static const _uuid = Uuid();

  final String value;

  @override
  bool operator ==(Object other) =>
      other is IdempotencyKey && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'IdempotencyKey($value)';
}
