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
  });

  final RefundState state;
  final PgResult pgResult;
  final int? amount;
  final DateTime? completedAt;

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
  });

  final String claimId;
  final String orderId;
  final ClaimType type;
  final ClaimState state;
  final DateTime? openedAt;
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
  _ => ClaimState.unknown,
};

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
  });

  final String claimId;
  final int version;
  final String orderId;
  final ClaimType type;
  final ClaimState state;
  final List<ClaimLineView> lines;
  final List<RefundView> refunds;

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
    s == ClaimState.withdrawn;
