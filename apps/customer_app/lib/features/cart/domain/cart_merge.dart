import 'package:flutter/foundation.dart';

/// 병합 상태(cart-service `MergeResult.state`).
enum MergeState { pending, partial, confirmed, rejected, unknown }

/// 항목별 이관 결과.
enum MergeItemResult { merged, rejected, unknown }

/// 이관을 요청할 비회원 장바구니 항목(고객이 고른 것만, 절대 수량).
@immutable
class MergeItemRequest {
  const MergeItemRequest({
    required this.sourceItemId,
    required this.sku,
    required this.quantity,
  });

  final String sourceItemId;
  final String sku;
  final int quantity;
}

@immutable
class MergeItem {
  const MergeItem({
    required this.result,
    this.sourceItemId,
    this.sku,
    this.requestedQuantity,
    this.mergedQuantity,
    this.reasonCode,
  });

  final String? sourceItemId;
  final String? sku;
  final int? requestedQuantity;
  final MergeItemResult result;
  final int? mergedQuantity;

  /// QUANTITY_LIMIT_EXCEEDED / INSUFFICIENT_AVAILABLE_QUANTITY / SKU_NOT_SALEABLE / SOURCE_ITEM_CHANGED 등.
  final String? reasonCode;
}

/// 서버가 돌려준 병합 결과. 성공분만 회원 장바구니에 합산됐다(실패분은 비회원 장바구니에 그대로).
@immutable
class CartMergeResult {
  const CartMergeResult({
    required this.mergeId,
    required this.state,
    this.items = const [],
  });

  final String mergeId;
  final MergeState state;
  final List<MergeItem> items;

  int get mergedCount =>
      items.where((i) => i.result == MergeItemResult.merged).length;
}

@immutable
sealed class MergeOutcome {
  const MergeOutcome();
}

/// 서버가 답했다(확정·일부·거절·정리 대기).
final class MergeAnswered extends MergeOutcome {
  const MergeAnswered(this.result);

  final CartMergeResult result;
}

/// 회원 장바구니가 그 사이 바뀌었다(409 CART_VERSION_CONFLICT) — 반영되지 않았다. 다시 읽고 새로 누른다.
final class MergeVersionConflict extends MergeOutcome {
  const MergeVersionConflict();
}

/// 같은 키로 다시 보내도 결과를 모른다. 새 키로 다시 합치지 않는다(중복 합산 금지) — 같은 키로만 다시 확인한다.
final class MergeUnknown extends MergeOutcome {
  const MergeUnknown();
}

abstract final class MergeProblemCode {
  static const forbiddenOwner = 'FORBIDDEN_OWNER';
  static const versionConflict = 'CART_VERSION_CONFLICT';
  static const sourceItemChanged = 'SOURCE_ITEM_CHANGED';
}
