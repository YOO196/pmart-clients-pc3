import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/cart/data/mock_cart_repository.dart';
import 'package:customer_app/features/cart/domain/cart.dart';
import 'package:customer_app/features/catalog/presentation/product_detail_screen.dart';
import 'package:customer_app/features/orders/data/mock_orders_repository.dart';
import 'package:customer_app/features/orders/domain/orders.dart';

import 'support/app_harness.dart';

Future<void> _login(WidgetTester t) async {
  await t.tap(find.text('마이페이지').last);
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('my-login')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('login-kakao')));
  await t.pumpAndSettle();
}

// 백엔드 요청 2026-11-26 자주 산 상품(order 0.24.0) F1~F3.
void main() {
  setUpAll(initPmartFormatting);

  testWidgets('비회원은 자주 산 상품 칸이 없다', (t) async {
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await openSearchScreen(t);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('frequent-items')), findsNothing);
  });

  testWidgets('회원: 자주 산 상품 칩(이름 없는 줄은 뺀다), 누르면 상품 상세', (t) async {
    final orders = MockOrdersRepository(latency: Duration.zero)
      ..frequent = const [
        FrequentItem(
          sku: 'E-00000001',
          productId: 'P-0001',
          productName: '서울우유 1L',
          orderCount: 3,
        ),
        FrequentItem(sku: 'E-OLD', orderCount: 2),
      ];
    await t.pumpWidget(testApp(const [], orders: orders));
    await t.pumpAndSettle();
    await _login(t);
    await openSearchScreen(t);
    await t.pumpAndSettle();
    expect(find.text('자주 산 상품'), findsOneWidget);
    expect(find.byKey(const ValueKey('frequent-E-OLD')), findsNothing);
    await t.tap(find.byKey(const ValueKey('frequent-E-00000001')));
    await t.pumpAndSettle();
    expect(find.byType(ProductDetailScreen), findsOneWidget);
  });

  testWidgets('회원이어도 빈 목록이면 칸을 숨긴다', (t) async {
    final orders = MockOrdersRepository(latency: Duration.zero)
      ..frequent = const [];
    await t.pumpWidget(testApp(const [], orders: orders));
    await t.pumpAndSettle();
    await _login(t);
    await openSearchScreen(t);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('frequent-items')), findsNothing);
  });

  boughtItemsTests();
}

// 홈 "내가 1번 구매한 상품 보기" → 산 상품 한 번에 담기(사용자 2026-11-26).
void boughtItemsTests() {
  testWidgets('산 상품 화면: 모두 골라 두고, 하나 빼면 나머지만 장바구니에 담는다', (t) async {
    final orders = MockOrdersRepository(latency: Duration.zero)
      ..frequent = const [
        FrequentItem(
          sku: 'E-00000001',
          productId: 'P-0001',
          productName: '서울우유 1L',
          orderCount: 3,
        ),
        FrequentItem(
          sku: 'E-00000003',
          productId: 'P-0003',
          productName: '제주 감귤 1kg',
          orderCount: 1,
        ),
      ];
    final cart = MockCartRepository(latency: Duration.zero, seeded: false);
    await t.pumpWidget(testApp(const [], orders: orders, cart: cart));
    await t.pumpAndSettle();
    await _login(t);
    final ctx = t.element(find.byType(Scaffold).first);
    GoRouter.of(ctx).push('/me/bought-items');
    await t.pumpAndSettle();
    expect(find.text('3회 구매'), findsOneWidget);
    expect(find.text('1회 구매'), findsOneWidget);
    expect(find.text('총 2개'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('bought-check-E-00000003')));
    await t.pumpAndSettle();
    expect(find.text('총 1개'), findsOneWidget);
    final before = cart.changes.length;
    await t.tap(find.byKey(const ValueKey('bought-add')));
    await t.pumpAndSettle();
    final sent = cart.changes.sublist(before);
    expect(sent, hasLength(1));
    expect((sent.single as AddItem).sku, 'E-00000001');
  });
}
