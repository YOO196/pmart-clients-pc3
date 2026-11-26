import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/reviews/data/mock_reviews_repository.dart';
import 'package:customer_app/features/reviews/data/reviews_repository.dart';
import 'package:customer_app/features/reviews/domain/reviews.dart';
import 'package:customer_app/features/reviews/presentation/product_reviews_screen.dart'
    show reviewDate;

import 'package:customer_app/shared/providers.dart'
    show imageOriginProvider, sourceSystem;

import 'support/app_harness.dart';

/// 상품 리뷰 추천순·옵션 필터·도움돼요(review 0.6.0, BR-76).
void main() {
  setUpAll(initPmartFormatting);
  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> open(
    WidgetTester t,
    MockReviewsRepository repo,
    String productId, {
    bool login = false,
    PmartEnv env = PmartEnv.mock,
  }) async {
    t.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp(
        // 목 모드는 상대 경로 사진을 그리지 않는다 — 출처를 준다(사진 누르기 시험).
        [imageOriginProvider.overrideWithValue('https://img.invalid')],
        reviews: repo,
        env: env,
      ),
    );
    await t.pumpAndSettle();
    if (login) {
      await t.tap(find.text('마이페이지').last);
      await t.pumpAndSettle();
      await t.tap(key('my-login'));
      await t.pumpAndSettle();
      await t.tap(key('login-kakao'));
      await t.pumpAndSettle();
    }
    final router = GoRouter.of(t.element(find.byType(Scaffold).first));
    unawaited(router.push('/products/$productId/reviews'));
    await t.pumpAndSettle();
  }

  testWidgets('정렬: 기본 최신순, 시트에는 최신순·도움돼요 많은순·별점 높은 순·별점 낮은 순', (t) async {
    final repo = MockReviewsRepository(latency: Duration.zero);
    await open(t, repo, 'P-0002');
    expect(repo.productQueries.first.sort, ReviewSort.newest);
    expect(find.text('최신순'), findsOneWidget);
    await t.tap(key('review-sort-open'));
    await t.pumpAndSettle();
    expect(key('review-sort-newest'), findsOneWidget);
    expect(key('review-sort-recommended'), findsOneWidget);
    expect(key('review-sort-ratingDesc'), findsOneWidget);
    expect(key('review-sort-ratingAsc'), findsOneWidget);
    await t.tap(key('review-sort-recommended'));
    await t.pumpAndSettle();
    expect(repo.productQueries.last.sort, ReviewSort.recommended);
    expect(find.text('도움돼요 많은순'), findsOneWidget);
  });
  testWidgets('새 레퍼런스(2026-11-25)에는 옵션 필터가 없다 — 옵션이 여럿이어도', (t) async {
    final repo = MockReviewsRepository(latency: Duration.zero);
    await open(t, repo, 'P-0001'); // 서울우유: 1개·2개 묶음
    expect(key('review-option-open'), findsNothing);
    expect(repo.productQueries.every((q) => q.sku == null), isTrue);
  });

  testWidgets('옵션이 하나인 상품은 옵션 필터가 없다', (t) async {
    final repo = MockReviewsRepository(latency: Duration.zero);
    await open(t, repo, 'P-0002');
    expect(key('review-option-open'), findsNothing);
  });

  testWidgets('도움돼요: 회원이 누르면 서버 수로 바뀌고, 다시 누르면 취소', (t) async {
    final repo = MockReviewsRepository(latency: Duration.zero);
    await open(t, repo, 'P-0002', login: true);
    final button = key('product-review-helpful-rv-p2-1');
    await t.scrollUntilVisible(
      button,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    String label() => t
        .widget<Text>(find.descendant(of: button, matching: find.byType(Text)))
        .data!;
    final before = label();
    await t.tap(button);
    await t.pumpAndSettle();
    expect(repo.helped, contains('rv-p2-1'));
    final n = int.parse(before.split(' ').last);
    expect(label(), '도움돼요 ${n + 1}');
    await t.tap(button);
    await t.pumpAndSettle();
    expect(repo.helped, isNot(contains('rv-p2-1')));
    expect(label(), before);
  });

  testWidgets('도움돼요: 비회원은 보내지 않고 로그인 안내', (t) async {
    final repo = MockReviewsRepository(latency: Duration.zero);
    await open(t, repo, 'P-0002');
    final button = key('product-review-helpful-rv-p2-1');
    await t.scrollUntilVisible(
      button,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(button);
    await t.pump();
    expect(find.text('로그인하면 도움돼요를 누를 수 있어요'), findsOneWidget);
    expect(repo.helpfulKeys, isEmpty);
  });

  testWidgets('도움돼요: 내 리뷰는 버튼 없이 수만', (t) async {
    final repo = MockReviewsRepository(latency: Duration.zero);
    await open(t, repo, 'P-0002', login: true);
    expect(key('product-review-helpful-rv-mine-1'), findsNothing);
    expect(key('product-review-helpful-mine-rv-mine-1'), findsOneWidget);
  });

  testWidgets('내 리뷰인지 알아내는 동안 도움돼요 칸은 비우고, 알아낸 뒤에도 카드 높이가 같다', (t) async {
    final gate = Completer<void>();
    final repo = MockReviewsRepository(latency: Duration.zero)
      ..eligibilityGate = gate.future;
    await open(t, repo, 'P-0002', login: true);
    final card = key('product-review-rv-mine-1');
    // 아직 모름: 버튼도 "N명에게 도움이 됐어요"도 없다(버튼을 그렸다가 바꾸지 않는다).
    expect(key('product-review-helpful-rv-mine-1'), findsNothing);
    expect(key('product-review-helpful-mine-rv-mine-1'), findsNothing);
    final before = t.getSize(card);
    gate.complete();
    await t.pumpAndSettle();
    expect(key('product-review-helpful-mine-rv-mine-1'), findsOneWidget);
    expect(key('product-review-edit-rv-mine-1'), findsOneWidget);
    expect(t.getSize(card), before);
  });

  testWidgets('도움돼요: 결과를 모르면 같은 키로 한 번 더', (t) async {
    final repo = MockReviewsRepository(latency: Duration.zero)
      ..helpfulFailures.add(const UnknownResultFailure(requestId: 'x'));
    await open(t, repo, 'P-0002', login: true);
    final button = key('product-review-helpful-rv-p2-1');
    await t.scrollUntilVisible(
      button,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(button);
    await t.pumpAndSettle();
    expect(repo.helpfulKeys, hasLength(2));
    expect(repo.helpfulKeys.toSet(), hasLength(1));
    expect(repo.helped, contains('rv-p2-1'));
  });

  group('API 저장소(review 0.6.0)', () {
    late FakeAdapter adapter;
    ApiReviewsRepository api(FakeReply Function(int i) reply) {
      adapter = FakeAdapter((_, i) async => reply(i));
      return ApiReviewsRepository(
        createPmartDio(
          baseUrl: 'http://test.invalid/api/v1',
          sourceSystem: sourceSystem,
          tokens: TokenStore(MemoryKeyValueStore()),
          refresher: (_) async => null,
          adapter: adapter,
          delay: (_) async {},
        ),
      );
    }

    test(
      '목록: sort=RECOMMENDED·sku 를 보내고 helpfulCount·helpedByMe 를 옮긴다',
      () async {
        final page = await api(
          (_) => const FakeReply(
            200,
            body: {
              'items': [
                {
                  'reviewId': 'rv-1',
                  'productId': 'P-1',
                  'rating': 5,
                  'state': 'PUBLISHED',
                  'createdAt': '2026-11-20T03:00:00Z',
                  'helpfulCount': 7,
                  'helpedByMe': null,
                },
              ],
              'page': {'size': 20},
              'summary': {'averageRating': 4.5, 'reviewCount': 1},
            },
          ),
        ).productReviews('P-1', sort: ReviewSort.recommended, sku: 'S-2');
        final q = adapter.requests.single.uri.queryParameters;
        expect(q['sort'], 'RECOMMENDED');
        expect(q['sku'], 'S-2');
        expect(page.items.single.helpfulCount, 7);
        expect(page.items.single.helpedByMe, isNull);
        expect(page.reviewCount, 1);
      },
    );

    test(
      '도움돼요: 누르기 PUT·취소 DELETE /reviews/{id}/helpful, 멱등 키·출처, 서버 값',
      () async {
        final key = IdempotencyKey.generate();
        final repo = api(
          (i) => FakeReply(
            200,
            body: {
              'reviewId': 'rv-1',
              'helpfulCount': i == 0 ? 8 : 7,
              'helpedByMe': i == 0,
            },
          ),
        );
        final on = await repo.setHelpful('rv-1', on: true, key: key);
        final off = await repo.setHelpful(
          'rv-1',
          on: false,
          key: IdempotencyKey.generate(),
        );
        expect(adapter.requests[0].method, 'PUT');
        expect(adapter.requests[0].uri.path, '/api/v1/reviews/rv-1/helpful');
        expect(adapter.requests[0].headers['Idempotency-Key'], key.value);
        expect(adapter.requests[0].headers['X-Source-System'], sourceSystem);
        expect(adapter.requests[1].method, 'DELETE');
        expect(on, (count: 8, helped: true));
        expect(off, (count: 7, helped: false));
      },
    );

    test('도움돼요: 삭제된 리뷰 409 REVIEW_NOT_PUBLISHED 는 code 로 받는다', () async {
      final repo = api(
        (_) => const FakeReply(
          409,
          body: {'code': 'REVIEW_NOT_PUBLISHED', 'status': 409},
        ),
      );
      await expectLater(
        repo.setHelpful('rv-1', on: true, key: IdempotencyKey.generate()),
        throwsA(
          isA<ProblemFailure>().having(
            (f) => f.problem.code,
            'code',
            ReviewHelpfulProblemCode.notPublished,
          ),
        ),
      );
    });
  });
  testWidgets('상세 → 리뷰 전체(옵션 이름을 같이 봄) → 같은 상품 상세를 다시 열어도 오류 없이 열린다', (
    t,
  ) async {
    final repo = MockReviewsRepository(latency: Duration.zero);
    await open(t, repo, 'P-0001');
    final router = GoRouter.of(t.element(find.byType(Scaffold).first));
    unawaited(router.push('/products/P-0001'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(key('product-price'), findsOneWidget);
  });
  testWidgets('리뷰 사진 → 사진 후기 → [구매하기]로 상품 상세, 도움돼요는 카드 왼쪽', (t) async {
    final repo = MockReviewsRepository(latency: Duration.zero);
    await open(t, repo, 'P-0001');
    // 만든 리뷰 0번은 사진 리뷰
    final photo = key('review-photo-rv-gen-P-0001-0-0');
    await t.scrollUntilVisible(
      photo,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    final card = key('product-review-rv-gen-P-0001-0');
    // 재구매(review 0.9.0 repurchased) — 0번은 true, 1번은 false.
    expect(key('review-repurchased-rv-gen-P-0001-0'), findsOneWidget);
    expect(key('review-repurchased-rv-gen-P-0001-1'), findsNothing);
    final button = key('product-review-helpful-rv-gen-P-0001-0');
    await t.scrollUntilVisible(
      button,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      t.getTopLeft(button).dx,
      closeTo(t.getTopLeft(card).dx + 16.7, 1),
      reason: '사용자 레퍼런스 2026-11-25 — 도움돼요는 카드 왼쪽(여백 16.7)',
    );
    await t.scrollUntilVisible(
      photo,
      -200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(photo);
    await t.pumpAndSettle();
    // 사진 후기(그 리뷰 한 건) — 큰 사진을 누르면 확대 보기, [구매하기]는 상품 상세
    expect(key('review-photo-detail'), findsOneWidget);
    expect(key('review-photo-detail-wish'), findsOneWidget);
    await t.tap(key('review-photo-detail-0'));
    await t.pumpAndSettle();
    expect(key('review-photo-viewer'), findsOneWidget);
    await t.tap(key('review-photo-viewer-close'));
    await t.pumpAndSettle();
    await t.tap(key('review-photo-detail-buy'));
    await t.pumpAndSettle();
    expect(key('review-photo-detail'), findsNothing);
    expect(key('product-price'), findsOneWidget);
  });

  testWidgets('사진 후기: 작은 사진을 누르면 큰 사진이 바뀌고, 도움돼요는 서버 값으로 목록과 같이 바뀐다', (
    t,
  ) async {
    final repo = MockReviewsRepository(latency: Duration.zero);
    await open(t, repo, 'P-0001', login: true);
    final photo = key('review-photo-rv-gen-P-0001-0-0');
    await t.scrollUntilVisible(
      photo,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(photo);
    await t.pumpAndSettle();
    expect(key('review-photo-detail'), findsOneWidget);
    final button = key('product-review-helpful-rv-gen-P-0001-0');
    String label() => t
        .widget<Text>(find.descendant(of: button, matching: find.byType(Text)))
        .data!;
    final before = int.parse(label().split(' ').last);
    await t.tap(button);
    await t.pumpAndSettle();
    expect(repo.helped, contains('rv-gen-P-0001-0'));
    expect(label(), '도움돼요 ${before + 1}');
    // 목록으로 돌아가도 같은 값(서버가 준 값으로 바뀐 목록)
    Navigator.of(t.element(key('review-photo-detail'))).pop();
    await t.pumpAndSettle();
    expect(label(), '도움돼요 ${before + 1}');
  });

  test('리뷰 날짜는 서울 달력 yyyy.MM.dd', () {
    expect(reviewDate(DateTime.utc(2026, 9, 23, 16)), '2026.09.24');
  });
  testWidgets('장바구니 상품 이름·사진을 누르면 그 상품 상세', (t) async {
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await t.tap(find.text('장바구니').last);
    await t.pumpAndSettle();
    await t.tap(key('cart-open-product-ci-1'));
    await t.pumpAndSettle();
    expect(find.text('서울우유 1L'), findsWidgets);
    expect(key('product-price'), findsOneWidget);
    Navigator.of(t.element(find.byType(Scaffold).last)).pop();
    await t.pumpAndSettle();
    await t.tap(key('cart-open-product-image-ci-2'));
    await t.pumpAndSettle();
    expect(find.text('감자칩 오리지널 110g'), findsWidgets);
  });
}
