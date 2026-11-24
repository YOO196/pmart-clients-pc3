import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/features/cart/domain/cart.dart';
import 'package:customer_app/shared/floating_cart_bar.dart';

Cart _cart({int? min, int? short, int? amount, int? discount, int? list}) =>
    Cart(
      cartId: 'c',
      version: 1,
      isMember: true,
      lines: const [],
      minOrderAmount: min,
      minOrderShortfall: short,
      selectedItemAmount: amount,
      selectedDiscountAmount: discount,
      selectedListAmount: list,
    );

/// 장바구니 막대 아래 최소 주문 줄(레퍼런스 "주문 가능" 막대) — 서버 값으로만 채운다.
void main() {
  test('모자람 0 이면 가득', () {
    expect(minOrderFill(_cart(min: 10000, short: 0)), 1);
    expect(minOrderFill(_cart(short: 0)), 1);
  });

  test('모자라면 (최소 − 모자람) / 최소', () {
    expect(minOrderFill(_cart(min: 10000, short: 2500)), 0.75);
  });

  test('모자람을 모르거나 최소 금액을 모르면 줄을 그리지 않는다', () {
    expect(minOrderFill(_cart(min: 10000)), isNull);
    expect(minOrderFill(_cart(short: 3000)), isNull);
  });

  test(
    '할인 전 금액(줄 긋기)은 서버 할인 전 합계(cart 0.5.0 BR-97) — 할인이 있을 때만, 앱이 더하지 않는다',
    () {
      expect(
        cartListPrice(_cart(amount: 31400, discount: 14180, list: 45580)),
        45580,
      );
      expect(
        cartListPrice(_cart(amount: 31400, discount: 0, list: 31400)),
        isNull,
      );
      // 서버가 할인 전 합계를 안 주면(옛 응답) 그리지 않는다 — 더해서 만들지 않는다.
      expect(cartListPrice(_cart(amount: 31400, discount: 14180)), isNull);
      expect(cartListPrice(_cart(discount: 1000)), isNull);
    },
  );
}
