import 'package:flutter/foundation.dart';
import 'package:pmart_core/pmart_core.dart';

/// 현장 명령(검사·적치·이동·반입·계수) 결과. 접수·불명을 성공으로 보이지 않는다.
@immutable
sealed class FieldOutcome<T> {
  const FieldOutcome();
}

/// 서버가 확정(APPLIED, 또는 접수 + 결과 ID). 화면은 이것만 완료로 보인다.
final class FieldDone<T> extends FieldOutcome<T> {
  const FieldDone(this.value);

  final T value;
}

/// 거절 확정. code 로 안내한다.
final class FieldRejected<T> extends FieldOutcome<T> {
  const FieldRejected(this.code);

  final String code;
}

/// 결과를 모른다. 같은 Idempotency-Key 로 다시 보내 확정한다.
final class FieldUnknown<T> extends FieldOutcome<T> {
  const FieldUnknown();
}

/// 전송 실패를 결과로 바꾼다. 재시도 가능한 멱등 충돌·의존 서비스 불가·결과 불명은 같은 키로 다시 보낼 대상.
FieldOutcome<T> fieldFailure<T>(PmartFailure f) => switch (f) {
  UnknownResultFailure() => FieldUnknown<T>(),
  ProblemFailure(:final problem)
      when problem.retryable || problem.isUnknownResult =>
    FieldUnknown<T>(),
  ProblemFailure(:final problem) => FieldRejected<T>(problem.code),
  _ => throw f,
};

/// 계약 CommandResponse.status 4값.
FieldOutcome<String?> fieldCommand(String status, String? resultId) =>
    switch (status) {
      'APPLIED' || 'ACCEPTED' => FieldDone<String?>(resultId),
      'REJECTED' => const FieldRejected<String?>('REJECTED'),
      _ => const FieldUnknown<String?>(),
    };
