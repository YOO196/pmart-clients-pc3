import 'package:flutter/foundation.dart';

/// 회원 탈퇴 상태(customer 0.12.0 `Withdrawal.state`, ADR-0077).
enum WithdrawalState {
  pending,
  checkingObligations,
  blockedByObligations,
  completing,
  completed,
  revoked,
  unknown;

  static WithdrawalState fromWire(String? v) => switch (v) {
    'PENDING' => pending,
    'CHECKING_OBLIGATIONS' => checkingObligations,
    'BLOCKED_BY_OBLIGATIONS' => blockedByObligations,
    'COMPLETING' => completing,
    'COMPLETED' => completed,
    'REVOKED' => revoked,
    // 모르는 값은 "확인 중"으로 — 끝났다고도 안 끝났다고도 하지 않는다.
    _ => unknown,
  };

  /// 탈퇴가 끝났다. 이 뒤 토큰은 더 쓸 수 없다.
  bool get done => this == completed;

  /// 접수됐고 아직 끝나지 않았다(철회할 수 있다). 완료·철회가 아니면 모두.
  bool get waiting => this != completed && this != revoked;
}

/// 탈퇴를 막고 있는 일의 종류(`openObligations[].kind`). 모르는 값은 [other] — 사유를 지어내지 않는다.
enum ObligationKind {
  orderInProgress,
  paymentUnknown,
  claimInProgress,
  refundInProgress,
  other;

  static ObligationKind fromWire(String? v) => switch (v) {
    'ORDER_IN_PROGRESS' => orderInProgress,
    'PAYMENT_UNKNOWN' => paymentUnknown,
    'CLAIM_IN_PROGRESS' => claimInProgress,
    'REFUND_IN_PROGRESS' => refundInProgress,
    _ => other,
  };

  /// `ref` 가 주문 ID 인 종류(주문 상세로 보낸다). 나머지 둘은 클레임 ID.
  bool get refersToOrder => this == orderInProgress || this == paymentUnknown;
  bool get refersToClaim => this == claimInProgress || this == refundInProgress;
}

@immutable
class WithdrawalObligation {
  const WithdrawalObligation({required this.kind, this.ref});

  final ObligationKind kind;

  /// 주문 ID 또는 클레임 ID(종류에 따라). 없을 수 있다.
  final String? ref;
}

@immutable
class Withdrawal {
  const Withdrawal({
    required this.withdrawalId,
    required this.state,
    required this.requestedAt,
    this.completedAt,
    this.lastCheckedAt,
    this.obligations = const [],
  });

  final String withdrawalId;
  final WithdrawalState state;
  final DateTime requestedAt;
  final DateTime? completedAt;

  /// 서버가 마지막으로 의무(진행 중 주문·환불)를 확인한 시각. 서버가 10분마다 다시 본다.
  final DateTime? lastCheckedAt;
  final List<WithdrawalObligation> obligations;
}

/// 탈퇴 사유(선택). 코드는 앱이 정한 값(`reasonCode`, 최대 40자) — 서버는 그대로 저장만 한다.
enum WithdrawalReason {
  rarelyUse('RARELY_USE'),
  delivery('DELIVERY'),
  products('PRODUCTS'),
  price('PRICE'),
  privacy('PRIVACY'),
  other('OTHER');

  const WithdrawalReason(this.code);

  final String code;
}

/// 사유 글 최대 길이(계약 `reasonText` maxLength).
const withdrawalReasonTextMax = 500;

/// 탈퇴·철회 요청의 거절 코드(Problem `code`).
abstract final class WithdrawalProblemCode {
  /// 재인증 토큰을 제공자가 거절했다 — 다시 로그인.
  static const providerRejected = 'PROVIDER_REJECTED';

  /// 이 계정에 연결된 소셜이 아니다.
  static const reauthenticationMismatch = 'REAUTHENTICATION_MISMATCH';

  /// 이미 신청했거나(접수), 이미 끝나 철회할 수 없다.
  static const invalidState = 'INVALID_STATE';
}
