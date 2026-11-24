import 'package:dio/dio.dart';
import 'package:pmart_api_claim/pmart_api_claim.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../domain/claims.dart';

/// 취소 접수·조회·철회. 실패는 [PmartFailure] 로 던진다.
abstract interface class ClaimsRepository {
  /// `POST /claims`(CANCEL). 접수는 취소 완료가 아니다. 같은 키·같은 본문 재전송은 기존 클레임을 준다.
  Future<ClaimView> requestCancel(
    String orderId,
    List<CancelLine> lines,
    CancelReason reason, {
    String? detail,
    required IdempotencyKey key,
  });

  Future<ClaimView> get(String claimId);

  /// 이 주문의 처리 내역 목록(`GET /claims?orderId=`, 최근 순). 주문 상세의 `claims` 는 서버가 아직 비워 보낸다
  /// (백엔드 안내 2026-10-31 주문 취소 §6). 실패는 던진다(빈 목록으로 바꾸지 않는다).
  Future<List<ClaimSummaryView>> listForOrder(String orderId);

  /// 내 취소·반품 목록(`GET /claims`, claim 0.6.0 BR-33 — 고객 토큰이면 본인 것만, 최근 순).
  /// [cursor] 는 앞 쪽 `nextCursor`. 실패는 던진다(빈 목록으로 바꾸지 않는다).
  Future<MyClaimsPage> listMine({String? cursor});

  /// 접수 결과를 모를 때의 짝 조회: 이 주문의 살아 있는 취소 클레임(철회·거절 제외, 최근 것).
  /// `GET /claims?orderId=&type=CANCEL`. 없으면 null.
  Future<ClaimView?> findActiveCancel(String orderId);

  /// `POST /claims/{id}/withdrawals`(202). 결과는 [withdrawal] 로 조회한다.
  Future<void> withdraw(
    String claimId, {
    required int expectedVersion,
    required IdempotencyKey key,
  });

  Future<RequestState> withdrawal(String claimId, IdempotencyKey key);

  /// 반품 회수비 결제가 실패한 뒤 새 결제 시도 — `POST /claims/{id}/fee-payment-attempts`(본문 없음, claim 0.2.0).
  /// 새 `paymentAttemptId` 가 든 클레임을 준다. 기한 지남·결제 대기 아님 409, 남의 것 404.
  Future<ClaimView> retryFeePayment(
    String claimId, {
    required IdempotencyKey key,
  });
}

final class ApiClaimsRepository implements ClaimsRepository {
  ApiClaimsRepository(Dio dio)
    : _claims = api.PmartApiClaim(dio: dio).getClaimsApi();

  final api.ClaimsApi _claims;

  @override
  Future<ClaimView> requestCancel(
    String orderId,
    List<CancelLine> lines,
    CancelReason reason, {
    String? detail,
    required IdempotencyKey key,
  }) async {
    final res = await pmartGuard(
      () => _claims.createClaim(
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        createClaimRequest: api.CreateClaimRequest(
          orderId: orderId,
          type: api.ClaimType.CANCEL,
          lines: [
            for (final l in lines)
              api.ClaimLineRequest(orderLineId: l.orderLineId, qty: l.qty),
          ],
          reason: switch (reason) {
            CancelReason.changeOfMind => api.ClaimReason.CHANGE_OF_MIND,
            CancelReason.addressError => api.ClaimReason.ADDRESS_ERROR,
            CancelReason.lateDelivery => api.ClaimReason.LATE_DELIVERY,
            CancelReason.other => api.ClaimReason.OTHER,
          },
          reasonDetail: detail,
          channel: api.CreateClaimRequestChannelEnum.CUSTOMER_APP,
        ),
        extra: commandOptions(key).extra,
      ),
    );
    return claimFromContract(
      res.data ?? (throw UnknownResultFailure(requestId: key.value)),
    );
  }

  @override
  Future<ClaimView> get(String claimId) async {
    final res = await pmartGuard(() => _claims.getClaim(claimId: claimId));
    return claimFromContract(
      res.data ?? (throw const ContractViolationFailure('Claim 본문 없음')),
    );
  }

