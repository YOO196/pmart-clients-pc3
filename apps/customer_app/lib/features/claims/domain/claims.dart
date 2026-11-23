import 'package:flutter/foundation.dart';

/// 클레임 상태. CANCEL 은 OPENED → STOP_PENDING → IN_PROGRESS → CLOSED 또는 REJECTED.
enum ClaimState {
  opened,
  underReview,
  stopPending,
  decided,
  inProgress,
  closed,
  withdrawn,
  rejected,

  /// 반품 회수비 결제 대기(claim 0.2.0) — 결제하면 회수를 시작한다.
  feePending,

  /// 회수가 두 번 실패했다 — 고객센터가 다시 연락한다.
  recoveryFailed,

  /// 반품이 취소됐다(회수비 기한 지남·반품 기한 지남·상담원 취소).
  cancelled,
  unknown,
}

enum ClaimType { cancel, returnItems, exchange, unknown }

/// 취소 사유(계약 ClaimReason 중 취소에 맞는 것만 고르게 한다).
enum CancelReason { changeOfMind, addressError, lateDelivery, other }

enum LineDecision { pending, approved, rejected }

@immutable
class ClaimLineView {
  const ClaimLineView({
    required this.orderLineId,
    required this.decision,
    this.sku,
    this.requestedQty,
    this.approvedQty,
    this.rejectReason,
    this.refundAmount,
  });

  final String orderLineId;
  final String? sku;
  final int? requestedQty;
  final int? approvedQty;
  final LineDecision decision;
  final String? rejectReason;
  final int? refundAmount;
}

enum RefundState {
  received,
  approved,
  pendingExecution,
  pgPending,
  completed,
  failed,
  unknown,
}

enum PgResult { success, failed, unknown }

@immutable
class RefundView {
  const RefundView({
    required this.state,
    required this.pgResult,
    this.amount,
    this.completedAt,
    this.returnFee = false,
  });

  final RefundState state;
  final PgResult pgResult;
  final int? amount;
  final DateTime? completedAt;

  /// 낸 반품 회수비를 돌려주는 환불(`kind: RETURN_FEE`, claim 0.3.0). 상품 환불이 아니다.
  final bool returnFee;

  /// "환불 완료"는 PG 성공일 때만이다.
  bool get done =>
      state == RefundState.completed && pgResult == PgResult.success;
}

@immutable
/// 클레임 목록 항목(`GET /claims?orderId=`). 주문 상세의 `claims` 는 서버가 아직 비워 보내므로
/// 주문의 처리 내역은 이 목록으로 보인다(백엔드 안내 2026-10-31 주문 취소 §6).
@immutable
class ClaimSummaryView {
  const ClaimSummaryView({
    required this.claimId,
    required this.orderId,
    required this.type,
    required this.state,
    this.openedAt,
    this.refund,
  });

  final String claimId;
  final String orderId;
  final ClaimType type;
  final ClaimState state;
  final DateTime? openedAt;

  /// 상품 환불 요약(claim 0.6.0, BR-33). 서버가 주지 않으면 null — "환불 없음"으로 바꾸지 않는다.
  final ClaimRefundSummaryView? refund;
}

/// 클레임 목록 줄의 환불 요약 상태. 진행 중은 PG 결과 전이라 완료로 보이지 않는다.
enum ClaimRefundState { none, inProgress, completed, failed, unknown }

@immutable
class ClaimRefundSummaryView {
  const ClaimRefundSummaryView({
    required this.state,
    required this.requestedAmount,
    required this.refundedAmount,
    this.completedAt,
  });

  final ClaimRefundState state;

  /// 환불하기로 한 금액 합(서버 값).
  final int requestedAmount;

  /// PG 가 성공한 금액 합(서버 값).
  final int refundedAmount;
  final DateTime? completedAt;
}

/// 내 취소·반품 목록 한 쪽(`GET /claims`, 고객 토큰이면 본인 것만, 최근 순).
@immutable
class MyClaimsPage {
  const MyClaimsPage({required this.items, this.nextCursor});

