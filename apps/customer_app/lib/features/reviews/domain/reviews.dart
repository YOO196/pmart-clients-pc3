import 'package:flutter/foundation.dart';
import 'package:pmart_core/pmart_core.dart' show ProblemCode;

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
    this.productName,
    this.deliveredAt,
    this.eligibleUntil,
    this.reviewId,
    this.orderedAt,
    this.mfcName,
    this.imageUrl,
    this.optionLabel,
    this.orderWritableCount,
  });

  /// 같은 주문에서 지금 쓸 수 있는 품목 수(review 0.6.1 BR-86 — 쪽과 상관없이 주문 기준). 없으면 null.
  final int? orderWritableCount;

  /// 주문 확정 시각·담당 센터 이름(review 0.5.0 — BR-67). 모르면 null(지어내지 않는다) — 주문 묶음 머리에 쓴다.
  final DateTime? orderedAt;
  final String? mfcName;

  /// 지금 상품의 대표 사진(주문 당시 사본 아님, 게시 안 된 상품은 null)·지금 그 SKU 의 옵션 표시.
  final String? imageUrl;
  final String? optionLabel;

  final String orderId;
  final String orderLineId;
  final String? sku;
  final String? productId;

  /// 주문 당시 상품명 사본(review 0.2.0, 없을 수 있다). 없으면 상품 정보를 조회해 보인다.
  final String? productName;
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

/// 상품 리뷰 정렬(계약 `sort` — RECOMMENDED(review 0.6.0, 도움돼요 많은 순)·NEWEST·RATING_DESC·RATING_ASC).
enum ReviewSort { recommended, newest, ratingDesc, ratingAsc }

/// 도움돼요 누르기에서 서버가 거절하는 code(review 0.6.0).
/// 리뷰 신고 사유(review 0.7.0 BR-90 — 사용자 결정 2026-11-23). 기타만 글을 쓴다.
enum ReviewReportReason {
  abuse('ABUSE'),
  ad('AD'),
  irrelevant('IRRELEVANT'),
  privacy('PRIVACY'),
  other('OTHER');

  const ReviewReportReason(this.wire);
  final String wire;
}

/// 기타 사유 글 최대 길이(계약 detail 300자).
const reviewReportDetailMax = 300;

abstract final class ReviewReportProblemCode {
  static const alreadyReported = 'ALREADY_REPORTED';
  static const ownReview = 'REPORT_OWN_REVIEW';
  static const notFound = 'REVIEW_NOT_FOUND';
}

abstract final class ReviewHelpfulProblemCode {
  static const ownReview = 'HELPFUL_OWN_REVIEW';
  static const notPublished = 'REVIEW_NOT_PUBLISHED';
}

/// 도움돼요를 누른 뒤 서버가 준 값(앱이 +1 하지 않는다).
typedef HelpfulResult = ({int count, bool helped});

/// 상품 리뷰 목록 조건: 상품·정렬·사진 리뷰만(`withPhotoOnly`)·옵션 [sku](review 0.6.0, 없으면 전체).
typedef ProductReviewQuery = ({
  String productId,
  ReviewSort sort,
  bool photoOnly,
  String? sku,
});

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
    this.photos = const [],
    this.version,
    this.editableUntil,
    this.updatedAt,
    this.helpfulCount,
    this.helpedByMe,
    this.reportedByMe,
    this.repurchased,
  });

  /// 작성자가 이 상품을 서로 다른 주문 2번 이상 받았는지(review 0.9.0 — 상품 리뷰 목록만, 그 밖 null).
  final bool? repurchased;

  /// 내가 이 리뷰를 신고했는지(review 0.7.0 BR-90 — 회원 토큰일 때만, 그 밖 null).
  final bool? reportedByMe;

  /// 도움돼요 수·내가 눌렀는지(review 0.6.0 — 내가 눌렀는지는 회원 토큰이 있을 때만). 모르면 null — 0·안 누름으로 바꾸지 않는다.
  final int? helpfulCount;
  final bool? helpedByMe;

  final String reviewId;
  final String productId;
  final String? sku;

  /// 서버가 가린 작성자 표시. 앱이 따로 가리거나 만들지 않는다.
  final String? authorMasked;
  final int rating;
  final String? text;

  /// 붙은 사진(서버 순서). 수정 때 그대로 두거나 바꿀 photoId 의 출처다.
  final List<ReviewPhotoRef> photos;
  final ReviewState state;
  final int? version;
  final DateTime createdAt;

  /// 수정 기한(서버 `editableUntil` = 등록 + 3일). 앱이 계산하지 않는다.
  final DateTime? editableUntil;
  final DateTime? updatedAt;

  List<String> get photoUrls => [for (final p in photos) ?p.url];

  /// 서버가 준 도움돼요 값으로 바꾼 사본.
  ReviewView withHelpful(HelpfulResult r) => ReviewView(
    reviewId: reviewId,
    productId: productId,
    rating: rating,
    state: state,
    createdAt: createdAt,
    sku: sku,
    authorMasked: authorMasked,
    text: text,
    photos: photos,
    version: version,
    editableUntil: editableUntil,
    updatedAt: updatedAt,
    helpfulCount: r.count,
    helpedByMe: r.helped,
    reportedByMe: reportedByMe,
    repurchased: repurchased,
  );

  /// 고칠 수 있다 — 서버 상태 `PUBLISHED` 일 때만(등록 후 3일이 지나면 서버가 `LOCKED` 로 준다).
  bool get editable => state == ReviewState.published && version != null;

  /// 지울 수 있다(공개 중인 내 리뷰).
  bool get deletable =>
      state == ReviewState.published || state == ReviewState.locked;
}

