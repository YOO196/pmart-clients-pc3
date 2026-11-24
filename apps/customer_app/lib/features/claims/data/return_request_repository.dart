import 'package:pmart_core/pmart_core.dart';

import '../../../shared/order_status.dart';
import '../../orders/data/mock_orders_repository.dart';
import '../domain/claims.dart';
import '../domain/return_request.dart';
import 'mock_claims_repository.dart';

/// 고객 반품·교환 신청(레퍼런스 12). 계약에 고객 접수·자격 조회가 없어(claim 0.2.0 — 인계 뒤 반품은 고객센터만)
/// 지금은 목에서만 쓴다. BR-95.
abstract interface class ReturnRequestRepository {
  /// 이 주문의 신청 자격·품목. 실패는 던진다(빈 목록으로 바꾸지 않는다).
  Future<ReturnEligibility> eligibility(String orderId);

  /// 신청 접수. 접수는 승인이 아니다 — 처리 내역(클레임 상세)이 진행을 보인다. 같은 키 재전송은 같은 클레임.
  Future<ClaimView> submit(
    ReturnRequestDraft draft, {
    required IdempotencyKey key,
  });
}

/// 실서버: 계약이 없어 앱에서 신청할 수 없다고 답한다(화면은 흐린 칸 + 고객센터 문의로 잇는다). BR-95.
final class UnavailableReturnRequestRepository
    implements ReturnRequestRepository {
  const UnavailableReturnRequestRepository();

  @override
  Future<ReturnEligibility> eligibility(String orderId) async =>
      ReturnEligibility(
        orderId: orderId,
        returnAllowed: false,
        exchangeAllowed: false,
        lines: const [],
        unavailable: const [],
      );

  @override
  Future<ClaimView> submit(
    ReturnRequestDraft draft, {
    required IdempotencyKey key,
  }) => throw const ProblemFailure(
    Problem(status: 422, code: 'UNSUPPORTED_ACTION'),
  );
}

/// 목: 주문 목의 전달 완료 수량으로 자격을 만들고, 접수하면 클레임 목에 반품·교환 클레임을 넣는다.
/// 변심 사유면 회수비 결제 대기(FEE_PENDING) — 지금 처리 내역 화면의 회수비 결제가 그대로 이어진다.
final class MockReturnRequestRepository implements ReturnRequestRepository {
  MockReturnRequestRepository({
    required this.orders,
    required this.claims,
    this.latency = const Duration(milliseconds: 300),
  });

  final MockOrdersRepository orders;
  final MockClaimsRepository claims;
  final Duration latency;

  /// 목 신선식품(변심 신청 불가·신선보장) — 감귤·방울토마토.
  static const freshProducts = {'P-0003', 'P-0004'};

  /// 목 판매 중지 상품(신청 불가 칸).
  final discontinued = <String>{};

  /// 목 배달팁(단순 변심) — 서버 정책 값 흉내.
  int changeOfMindFee = 9000;

  /// 받은 신청(시험용).
  final submitted = <ReturnRequestDraft>[];

  final _byKey = <String, String>{};

  @override
  Future<ReturnEligibility> eligibility(String orderId) async {
    await Future<void>.delayed(latency);
    final order = await orders.get(orderId);
    final completed = order.status == OrderStatus.completed;
    final taken = claims.takenQtyByLine(orderId);
    final lines = <ReturnableLine>[];
    final unavailable = <UnavailableLine>[];
    for (final l in order.lines) {
      final id = l.orderLineId;
      final delivered = l.deliveredQty ?? 0;
      final left = delivered - (taken[id] ?? 0);
      if (left <= 0 || discontinued.contains(l.productId)) {
        unavailable.add(
          UnavailableLine(
            orderLineId: id,
            title: l.title,
            imageUrl: l.imageUrl,
            unitPrice: l.unitPrice,
            lineAmount: l.lineAmount,
            qty: l.originalQty ?? delivered,
          ),
        );
        continue;
      }
      final fresh = freshProducts.contains(l.productId);
      lines.add(
        ReturnableLine(
          orderLineId: id,
          productId: l.productId,
          title: l.title,
          imageUrl: l.imageUrl,
          unitPrice: l.unitPrice,
          lineAmount: l.lineAmount,
          orderedQty: delivered,
          requestableQty: left,
          changeOfMindAllowed: !fresh,
          freshGuarantee: fresh,
        ),
      );
    }
    final any = completed && lines.isNotEmpty;
    return ReturnEligibility(
      orderId: orderId,
      // 반품은 고객센터로만(BR-95 회신 2026-11-25). 목도 앱 반품 접수를 열지 않는다.
      returnAllowed: false,
      exchangeAllowed: any,
      lines: lines,
      unavailable: unavailable,
      changeOfMindFee: changeOfMindFee,
      pickupAddress: order.shippingAddress,
    );
  }

  @override
  Future<ClaimView> submit(
    ReturnRequestDraft draft, {
    required IdempotencyKey key,
  }) async {
    await Future<void>.delayed(latency);
    final id =
        _byKey[key.value] ??
        claims.fileCustomerReturn(
          orderId: draft.orderId,
          exchange: draft.type == ReturnRequestType.exchange,
          lines: draft.lines,
          reason: wireReason(draft.reason),
          fee: draft.reason.group == ReturnReasonGroup.changeOfMind
              ? changeOfMindFee
              : null,
        );
    if (!_byKey.containsKey(key.value)) submitted.add(draft);
    _byKey[key.value] = id;
    return claims.get(id);
  }

  /// 앱 이유 → 계약 ClaimReason(BR-95 요청서와 같은 대응).
  static String wireReason(ReturnReason r) => switch (r) {
    ReturnReason.dislike || ReturnReason.wrongOrder => 'CHANGE_OF_MIND',
    ReturnReason.wrongAddress => 'ADDRESS_ERROR',
    ReturnReason.notAsDescribed => 'NOT_AS_ADVERTISED',
    ReturnReason.malfunction ||
    ReturnReason.spoiled ||
    ReturnReason.foreignObject ||
    ReturnReason.expired => 'DEFECT',
    ReturnReason.damaged => 'DAMAGED_IN_DELIVERY',
    ReturnReason.partlyWrong || ReturnReason.allWrong => 'WRONG_ITEM',
    ReturnReason.partlyMissing || ReturnReason.notArrived => 'MISSING_ITEM',
  };
}
