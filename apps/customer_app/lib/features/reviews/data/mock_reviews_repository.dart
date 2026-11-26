import 'dart:collection';

import 'package:pmart_api_review/pmart_api_review.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../../catalog/data/mock_catalog_repository.dart' show mockProducts;
import '../domain/reviews.dart';
import 'reviews_repository.dart';

/// 목 리뷰(목 모드 전용). 데이터는 계약 JSON(`Eligibility`·`Review`·`ReviewPhoto`)으로 두고
/// 생성 모델로 읽는다. 주문·상품 참조는 주문 목(`order-seed-*`)·상품 목(`P-000*`)에 맞춘다.
final class MockReviewsRepository implements ReviewsRepository {
  MockReviewsRepository({
    this.latency = const Duration(milliseconds: 200),
    this.pageSize = 5,
    List<Map<String, dynamic>>? eligibilities,
    List<Map<String, dynamic>>? reviews,
    this.synthesizeFromCatalog = true,
  }) : eligibilityJson = eligibilities ?? seedEligibilities(),
       reviewJson = reviews ?? seedReviews();

  /// 심어 둔 리뷰가 없는 상품의 리뷰를 상품 목(별점·리뷰 수)에 맞춰 만든다. 시험에서 "리뷰 0건"을 보려면 끈다.
  final bool synthesizeFromCatalog;

  final Duration latency;
  final int pageSize;

  /// 본인 자격(계약 `Eligibility` JSON).
  final List<Map<String, dynamic>> eligibilityJson;

  /// 모든 리뷰(계약 `Review` JSON, 최신 순).
  final List<Map<String, dynamic>> reviewJson;

  /// 다음 자격 조회에서 던질 실패(앞에서부터 하나씩).
  final eligibilityFailures = Queue<PmartFailure>();

  /// 있으면 [eligibilities] 가 이것이 끝날 때까지 기다린다(첫 로딩 중 화면을 보는 시험).
  Future<void>? eligibilityGate;

  /// 다음 작성에서 던질 실패. [createFailureApplies] 면 서버는 반영한 뒤 응답만 잃은 것처럼 한다.
  final createFailures = Queue<PmartFailure>();
  bool createFailureApplies = false;

  /// 다음 단건 조회에서 던질 실패.
  final getFailures = Queue<PmartFailure>();

  /// 다음 상품 리뷰 조회에서 던질 실패.
  final productFailures = Queue<PmartFailure>();

  /// 다음 사진 올리기에서 던질 실패(앞에서부터 하나씩).
  final uploadFailures = Queue<PmartFailure>();

  final createKeys = <String>[];
  final createBodies =
      <
        ({String orderLineId, int rating, String? text, List<String> photoIds})
      >[];
  final uploadKeys = <String>[];

  /// 다음 수정·삭제에서 던질 실패. [updateFailureApplies]·[deleteFailureApplies] 면 반영한 뒤 응답만 잃은 것처럼 한다.
  final updateFailures = Queue<PmartFailure>();
  bool updateFailureApplies = false;
  final deleteFailures = Queue<PmartFailure>();
  bool deleteFailureApplies = false;

  final updateKeys = <String>[];
  final updateBodies =
      <
        ({
          String reviewId,
          int expectedVersion,
          int? rating,
          String? text,
          List<String>? photoIds,
        })
      >[];
  final deleteKeys = <String>[];
  final _updatedByKey = <String, String>{};

