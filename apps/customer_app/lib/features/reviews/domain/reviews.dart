import 'package:flutter/foundation.dart';

/// 리뷰 상태(계약 `ReviewState`). 작성 가능 여부·수정 가능 여부는 서버가 준 이 값으로만 판단한다.
enum ReviewState {
  eligible,
  submitPending,
  published,
  locked,
  deleted,
  expired,
  unknown,
}

ReviewState reviewStateFromWire(String? wire) => switch (wire) {
  'REV_ELIGIBLE' => ReviewState.eligible,
  'SUBMIT_PENDING' => ReviewState.submitPending,
  'PUBLISHED' => ReviewState.published,
  'LOCKED' => ReviewState.locked,
  'DELETED' => ReviewState.deleted,
  'EXPIRED' => ReviewState.expired,
  _ => ReviewState.unknown,
};

/// 계약 입력 한도(`CreateReviewRequest`): 별점 1~5, 본문 최대 1,000자.
const reviewRatingMax = 5;
const reviewTextMaxLength = 1000;

/// 주문 품목 하나의 리뷰 자격(`GET /me/review-eligibilities`). 기한(`eligibleUntil`)은 서버 값이다.
@immutable
class ReviewEligibility {
  const ReviewEligibility({
    required this.orderId,
    required this.orderLineId,
    required this.state,
    this.sku,
    this.productId,
    this.deliveredAt,
    this.eligibleUntil,
    this.reviewId,
  });

  final String orderId;
  final String orderLineId;
  final String? sku;
  final String? productId;
  final DateTime? deliveredAt;
  final DateTime? eligibleUntil;
  final ReviewState state;
  final String? reviewId;

  /// 서버가 "작성 가능"이라고 준 품목. 기한을 앱이 다시 계산하지 않는다(제출 때 서버가 다시 검사한다).
  bool get writable => state == ReviewState.eligible && reviewId == null;

  /// 이미 쓴 리뷰가 있고 삭제되지 않았다("내가 쓴 리뷰"에 보인다).
  bool get written =>
      reviewId != null &&
      state != ReviewState.deleted &&
      state != ReviewState.eligible;
}

@immutable
class ReviewView {
  const ReviewView({
    required this.reviewId,
    required this.productId,
    required this.rating,
    required this.state,
    required this.createdAt,
    this.sku,
    this.authorMasked,
    this.text,
    this.photoUrls = const [],
    this.version,
    this.editableUntil,
    this.updatedAt,
  });

  final String reviewId;
  final String productId;
  final String? sku;

  /// 서버가 가린 작성자 표시. 앱이 따로 가리거나 만들지 않는다.
  final String? authorMasked;
  final int rating;
  final String? text;
  final List<String> photoUrls;
  final ReviewState state;
  final int? version;
  final DateTime createdAt;
  final DateTime? editableUntil;
  final DateTime? updatedAt;
}

@immutable
class EligibilityPage {
  const EligibilityPage({required this.items, this.nextCursor});

  final List<ReviewEligibility> items;
  final String? nextCursor;
}

@immutable
class ProductReviewPage {
  const ProductReviewPage({
    required this.items,
    this.nextCursor,
    this.averageRating,
    this.reviewCount,
  });

  final List<ReviewView> items;
  final String? nextCursor;

  /// 응답 `summary`. 없으면 null(0으로 바꾸지 않는다).
  final double? averageRating;
  final int? reviewCount;
}

/// 리뷰를 쓸 대상(자격 목록·주문 상세에서 넘긴다).
@immutable
class ReviewTarget {
  const ReviewTarget({
    required this.orderId,
    required this.orderLineId,
    this.productId,
    this.title,
    this.eligibleUntil,
    this.initialRating,
  });

  ReviewTarget.of(ReviewEligibility e, {String? title, int? initialRating})
    : this(
        orderId: e.orderId,
        orderLineId: e.orderLineId,
        productId: e.productId,
        title: title,
        eligibleUntil: e.eligibleUntil,
        initialRating: initialRating,
      );

  final String orderId;
  final String orderLineId;
  final String? productId;

  /// 주문 당시 상품명 사본(주문 상세에서 올 때). 없으면 상품 정보를 조회해 이름을 보인다.
  final String? title;
  final DateTime? eligibleUntil;
  final int? initialRating;
}

/// 계약 `POST /reviews` 422 코드.
abstract final class ReviewProblemCode {
  static const notEligible = 'NOT_ELIGIBLE';
  static const eligibilityExpired = 'ELIGIBILITY_EXPIRED';
  static const alreadyReviewed = 'ALREADY_REVIEWED';
  static const rewriteAfterDeleteForbidden = 'REWRITE_AFTER_DELETE_FORBIDDEN';
}
