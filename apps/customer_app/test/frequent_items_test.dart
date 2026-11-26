import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_ui/pmart_ui.dart';

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
}
