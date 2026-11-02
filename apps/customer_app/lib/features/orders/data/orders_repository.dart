import 'package:dio/dio.dart';
import 'package:pmart_api_delivery_tracking/pmart_api_delivery_tracking.dart'
    as trk;
import 'package:pmart_api_order/pmart_api_order.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/order_status.dart';
import '../../checkout/data/checkout_repository.dart'
    show quoteFromContract, shippingAddressFromContract;
import '../../checkout/domain/checkout.dart' show ArrivalWindow;
import '../../../shared/providers.dart' show sourceSystem;
import '../../claims/data/claims_repository.dart' show requestStateOf;
import '../../claims/domain/claims.dart' show RequestState;
import '../domain/orders.dart';

/// 주문 조회·배송 도착 예상. 실패는 [PmartFailure] 로 던진다(빈 목록·배송 실패로 바꾸지 않는다).
abstract interface class OrdersRepository {
  Future<OrderPage> list({String? cursor});

  Future<OrderDetail> get(String orderId);

  /// `GET /deliveries/{id}/eta`. 실시간 구독(SSE)은 아직 붙이지 않았다(조회로 갱신).
  Future<DeliveryEtaView> eta(String deliveryId);

  /// `POST /orders/{id}/reservation-time-changes`(202). 상품 준비 전만 받는다(INVALID_STATE).
  Future<void> requestTimeChange(
    String orderId,
    ArrivalWindow window, {
    required int expectedVersion,
    required IdempotencyKey key,
  });

  /// 시간 변경 결과 조회. 불명이면 [RequestState.unknown].
  Future<RequestState> timeChange(String orderId, IdempotencyKey key);
}

final class ApiOrdersRepository implements OrdersRepository {
  ApiOrdersRepository(Dio dio)
    : _orders = api.PmartApiOrder(dio: dio).getOrdersApi(),
      _eta = trk.PmartApiDeliveryTracking(dio: dio).getEtaApi();

  final api.OrdersApi _orders;
  final trk.EtaApi _eta;

  @override
  Future<OrderPage> list({String? cursor}) async {
    final res = await pmartGuard(() => _orders.listOrders(cursor: cursor));
    return orderPageFromContract(
      res.data ?? (throw const ContractViolationFailure('주문 목록 본문 없음')),
    );
  }

  @override
  Future<OrderDetail> get(String orderId) async {
    final res = await pmartGuard(() => _orders.getOrder(orderId: orderId));
    return orderFromContract(
      res.data ?? (throw const ContractViolationFailure('주문 본문 없음')),
    );
  }

  @override
  Future<DeliveryEtaView> eta(String deliveryId) async {
    final res = await pmartGuard(
      () => _eta.getDeliveryEta(deliveryId: deliveryId),
    );
    return etaFromContract(
      deliveryId,
      res.data ?? (throw const ContractViolationFailure('ETA 본문 없음')),
    );
  }

  @override
  Future<void> requestTimeChange(
    String orderId,
    ArrivalWindow window, {
    required int expectedVersion,
    required IdempotencyKey key,
  }) async {
    await pmartGuard(
      () => _orders.requestReservationTimeChange(
        orderId: orderId,
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        xExpectedVersion: expectedVersion,
        requestReservationTimeChangeRequest:
            api.RequestReservationTimeChangeRequest(
              newArrivalWindow: api.ArrivalWindow(
                date: window.date,
                start: window.start,
                end: window.end,
              ),
            ),
        extra: commandOptions(key, expectedVersion: expectedVersion).extra,
      ),
    );
  }

  @override
  Future<RequestState> timeChange(String orderId, IdempotencyKey key) async {
    try {
      final res = await pmartGuard(
        () => _orders.getReservationTimeChange(
          orderId: orderId,
          requestId: key.value,
        ),
      );
      return requestStateOf(res.data?.state?.value);
    } on ProblemFailure catch (f) {
      if (f.problem.code == ProblemCode.notFound) return RequestState.unknown;
      rethrow;
    }
  }
}

T _need<T>(T? v, String field) =>
    v ?? (throw ContractViolationFailure('$field 없음'));

Freshness _freshness(String? wire) => switch (wire) {
  'CURRENT' => Freshness.current,
  'STALE' => Freshness.stale,
  'UNAVAILABLE' => Freshness.unavailable,
  _ => Freshness.unknown,
};

OrderPage orderPageFromContract(api.ListOrders200Response r) => OrderPage(
  items: [
    for (final o in r.items ?? const <api.OrderSummary>[])
      OrderListItem(
        orderId: _need(o.orderId, 'OrderSummary.orderId'),
        status: OrderStatus.fromWire(o.status?.value),
        orderedAt: o.orderedAt,
        totalAmount: o.totalAmount,
        itemCount: o.itemCount,
      ),
  ],
  nextCursor: r.page?.nextCursor,
);