  final List<ClaimSummaryView> items;

  /// 다음 쪽 커서. null 이면 끝.
  final String? nextCursor;
}

/// 계약 ClaimType 문자열 → 앱 값. 모르는 값은 unknown.
ClaimType claimTypeFromWire(String? wire) => switch (wire) {
  'CANCEL' => ClaimType.cancel,
  'RETURN' => ClaimType.returnItems,
  'EXCHANGE' => ClaimType.exchange,
  _ => ClaimType.unknown,
};

/// 계약 ClaimState 문자열 → 앱 값. 모르는 값은 unknown.
ClaimState claimStateFromWire(String? wire) => switch (wire) {
  'OPENED' => ClaimState.opened,
  'UNDER_REVIEW' => ClaimState.underReview,
  'STOP_PENDING' => ClaimState.stopPending,
  'DECIDED' => ClaimState.decided,
  'IN_PROGRESS' => ClaimState.inProgress,
  'CLOSED' => ClaimState.closed,
  'WITHDRAWN' => ClaimState.withdrawn,
  'REJECTED' => ClaimState.rejected,
  'FEE_PENDING' => ClaimState.feePending,
  'RECOVERY_FAILED' => ClaimState.recoveryFailed,
  'CANCELLED' => ClaimState.cancelled,
  _ => ClaimState.unknown,
};

/// 반품 회수비 결제 상태(계약 `ReturnFeePayment.state`).
enum ReturnFeeState {
  /// 결제 대기 — 기한 안에 결제하면 회수를 시작한다.
  waiting,
  paid,

  /// 기한 안에 결제하지 않았다(반품 취소).
  unpaid,

  /// 기한 뒤 승인이 와서 서버가 그 결제를 취소하는 중·취소함·취소 실패(서버가 처리).
  lateCancel,
  unknown,
}

/// 고객 사유 반품의 회수비 결제(claim 0.2.0 `Claim.feePayment`). 회사 잘못 반품은 없다(null).
@immutable
class ReturnFeeView {
  const ReturnFeeView({
    required this.state,
    this.amount,
    this.orderName,
    this.paymentAttemptId,
    this.deadlineAt,
    this.refunded = false,
  });

  final ReturnFeeState state;

  /// 서버 금액(지금 9,000원). 앱이 계산하지 않는다.
  final int? amount;

  /// 결제위젯 주문명. 없으면 앱 문구.
  final String? orderName;

  /// 결제위젯 `orderId` 로 그대로 쓴다. 비었으면 결제 시도 준비 중 — 잠시 뒤 다시 읽는다.
  final String? paymentAttemptId;

  /// 결제 기한(24시간). 지나면 서버가 반품을 취소한다 — 앱은 표시·결제창 열기 판단에만 쓴다.
  final DateTime? deadlineAt;

  /// 반품 취소 때 낸 회수비를 돌려주기로 했다(`refundDecision` REFUND, claim 0.3.0).
  final bool refunded;
}

@immutable
class ClaimView {
  const ClaimView({
    required this.claimId,
    required this.version,
    required this.orderId,
    required this.type,
    required this.state,
    required this.lines,
    required this.refunds,
    this.autoCancelled = false,
    this.feePayment,
    this.openedAt,
  });

  /// 접수 시각(계약 `Claim.openedAt`). 모르면 null — 상세 상태 카드의 "접수" 날짜에 쓴다(초안 08-B).
  final DateTime? openedAt;

  final String claimId;
  final int version;
  final String orderId;
  final ClaimType type;
  final ClaimState state;
  final List<ClaimLineView> lines;
  final List<RefundView> refunds;

  /// MFC 가 작업을 받지 못해 시스템이 자동으로 연 전체 취소(`reason = FULFILLMENT_REJECTED`, 백엔드 공지 2026-11-07).
  /// 고객이 접수한 클레임이 아니므로 "요청하신" 같은 문구를 쓰지 않는다.
  final bool autoCancelled;

