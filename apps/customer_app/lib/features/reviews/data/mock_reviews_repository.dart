import 'dart:collection';

import 'package:pmart_api_review/pmart_api_review.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../domain/reviews.dart';
import 'reviews_repository.dart';

/// 목 리뷰(review-service 미구현 동안 목 모드 전용). 데이터는 계약 JSON(`Eligibility`·`Review`)으로 두고
/// 생성 모델로 읽는다. 주문·상품 참조는 주문 목(`order-seed-*`)·상품 목(`P-000*`)에 맞춘다.
final class MockReviewsRepository implements ReviewsRepository {
  MockReviewsRepository({
    this.latency = const Duration(milliseconds: 200),
    this.pageSize = 5,
    List<Map<String, dynamic>>? eligibilities,
    List<Map<String, dynamic>>? reviews,
  }) : eligibilityJson = eligibilities ?? seedEligibilities(),
       reviewJson = reviews ?? seedReviews();

  final Duration latency;
  final int pageSize;

  /// 본인 자격(계약 `Eligibility` JSON).
  final List<Map<String, dynamic>> eligibilityJson;

  /// 모든 리뷰(계약 `Review` JSON, 최신 순).
  final List<Map<String, dynamic>> reviewJson;

  /// 다음 자격 조회에서 던질 실패(앞에서부터 하나씩).
  final eligibilityFailures = Queue<PmartFailure>();

  /// 다음 작성에서 던질 실패. [createFailureApplies] 면 서버는 반영한 뒤 응답만 잃은 것처럼 한다.
  final createFailures = Queue<PmartFailure>();
  bool createFailureApplies = false;

  /// 다음 단건 조회에서 던질 실패.
  final getFailures = Queue<PmartFailure>();

  /// 다음 상품 리뷰 조회에서 던질 실패.
  final productFailures = Queue<PmartFailure>();

  final createKeys = <String>[];
  final createBodies = <({String orderLineId, int rating, String? text})>[];
  final eligibilityQueries = <({String? orderId, ReviewState? state})>[];
  final productCursors = <String?>[];
  int calls = 0;

  final _byKey = <String, String>{};
  int _seq = 0;

  Future<void> _wait() => Future<void>.delayed(latency);

  static List<Map<String, dynamic>> seedEligibilities() => [
    {
      'orderId': 'order-seed-1',
      'orderLineId': 'ol-1',
      'sku': 'E-00000001',
      'productId': 'P-0001',
      'deliveredAt': '2026-10-24T02:30:00Z',
      'eligibleUntil': '2026-11-07T02:30:00Z',
      'state': 'REV_ELIGIBLE',
      'reviewId': null,
    },
    {
      'orderId': 'order-seed-2',
      'orderLineId': 'ol-3',
      'sku': 'E-00000002',
      'productId': 'P-0002',
      'deliveredAt': '2026-10-22T08:00:00Z',
      'eligibleUntil': '2026-11-05T08:00:00Z',
      'state': 'PUBLISHED',
      'reviewId': 'rv-mine-1',
    },
  ];

  static List<Map<String, dynamic>> seedReviews() => [
    {
      'reviewId': 'rv-mine-1',
      'productId': 'P-0002',
      'sku': 'E-00000002',
      'authorMasked': '김**',
      'rating': 5,
      'text': '꾸덕하고 맛있어요. 다음에도 살게요.',
      'photos': <Object?>[],
      'state': 'PUBLISHED',
      'version': 1,
      'createdAt': '2026-10-23T01:00:00Z',
      'editableUntil': '2026-10-26T01:00:00Z',
      'updatedAt': null,
    },
    for (var i = 1; i <= 6; i++)
      {
        'reviewId': 'rv-p2-$i',
        'productId': 'P-0002',
        'sku': 'E-00000002',
        'authorMasked': '이*$i',
        'rating': i.isEven ? 4 : 5,
        'text': '그릭요거트 후기 $i',
        'state': i == 6 ? 'LOCKED' : 'PUBLISHED',
        'version': 1,
        'createdAt': '2026-10-${(20 - i).toString().padLeft(2, '0')}T03:00:00Z',
      },
  ];

