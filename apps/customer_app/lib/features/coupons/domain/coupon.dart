import 'package:flutter/foundation.dart';

/// 쿠폰(promotion-service 0.2.0, ADR-0082 — 백엔드 요청 2026-11-21 coupons-discounts).
/// 장바구니 쿠폰만(주문 1건에 1장). 할인액·쓸 수 있는지는 주문서 견적(서버)이 정한다 — 앱은 계산하지 않는다.

enum CouponDiscountType { rate, amount }

/// 계약 `Discount`. RATE 는 %(1~90), AMOUNT 는 원. 정률 쿠폰은 [maxAmount](최대 할인액)가 있을 수 있다.
@immutable
class CouponDiscount {
  const CouponDiscount({
    required this.type,
    required this.value,
    this.maxAmount,
  });

  final CouponDiscountType type;
  final int value;
  final int? maxAmount;
}

enum CouponStatus {
  available,

  /// 사용(주문 결제 중 점유 포함).
  used,
  expired,
  unknown;

  static CouponStatus fromWire(String? wire) => switch (wire) {
    'AVAILABLE' => available,
    'USED' => used,
    'EXPIRED' => expired,
    _ => unknown,
  };
}

/// 내 쿠폰 한 장(계약 `Coupon`).
@immutable
class Coupon {
  const Coupon({
    required this.couponId,
    required this.promotionId,
    required this.name,
    required this.discount,
    required this.minOrderAmount,
    required this.status,
    required this.issuedAt,
    required this.validUntil,
    this.usedOrderId,
  });

  final String couponId;
  final String promotionId;
  final String name;
  final CouponDiscount discount;

  /// 최소 주문금액(기간 할인 뒤·쿠폰 전 상품액 기준 — 판정은 서버).
  final int minOrderAmount;
  final CouponStatus status;
  final DateTime issuedAt;
  final DateTime validUntil;
  final String? usedOrderId;
}

/// 지금 받을 수 있는 쿠폰 행사(계약 `CouponCampaign`).
@immutable
class CouponCampaign {
  const CouponCampaign({
    required this.promotionId,
    required this.name,
    required this.discount,
    required this.minOrderAmount,
    required this.perCustomerLimit,
    required this.myIssuedCount,
    required this.endsAt,
    this.remaining,
    this.useDays,
    this.useUntil,
  });

  final String promotionId;
  final String name;
  final CouponDiscount discount;
  final int minOrderAmount;
  final int perCustomerLimit;

  /// 내가 이미 받은 수(서버 값).
  final int myIssuedCount;

  /// 남은 수량. 총 수량이 없으면 null(무제한 — 0 이 아니다).
  final int? remaining;

  /// 받기 끝.
  final DateTime endsAt;

  /// 받은 날 포함 N일 동안 쓸 수 있다. 없으면 [useUntil].
  final int? useDays;
  final DateTime? useUntil;

  /// 서버가 준 수로 본 "다 받음"(버튼 표시만 — 받을 수 있는지는 내려받기 응답이 정한다).
  bool get reachedLimit => myIssuedCount >= perCustomerLimit;

  /// 서버가 준 남은 수량이 0.
  bool get soldOut => remaining == 0;
}

abstract final class CouponProblemCode {
  static const limitReached = 'COUPON_LIMIT_REACHED';
  static const soldOut = 'COUPON_SOLD_OUT';
  static const notActive = 'NOT_ACTIVE';
  static const unsupported = 'UNSUPPORTED_ACTION';
}
