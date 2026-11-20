import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_api_cart/pmart_api_cart.dart' as api;
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/cart/data/cart_repository.dart';
import 'package:customer_app/features/cart/data/mock_cart_repository.dart';

import 'support/app_harness.dart';

/// 서버가 부족액을 정하지 못한 장바구니(가격 모르는 줄 — cart 0.2.0 `minOrderShortfall` null).
base class _ShortfallUnknown extends MockCartRepository {
  _ShortfallUnknown() : super(latency: Duration.zero);

  @override
  Map<String, Object?> cartJson() => {
    ...super.cartJson(),
    'minOrderShortfall': null,
  };
}

/// 장바구니 최소 주문 금액 진행 바(cart 0.2.0, 백엔드 알림 2026-11-18 gap-a §5). 목 모드.
void main() {
  setUpAll(initPmartFormatting);

  Future<void> openCart(WidgetTester t, MockCartRepository cart) async {
    await t.pumpWidget(testApp(const [], cart: cart));
    await t.pumpAndSettle();
    await t.tap(find.text('장바구니').last);
    await t.pumpAndSettle();
  }

  testWidgets('서버 부족액으로 "15,000원부터 / N원 더" + 바, 주문 버튼은 막힌다(레퍼런스 5-1)', (
    t,
  ) async {
    // 목 장바구니 선택 합계 7,940원 → 부족 7,060원
    await openCart(t, MockCartRepository(latency: Duration.zero));
    expect(find.text('15,000원부터 배달 가능해요'), findsOneWidget);
    expect(
      t
          .widget<Text>(find.byKey(const ValueKey('cart-min-order-shortfall')))
          .data,
      '7,060원 더 담으면 주문할 수 있어요',
    );
    final bar = t.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('cart-min-order-bar')),
    );
    expect(bar.value, closeTo(7940 / 15000, 0.0001));
    expect(
      t
          .widget<FilledButton>(find.byKey(const ValueKey('cart-order')))
          .onPressed,
      isNull,
    );
    expect(find.text('최소주문금액을 채워주세요'), findsOneWidget);
  });

  testWidgets('부족액이 null 이면 바를 숨긴다(0 으로 보이지 않는다)', (t) async {
    await openCart(t, _ShortfallUnknown());
    expect(find.byKey(const ValueKey('cart-min-order')), findsNothing);
  });

  testWidgets('최소금액을 채우면 버튼이 다시 열린다(서버 부족액 0)', (t) async {
    await openCart(t, MockCartRepository(latency: Duration.zero));
    for (var i = 0; i < 3; i++) {
      await t.tap(find.byKey(const ValueKey('cart-inc-ci-1')));
      await t.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('cart-min-order')), findsNothing);
    expect(
      t
          .widget<FilledButton>(find.byKey(const ValueKey('cart-order')))
          .onPressed,
      isNotNull,
    );
  });

  test('계약 → 앱: minOrderAmount·minOrderShortfall 그대로, 없으면 null', () {
    Map<String, Object?> base() => {
      'cartId': 'c-1',
      'cartVersion': 1,
      'ownerType': 'GUEST',
      'items': <Object?>[],
    };
    final c = cartFromContract(
      api.Cart.fromJson({
        ...base(),
        'selectedItemAmount': 16000,
        'minOrderAmount': 15000,
        'minOrderShortfall': 0,
      }),
    );
    expect(c.minOrderAmount, 15000);
    expect(c.minOrderShortfall, 0);
    final none = cartFromContract(api.Cart.fromJson(base()));
    expect(none.minOrderShortfall, isNull);
  });
}
