import 'package:dio/dio.dart';
import 'package:pmart_api_review/pmart_api_review.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../domain/reviews.dart';

/// 리뷰 자격·작성·조회(`review-service` 계약). 실패는 [PmartFailure] 로 던진다(빈 목록으로 바꾸지 않는다).
///
/// 2026-11-04 기준 백엔드에 review-service 구현·게이트웨이 경로가 없다. 실서버 모드에서는 호출이 실패하고
/// 화면은 실패 상태를 보인다(목 모드에서만 동작).
abstract interface class ReviewsRepository {
  /// `GET /me/review-eligibilities`. [orderId]·[state] 로 좁힌다.
  Future<EligibilityPage> eligibilities({
    String? orderId,
    ReviewState? state,
    String? cursor,
  });

  /// `POST /reviews`. 같은 키·같은 본문 재전송은 같은 리뷰를 돌려줘야 한다(멱등).
  /// 사진 업로드 API 가 없어(BR-07) `photoIds` 는 보내지 않는다.
  Future<ReviewView> create({
    required String orderLineId,
    required int rating,
    String? text,
    required IdempotencyKey key,
  });

  /// `GET /reviews/{reviewId}`.
  Future<ReviewView> get(String reviewId);

  /// `GET /products/{productId}/reviews`(최신 순).
  Future<ProductReviewPage> productReviews(String productId, {String? cursor});
}

final class ApiReviewsRepository implements ReviewsRepository {
  ApiReviewsRepository(Dio dio)
    : _eligibilities = api.PmartApiReview(dio: dio).getEligibilitiesApi(),
      _reviews = api.PmartApiReview(dio: dio).getReviewsApi();

  final api.EligibilitiesApi _eligibilities;
  final api.ReviewsApi _reviews;

  @override
  Future<EligibilityPage> eligibilities({
    String? orderId,
    ReviewState? state,
    String? cursor,
  }) async {
    final res = await pmartGuard(
      () => _eligibilities.listMyReviewEligibilities(
        orderId: orderId,
        state: switch (state) {
          null => null,
          ReviewState.eligible => api.ReviewState.REV_ELIGIBLE,
          ReviewState.submitPending => api.ReviewState.SUBMIT_PENDING,
          ReviewState.published => api.ReviewState.PUBLISHED,
          ReviewState.locked => api.ReviewState.LOCKED,
          ReviewState.deleted => api.ReviewState.DELETED,
          ReviewState.expired => api.ReviewState.EXPIRED,
          ReviewState.unknown => null,
        },
        cursor: cursor,
      ),
    );
    final body =
        res.data ??
        (throw const ContractViolationFailure('Eligibility 목록 본문 없음'));
    return eligibilityPageFromContract(body);
  }

  @override
  Future<ReviewView> create({
    required String orderLineId,
    required int rating,
    String? text,
    required IdempotencyKey key,
  }) async {
    final res = await pmartGuard(
      () => _reviews.createReview(
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        createReviewRequest: api.CreateReviewRequest(
          orderLineId: orderLineId,
          rating: rating,
          text: text,
        ),
        extra: commandOptions(key).extra,
      ),
    );
    return reviewFromContract(
      res.data ?? (throw UnknownResultFailure(requestId: key.value)),
    );
  }

  @override
  Future<ReviewView> get(String reviewId) async {
    final res = await pmartGuard(() => _reviews.getReview(reviewId: reviewId));
    return reviewFromContract(
      res.data ?? (throw const ContractViolationFailure('Review 본문 없음')),
    );
  }

  @override
  Future<ProductReviewPage> productReviews(
    String productId, {
    String? cursor,
  }) async {
    final res = await pmartGuard(
      () => _reviews.listProductReviews(productId: productId, cursor: cursor),
    );
    final body =
        res.data ?? (throw const ContractViolationFailure('리뷰 목록 본문 없음'));
    return productReviewPageFromContract(body);
  }
}

EligibilityPage eligibilityPageFromContract(
  api.ListMyReviewEligibilities200Response body,
) => EligibilityPage(
  items: [
    for (final e in body.items ?? const <api.Eligibility>[])
      // 주문·품목 식별이 없으면 작성 대상으로 쓸 수 없다. 추측해 채우지 않고 뺀다.
      if ((e.orderId, e.orderLineId) case (final String o, final String l))
        ReviewEligibility(
          orderId: o,
          orderLineId: l,
          sku: e.sku,
          productId: e.productId,
          deliveredAt: e.deliveredAt,
          eligibleUntil: e.eligibleUntil,
          state: reviewStateFromWire(e.state?.value),
          reviewId: e.reviewId,
        ),
  ],
  nextCursor: body.page?.nextCursor,
);

ProductReviewPage productReviewPageFromContract(
  api.ListProductReviews200Response body,
) => ProductReviewPage(
  items: [
    for (final r in body.items ?? const <api.Review>[]) reviewFromContract(r),
  ],
  nextCursor: body.page?.nextCursor,
  averageRating: body.summary?.averageRating?.toDouble(),
  reviewCount: body.summary?.reviewCount,
);

ReviewView reviewFromContract(api.Review r) => ReviewView(
  reviewId: r.reviewId,
  productId: r.productId,
  sku: r.sku,
  authorMasked: r.authorMasked,
  rating: r.rating,
  text: r.text,
  photoUrls: [
    for (final p in r.photos ?? const <api.ReviewPhotosInner>[]) ?p.url,
  ],
  state: reviewStateFromWire(r.state.value),
  version: r.version,
  createdAt: r.createdAt,
  editableUntil: r.editableUntil,
  updatedAt: r.updatedAt,
);
