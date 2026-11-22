// 카테고리 화면 레퍼런스 3-3 보강(사용자 2026-11-22 "7, 8 다 추가"):
// 맨 위 CATEGORY 배너(storefront placement=CATEGORY, BR-82), 아래 추천 타일(할인·기획전·인기·신상)·고객센터 상자.
import 'package:customer_app/features/catalog/data/mock_catalog_repository.dart';
import 'package:customer_app/features/coupons/presentation/coupon_screens.dart';
import 'package:customer_app/features/support/presentation/inquiry_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart' show initPmartFormatting;

import 'support/app_harness.dart';

void main() {
  setUpAll(initPmartFormatting);
  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> openCategories(
    WidgetTester t, {
    MockCatalogRepository? catalog,
  }) async {
    t.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const [], catalog: catalog));
    await t.pumpAndSettle();
    await t.tap(find.text('카테고리').last);
    await t.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester t, String k) async {
    await t.scrollUntilVisible(
      key(k),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
  }

  testWidgets('CATEGORY 배너가 있으면 맨 위에, 없으면 자리가 없다', (t) async {
    await openCategories(t);
    expect(key('category-banners'), findsNothing);

    await openCategories(
      t,
      catalog: MockCatalogRepository(latency: Duration.zero)
        ..placementBannersJson['CATEGORY'] = [
          {
            'bannerId': 'CB-1',
            'placement': 'CATEGORY',
            'altText': '라면 특가',
            'linkType': 'NONE',
            'sortOrder': 1,
          },
        ],
    );
    expect(key('category-banners'), findsOneWidget);
  });

  testWidgets('추천 타일 4개·고객센터 상자 — [인기]는 홈 랭킹 탭, [신상]은 신상품 탭', (t) async {
    await openCategories(t);
    await scrollTo(t, 'category-support');
    for (final k in ['discount', 'event', 'popular', 'new']) {
      expect(key('category-pick-$k'), findsOneWidget);
    }
    expect(find.text('바로픽 추천'), findsOneWidget);
    expect(find.text('자주 묻는 질문 · 채팅 상담 · 내 문의'), findsOneWidget);

    await t.tap(key('category-pick-popular'));
    await t.pumpAndSettle();
    expect(key('home-tab-body-ranking'), findsOneWidget);

    await t.tap(find.text('카테고리').last);
    await t.pumpAndSettle();
    await scrollTo(t, 'category-pick-new');
    await t.tap(key('category-pick-new'));
    await t.pumpAndSettle();
    expect(key('home-tab-body-isNew'), findsOneWidget);
  });

  testWidgets('[기획전]은 지금 MD 탭, 없으면 홈', (t) async {
    await openCategories(t);
    await scrollTo(t, 'category-pick-event');
    await t.tap(key('category-pick-event'));
    await t.pumpAndSettle();
    expect(key('home-tab-body-ranking'), findsNothing);
    expect(key('home-tab-body-isNew'), findsNothing);
    expect(key('home-scroll'), findsOneWidget);

    await openCategories(
      t,
      catalog: MockCatalogRepository(latency: Duration.zero)
        ..customTabs['X-DEAL'] = (
          title: '5일장',
          endsAt: null,
          showTimer: false,
          sections: [('S-X-2', 'THEME', '오일장 특가')],
        ),
    );
    await scrollTo(t, 'category-pick-event');
    await t.tap(key('category-pick-event'));
    await t.pumpAndSettle();
    expect(key('home-tab-body-X-DEAL'), findsOneWidget);
  });

  testWidgets('[할인]은 쿠폰함, 고객센터 상자는 고객센터로', (t) async {
    await openCategories(t);
    await scrollTo(t, 'category-pick-discount');
    await t.tap(key('category-pick-discount'));
    await t.pumpAndSettle();
    expect(find.byType(CouponBoxScreen), findsOneWidget);
    GoRouter.of(t.element(find.byType(CouponBoxScreen))).pop();
    await t.pumpAndSettle();

    await scrollTo(t, 'category-support');
    await t.tap(key('category-support'));
    await t.pumpAndSettle();
    expect(find.byType(SupportScreen), findsOneWidget);
  });
}