  @override
  Future<EligibilityPage> eligibilities({
    String? orderId,
    ReviewState? state,
    String? cursor,
  }) async {
    calls++;
    await _wait();
    eligibilityQueries.add((orderId: orderId, state: state));
    if (eligibilityFailures.isNotEmpty) throw eligibilityFailures.removeFirst();
    final matched = [
      for (final e in eligibilityJson)
        if ((orderId == null || e['orderId'] == orderId) &&
            (state == null ||
                reviewStateFromWire(e['state'] as String?) == state))
          e,
    ];
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = (start + pageSize).clamp(0, matched.length);
    return eligibilityPageFromContract(
      api.ListMyReviewEligibilities200Response.fromJson({
        'items': matched.sublist(start, end),
        'page': {
          'nextCursor': end < matched.length ? '$end' : null,
          'size': pageSize,
        },
      }),
    );
  }

  @override
  Future<ReviewView> create({
    required String orderLineId,
    required int rating,
    String? text,
    required IdempotencyKey key,
  }) async {
    calls++;
    await _wait();
    createKeys.add(key.value);
    createBodies.add((orderLineId: orderLineId, rating: rating, text: text));
    if (createFailures.isNotEmpty) {
      final f = createFailures.removeFirst();
      if (createFailureApplies) _apply(orderLineId, rating, text, key);
      throw f;
    }
    return _apply(orderLineId, rating, text, key);
  }

  /// 서버 판정을 흉내 낸다. 같은 키 재전송은 처음 만든 리뷰를 그대로 준다.
  ReviewView _apply(
    String orderLineId,
    int rating,
    String? text,
    IdempotencyKey key,
  ) {
    if (_byKey[key.value] case final id?) return _view(id);
    final e = eligibilityJson
        .where((e) => e['orderLineId'] == orderLineId)
        .firstOrNull;
    if (e == null) {
      throw const ProblemFailure(
        Problem(status: 422, code: ReviewProblemCode.notEligible),
      );
    }
    final state = reviewStateFromWire(e['state'] as String?);
    if (state == ReviewState.deleted) {
      throw const ProblemFailure(
        Problem(
          status: 422,
          code: ReviewProblemCode.rewriteAfterDeleteForbidden,
        ),
      );
    }
    if (state == ReviewState.expired) {
      throw const ProblemFailure(
        Problem(status: 422, code: ReviewProblemCode.eligibilityExpired),
      );
    }
    if (state != ReviewState.eligible || e['reviewId'] != null) {
      throw const ProblemFailure(
        Problem(status: 422, code: ReviewProblemCode.alreadyReviewed),
      );
    }
    final id = 'rv-new-${++_seq}';
    reviewJson.insert(0, {
      'reviewId': id,
      'productId': e['productId'],
      'sku': e['sku'],
      'authorMasked': '김**',
      'rating': rating,
      'text': ?text,
      'state': 'PUBLISHED',
      'version': 1,
      'createdAt': '2026-11-04T03:00:00Z',
      'editableUntil': '2026-11-07T03:00:00Z',
    });
    e['state'] = 'PUBLISHED';
    e['reviewId'] = id;
    _byKey[key.value] = id;
    return _view(id);
  }

  ReviewView _view(String id) => reviewFromContract(
    api.Review.fromJson(reviewJson.firstWhere((r) => r['reviewId'] == id)),
  );

  @override
  Future<ReviewView> get(String reviewId) async {
    calls++;
    await _wait();
    if (getFailures.isNotEmpty) throw getFailures.removeFirst();
    if (!reviewJson.any((r) => r['reviewId'] == reviewId)) {
      throw const ProblemFailure(
        Problem(status: 404, code: ProblemCode.notFound),
      );
    }
    return _view(reviewId);
  }

  @override
  Future<ProductReviewPage> productReviews(
    String productId, {
    String? cursor,
  }) async {
    calls++;
    await _wait();
    productCursors.add(cursor);
    if (productFailures.isNotEmpty) throw productFailures.removeFirst();
    // 공개 목록은 PUBLISHED·LOCKED 만(계약).
    final visible = [
      for (final r in reviewJson)
        if (r['productId'] == productId &&
            (r['state'] == 'PUBLISHED' || r['state'] == 'LOCKED'))
          r,
    ];
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = (start + pageSize).clamp(0, visible.length);
    final ratings = [for (final r in visible) r['rating'] as int];
    return productReviewPageFromContract(
      api.ListProductReviews200Response.fromJson({
        'items': visible.sublist(start, end),
        'page': {
          'nextCursor': end < visible.length ? '$end' : null,
          'size': pageSize,
        },
        'summary': {
          'averageRating': ratings.isEmpty
              ? null
              : ratings.reduce((a, b) => a + b) / ratings.length,
          'reviewCount': visible.length,
        },
      }),
    );
  }
}