  @override
  Future<List<ClaimSummaryView>> listForOrder(String orderId) async {
    final res = await pmartGuard(() => _claims.listClaims(orderId: orderId));
    final items =
        res.data?.items ??
        (throw const ContractViolationFailure('ClaimList 본문 없음'));
    return [
      for (final s in items) ?claimSummaryFromContract(s, orderId: orderId),
    ];
  }

  /// 한 쪽 크기. 서버 기본 50 대신 화면 두세 쪽 분량.
  static const myClaimsPageSize = 20;

  @override
  Future<MyClaimsPage> listMine({String? cursor}) async {
    final res = await pmartGuard(
      () => _claims.listClaims(size: myClaimsPageSize, cursor: cursor),
    );
    final body =
        res.data ?? (throw const ContractViolationFailure('ClaimList 본문 없음'));
    final items =
        body.items ?? (throw const ContractViolationFailure('ClaimList 본문 없음'));
    return MyClaimsPage(
      items: [for (final s in items) ?claimSummaryFromContract(s)],
      nextCursor: body.page?.nextCursor,
    );
  }

  @override
  Future<ClaimView?> findActiveCancel(String orderId) async {
    final res = await pmartGuard(
      () => _claims.listClaims(orderId: orderId, type: api.ClaimType.CANCEL),
    );
    final items =
        res.data?.items ??
        (throw const ContractViolationFailure('ClaimList 본문 없음'));
    // 서버는 최근 순으로 준다(handoff 2026-10-31 §6).
    for (final s in items) {
      final id = s.claimId;
      if (id == null || s.orderId != orderId) continue;
      if (s.state == api.ClaimState.WITHDRAWN ||
          s.state == api.ClaimState.REJECTED) {
        continue;
      }
      return get(id);
    }
    return null;
  }

  @override
  Future<void> withdraw(
    String claimId, {
    required int expectedVersion,
    required IdempotencyKey key,
  }) async {
    await pmartGuard(
      () => _claims.createClaimWithdrawal(
        claimId: claimId,
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        xExpectedVersion: expectedVersion,
        extra: commandOptions(key, expectedVersion: expectedVersion).extra,
      ),
    );
  }

  @override
  Future<RequestState> withdrawal(String claimId, IdempotencyKey key) async {
    try {
      final res = await pmartGuard(
        () =>
            _claims.getClaimWithdrawal(claimId: claimId, requestId: key.value),
      );
      return requestStateOf(res.data?.state?.value);
    } on ProblemFailure catch (f) {
      if (f.problem.code == ProblemCode.notFound) return RequestState.unknown;
      rethrow;
    }
  }

  @override
  Future<ClaimView> retryFeePayment(
    String claimId, {
    required IdempotencyKey key,
  }) async {
    final res = await pmartGuard(
      () => _claims.createReturnFeePaymentAttempt(
        claimId: claimId,
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        extra: commandOptions(key).extra,
      ),
    );
    return claimFromContract(
      res.data ?? (throw const ContractViolationFailure('회수비 결제 다시 시도 본문 없음')),
    );
  }
}

RequestState requestStateOf(String? wire) => switch (wire) {
  'PENDING' => RequestState.pending,
  'WITHDRAWN' || 'CONFIRMED' => RequestState.confirmed,
  'REJECTED' => RequestState.rejected,
  _ => RequestState.unknown,
};

/// 목록 줄 → 앱 값. claimId 가 없으면 null(줄을 뺀다).
ClaimSummaryView? claimSummaryFromContract(
  api.ClaimSummary s, {
  String? orderId,
}) {
  final id = s.claimId;
  if (id == null) return null;
  return ClaimSummaryView(
    claimId: id,
    orderId: s.orderId ?? orderId ?? '',
    type: claimTypeFromWire(s.type?.value),
    state: claimStateFromWire(s.state?.value),
    openedAt: s.openedAt,
    refund: switch (s.refund) {
      null => null,
      final r => ClaimRefundSummaryView(
        state: switch (r.state) {
          api.ClaimRefundSummaryStateEnum.NONE => ClaimRefundState.none,
          api.ClaimRefundSummaryStateEnum.IN_PROGRESS =>
            ClaimRefundState.inProgress,
          api.ClaimRefundSummaryStateEnum.COMPLETED =>
            ClaimRefundState.completed,
          api.ClaimRefundSummaryStateEnum.FAILED => ClaimRefundState.failed,
        },
        requestedAmount: r.requestedAmount,
        refundedAmount: r.refundedAmount,
        completedAt: r.completedAt,
      ),
    },
  );
}

