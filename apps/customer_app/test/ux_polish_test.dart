import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/features/catalog/presentation/category_browse_screen.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/catalog/data/mock_catalog_repository.dart';
import 'package:customer_app/features/catalog/presentation/product_detail_screen.dart';

import 'support/app_harness.dart';

/// 사용자 요청(2026-11-20): 카테고리 화면 밀어 넣기, 홈 검색창 고정, 읽는 중 자리 표시.
void main() {
  setUpAll(initPmartFormatting);

  void tall(WidgetTester t) {
    t.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  testWidgets('홈 카테고리: 오른쪽에서 밀려 들어오고, 뒤로 가면 오른쪽으로 빠진다', (t) async {
    tall(t);
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    final category = find
        .byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('home-category-'),
        )
        .first;
    await t.ensureVisible(category);
    await t.pumpAndSettle();
    await t.tap(category);
    await t.pump();
    await t.pump(const Duration(milliseconds: 120));
    // 들어오는 중: 새 화면 왼쪽 끝이 화면 오른쪽 쪽에 있다.
    final entering = t.getTopLeft(find.byType(CategoryBrowseScreen)).dx;
    expect(entering, greaterThan(0));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.byType(CategoryBrowseScreen)).dx, 0);
    // 초안 15 B·레퍼런스 3-3: 카테고리 화면은 아래 탭 막대를 둔 채 연다.
    expect(find.byType(NavigationBar), findsOneWidget);

    await t.tap(find.byType(BackButton));
    await t.pump();
    await t.pump(const Duration(milliseconds: 120));
    expect(t.getTopLeft(find.byType(CategoryBrowseScreen)).dx, greaterThan(0));
    await t.pumpAndSettle();
    expect(find.byType(CategoryBrowseScreen), findsNothing);
  });

  testWidgets('상품 상세: 상품을 누르면 오른쪽에서 밀려 들어오고, 뒤로 가면 오른쪽으로 빠진다', (t) async {
    tall(t);
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await t.tap(find.text('검색').last);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('search-field')), '우유');
    await t.tap(find.byKey(const ValueKey('search-submit')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('tile-P-0001')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 120));
    expect(t.getTopLeft(find.byType(ProductDetailScreen)).dx, greaterThan(0));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.byType(ProductDetailScreen)).dx, 0);

    await t.binding.handlePopRoute();
    await t.pump();
    await t.pump(const Duration(milliseconds: 120));
    expect(t.getTopLeft(find.byType(ProductDetailScreen)).dx, greaterThan(0));
    await t.pumpAndSettle();
    expect(find.byType(ProductDetailScreen), findsNothing);
  });

  testWidgets('홈을 아래로 내려도 검색창은 위에 붙어 남는다', (t) async {
    tall(t);
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    final search = find.byKey(const ValueKey('home-search'));
    final before = t.getTopLeft(search).dy;
    await t.drag(
      find.byKey(const ValueKey('home-scroll')),
      const Offset(0, -1500),
    );
    await t.pumpAndSettle();
    expect(search, findsOneWidget);
    final after = t.getTopLeft(search).dy;
    // 앱바(주소·알림) 바로 아래에 붙는다 — 화면 밖으로 사라지지 않는다.
    expect(after, lessThan(before));
    expect(after, greaterThan(0));
    expect(after, lessThan(140));
  });

  testWidgets('검색 결과를 읽는 중에는 상품 격자 자리 표시', (t) async {
    tall(t);
    await t.pumpWidget(
      testApp(
        const [],
        catalog: MockCatalogRepository(
          latency: const Duration(milliseconds: 500),
        ),
      ),
    );
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    await t.tap(find.text('검색').last);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('search-field')), '우유');
    await t.tap(find.byKey(const ValueKey('search-submit')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(find.byType(PmartGridSkeleton), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(find.byType(PmartGridSkeleton), findsNothing);
    expect(find.byKey(const ValueKey('tile-P-0001')), findsOneWidget);
    // 결과 뒤에 읽는 "찾으시는 키워드의 할인 상품" 줄(초안 16 B)도 마저 받는다.
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
  });
}
