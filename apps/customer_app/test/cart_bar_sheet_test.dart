import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_ui/pmart_ui.dart' show initPmartFormatting;

import 'package:customer_app/features/cart/data/mock_cart_repository.dart';
import 'package:customer_app/features/catalog/domain/catalog.dart';
import 'package:customer_app/features/catalog/presentation/catalog_providers.dart';
import 'package:customer_app/shared/cart_recommendations.dart';

import 'support/app_harness.dart';

ProductTile _tile(int i) => ProductTile(
  productId: 'R$i',
  name: '추천 상품 $i',
  saleState: SaleState.onSale,
  carried: true,
  basePrice: 1000 * i,
);

/// 고정 추천 6개(시트 그리기 확인용).
class _Recs extends CartRecommendationsController {
  @override
  Future<List<ProductTile>> build() async => [
    for (var i = 1; i <= 6; i++) _tile(i),
  ];
}

/// 장바구니 막대 ^ → 추천 시트(사용자 새 UI 2026-11-24).
void main() {
  setUpAll(initPmartFormatting);
  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> open(
    WidgetTester t, {
    List<Override> overrides = const [],
  }) async {
    t.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp(
        overrides,
        cart: MockCartRepository(latency: Duration.zero, minOrderAmount: 0)
          ..seedLine('E-00000002', 2),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('닫힌 막대: 금액 옆 할인 전 금액(줄 긋기)과 ^ — 누르면 시트, ⌄ 를 누르면 닫힌다', (t) async {
    await open(
      t,
      overrides: [cartRecommendationsProvider.overrideWith(_Recs.new)],
    );
    expect(key('home-cart-before'), findsOneWidget);
    await t.tap(key('home-cart-expand'));
    await t.pumpAndSettle();
    expect(key('cart-bar-sheet'), findsOneWidget);
    expect(find.text('회원님을 위한 추천 상품'), findsOneWidget);
    for (var i = 1; i <= 6; i++) {
      expect(key('cart-reco-R$i'), findsOneWidget);
    }
    await t.tap(key('home-cart-collapse'));
    await t.pumpAndSettle();
    expect(key('cart-bar-sheet'), findsNothing);
  });

  test('홈 첫 상품 영역에서 6개씩, 다음은 이어서·끝이면 처음으로(다음 묶음 없을 때)', () async {
    final home = HomeView(
      layoutVersion: 1,
      tabs: const [HomeTab.home],
      banners: const [],
      sections: [
        HomeSection(
          sectionId: 'S1',
          kind: SectionKind.weeklyPick,
          title: '이번 주 추천',
          available: true,
          items: [for (var i = 1; i <= 8; i++) _tile(i)],
        ),
      ],
    );
    final c = ProviderContainer(
      overrides: [homeProvider.overrideWith((_) async => home)],
    );
    addTearDown(c.dispose);
    c.listen(cartRecommendationsProvider, (_, _) {});
    List<String> ids() => [
      for (final t in c.read(cartRecommendationsProvider).value!) t.productId,
    ];
    await c.read(cartRecommendationsProvider.future);
    expect(ids(), ['R1', 'R2', 'R3', 'R4', 'R5', 'R6']);
    await c.read(cartRecommendationsProvider.notifier).next();
    expect(ids(), ['R7', 'R8', 'R1', 'R2', 'R3', 'R4']);
    await c.read(cartRecommendationsProvider.notifier).next();
    expect(ids(), ['R1', 'R2', 'R3', 'R4', 'R5', 'R6']);
  });
}
