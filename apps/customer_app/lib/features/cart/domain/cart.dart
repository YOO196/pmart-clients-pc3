import 'package:flutter/foundation.dart';

import '../../catalog/domain/catalog.dart' show SaleDiscount, SaleState;

/// 장바구니 품목의 현재 센터 가용 사본. 조회 실패는 [unknown] 이지 품절이 아니다.
enum LineAvailability { available, low, soldOut, notCarried, unknown }

/// 서버가 확정한 장바구니 품목. 표시값(이름·가격·가용)은 사본이고 구매 보장이 아니다.
@immutable
class CartLine {
  const CartLine({
    required this.cartItemId,
    required this.sku,
    required this.quantity,
    required this.selected,
    required this.saleState,
    required this.availability,
    this.productId,
    this.name,
    this.optionLabel,
    this.imageUrl,
    this.unitPrice,
    this.availableQty,
    this.discount,
  });

  /// 기간 할인(cart 0.4.0 `display.salePrice` 등). 없으면 정가([unitPrice])만.
  final SaleDiscount? discount;

  final String cartItemId;
  final String sku;
  final String? productId;
  final int quantity;
  final bool selected;
  final String? name;
  final String? optionLabel;
  final String? imageUrl;

  /// 표시 단가 사본. 없으면 null(0원 아님).
  final int? unitPrice;
  final SaleState saleState;
  final LineAvailability availability;

  /// 공개 범위 가용 수량. 불명이면 null.
  final int? availableQty;

  /// 지금 고를 수 있는지(안내용). 합계·주문 가능은 서버가 정한다.
  bool get purchasable =>
      saleState == SaleState.onSale &&
      availability != LineAvailability.soldOut &&
      availability != LineAvailability.notCarried;

  /// 서버 사본이 지금 살 수 없다고 확정한 품목(일시품절·판매중지·가용 0·미취급). 판매 상태·가용을 모르는 것(UNKNOWN)은
  /// 넣지 않는다 — 모르는 것을 품절로 단정하지 않는다.
  bool get definitelyUnavailable =>
      saleState == SaleState.temporarilySoldOut ||
      saleState == SaleState.saleStopped ||
      availability == LineAvailability.soldOut ||
      availability == LineAvailability.notCarried;

  /// 서버가 APPLIED 로 확정한 수량·선택을 반영한 사본(표시용 사본은 그대로).
  CartLine copyWith({int? quantity, bool? selected}) => CartLine(
    cartItemId: cartItemId,
    sku: sku,
    productId: productId,
    quantity: quantity ?? this.quantity,
    selected: selected ?? this.selected,
    name: name,
    optionLabel: optionLabel,
    imageUrl: imageUrl,
    unitPrice: unitPrice,
    saleState: saleState,
    availability: availability,
    availableQty: availableQty,
    discount: discount,
  );
}

@immutable
class Cart {
  const Cart({
    required this.cartId,
    required this.version,
    required this.isMember,
    required this.lines,
    this.mfcId,
    this.selectedItemAmount,
    this.selectedDiscountAmount,
    this.minOrderAmount,
    this.minOrderShortfall,
    this.expiresAt,
    this.sources = const [],
  });

  final String cartId;

  /// 서버 cartVersion. 변경 명령의 expectedVersion.
  final int version;
  final bool isMember;
  final String? mfcId;
  final List<CartLine> lines;

  /// 서버가 준 선택 품목 표시 합계(견적 아님). 없으면 null. 앱에서 더하지 않는다.
  final int? selectedItemAmount;

  /// 선택 품목 기간 할인 합계(cart 0.4.0 — [selectedItemAmount] 는 이미 할인 뒤). 없으면 null.
  final int? selectedDiscountAmount;

  /// 최소 주문 금액(cart 0.2.0, 안내용 — 최종 판정은 주문서 견적).
  final int? minOrderAmount;

  /// 최소 주문까지 모자란 금액 = max(0, 최소 − 선택 합계)(서버 값). 가격 모르는 줄이 있으면 null — 바를 숨긴다(0 으로 바꾸지 않는다).
  final int? minOrderShortfall;
  final DateTime? expiresAt;

  /// 표시용 사본의 원천별 신선도(계약 `Cart.sources`). 어느 원천을 못 받았는지 안내에 쓴다.
  final List<CartSource> sources;

  /// 재고 원천(mfc-inventory-service)을 못 받았다 → 가용 UNKNOWN 은 "재고 정보 없음"이지 품절·0 이 아니다.
  bool get inventoryUnavailable =>
      sources.any((s) => s.system == CartSource.inventory && s.unavailable);

  CartLine? lineForSku(String sku) =>
      lines.where((l) => l.sku == sku).firstOrNull;

