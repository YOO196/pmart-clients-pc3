import 'package:flutter/foundation.dart';

import '../../../shared/order_status.dart';
import '../../checkout/domain/checkout.dart'
    show
        ArrivalWindow,
        DeliveryMode,
        OutOfStockPreference,
        Quote,
        ShippingAddress;

/// 주문 목록 카드의 상품 줄(주문 당시 사본 — order 0.17.0). 금액은 서버 값(단가×수량, 할인 나눔 전).
@immutable
class OrderListLine {
  const OrderListLine({
    required this.orderLineId,
    required this.sku,
    required this.quantity,
    required this.lineAmount,
    this.productId,
    this.productName,
    this.optionLabel,
    this.imageUrl,
  });

  final String orderLineId;

  /// 지금 상품의 대표 사진(order 0.19.0 BR-71 `lines[].imageUrl`). null 이면(게시 안 됨·조회 실패·옛 응답) 상품 조회로 찾는다.
  final String? imageUrl;

  /// 상품 ID(order 0.17.0 `lines[].productId`, 없을 수 있음). 줄 사진([imageUrl])이 없을 때 상품 상세의 대표 사진을 찾는다.
  final String? productId;

  /// 다시 담을 때 쓰는 SKU(order 0.17.0 `lines[].sku`).
  final String sku;
  final String? productName;
  final String? optionLabel;
  final int quantity;
  final int lineAmount;
}

@immutable
class OrderListItem {
  const OrderListItem({
    required this.orderId,
    required this.status,
    this.orderNumber,
    this.orderedAt,
    this.totalAmount,
    this.itemCount,
    this.deliveryMode,
    this.representativeName,
    this.representativeQty,
    this.mfcName,
    this.lines = const [],
  });

  /// 주문 담당 센터 이름(order 0.17.0 — 상세와 같은 값). 모르면 null.
  final String? mfcName;

  /// 앞 주문 행(서버가 5개까지 — order 0.17.0, BR-68). 전체 수량은 [itemCount]. 예전 서버·모름은 빈 목록.
  final List<OrderListLine> lines;

  /// [lines] 에 안 실린 나머지 수량 합(`itemCount` − 실린 행의 수량 합). 모르거나 없으면 null.
  int? get moreQty => switch (itemCount) {
    final int all when lines.isNotEmpty => switch (all -
        lines.fold<int>(0, (a, l) => a + l.quantity)) {
      final int rest when rest > 0 => rest,
      _ => null,
    },
    _ => null,
  };

  final String orderId;

  /// 화면용 주문번호(숫자 8자리, order 0.11.0). 없으면 [orderId] 를 보인다.
  final String? orderNumber;
  final OrderStatus status;
  final DateTime? orderedAt;
  final int? totalAmount;

  /// 주문행 수량 합(계약 `itemCount`).
  final int? itemCount;

  /// 배송 방식(order 0.12.0). 모르는 값·없음은 null — 칸을 숨긴다.
  final DeliveryMode? deliveryMode;

  /// 대표 상품(첫 주문 행)의 주문 당시 상품명 사본(order 0.12.0). 2026-11-02 전 주문은 null → "상품 N개".
  final String? representativeName;

  /// 대표 상품의 주문 수량.
  final int? representativeQty;

  /// "<대표 상품> 외 N개"의 N — 다른 상품 수량 합(`itemCount` − 대표 수량). 둘 중 하나라도 없으면 null.
  int? get othersQty => switch ((itemCount, representativeQty)) {
    (final int all, final int rep) when all >= rep => all - rep,
    _ => null,
  };

  /// 끝난 주문만 숨길 수 있다(order 0.12.0 — 그 밖 409 `ORDER_NOT_FINISHED`, 최종 판정은 서버).
  bool get canHide => switch (status) {
    OrderStatus.completed ||
    OrderStatus.cancelled ||
    OrderStatus.expired => true,
    _ => false,
  };
}

/// 주문 내역 조회 기간. 서버 기본(조건 없음)은 최근 3개월이다(order 0.12.0).
enum OrderPeriod { months3, months6, year1, all }

/// 주문 내역 조회 조건. 다음 쪽도 같은 조건으로 묻는다.
@immutable
class OrderListQuery {
  const OrderListQuery({
    this.status,
    this.period = OrderPeriod.months3,
    this.q,
  });

  /// null 이면 전체 상태.
  final OrderStatus? status;
  final OrderPeriod period;

  /// 상품명 검색어(앞뒤 공백 제거, 비면 null).
  final String? q;

  @override
  bool operator ==(Object other) =>
      other is OrderListQuery &&
      other.status == status &&
      other.period == period &&
      other.q == q;

  @override
  int get hashCode => Object.hash(status, period, q);
}