  /// 반품 회수비 결제. 회사 잘못 반품·취소·교환은 null.
  final ReturnFeeView? feePayment;

  /// 회수비를 결제해야 반품이 진행된다.
  bool get awaitingFee =>
      state == ClaimState.feePending &&
      feePayment?.state == ReturnFeeState.waiting;

  /// 철회는 심사 전(접수 상태)까지만 고를 수 있다. 최종 판정은 서버.
  bool get canWithdraw => state == ClaimState.opened;
}

@immutable
class CancelLine {
  const CancelLine({required this.orderLineId, required this.qty});

  final String orderLineId;
  final int qty;
}

/// 철회·예약시간 변경 같은 비동기 요청의 결과 조회 상태.
enum RequestState { pending, confirmed, rejected, unknown }

/// 예약 시간 변경 결과(`GET /orders/{id}/reservation-time-changes/{requestId}`, order 0.10.0).
/// REJECTED 면 기존 시간 그대로이고 [reason] 이 원인 코드(CAPACITY_EXCEEDED·SLOT_NOT_SELECTABLE·
/// OPERATION_RESTRICTED·LOT_EXPIRY_NOT_MET·PREPARATION_STARTED 등 — 모르는 코드도 올 수 있다).
@immutable
class TimeChangeResult {
  const TimeChangeResult(this.state, {this.reason});

  final RequestState state;
  final String? reason;
}

/// 예약 시간 변경의 요청·결과 거절 코드.
abstract final class TimeChangeCode {
  static const notScheduled = 'NOT_SCHEDULED';
  static const sameSlot = 'SAME_SLOT';
  static const inProgress = 'TIME_CHANGE_IN_PROGRESS';
  static const capacityExceeded = 'CAPACITY_EXCEEDED';
  static const slotNotSelectable = 'SLOT_NOT_SELECTABLE';
  static const operationRestricted = 'OPERATION_RESTRICTED';
  static const lotExpiryNotMet = 'LOT_EXPIRY_NOT_MET';
  static const preparationStarted = 'PREPARATION_STARTED';
}

abstract final class ClaimProblemCode {
  static const orderNotCancellable = 'ORDER_NOT_CANCELLABLE';
  static const quantityExceedsAvailable = 'QUANTITY_EXCEEDS_AVAILABLE';
  static const duplicateClaim = 'DUPLICATE_CLAIM';
  static const invalidState = 'INVALID_STATE';
  static const partialCancelNotAllowed = 'PARTIAL_CANCEL_NOT_ALLOWED';
  static const unsupportedAction = 'UNSUPPORTED_ACTION';

  /// 앱 내부 표시: 서버가 501(미구현)로 답했다. 서버 code 가 아니다.
  static const notImplemented = 'CLIENT_NOT_IMPLEMENTED';
}

/// 고객 취소는 주문 전체만(백엔드 handoff 2026-10-31 주문 취소 §2, OMS 8.4).
/// 모든 행 × 서버가 준 미이행 수량. 미이행 0 인 행은 뺀다.
/// 미이행 수량을 모르는 행이 있으면 null — 전체 취소 본문을 만들 수 없다(추측해 채우지 않는다).
List<CancelLine>? wholeOrderCancelLines(
  Iterable<({String orderLineId, int? unfulfilledQty})> lines,
) {
  final out = <CancelLine>[];
  for (final l in lines) {
    final q = l.unfulfilledQty;
    if (q == null) return null;
    if (q > 0) out.add(CancelLine(orderLineId: l.orderLineId, qty: q));
  }
  return out;
}

/// 더 바뀌지 않는 클레임 상태. 이 상태가 되면 진행 조회를 멈춘다.
bool isClaimSettled(ClaimState s) =>
    s == ClaimState.closed ||
    s == ClaimState.rejected ||
    s == ClaimState.withdrawn ||
    s == ClaimState.cancelled;
