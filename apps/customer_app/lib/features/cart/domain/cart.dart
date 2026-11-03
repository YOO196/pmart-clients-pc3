import 'package:flutter/foundation.dart';

import '../../catalog/domain/catalog.dart' show SaleState;

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
  });

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
  final DateTime? expiresAt;

  /// 표시용 사본의 원천별 신선도(계약 `Cart.sources`). 어느 원천을 못 받았는지 안내에 쓴다.
  final List<CartSource> sources;

  /// 재고 원천(mfc-inventory-service)을 못 받았다 → 가용 UNKNOWN 은 "재고 정보 없음"이지 품절·0 이 아니다.
  bool get inventoryUnavailable =>
      sources.any((s) => s.system == CartSource.inventory && s.unavailable);

  CartLine? lineForSku(String sku) =>
      lines.where((l) => l.sku == sku).firstOrNull;

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
  const CartChangeApplied({required this.cartVersion});

  final int? cartVersion;
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
