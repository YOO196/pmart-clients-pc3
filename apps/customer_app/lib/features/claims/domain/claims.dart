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
}