/// 리뷰에 붙은 사진 하나(`Review.photos[]`).
@immutable
class ReviewPhotoRef {
  const ReviewPhotoRef({required this.photoId, this.url});

  final String photoId;

  /// 사진 본문 경로(`/api/v1/review-photos/{photoId}`).
  final String? url;
}

@immutable
class EligibilityPage {
  const EligibilityPage({required this.items, this.nextCursor, this.counts});

  final List<ReviewEligibility> items;
  final String? nextCursor;

  /// 탭 머리 숫자(review 0.5.0). 서버 값만 — 받은 쪽을 세어 만들지 않는다.
  final ReviewCounts? counts;
}

/// 리뷰관리 탭 머리 숫자: 쓸 수 있는 품목 수·쓴 리뷰 수(삭제 제외). 상태 거르기와 상관없는 전체 값.
@immutable
class ReviewCounts {
  const ReviewCounts({required this.writable, required this.written});

  final int writable;
  final int written;
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
    this.imageUrl,
  });

  ReviewTarget.of(ReviewEligibility e, {String? title, int? initialRating})
    : this(
        orderId: e.orderId,
        orderLineId: e.orderLineId,
        productId: e.productId,
        title: title ?? e.productName,
        eligibleUntil: e.eligibleUntil,
        initialRating: initialRating,
        imageUrl: e.imageUrl,
      );

  final String orderId;
  final String orderLineId;
  final String? productId;

  /// 주문 당시 상품명 사본(주문 상세에서 올 때). 없으면 상품 정보를 조회해 이름을 보인다.
  final String? title;
  final DateTime? eligibleUntil;
  final int? initialRating;

  /// 지금 상품의 대표 사진(자격 응답 값, 없으면 자리 그림). 쓰기 화면 상품 줄에 쓴다(초안 09-C).
  final String? imageUrl;
}

/// 계약 `POST /reviews`·`POST /review-photos` 422 코드.
abstract final class ReviewProblemCode {
  static const notEligible = 'NOT_ELIGIBLE';
  static const eligibilityExpired = 'ELIGIBILITY_EXPIRED';
  static const alreadyReviewed = 'ALREADY_REVIEWED';
  static const rewriteAfterDeleteForbidden = 'REWRITE_AFTER_DELETE_FORBIDDEN';

  /// 내가 올린 사진이 아니거나 다른 리뷰에 쓰인 사진(24시간 지나 지워진 사진 포함).
  static const photoNotFound = 'PHOTO_NOT_FOUND';

  /// 사진 형식(JPEG·PNG·WEBP)·크기(10MB) 거절 — 서버가 파일 내용으로 판정한다.
  static const photoInvalid = 'PHOTO_INVALID';

  /// 수정 409: 등록 후 3일이 지났거나(LOCKED) 삭제됨.
  static const invalidState = ProblemCode.invalidState;

  /// 수정 409: 다른 곳에서 먼저 고쳤다(`X-Expected-Version` 불일치).
  static const versionConflict = ProblemCode.versionConflict;
}

/// 계약 사진 한도(review 0.2.0, 사용자 결정): 리뷰당 5장, 장당 10MB. 서버가 다시 검사한다.
const reviewPhotoMax = 5;
const reviewPhotoMaxBytes = 10 * 1024 * 1024;

/// 올릴 사진 한 장(기기에 있는 원본). 미리보기는 이 바이트로 그린다(올린 사진은 공개 전에는 서버에서 열리지 않는다).
@immutable
class ReviewPhotoFile {
  const ReviewPhotoFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  @override
  String toString() => 'ReviewPhotoFile($name, ${bytes.length}B)';
}

/// 서버에 올라간 사진(`POST /review-photos` 201).
@immutable
class UploadedReviewPhoto {
  const UploadedReviewPhoto({required this.photoId, this.url});

  final String photoId;
  final String? url;
}
