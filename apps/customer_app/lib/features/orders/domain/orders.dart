import 'package:flutter/foundation.dart';

import '../../../shared/order_status.dart';
import '../../checkout/domain/checkout.dart' show ArrivalWindow, Quote;

@immutable
class OrderListItem {
  const OrderListItem({
    required this.orderId,
    required this.status,
    this.orderedAt,
    this.totalAmount,
    this.itemCount,
  });

  final String orderId;
  final OrderStatus status;
  final DateTime? orderedAt;
  final int? totalAmount;
  final int? itemCount;
}

@immutable
class OrderPage {
  const OrderPage({required this.items, this.nextCursor});

  final List<OrderListItem> items;
  final String? nextCursor;
}

/// 주문 품목. 이름·단가는 주문 당시 스냅샷이다. 수량은 서버가 나눠 준 값만 쓴다.
@immutable
class OrderLineView {
  const OrderLineView({
    required this.orderLineId,
    required this.sku,
    this.productName,
    this.unitPrice,
    this.originalQty,
    this.cancelledBeforeShipQty,
    this.handedOverQty,
    this.deliveredQty,
    this.returnedQty,
    this.unfulfilledQty,
  });

  final String orderLineId;
  final String sku;
  final String? productName;
  final int? unitPrice;
  final int? originalQty;
  final int? cancelledBeforeShipQty;
  final int? handedOverQty;
  final int? deliveredQty;
  final int? returnedQty;
  final int? unfulfilledQty;
}

enum ShipmentState {
  planned,
  preparing,
  ready,
  handedOver,
  inDelivery,
  delivered,
  failed,
  cancelled,
  unknown,
}

@immutable
class ShipmentView {
  const ShipmentView({
    required this.shipmentId,
    required this.state,
    required this.lines,
    this.deliveryId,
    this.eta,
  });

  final String shipmentId;
  final String? deliveryId;
  final ShipmentState state;

  /// (orderLineId, 수량)
  final List<({String orderLineId, int qty})> lines;
  final DateTime? eta;
}

/// 원천별 기준시각. STALE·UNAVAILABLE 이면 화면에 "늦을 수 있음"을 붙인다.
enum Freshness { current, stale, unavailable, unknown }

@immutable
class SourceStamp {
  const SourceStamp({required this.system, required this.freshness, this.asOf});

  final String system;
  final DateTime? asOf;
  final Freshness freshness;
}

@immutable
class OrderDetail {
  const OrderDetail({
    required this.orderId,
    required this.version,
    required this.status,
    required this.lines,
    required this.shipments,
    required this.sources,
    this.deliveryMode,
    this.mfcId,
    this.window,
    this.quote,
    this.paymentState,
    this.refundedAmount,
    this.claims = const [],
  });

  final String orderId;
  final int version;
  final OrderStatus status;
  final String? mfcId;
  final String? deliveryMode;
  final ArrivalWindow? window;
  final Quote? quote;
  final List<OrderLineView> lines;
  final List<ShipmentView> shipments;
  final String? paymentState;

  /// 서버가 준 환불 성공액. 앱이 계산하지 않는다.
  final int? refundedAmount;
  final List<({String claimId, String type, String state})> claims;
  final List<SourceStamp> sources;

  bool get isSplit => shipments.length > 1;

  List<SourceStamp> get staleSources => [
    for (final s in sources)
      if (s.freshness != Freshness.current) s,
  ];
}

/// 배송 진행 단계(고객 노출).
enum DeliveryStage {
  unassigned,
  toStore,
  atStore,
  toCustomer,
  atCustomer,
  done,
  unknown,
}

/// 도착 예상 상태. LOCATING·ETA_PENDING 이면 수치가 없다(위치 실패 ≠ 배송 실패).
enum EtaStatus { available, locating, pending, finalized, unknown }

@immutable
class DeliveryEtaView {
  const DeliveryEtaView({
    required this.deliveryId,
    required this.stage,
    required this.status,
    this.etaAt,
    this.remainingSeconds,
    this.delayedBySeconds,
    this.window,
    this.delayAlert = false,
    this.asOf,
    this.freshness = Freshness.unknown,
  });

  final String deliveryId;
  final DeliveryStage stage;
  final EtaStatus status;
  final DateTime? etaAt;
  final int? remainingSeconds;
  final int? delayedBySeconds;
  final ArrivalWindow? window;
  final bool delayAlert;
  final DateTime? asOf;
  final Freshness freshness;
}
