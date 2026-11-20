import 'package:flutter/foundation.dart';

/// 찜한 상품의 판매 상태(customer 0.13.0 `WishlistItem.saleState`, ADR-0081).
enum WishSaleState {
  /// 살 수 있다.
  onSale,

  /// 품절 — 지금 쇼핑 주소 센터 기준.
  soldOut,

  /// 판매 종료.
  ended,

  /// 상품 정보를 못 읽었다(모르는 값 포함) — 품절·판매 중 어느 쪽으로도 보이지 않는다.
  unknown;

  static WishSaleState fromWire(String? v) => switch (v) {
    'ON_SALE' => onSale,
    'SOLD_OUT' => soldOut,
    'ENDED' => ended,
    _ => unknown,
  };
}

/// 찜 한 줄. 이름·사진·가격은 조회 때 서버가 상품 카드에서 채운다 — 모르면 null(지어내지 않는다).
@immutable
class WishlistItem {
  const WishlistItem({
    required this.productId,
    required this.addedAt,
    required this.saleState,
    this.name,
    this.imageUrl,
    this.price,
  });

  final String productId;
  final DateTime addedAt;
  final String? name;
  final String? imageUrl;

  /// 대표 가격(원). 가격 미설정이면 null — 0원으로 바꾸지 않는다.
  final int? price;
  final WishSaleState saleState;

  /// 상품 정보를 읽지 못했다 — "상품 정보를 불러오지 못했어요".
  bool get infoMissing => saleState == WishSaleState.unknown || name == null;
}

@immutable
class WishlistPage {
  const WishlistPage({
    required this.items,
    required this.total,
    required this.limit,
  });

  final List<WishlistItem> items;

  /// 전체 찜 수(서버 값).
  final int total;

  /// 최대 찜 수(서버 설정, 지금 200).
  final int limit;
}

/// 찜 요청의 거절 코드(Problem `code`).
abstract final class WishlistProblemCode {
  /// 최대 개수를 넘었다(422, details `limit`).
  static const limitExceeded = 'WISHLIST_LIMIT_EXCEEDED';

  /// 탈퇴 신청 이후(409).
  static const invalidState = 'INVALID_STATE';
}
