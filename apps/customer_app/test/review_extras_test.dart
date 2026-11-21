import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/reviews/data/mock_reviews_repository.dart';
import 'package:customer_app/features/reviews/data/reviews_repository.dart';
import 'package:customer_app/features/reviews/domain/reviews.dart';

import 'support/app_harness.dart';

/// 상품 리뷰 추천순·옵션 필터·도움돼요(BR-76 — 계약 전, 목 모드만).
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
    await t.pumpWidget(testApp(const [], reviews: repo, env: env));
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

  testWidgets('목 모드: 기본 추천순, 정렬에 추천순·최근 등록순', (t) async {
    final repo = MockReviewsRepository(latency: Duration.zero);
    await open(t, repo, 'P-0002');
    expect(repo.productQueries.first.sort, ReviewSort.recommended);
    expect(find.text('추천순'), findsOneWidget);
    await t.tap(key('review-sort-open'));
    await t.pumpAndSettle();
    expect(key('review-sort-recommended'), findsOneWidget);
    expect(find.text('최근 등록순'), findsOneWidget);
  });

  testWidgets('실서버 모드: 추천순·옵션·도움돼요가 없다(계약 전)', (t) async {
    final repo = MockReviewsRepository(latency: Duration.zero);
    await open(t, repo, 'P-0001', env: PmartEnv.local);
    expect(repo.productQueries.first.sort, ReviewSort.newest);
    expect(key('review-option-open'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(
              'product-review-helpful-',
            ),
      ),
      findsNothing,
    );
    await t.tap(key('review-sort-open'));
    await t.pumpAndSettle();
    expect(key('review-sort-recommended'), findsNothing);
  });

  testWidgets('옵션이 2개 이상인 상품만 옵션 필터 — 고르면 그 SKU 로 묻는다', (t) async {
    final repo = MockReviewsRepository(latency: Duration.zero);
    await open(t, repo, 'P-0001'); // 서울우유: 1개·2개 묶음
    expect(key('review-option-open'), findsOneWidget);
    await t.tap(key('review-option-open'));
    await t.pumpAndSettle();
    await t.tap(key('review-option-B-00000011'));
    await t.pumpAndSettle();
    expect(repo.productQueries.last.sku, 'B-00000011');
    expect(t.widget<Text>(key('review-option-label')).data, '2개 묶음');
    await t.tap(key('review-option-open'));
    await t.pumpAndSettle();
    await t.tap(key('review-option-all'));
    await t.pumpAndSettle();
    expect(repo.productQueries.last.sku, isNull);
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

  test('API 저장소는 계약 전 조건·도움돼요를 실서버에 보내지 않는다', () async {
    final repo = ApiReviewsRepository(Dio());
    expect(
      () => repo.setHelpful('r-1', on: true, key: IdempotencyKey.generate()),
      throwsUnsupportedError,
    );
    expect(
      () => repo.productReviews('P-1', sku: 'S-1'),
      throwsUnsupportedError,
    );
    expect(
      () => repo.productReviews('P-1', sort: ReviewSort.recommended),
      throwsUnsupportedError,
    );
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
}