/// 기간 → 서버 `from`(Asia/Seoul 날짜 `yyyy-MM-dd`). 3개월은 서버 기본이라 보내지 않는다(null).
/// 전체는 서버 안내대로 오래전 날짜를 보낸다(2026-11-18 백엔드 알림 §3).
String? orderPeriodFrom(OrderPeriod p, DateTime seoulToday) {
  DateTime monthsAgo(int m) =>
      DateTime(seoulToday.year, seoulToday.month - m, seoulToday.day);
  final from = switch (p) {
    OrderPeriod.months3 => null,
    OrderPeriod.months6 => monthsAgo(6),
    OrderPeriod.year1 => monthsAgo(12),
    OrderPeriod.all => DateTime(2020),
  };
  if (from == null) return null;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${from.year}-${two(from.month)}-${two(from.day)}';
}

@immutable
class OrderPage {
  const OrderPage({required this.items, this.nextCursor});

  final List<OrderListItem> items;
  final String? nextCursor;
}

/// 주문 품목. 이름·옵션 라벨·단가는 주문 당시 사본(BR-35, 초안 때 고정)이다. 수량은 서버가 나눠 준 값만 쓴다.
/// 이름이 없으면(사본 조회 실패·2026-11-02 이전 주문) 그때만 sku 로 대신 보인다.
@immutable
class OrderLineView {
  const OrderLineView({
    required this.orderLineId,
    required this.sku,
    this.productName,
    this.optionLabel,
    this.unitPrice,
    this.originalQty,
    this.cancelledBeforeShipQty,
    this.handedOverQty,
    this.deliveredQty,
    this.returnedQty,
    this.unfulfilledQty,
    this.productId,
    this.lineAmount,
    this.discountShare,
    this.imageUrl,
  });

  /// 지금 상품의 대표 사진(order 0.19.0 BR-71). null 이면 상품 조회로 찾는다.
  final String? imageUrl;

  /// 이 줄에 나눠 넣은 할인(order 0.18.0 — 기간 할인 + 쿠폰 안분, 서버 값). 0·없으면 표시하지 않는다.
  final int? discountShare;

  /// 상품 ID(order `productId`). 줄 사진이 없을 때 대표 사진을, "지금 더 할인 중"에 지금 할인을 찾는다. 없으면 null.
  final String? productId;

  /// 행 금액(단가×수량, 할인 나눔 전 — 서버 값). 없으면 null.
  final int? lineAmount;

  final String orderLineId;
  final String sku;
  final String? productName;

  /// 옵션 라벨 사본. 단일 옵션 상품은 null 일 수 있다(상세 화면의 옵션 숨김 정책과 같다).
  final String? optionLabel;
  final int? unitPrice;

  /// 화면 제목: 상품명(+ 옵션). 이름이 없을 때만 sku.
  String get title => [
    productName ?? sku,
    if (productName != null && optionLabel != null) optionLabel!,
  ].join(' · ');
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
    this.orderNumber,
    this.deliveryMode,
    this.mfcId,
    this.mfcName,
    this.window,
    this.quote,
    this.paymentState,
    this.paymentAttemptId,
    this.refundedAmount,
    this.confirmedAt,
    this.deliveryNote,
    this.outOfStock,
    this.claims = const [],
    this.shippingAddress,
  });

  final String orderId;

  /// 화면용 주문번호(숫자 8자리, order 0.11.0 — 고객·라이더·MFC·상담원이 같은 번호를 본다). 시스템 키는 [orderId].
  /// 서버가 비워 주면 null — 그때는 [orderId] 를 보인다.
  final String? orderNumber;

  /// 고객에게 보일 주문번호: [orderNumber], 없으면 [orderId].
  String get displayNumber => orderNumber ?? orderId;
  final int version;
  final OrderStatus status;
  final String? mfcId;

  /// 주문한 센터의 고객용 이름(order 0.15.0 — BR-62, center-master 이름). 모르면 null(브랜드만 보인다).
  final String? mfcName;

  /// 주문 당시 배송지 사본(BR-37). null 이면 "배송지 정보 없음" — 주소록을 다시 부르지 않는다.
  final ShippingAddress? shippingAddress;
  final String? deliveryMode;
  final ArrivalWindow? window;
  final Quote? quote;
  final List<OrderLineView> lines;
  final List<ShipmentView> shipments;
  final String? paymentState;

  /// 결제 시도 ID(`Order.payment.paymentAttemptId`). 결제 수단은 이것으로 `GET /payments/{id}` 를 묻는다. 없으면 null.
  final String? paymentAttemptId;

  /// 고객이 남긴 배달 요청사항(`Order.deliveryNote`). 없으면 null.
  final String? deliveryNote;

  /// 품절 시 처리(`Order.outOfStockPreference`). 값이 없으면 null(표시하지 않음).
  final OutOfStockPreference? outOfStock;

  /// 서버가 준 환불 성공액. 앱이 계산하지 않는다.
  final int? refundedAmount;

  /// 주문 확정 시각(계약 `Order.confirmedAt`) — 주문 상세 "주문일시" 줄(사용자 레퍼런스 2026-11-26). 없으면 줄 없음.
  final DateTime? confirmedAt;
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