  /// 올린 사진 photoId → 붙은 리뷰(아직 안 붙었으면 null).
  final uploadedPhotos = <String, String?>{};
  final _photoByKey = <String, String>{};
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
      'productName': '서울우유 1L',
      'deliveredAt': '2026-10-24T02:30:00Z',
      'eligibleUntil': '2026-11-07T02:30:00Z',
      'state': 'REV_ELIGIBLE',
      'reviewId': null,
      'orderedAt': '2026-10-24T01:10:00Z',
      'mfcName': '바로픽 부산동래',
      'optionLabel': '1개',
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
      'orderedAt': '2026-10-22T06:40:00Z',
      'mfcName': '바로픽 부산동래',
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
    if (eligibilityGate case final g?) await g;
    eligibilityQueries.add((orderId: orderId, state: state));
    if (eligibilityFailures.isNotEmpty) throw eligibilityFailures.removeFirst();
    final matched = [
      for (final e in eligibilityJson)
        if ((orderId == null || e['orderId'] == orderId) &&
            (state == null ||
                reviewStateFromWire(e['state'] as String?) == state))
          e,
    ];
    // 탭 머리 숫자: 상태 거르기와 상관없이, 주문 거르기는 따른다(review 0.5.0).
    final inOrder = [
      for (final e in eligibilityJson)
        if (orderId == null || e['orderId'] == orderId) e,
    ];
    bool isState(Map<String, dynamic> e, ReviewState s) =>
        reviewStateFromWire(e['state'] as String?) == s;
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = (start + pageSize).clamp(0, matched.length);
    return eligibilityPageFromContract(
      api.ListMyReviewEligibilities200Response.fromJson({
        // BR-86: 품목마다 그 주문의 지금 쓸 수 있는 품목 수(쪽과 상관없이).
        'items': [
          for (final e in matched.sublist(start, end))
            {
              ...e,
              'orderWritableCount': eligibilityJson
                  .where(
                    (x) =>
                        x['orderId'] == e['orderId'] &&
                        reviewStateFromWire(x['state'] as String?) ==
                            ReviewState.eligible &&
                        x['reviewId'] == null,
                  )
                  .length,
            },
        ],
        'page': {
          'nextCursor': end < matched.length ? '$end' : null,
          'size': pageSize,
        },
        'total': matched.length,
        'counts': {
          'writable': inOrder
              .where(
                (e) =>
                    isState(e, ReviewState.eligible) && e['reviewId'] == null,
              )
              .length,
          'written': inOrder
              .where(
                (e) =>
                    e['reviewId'] != null &&
                    !isState(e, ReviewState.deleted) &&
                    !isState(e, ReviewState.eligible),
              )
              .length,
        },
      }),
    );
  }

  @override
  Future<ReviewView> create({
    required String orderLineId,
    required int rating,
    String? text,
    List<String> photoIds = const [],
    required IdempotencyKey key,
  }) async {
    calls++;
    await _wait();
    createKeys.add(key.value);
    createBodies.add((
      orderLineId: orderLineId,
      rating: rating,
      text: text,
      photoIds: photoIds,
    ));
    if (createFailures.isNotEmpty) {
      final f = createFailures.removeFirst();
      if (createFailureApplies) {
        _apply(orderLineId, rating, text, photoIds, key);
      }
      throw f;
    }
    return _apply(orderLineId, rating, text, photoIds, key);
  }

  @override
  Future<UploadedReviewPhoto> uploadPhoto(
    ReviewPhotoFile photo, {
    required IdempotencyKey key,
  }) async {
    calls++;
    await _wait();
    uploadKeys.add(key.value);
    if (uploadFailures.isNotEmpty) throw uploadFailures.removeFirst();
    if (_photoByKey[key.value] case final id?) {
      return UploadedReviewPhoto(photoId: id, url: '/api/v1/review-photos/$id');
    }
    if (photo.bytes.isEmpty || photo.bytes.length > reviewPhotoMaxBytes) {
      throw const ProblemFailure(
        Problem(status: 422, code: ReviewProblemCode.photoInvalid),
      );
    }
    final id = 'rph-${++_seq}';
    _photoByKey[key.value] = id;
    uploadedPhotos[id] = null;
    final body = api.ReviewPhoto.fromJson({
      'photoId': id,
      'url': '/api/v1/review-photos/$id',
      'contentType': 'image/jpeg',
      'sizeBytes': photo.bytes.length,
      'uploadedAt': '2026-11-16T03:00:00Z',
    });
    return UploadedReviewPhoto(photoId: body.photoId, url: body.url);
  }

  /// 서버 판정을 흉내 낸다. 같은 키 재전송은 처음 만든 리뷰를 그대로 준다.
  ReviewView _apply(
    String orderLineId,
    int rating,
    String? text,
    List<String> photoIds,
    IdempotencyKey key,
  ) {
    if (_byKey[key.value] case final id?) return _view(id);
    // 내가 올렸고 아직 어느 리뷰에도 안 붙은 사진만(계약 PHOTO_NOT_FOUND).
    if (photoIds.any(
      (p) => !uploadedPhotos.containsKey(p) || uploadedPhotos[p] != null,
    )) {
      throw const ProblemFailure(
        Problem(status: 422, code: ReviewProblemCode.photoNotFound),
      );
    }
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
      'photos': [
        for (final p in photoIds)
          {'photoId': p, 'url': '/api/v1/review-photos/$p'},
      ],
      'state': 'PUBLISHED',
      'version': 1,
      'createdAt': '2026-11-04T03:00:00Z',
      'editableUntil': '2026-11-07T03:00:00Z',
    });
    e['state'] = 'PUBLISHED';
    e['reviewId'] = id;
    for (final p in photoIds) {
      uploadedPhotos[p] = id;
    }
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
  Future<ReviewView> update(
    String reviewId, {
    required int expectedVersion,
    int? rating,
    String? text,
    List<String>? photoIds,
    required IdempotencyKey key,
  }) async {
    calls++;
    await _wait();
    updateKeys.add(key.value);
    updateBodies.add((
      reviewId: reviewId,
      expectedVersion: expectedVersion,
      rating: rating,
      text: text,
      photoIds: photoIds,
    ));
    ReviewView apply() =>
        _applyUpdate(reviewId, expectedVersion, rating, text, photoIds, key);
    if (updateFailures.isNotEmpty) {
      final f = updateFailures.removeFirst();
      if (updateFailureApplies) apply();
      throw f;
    }
    return apply();
  }

  /// 서버 판정을 흉내 낸다(계약 PATCH /reviews/{id}). 같은 키 재전송은 처음 결과를 그대로 준다.
  ReviewView _applyUpdate(
    String reviewId,
    int expectedVersion,
    int? rating,
    String? text,
    List<String>? photoIds,
    IdempotencyKey key,
  ) {
    if (_updatedByKey[key.value] case final id?) return _view(id);
    final r = reviewJson.where((r) => r['reviewId'] == reviewId).firstOrNull;
    if (r == null) {
      throw const ProblemFailure(
        Problem(status: 404, code: ProblemCode.notFound),
      );
    }
    if (r['state'] != 'PUBLISHED') {
      throw const ProblemFailure(
        Problem(status: 409, code: ReviewProblemCode.invalidState),
      );
    }
    if (r['version'] != expectedVersion) {
      throw const ProblemFailure(
        Problem(status: 409, code: ReviewProblemCode.versionConflict),
      );
    }
    if (rating == null && text == null && photoIds == null) {
      throw const ProblemFailure(
        Problem(status: 400, code: ProblemCode.validationFailed),
      );
    }
    if (photoIds != null &&
        photoIds.any(
          (p) =>
              !uploadedPhotos.containsKey(p) ||
              (uploadedPhotos[p] != null && uploadedPhotos[p] != reviewId),
        )) {
      throw const ProblemFailure(
        Problem(status: 422, code: ReviewProblemCode.photoNotFound),
      );
    }
    if (rating != null) r['rating'] = rating;
    if (text != null) r['text'] = text;
    if (photoIds != null) {
      // 빠진 사진은 서버가 정리한다.
      uploadedPhotos.removeWhere(
        (p, owner) => owner == reviewId && !photoIds.contains(p),
      );
      for (final p in photoIds) {
        uploadedPhotos[p] = reviewId;
      }
      r['photos'] = [
        for (final p in photoIds)
          {'photoId': p, 'url': '/api/v1/review-photos/$p'},
      ];
    }
    r['version'] = (r['version'] as int) + 1;
    r['updatedAt'] = '2026-11-16T04:00:00Z';
    _updatedByKey[key.value] = reviewId;
    return _view(reviewId);
  }

  @override
  Future<void> delete(String reviewId, {required IdempotencyKey key}) async {
    calls++;
    await _wait();
    deleteKeys.add(key.value);
    void apply() {
      final r = reviewJson.where((r) => r['reviewId'] == reviewId).firstOrNull;
      if (r == null) {
        throw const ProblemFailure(
          Problem(status: 404, code: ProblemCode.notFound),
        );
      }
      // 이미 삭제여도 성공(멱등).
      r['state'] = 'DELETED';
      for (final e in eligibilityJson) {
        if (e['reviewId'] == reviewId) e['state'] = 'DELETED';
      }
      uploadedPhotos.removeWhere((_, owner) => owner == reviewId);
    }

    if (deleteFailures.isNotEmpty) {
      final f = deleteFailures.removeFirst();
      if (deleteFailureApplies) apply();
      throw f;
    }
    apply();
  }

  @override
  Future<ProductReviewPage> productReviews(
    String productId, {
    String? cursor,
    ReviewSort sort = ReviewSort.newest,
    bool withPhotoOnly = false,
    String? sku,
  }) async {
    calls++;
    productQueries.add((sort: sort, photoOnly: withPhotoOnly, sku: sku));
    await _wait();
    productCursors.add(cursor);
    if (productFailures.isNotEmpty) throw productFailures.removeFirst();
    // 공개 목록은 PUBLISHED·LOCKED 만(계약).
    final visible = [
      for (final r in reviewJson)
        if (r['productId'] == productId &&
            (r['state'] == 'PUBLISHED' || r['state'] == 'LOCKED') &&
            (sku == null || r['sku'] == sku) &&
            (!withPhotoOnly || ((r['photos'] as List?)?.isNotEmpty ?? false)))
          r,
    ];
    _sortJson(visible, sort);
    final start = cursor == null ? 0 : int.parse(cursor);
    // 심어 둔 리뷰가 없는 상품은 상품 목(별점·리뷰 수)과 같게 그때그때 만든다 — 상세 위 "★4.8 (1,203)" 과
    // 아래 "리뷰 0개"가 어긋나지 않게(실서버는 같은 집계에서 온다). 요청한 쪽만 만든다.
    final product = mockProducts
        .where((p) => p.productId == productId)
        .firstOrNull;
    // 옵션 조건이 대표 SKU 가 아니면(묶음 등) 만든 리뷰가 없다 — 빈 목록.
    if (visible.isEmpty &&
        synthesizeFromCatalog &&
        product != null &&
        (sku == null || sku == product.sku) &&
        (product.reviewCount ?? 0) > 0) {
      // 목: 3건마다 1건이 사진 리뷰. 사진 리뷰만이면 그 건들만.
      final all = product.reviewCount!;
      final total = withPhotoOnly ? (all / 3).ceil() : all;
      int at(int i) => withPhotoOnly ? i * 3 : i;
      final avg = product.rating ?? 5;
      int rate(int n) => (n % 4 == 3 ? avg - 1 : avg).round().clamp(1, 5);
      final end = (start + pageSize).clamp(0, total);
      return _withHelpful(
        productReviewPageFromContract(
          api.ListProductReviews200Response.fromJson({
            'items': [
              for (var i = start; i < end; i++)
                _genReview(productId, product.sku, product.name, switch (sort) {
                  // 별점순은 높은(낮은) 것부터 — 목은 번호를 별점 묶음 순으로 다시 센다.
                  // 추천순: 만든 리뷰는 앞 번호일수록 도움돼요가 많다(목) — 최근 등록순과 같은 차례.
                  ReviewSort.newest || ReviewSort.recommended => at(i),
                  ReviewSort.ratingDesc => at(i),
                  ReviewSort.ratingAsc => at(total - 1 - i),
                }, rate),
            ],
            'page': {
              'nextCursor': end < total ? '$end' : null,
              'size': pageSize,
            },
            'summary': {'averageRating': avg, 'reviewCount': total},
          }),
        ),
      );
    }
    final end = (start + pageSize).clamp(0, visible.length);
    final ratings = [for (final r in visible) r['rating'] as int];
    return _withHelpful(
      productReviewPageFromContract(
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
      ),
    );
  }

  /// 받은 상품 리뷰 조회 조건(시험용).
  final productQueries = <({ReviewSort sort, bool photoOnly, String? sku})>[];

  // ── 도움돼요(BR-76 제안 — 계약 전, 목만) ──

  /// 내가 도움돼요를 누른 리뷰.
  final helped = <String>{};

  /// 보낸 도움돼요 요청 키(시험용 — 같은 행위는 같은 키).
  final helpfulKeys = <String>[];

  /// 다음 도움돼요 요청을 실패시킨다.
  final helpfulFailures = Queue<PmartFailure>();
  final _helpfulByKey = <String, HelpfulResult>{};

  /// 목의 다른 사람 도움돼요 수(리뷰 ID 로 정한 값). 만든 리뷰는 앞 번호일수록 많다.
  static int _baseHelpful(String reviewId) {
    final gen = RegExp(r'^rv-gen-.+-(\d+)$').firstMatch(reviewId);
    if (gen != null) return (30 - int.parse(gen.group(1)!)).clamp(0, 30);
    return reviewId.codeUnits.fold(0, (a, c) => a + c) % 15;
  }

  int _helpfulCount(String reviewId) =>
      _baseHelpful(reviewId) + (helped.contains(reviewId) ? 1 : 0);

  ProductReviewPage _withHelpful(ProductReviewPage p) => ProductReviewPage(
    items: [
      for (final r in p.items)
        r.withHelpful((
          count: _helpfulCount(r.reviewId),
          helped: helped.contains(r.reviewId),
        )),
    ],
    nextCursor: p.nextCursor,
    averageRating: p.averageRating,
    reviewCount: p.reviewCount,
  );

  @override
  Future<HelpfulResult> setHelpful(
    String reviewId, {
    required bool on,
    required IdempotencyKey key,
  }) async {
    await _wait();
    helpfulKeys.add(key.value);
    if (_helpfulByKey[key.value] case final r?) return r;
    if (helpfulFailures.isNotEmpty) throw helpfulFailures.removeFirst();
    // 내 리뷰는 누를 수 없다(목: 내가 쓴 리뷰는 rv-mine-*).
    if (reviewId.startsWith('rv-mine')) {
      throw const ProblemFailure(
        Problem(status: 422, code: ReviewHelpfulProblemCode.ownReview),
      );
    }
    on ? helped.add(reviewId) : helped.remove(reviewId);
    final r = (count: _helpfulCount(reviewId), helped: on);
    _helpfulByKey[key.value] = r;
    return r;
  }

  /// 신고한 리뷰(목) · 보낸 신고 키.
  final reported = <String>{};
  final reportKeys = <String>[];

  /// 시험용: 다음 신고에 던질 실패.
  final reportFailures = Queue<PmartFailure>();

  @override
  Future<void> report(
    String reviewId, {
    required ReviewReportReason reason,
    String? detail,
    required IdempotencyKey key,
  }) async {
    await _wait();
    final again = reportKeys.contains(key.value);
    reportKeys.add(key.value);
    if (reportFailures.isNotEmpty) throw reportFailures.removeFirst();
    if (again && reported.contains(reviewId)) return;
    if (reviewId.startsWith('rv-mine')) {
      throw const ProblemFailure(
        Problem(status: 422, code: ReviewReportProblemCode.ownReview),
      );
    }
    if (reason == ReviewReportReason.other &&
        (detail == null || detail.trim().isEmpty)) {
      throw const ProblemFailure(
        Problem(status: 400, code: 'VALIDATION_FAILED'),
      );
    }
    if (!reported.add(reviewId)) {
      throw const ProblemFailure(
        Problem(status: 409, code: ReviewReportProblemCode.alreadyReported),
      );
    }
  }

  static void _sortJson(List<Map<String, Object?>> list, ReviewSort sort) {
    int rating(Map<String, Object?> r) => r['rating'] as int;
    String at(Map<String, Object?> r) => r['createdAt'] as String;
    list.sort(
      (a, b) => switch (sort) {
        ReviewSort.newest => at(b).compareTo(at(a)),
        // 추천순(목): 도움돼요 많은 순, 같으면 최근 등록순.
        ReviewSort.recommended => switch (_baseHelpful(b['reviewId']! as String)
            .compareTo(_baseHelpful(a['reviewId']! as String))) {
          0 => at(b).compareTo(at(a)),
          final c => c,
        },
        ReviewSort.ratingDesc => rating(b).compareTo(rating(a)),
        ReviewSort.ratingAsc => rating(a).compareTo(rating(b)),
      },
    );
  }

  Map<String, Object?> _genReview(
    String productId,
    String? sku,
    String name,
    int i,
    int Function(int) rate,
  ) => {
    'reviewId': 'rv-gen-$productId-$i',
    'productId': productId,
    'sku': sku,
    'authorMasked': '${'김이박최정'[i % 5]}**',
    // review 0.9.0 재구매 — 네 번째마다 true.
    'repurchased': i % 4 == 0,
    'rating': rate(i),
    'text': '[목] $name 후기 ${i + 1}',
    if (i % 3 == 0)
      'photos': [
        {
          'photoId': 'rp-gen-$productId-$i',
          'url': '/api/v1/review-photos/rp-gen-$productId-$i',
        },
      ],
    'state': 'PUBLISHED',
    'version': 1,
    'createdAt': DateTime.utc(
      2026,
      10,
      20,
    ).subtract(Duration(hours: i * 7)).toIso8601String(),
  };
}