ClaimView claimFromContract(api.Claim c) => ClaimView(
  claimId: c.claimId ?? (throw const ContractViolationFailure('claimId 없음')),
  version: c.version ?? 0,
  orderId: c.orderId ?? '',
  type: claimTypeFromWire(c.type?.value),
  state: claimStateFromWire(c.state?.value),
  autoCancelled: c.reason == api.ClaimReason.FULFILLMENT_REJECTED,
  openedAt: c.openedAt,
  feePayment: switch (c.feePayment) {
    null => null,
    final f => ReturnFeeView(
      state: switch (f.state) {
        api.ReturnFeePaymentStateEnum.WAITING => ReturnFeeState.waiting,
        api.ReturnFeePaymentStateEnum.PAID => ReturnFeeState.paid,
        api.ReturnFeePaymentStateEnum.UNPAID => ReturnFeeState.unpaid,
        api.ReturnFeePaymentStateEnum.LATE_CANCEL_PENDING ||
        api.ReturnFeePaymentStateEnum.LATE_CANCELLED ||
        api.ReturnFeePaymentStateEnum.LATE_CANCEL_FAILED =>
          ReturnFeeState.lateCancel,
        _ => ReturnFeeState.unknown,
      },
      amount: f.amount,
      orderName: switch (f.orderName?.trim()) {
        final n? when n.isNotEmpty => n,
        _ => null,
      },
      paymentAttemptId: switch (f.paymentAttemptId?.trim()) {
        final a? when a.isNotEmpty => a,
        _ => null,
      },
      deadlineAt: f.deadlineAt,
      refunded:
          f.refundDecision == api.ReturnFeePaymentRefundDecisionEnum.REFUND,
    ),
  },
  lines: [
    for (final l in c.lines ?? const <api.ClaimLine>[])
      if (l.orderLineId != null)
        ClaimLineView(
          orderLineId: l.orderLineId!,
          sku: l.sku,
          productName: _blankToNull(l.productName),
          optionLabel: _blankToNull(l.optionLabel),
          imageUrl: _blankToNull(l.imageUrl),
          requestedQty: l.requestedQty,
          approvedQty: l.approvedQty,
          decision: switch (l.decision?.value) {
            'APPROVED' => LineDecision.approved,
            'REJECTED' => LineDecision.rejected,
            _ => LineDecision.pending,
          },
          rejectReason: l.rejectReason,
          refundAmount: l.refundAmount,
        ),
  ],
  refunds: [
    for (final r in c.refunds ?? const <api.Refund>[])
      RefundView(
        state: switch (r.state) {
          api.RefundState.RECEIVED => RefundState.received,
          api.RefundState.APPROVED => RefundState.approved,
          api.RefundState.PENDING_EXECUTION => RefundState.pendingExecution,
          api.RefundState.PG_PENDING => RefundState.pgPending,
          api.RefundState.COMPLETED => RefundState.completed,
          api.RefundState.FAILED => RefundState.failed,
          _ => RefundState.unknown,
        },
        pgResult: switch (r.pgResult?.value) {
          'SUCCESS' => PgResult.success,
          'FAILED' => PgResult.failed,
          _ => PgResult.unknown,
        },
        amount: r.amount,
        completedAt: r.completedAt,
        returnFee: r.kind == api.RefundKindEnum.RETURN_FEE,
      ),
  ],
);

/// 빈 글자는 없는 값으로 본다.
String? _blankToNull(String? v) => switch (v?.trim()) {
  final t? when t.isNotEmpty => t,
  _ => null,
};