/// 라이더 마지막 위치(`DeliveryEta.riderLocation`, tracking 0.6.0). 서버는 고객에게 **내 상품을 픽업한 뒤 ~
/// 끝나기 전**(TO_CUSTOMER·AT_CUSTOMER)만 준다. 지금 한 점만 — 지나온 동선은 없다.
/// 좌표는 화면 지도에만 쓰고 로그·분석에 남기지 않는다([toString] 에 넣지 않는다).
@immutable
class RiderPosition {
  const RiderPosition({
    required this.lat,
    required this.lng,
    this.recordedAt,
    this.staleSeconds,
  });

  final double lat;
  final double lng;

  /// 단말이 기록한 시각.
  final DateTime? recordedAt;

  /// 서버가 받은 뒤 지난 초(서버 값).
  final int? staleSeconds;

  /// 이보다 오래 지난 위치는 "확인 중"으로 보인다(PC 5 요청 2026-11-19 — 마커를 흐리게).
  static const staleAfterSeconds = 60;

  /// 서버가 받은 지 [staleAfterSeconds] 초가 넘었다(앱이 꺼졌거나 신호가 끊긴 라이더).
  bool get stale => (staleSeconds ?? 0) > staleAfterSeconds;

  @override
  bool operator ==(Object other) =>
      other is RiderPosition &&
      other.lat == lat &&
      other.lng == lng &&
      other.recordedAt == recordedAt &&
      other.staleSeconds == staleSeconds;

  @override
  int get hashCode => Object.hash(lat, lng, recordedAt, staleSeconds);

  @override
  String toString() => 'RiderPosition(recordedAt: $recordedAt)';
}

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
    this.riderLocation,
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

  /// 라이더 지금 위치. 픽업 전·끝난 뒤·위치 미수신이면 null(서버가 정한다).
  final RiderPosition? riderLocation;

  /// 실시간 구독의 STAGE_CHANGED(단계만 옴)를 반영한 사본. 도착 예상 수치는 그대로 둔다.
  DeliveryEtaView withStage(DeliveryStage next) => DeliveryEtaView(
    deliveryId: deliveryId,
    stage: next,
    status: status,
    etaAt: etaAt,
    remainingSeconds: remainingSeconds,
    delayedBySeconds: delayedBySeconds,
    window: window,
    delayAlert: delayAlert,
    asOf: asOf,
    freshness: freshness,
    riderLocation: riderLocation,
  );
}

/// 고객용 전달 완료 증빙(delivery-execution 0.9.0 `GET /deliveries/{id}/delivery-proof`) — 본인 주문의 배송이
/// 전달 완료된 뒤만. 라이더 ID·위치·전화는 없다. 사진은 [photoRefs] 로 따로 받는다(`…/evidence-photos/{photoRef}`).
@immutable
class DeliveryProof {
  const DeliveryProof({
    required this.deliveryId,
    required this.photoRefs,
    this.completedAt,
    this.placementDetail,
  });

  final String deliveryId;
  final List<String> photoRefs;
  final DateTime? completedAt;

  /// 놓은 곳 설명(라이더가 쓴 글). 없으면 null.
  final String? placementDetail;
}

/// 자주 산 상품 한 줄(order 0.24.0 `GET /orders/frequent-items`, 백엔드 요청 2026-11-26).
/// 이름·옵션은 가장 최근 주문 당시 사본, 사진은 지금 대표 사진(없으면 null).
@immutable
class FrequentItem {
  const FrequentItem({
    required this.sku,
    required this.orderCount,
    this.productId,
    this.productName,
    this.optionLabel,
    this.imageUrl,
  });

  final String sku;
  final String? productId;
  final String? productName;
  final String? optionLabel;

  /// 서로 다른 주문 수(한 주문에 2개 = 1번).
  final int orderCount;
  final String? imageUrl;

  /// 화면에 보일 이름: 상품 이름 + " · 옵션". 옵션이 이름에 이미 들어 있으면(예 "통삼겹살 1kg" · "1kg") 붙이지 않는다
  /// (사용자 2026-11-26 "용량이 두 번 나온다"). 이름이 없으면 null.
  String? get displayName {
    final name = productName?.trim();
    if (name == null || name.isEmpty) return null;
    final option = optionLabel?.trim();
    if (option == null || option.isEmpty) return name;
    String squash(String v) => v.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (squash(name).contains(squash(option))) return name;
    return '$name · $option';
  }
}