OrderDetail orderFromContract(api.Order o) => OrderDetail(
  orderId: _need(o.orderId, 'Order.orderId'),
  version: o.version ?? 0,
  status: OrderStatus.fromWire(o.status?.value),
  deliveryMode: o.deliveryMode,
  mfcId: o.mfcId,
  window: switch (o.arrivalWindow) {
    final w? => ArrivalWindow(date: w.date, start: w.start, end: w.end),
    null => null,
  },
  quote: o.quote == null ? null : quoteFromContract(o.quote!),
  shippingAddress: shippingAddressFromContract(o.shippingAddress),
  lines: [
    for (final l in o.lines ?? const <api.OrderLine>[])
      OrderLineView(
        orderLineId: _need(l.orderLineId, 'OrderLine.orderLineId'),
        sku: _need(l.sku, 'OrderLine.sku'),
        productName: l.productName,
        unitPrice: l.unitPrice,
        originalQty: l.originalQty,
        cancelledBeforeShipQty: l.cancelledBeforeShipQty,
        handedOverQty: l.handedOverQty,
        deliveredQty: l.deliveredQty,
        returnedQty: l.returnedQty,
        unfulfilledQty: l.unfulfilledQty,
      ),
  ],
  shipments: [
    for (final s in o.shipments ?? const <api.Shipment>[])
      ShipmentView(
        shipmentId: _need(s.shipmentId, 'Shipment.shipmentId'),
        deliveryId: s.deliveryId,
        state: switch (s.state?.value) {
          'PLANNED' => ShipmentState.planned,
          'PREPARING' => ShipmentState.preparing,
          'READY' => ShipmentState.ready,
          'HANDED_OVER' => ShipmentState.handedOver,
          'IN_DELIVERY' => ShipmentState.inDelivery,
          'DELIVERED' => ShipmentState.delivered,
          'FAILED' => ShipmentState.failed,
          'CANCELLED' => ShipmentState.cancelled,
          _ => ShipmentState.unknown,
        },
        lines: [
          for (final l in s.lines ?? const <api.ShipmentLinesInner>[])
            if (l.orderLineId != null)
              (orderLineId: l.orderLineId!, qty: l.qty ?? 0),
        ],
        eta: s.eta,
      ),
  ],
  paymentState: o.payment?.state,
  refundedAmount: o.payment?.refundedAmount,
  claims: [
    for (final c in o.claims ?? const <api.OrderClaimsInner>[])
      if (c.claimId != null)
        (claimId: c.claimId!, type: c.type ?? '', state: c.state ?? ''),
  ],
  sources: [
    for (final s in o.sources ?? const <api.OrderSourcesInner>[])
      SourceStamp(
        system: s.system ?? '',
        asOf: s.asOf?.asOf,
        freshness: _freshness(s.asOf?.freshness?.value),
      ),
  ],
);

DeliveryEtaView etaFromContract(String deliveryId, trk.DeliveryEta e) {
  final drop = e.dropEta;
  return DeliveryEtaView(
    deliveryId: e.deliveryId ?? deliveryId,
    stage: switch (e.stage?.value) {
      'UNASSIGNED' => DeliveryStage.unassigned,
      'TO_STORE' => DeliveryStage.toStore,
      'AT_STORE' => DeliveryStage.atStore,
      'TO_CUSTOMER' => DeliveryStage.toCustomer,
      'AT_CUSTOMER' => DeliveryStage.atCustomer,
      'DONE' => DeliveryStage.done,
      _ => DeliveryStage.unknown,
    },
    status: switch (drop?.status) {
      trk.EtaStatus.AVAILABLE => EtaStatus.available,
      trk.EtaStatus.LOCATING => EtaStatus.locating,
      trk.EtaStatus.ETA_PENDING => EtaStatus.pending,
      trk.EtaStatus.FINAL => EtaStatus.finalized,
      null => EtaStatus.unknown,
    },
    // 수치는 AVAILABLE 일 때만 쓴다(위치 확인 중에 이전 값이 남아 있어도 보이지 않는다).
    etaAt: drop?.status == trk.EtaStatus.AVAILABLE ? drop?.etaAt : null,
    remainingSeconds: drop?.status == trk.EtaStatus.AVAILABLE
        ? drop?.remainingSeconds
        : null,
    delayedBySeconds: drop?.delayedBySeconds,
    window: switch (e.arrivalWindow) {
      final w? when w.date != null && w.start != null && w.end != null =>
        ArrivalWindow(date: w.date!, start: w.start!, end: w.end!),
      _ => null,
    },
    delayAlert: e.delayAlertTriggered ?? false,
    asOf: e.asOf?.asOf,
    freshness: _freshness(e.asOf?.freshness?.value),
  );
}
