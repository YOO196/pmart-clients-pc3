/// 계약 `OrderStatus`. 고객 문구는 잠정(BR-12, `docs/apps/customer-app.md` §4).
enum OrderStatus {
  draft,
  resourcePending,
  paymentPending,
  paymentUnknown,
  confirmed,
  preparing,
  partiallyHandedOver,
  inDelivery,
  partiallyDelivered,
  completed,
  cancelled,
  expired,
  unknown;

  static OrderStatus fromWire(String? wire) => switch (wire) {
    'DRAFT' => draft,
    'RESOURCE_PENDING' => resourcePending,
    'PAYMENT_PENDING' => paymentPending,
    'PAYMENT_UNKNOWN' => paymentUnknown,
    'CONFIRMED' => confirmed,
    'PREPARING' => preparing,
    'PARTIALLY_HANDED_OVER' => partiallyHandedOver,
    'IN_DELIVERY' => inDelivery,
    'PARTIALLY_DELIVERED' => partiallyDelivered,
    'COMPLETED' => completed,
    'CANCELLED' => cancelled,
    'EXPIRED' => expired,
    _ => unknown,
  };

  /// 주문이 확정된 뒤의 상태인지. 결제창 복귀·ACCEPTED 로는 이 값이 되지 않는다.
  bool get isConfirmedOrLater => switch (this) {
    confirmed ||
    preparing ||
    partiallyHandedOver ||
    inDelivery ||
    partiallyDelivered ||
    completed => true,
    _ => false,
  };
}
