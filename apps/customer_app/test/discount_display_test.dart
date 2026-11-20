import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_api_cart/pmart_api_cart.dart' as ca;
import 'package:pmart_api_product_content/pmart_api_product_content.dart' as pc;
import 'package:pmart_api_search/pmart_api_search.dart' as sr;
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/cart/data/cart_repository.dart';
import 'package:customer_app/features/cart/data/mock_cart_repository.dart';
import 'package:customer_app/features/catalog/data/catalog_repository.dart';
import 'package:customer_app/features/catalog/domain/catalog.dart';

import 'support/app_harness.dart';

/// 상품 할인가 표시(ADR-0082 4단계 — search 0.6.0·storefront 0.8.0·pricing 0.3.0·cart 0.4.0). 목 기준.
void main() {
  setUpAll(initPmartFormatting);

  group('계약 → 화면 모델', () {
    test('검색 카드: 할인가·할인율·이름을 옮기고, 없으면 할인 없음', () {
      final page = searchFromContract(
        sr.SearchResult.fromJson({
          'items': [
            {
              'productId': 'P-1',
              'name': '요거트',
              'basePrice': 5980,
              'salePrice': 3990,
              'discountRatePercent': 33,
              'discountName': '이번 주 할인',
              'discountEndsAt': '2026-11-30T14:59:59Z',
              'saleState': 'ON_SALE',
            },
            {
              'productId': 'P-2',
              'name': '우유',
              'basePrice': 2980,
              'salePrice': null,
              'saleState': 'ON_SALE',
            },
          ],
          'page': {'size': 20},
          'total': 2,
        }),
      );
      final d = page.items.first.discount!;
      expect(d.salePrice, 3990);
      expect(d.ratePercent, 33);
      expect(d.name, '이번 주 할인');
      expect(page.items.last.discount, isNull);
    });

    test('할인가가 정가 이상이면 할인으로 보지 않는다', () {
      expect(saleDiscountOf(salePrice: 3000, basePrice: 3000), isNull);
      expect(saleDiscountOf(salePrice: null, basePrice: 3000), isNull);
      expect(saleDiscountOf(salePrice: 2000, basePrice: 3000), isNotNull);
    });

    test('상세: 가격 조회의 할인을 옵션에 붙인다(정가는 그대로)', () {
      final p = productFromContract(
        pc.ProductContent.fromJson({
          'productId': 'P-1',
          'name': '요거트',
          'options': [
            {
              'sku': 'E-1',
              'saleState': 'ON_SALE',
              'price': {'basePrice': 5980, 'priceVersion': 1},
            },
          ],
        }),
        prices: const OptionPrices(
          prices: {},
          notSet: {},
          discounts: {'E-1': SaleDiscount(salePrice: 3990, ratePercent: 33)},
        ),
      );
      expect(p.options.single.basePrice, 5980);
      expect(p.options.single.discount!.salePrice, 3990);
    });

    test('장바구니: 품목 할인과 선택 할인 합계(상품금액은 할인 뒤 서버 값)', () {
      final c = cartFromContract(
        ca.Cart.fromJson({
          'cartId': 'c-1',
          'cartVersion': 1,
          'ownerType': 'GUEST',
          'items': [
            {
              'cartItemId': 'ci-1',
              'sku': 'E-1',
              'quantity': 2,
              'selected': true,
              'display': {
                'name': '요거트',
                'unitPrice': 5980,
                'salePrice': 3990,
                'discountRatePercent': 33,
                'discountName': '이번 주 할인',
                'saleState': 'ON_SALE',
                'availability': 'AVAILABLE',
              },
            },
          ],
          'selectedItemAmount': 7980,
          'selectedDiscountAmount': 3980,
        }),
      );
      expect(c.lines.single.discount!.salePrice, 3990);
      expect(c.selectedItemAmount, 7980);
      expect(c.selectedDiscountAmount, 3980);
    });
  });

  testWidgets('장바구니 줄: "33% 7,980원 11,960원(취소선)" — 수량만큼, 서버 할인가', (t) async {
    final cart = MockCartRepository(
      latency: Duration.zero,
      seeded: false,
      minOrderAmount: 0,
    )..seedLine('E-00000002', 2);
    await t.pumpWidget(testApp(const [], cart: cart));
    await t.pumpAndSettle();
    await t.tap(find.text('장바구니').last);
    await t.pumpAndSettle();
    final line = find.byKey(const ValueKey('cart-amount-ci-1'));
    expect(line, findsOneWidget);
    final text = t
        .widget<Text>(find.descendant(of: line, matching: find.byType(Text)))
        .textSpan!
        .toPlainText();
    expect(text, '33% 7,980원 11,960원');
    expect(
      t.widget<Text>(find.byKey(const ValueKey('cart-total'))).data,
      '7,980원',
    );
  });

  testWidgets('상세: 할인 상품은 할인율·할인가·정가, 할인 없는 상품은 정가만', (t) async {
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await tapTile(t, 'P-0002');
    expect(
      t
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('product-price')),
              matching: find.byType(Text),
            ),
          )
          .textSpan!
          .toPlainText(),
      '33% 3,990원 5,980원',
    );
  });
  testWidgets('주문상세 줄: 나눠 넣은 할인(discountShare)과 "지금 더 할인 중"(지금 할인 상품만)', (
    t,
  ) async {
    t.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    final router = GoRouter.of(t.element(find.byType(Scaffold).first));
    unawaited(router.push('/orders/order-seed-2'));
    await t.pumpAndSettle();
    final discount = find.byKey(const ValueKey('line-discount-ol-3'));
    await t.scrollUntilVisible(
      discount,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(t.widget<Text>(discount).data, '할인 -3,980원');
    expect(find.byKey(const ValueKey('line-now-sale-ol-3')), findsOneWidget);

    // 할인 없는 주문·상품(서울우유)은 둘 다 없다.
    unawaited(router.push('/orders/order-seed-1'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('line-discount-ol-1')), findsNothing);
    expect(find.byKey(const ValueKey('line-now-sale-ol-1')), findsNothing);
  });
}