  /// 서버가 APPLIED 로 확정한 변경(수량·선택·삭제)을 응답 버전으로 반영한 사본. 합계는 서버가 다시 줘야 하므로 비운다.
  Cart applied(CartChange change, {required int? cartVersion}) {
    final next = switch (change) {
      AddItem() => lines, // 새 행은 표시용 사본이 필요해 여기서 만들지 않는다(다시 읽는다)
      SetQuantity(:final cartItemId, :final quantity) => [
        for (final l in lines)
          l.cartItemId == cartItemId ? l.copyWith(quantity: quantity) : l,
      ],
      SetSelected(:final cartItemId, :final selected) => [
        for (final l in lines)
          l.cartItemId == cartItemId ? l.copyWith(selected: selected) : l,
      ],
      RemoveItem(:final cartItemId) => [
        for (final l in lines)
          if (l.cartItemId != cartItemId) l,
      ],
    };
    return Cart(
      cartId: cartId,
      version: cartVersion ?? version + 1,
      isMember: isMember,
      lines: next,
      mfcId: mfcId,
      selectedItemAmount: null,
      selectedDiscountAmount: null,
      minOrderAmount: minOrderAmount,
      minOrderShortfall: null,
      expiresAt: expiresAt,
      sources: sources,
    );
  }

  bool get hasSelectedPurchasable =>
      lines.any((l) => l.selected && l.purchasable);
}

/// 장바구니 표시용 사본의 원천 하나(계약 `Cart.sources[]`).
@immutable
class CartSource {
  const CartSource({required this.system, required this.unavailable});

  /// 재고 가용 원천 이름(백엔드 cart-service `CartView` 가 쓰는 값).
  static const inventory = 'mfc-inventory-service';

  final String system;

  /// `asOf.freshness == UNAVAILABLE`.
  final bool unavailable;
}

/// 고객의 장바구니 변경 의도 1회. 수량은 항상 절대값이다(합산 아님).
@immutable
sealed class CartChange {
  const CartChange();
}

final class AddItem extends CartChange {
  const AddItem({required this.sku, required this.quantity});

  final String sku;
  final int quantity;
}

final class SetQuantity extends CartChange {
  const SetQuantity({required this.cartItemId, required this.quantity});

  final String cartItemId;

  /// 1 이상. 0 은 [RemoveItem] 으로 보낸다(계약상 PATCH 0 금지).
  final int quantity;
}

final class SetSelected extends CartChange {
  const SetSelected({required this.cartItemId, required this.selected});

  final String cartItemId;
  final bool selected;
}

final class RemoveItem extends CartChange {
  const RemoveItem({required this.cartItemId});

  final String cartItemId;
}

/// 수량 상한 초과 정보(서버 값). 앱이 계산하지 않는다.
@immutable
class QuantityLimit {
  const QuantityLimit({
    this.totalUnits,
    this.limitUnits,
    this.suggestedQuantity,
  });

  final int? totalUnits;
  final int? limitUnits;
  final int? suggestedQuantity;
}

/// 변경 명령의 결과.
@immutable
sealed class CartChangeOutcome {
  const CartChangeOutcome();
}

/// 서버가 반영했다.
final class CartChangeApplied extends CartChangeOutcome {
  const CartChangeApplied({required this.cartVersion, this.cart});

  final int? cartVersion;

  /// 응답 시점의 장바구니 전체(BR-43 회신 2026-11-03: `GET /carts/{id}` 와 같은 모양). 있으면 다시 읽지 않는다.
  /// 결과 조회(change-requests)의 것은 "지금" 장바구니라 그 변경 직후가 아닐 수 있다 — [cartVersion] 으로 비교.
  final Cart? cart;
}

/// 서버가 거절했다(업무 규칙). [code] 로 문구를 고른다.
final class CartChangeRejected extends CartChangeOutcome {
  const CartChangeRejected(this.code, {this.limit, this.availableQty});

  final String code;
  final QuantityLimit? limit;

  /// INSUFFICIENT_AVAILABLE_QUANTITY 일 때 확인된 가용. 불명이면 null.
  final int? availableQty;
}

/// 고객이 본 장바구니가 최신이 아니다. 다시 조회해 고객이 재확정한다.
final class CartVersionConflict extends CartChangeOutcome {
  const CartVersionConflict();
}

/// 반영 여부를 모른다. 같은 키로 원결과를 조회한다.
final class CartChangeUnknown extends CartChangeOutcome {
  const CartChangeUnknown();
}

/// 원결과 조회 결과: 그 키로 접수된 변경이 없다(미적용).
final class CartChangeNotApplied extends CartChangeOutcome {
  const CartChangeNotApplied();
}

abstract final class CartProblemCode {
  static const versionConflict = 'CART_VERSION_CONFLICT';
  static const quantityLimitExceeded = 'QUANTITY_LIMIT_EXCEEDED';
  static const insufficientAvailableQuantity =
      'INSUFFICIENT_AVAILABLE_QUANTITY';
  static const skuNotSaleable = 'SKU_NOT_SALEABLE';
  static const requestResultUnknown = 'REQUEST_RESULT_UNKNOWN';
  static const forbiddenOwner = 'FORBIDDEN_OWNER';
}
