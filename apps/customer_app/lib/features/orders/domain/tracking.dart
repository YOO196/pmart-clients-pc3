import 'package:flutter/foundation.dart';

import '../../../shared/order_status.dart';
import 'orders.dart';

/// 배송현황 4단계(고객 노출). 단계 대응은 잠정(BR-12).
enum TrackStep { confirmed, preparing, delivering, delivered }

/// 배송현황 진행 표시. [step] 이 null 이면 "확인 중"(서버 상태로 단계를 정할 수 없음).
/// [halted] 면 배송이 취소·실패로 멈췄다(단계를 진행으로 그리지 않는다).
/// [partial] 이면 주문이 일부만 다음 단계로 넘어갔다(PARTIALLY_*).
@immutable
class TrackProgress {
  const TrackProgress({this.step, this.halted = false, this.partial = false});

  final TrackStep? step;
  final bool halted;
  final bool partial;

  @override
  bool operator ==(Object other) =>
      other is TrackProgress &&
      other.step == step &&
      other.halted == halted &&
      other.partial == partial;

  @override
  int get hashCode => Object.hash(step, halted, partial);

  @override
  String toString() =>
      'TrackProgress(step: $step, halted: $halted, partial: $partial)';
}

/// 주문 상태 → 단계. 결제 전·확인 중·모르는 값은 null(단계를 앞당기지 않는다).
/// PARTIALLY_* 는 주문 전체가 다음 단계에 닿지 않았으므로 아래 단계에 둔다(부분 표시는 따로).
TrackStep? trackStepOfOrder(OrderStatus s) => switch (s) {
  OrderStatus.confirmed => TrackStep.confirmed,
  OrderStatus.preparing ||
  OrderStatus.partiallyHandedOver => TrackStep.preparing,
  OrderStatus.inDelivery ||
  OrderStatus.partiallyDelivered => TrackStep.delivering,
  OrderStatus.completed => TrackStep.delivered,
  _ => null,
};

/// 배송(Shipment) 상태 → 단계. FAILED·CANCELLED 는 단계가 아니라 멈춤이다.
TrackStep? trackStepOfShipment(ShipmentState s) => switch (s) {
  ShipmentState.planned => TrackStep.confirmed,
  ShipmentState.preparing || ShipmentState.ready => TrackStep.preparing,
  ShipmentState.handedOver || ShipmentState.inDelivery => TrackStep.delivering,
  ShipmentState.delivered => TrackStep.delivered,
  _ => null,
};

/// 배달 진행 단계(`DeliveryEta.stage`) → 단계. DONE 은 "끝남"일 뿐 배달 완료·실패·취소를 가르지 않으므로 null.
/// 라이더가 상품을 받기 전(UNASSIGNED·TO_STORE·AT_STORE)은 상품 준비가 시작됐다는 뜻이 아니므로 주문 확인까지만.
TrackStep? trackStepOfStage(DeliveryStage s) => switch (s) {
  DeliveryStage.unassigned ||
  DeliveryStage.toStore ||
  DeliveryStage.atStore => TrackStep.confirmed,
  DeliveryStage.toCustomer || DeliveryStage.atCustomer => TrackStep.delivering,
  DeliveryStage.done || DeliveryStage.unknown => null,
};

/// 서버가 준 값들로만 진행 표시를 정한다. 각 원천이 알려 준 단계 중 가장 앞선 것을 쓴다(모두 서버 값).
/// 배달 완료는 배송 DELIVERED 나 주문 COMPLETED 일 때만이다(ETA FINAL·stage DONE 만으로는 아니다).
TrackProgress trackProgressOf({
  OrderStatus? order,
  ShipmentState? shipment,
  DeliveryStage? stage,
}) {
  final halted =
      shipment == ShipmentState.failed ||
      shipment == ShipmentState.cancelled ||
      order == OrderStatus.cancelled ||
      order == OrderStatus.expired;
  final partial =
      order == OrderStatus.partiallyHandedOver ||
      order == OrderStatus.partiallyDelivered;
  if (halted) return TrackProgress(halted: true, partial: partial);
  final steps = [
    if (order != null) trackStepOfOrder(order),
    if (shipment != null) trackStepOfShipment(shipment),
    if (stage != null) trackStepOfStage(stage),
  ].nonNulls;
  final step = steps.isEmpty
      ? null
      : steps.reduce((a, b) => a.index >= b.index ? a : b);
  return TrackProgress(step: step, partial: partial);
}

/// 실시간 구독(`GET /deliveries/{id}/stream`) 이벤트 종류. 모르는 값은 [unknown](연결 살아 있음 표시에만 쓴다).
enum TrackingEventType {
  etaUpdated,
  stageChanged,
  locationStale,
  delayAlert,
  streamEnd,
  heartbeat,
  unknown,
}

/// 실시간 구독 이벤트(계약 `StreamEvent`). `ETA_UPDATED`·`STAGE_CHANGED` 의 [eta] 에 라이더 위치(`riderLocation`)가
/// 실린다 — 서버는 볼 수 있는 위치가 바뀌면 3초 안에 보낸다(tracking 0.11.1 설명, PC 5 2026-11-19).
@immutable
class TrackingEvent {
  const TrackingEvent({required this.type, this.id, this.eta, this.stage});

  /// `Last-Event-ID` 재개용.
  final String? id;
  final TrackingEventType type;
  final DeliveryEtaView? eta;
  final DeliveryStage? stage;
}
