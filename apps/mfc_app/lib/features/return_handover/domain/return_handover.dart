import 'package:flutter/foundation.dart';

/// 회수 배송의 목적(계약 `ReturnHandover.purpose`). 모르는 값은 [other].
enum ReturnPurpose {
  claimReturn,
  misdeliveryRecovery,
  failedDeliveryReturn,
  other,
}

/// MFC 반납 인증번호(delivery-execution 0.28.0 `ReturnHandover`).
///
/// 라이더가 회수품을 MFC 에 가져오면 직원이 이 4자리 번호를 알려 주고, 라이더가 라이더 앱에 넣어야 반납이 끝난다.
/// 번호는 화면에만 보인다 — 로그·분석 이벤트에 남기지 않는다(계약).
@immutable
class ReturnHandoverView {
  const ReturnHandoverView({
    required this.deliveryId,
    required this.code,
    required this.failedAttempts,
    required this.locked,
    required this.issuedAt,
    required this.state,
    this.deliveryNumber,
    this.purpose = ReturnPurpose.other,
    this.riderId,
  });

  final String deliveryId;

  /// 화면 번호(ADR-0070). 없으면 배송 ID 를 보인다.
  final String? deliveryNumber;
  final ReturnPurpose purpose;
  final String state;

  /// 라이더 이름은 이 응답에 없고, MFC 직원은 라이더 상세(rider-service)를 부를 수 없어 ID 만 보인다.
  final String? riderId;
  final String code;
  final int failedAttempts;

  /// 5번 틀려 잠김 — 새 번호를 내면 풀린다.
  final bool locked;
  final DateTime issuedAt;

  /// 계약 문구가 바뀌어도 번호가 [toString] 으로 새지 않게 가린다.
  @override
  String toString() => 'ReturnHandoverView($deliveryId, locked: $locked)';
}

/// 새 번호 내기(`POST /return-handovers/{deliveryId}/code-reissues`) 결과.
sealed class ReissueOutcome {
  const ReissueOutcome();
}

final class Reissued extends ReissueOutcome {
  const Reissued(this.handover);

  final ReturnHandoverView handover;
}

/// 서버가 거절(409 = 더는 반납을 기다리는 배송이 아님, 403·404 등). 코드로만 나눈다.
final class ReissueRejected extends ReissueOutcome {
  const ReissueRejected(this.code);

  final String code;
}

/// 응답을 잃음 — 같은 키로 다시 보내거나 목록을 다시 본다(이미 바뀌었을 수 있다).
final class ReissueUnknown extends ReissueOutcome {
  const ReissueUnknown();
}
