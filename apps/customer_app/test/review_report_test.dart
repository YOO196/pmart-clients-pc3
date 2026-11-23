// 리뷰 신고하기(review 0.7.0 BR-90 — 사용자 결정 2026-11-23: 회원만·사유 5·한 번만·자기 리뷰 불가).
import 'dart:async';

import 'package:customer_app/features/reviews/data/mock_reviews_repository.dart';
import 'package:customer_app/shared/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'support/app_harness.dart';

void main() {
  setUpAll(initPmartFormatting);
  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> open(
    WidgetTester t,
    MockReviewsRepository repo, {
    bool login = true,
  }) async {
    t.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp([
        imageOriginProvider.overrideWithValue('https://img.invalid'),
      ], reviews: repo),
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
    unawaited(router.push('/products/P-0002/reviews'));
    await t.pumpAndSettle();
  }

  Future<void> openSheet(WidgetTester t) async {
    final link = key('product-review-report-rv-p2-1');
    await t.scrollUntilVisible(
      link,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(link);
    await t.pumpAndSettle();
  }

  FilledButton send(WidgetTester t) => t.widget(key('review-report-send'));

  testWidgets('사유를 골라야 보낼 수 있고, 접수되면 "신고함"으로 바뀐다', (t) async {
    final repo = MockReviewsRepository(latency: Duration.zero);
    await open(t, repo);
    await openSheet(t);
    expect(key('review-report-sheet'), findsOneWidget);
    expect(send(t).onPressed, isNull);
    await t.tap(key('review-report-ad'));
    await t.pump();
    expect(send(t).onPressed, isNotNull);
    await t.tap(key('review-report-send'));
    await t.pumpAndSettle();
    expect(repo.reported, contains('rv-p2-1'));
    expect(find.text('신고가 접수됐어요'), findsOneWidget);
    expect(key('review-report-sheet'), findsNothing);
    expect(key('product-review-reported-rv-p2-1'), findsOneWidget);
  });

  testWidgets('기타는 글을 적어야 보낼 수 있다', (t) async {
    final repo = MockReviewsRepository(latency: Duration.zero);
    await open(t, repo);
    await openSheet(t);
    await t.tap(key('review-report-other'));
    await t.pump();
    expect(key('review-report-detail'), findsOneWidget);
    expect(send(t).onPressed, isNull);
    await t.enterText(key('review-report-detail'), '다른 상품 이야기예요');
    await t.pump();
    expect(send(t).onPressed, isNotNull);
  });

  testWidgets('비회원은 보내지 않고 로그인 안내', (t) async {
    final repo = MockReviewsRepository(latency: Duration.zero);
    await open(t, repo, login: false);
    await openSheet(t);
    expect(key('review-report-sheet'), findsNothing);
    expect(find.text('로그인하면 리뷰를 신고할 수 있어요'), findsOneWidget);
    expect(repo.reportKeys, isEmpty);
  });

  testWidgets('내 리뷰에는 신고하기가 없다', (t) async {
    final repo = MockReviewsRepository(latency: Duration.zero);
    await open(t, repo);
    expect(key('product-review-report-rv-mine-1'), findsNothing);
  });

  testWidgets('이미 신고했으면(409) "이미 신고한 리뷰예요"로 닫고 신고함', (t) async {
    final repo = MockReviewsRepository(latency: Duration.zero)
      ..reportFailures.add(
        const ProblemFailure(Problem(status: 409, code: 'ALREADY_REPORTED')),
      );
    await open(t, repo);
    await openSheet(t);
    await t.tap(key('review-report-abuse'));
    await t.pump();
    await t.tap(key('review-report-send'));
    await t.pumpAndSettle();
    expect(find.text('이미 신고한 리뷰예요'), findsOneWidget);
    expect(key('product-review-reported-rv-p2-1'), findsOneWidget);
  });

  testWidgets('결과를 모르면 접수로 보이지 않고, 다시 확인은 같은 키', (t) async {
    final repo = MockReviewsRepository(latency: Duration.zero)
      ..reportFailures.add(const UnknownResultFailure(requestId: 'x'));
    await open(t, repo);
    await openSheet(t);
    await t.tap(key('review-report-privacy'));
    await t.pump();
    await t.tap(key('review-report-send'));
    await t.pumpAndSettle();
    expect(find.text('신고가 접수됐어요'), findsNothing);
    expect(find.text('접수됐는지 다시 확인'), findsOneWidget);
    expect(key('product-review-reported-rv-p2-1'), findsNothing);
    await t.tap(key('review-report-send'));
    await t.pumpAndSettle();
    expect(repo.reportKeys, hasLength(2));
    expect(repo.reportKeys.toSet(), hasLength(1));
    expect(find.text('신고가 접수됐어요'), findsOneWidget);
  });
}
