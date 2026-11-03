import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/cart/data/mock_cart_repository.dart';
import 'package:customer_app/features/cart/domain/cart.dart';
import 'package:customer_app/features/cart/presentation/cart_controller.dart';

import 'support/app_harness.dart';

base class _CartDown extends MockCartRepository {
  _CartDown() : super(latency: Duration.zero);

  @override
  Future<Cart> open({String? mfcId}) async =>
      throw const NetworkFailure(DioExceptionType.connectionError);
}

Future<void> _openCartTab(WidgetTester t) async {
  await t.pumpAndSettle();
  await t.tap(find.text('장바구니').last);
  await t.pumpAndSettle();
}

void main() {
  setUpAll(initPmartFormatting);

  late MockCartRepository cart;
  setUp(() => cart = MockCartRepository(latency: Duration.zero));

  testWidgets('장바구니는 서버 합계를 그대로 보인다', (t) async {
    await t.pumpWidget(testApp(const [], cart: cart));
    await _openCartTab(t);

    expect(find.byKey(const ValueKey('cart-line-ci-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('cart-line-ci-2')), findsOneWidget);
    expect(
      t.widget<Text>(find.byKey(const ValueKey('cart-total'))).data,
      '7,940원',
    );
    // 품목 줄은 "개당 단가"가 아니라 담은 수량만큼의 금액(단가 2,980 × 2개).
    expect(
      t.widget<Text>(find.byKey(const ValueKey('cart-amount-ci-1'))).data,
      '5,960원',
    );
    expect(find.textContaining('개당'), findsNothing);
  });

  testWidgets('조회 실패는 빈 장바구니가 아니라 오류로 보인다', (t) async {
    await t.pumpWidget(testApp(const [], cart: _CartDown()));
    await _openCartTab(t);

    expect(find.byKey(const ValueKey('cart-empty')), findsNothing);
    expect(find.text('정보를 불러오지 못했어요'), findsOneWidget);
  });

  testWidgets('수량 +는 서버 반영 뒤에만 숫자가 바뀐다', (t) async {
    await t.pumpWidget(testApp(const [], cart: cart));
    await _openCartTab(t);

    await t.tap(find.byKey(const ValueKey('cart-inc-ci-1')));
    await t.pumpAndSettle();

    expect(
      t.widget<Text>(find.byKey(const ValueKey('cart-qty-ci-1'))).data,
      '3개',
    );
    expect(
      t.widget<Text>(find.byKey(const ValueKey('cart-amount-ci-1'))).data,
      '8,940원',
    );
    expect(
      t.widget<Text>(find.byKey(const ValueKey('cart-total'))).data,
      '10,920원',
    );
  });

  testWidgets('연속으로 누른 수량 ± 는 모아서 최종 수량 한 번만 보낸다', (t) async {
    await t.pumpWidget(
      testApp(
        const [],
        cart: cart,
        stepperDelay: const Duration(milliseconds: 300),
      ),
    );
    await _openCartTab(t);
    final sent = cart.changes.length;

    // 2개 → + + + - = 4개. 기다리는 동안은 목표 수량을 바로 보이되 서버에는 아직 안 보냈다.
    for (final key in [
      'cart-inc-ci-1',
      'cart-inc-ci-1',
      'cart-inc-ci-1',
      'cart-dec-ci-1',
    ]) {
      await t.tap(find.byKey(ValueKey(key)));
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(
      t.widget<Text>(find.byKey(const ValueKey('cart-qty-ci-1'))).data,
      '4개',
    );
    expect(cart.changes.length, sent);

    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle();
    expect(cart.changes.length, sent + 1);
    expect(
      cart.changes.last,
      isA<SetQuantity>().having((c) => c.quantity, 'quantity', 4),
    );
    expect(
      t.widget<Text>(find.byKey(const ValueKey('cart-qty-ci-1'))).data,
      '4개',
    );
    expect(
      t.widget<Text>(find.byKey(const ValueKey('cart-amount-ci-1'))).data,
      '11,920원',
    );
  });

  testWidgets('수량 변경은 서버가 확정한 응답으로 바로 반영하고, 합계는 뒤에서 다시 읽어 채운다(BR-43 전 임시)', (
    t,
  ) async {
    cart.getLatency = const Duration(milliseconds: 500);
    await t.pumpWidget(testApp(const [], cart: cart));
    await _openCartTab(t);
    final gets = cart.gets;

    await t.tap(find.byKey(const ValueKey('cart-inc-ci-1')));
    await t.pump(const Duration(milliseconds: 50));

    // 변경 응답(APPLIED)만으로 수량·줄 금액이 바뀌고 다른 변경도 바로 할 수 있다. 합계는 아직 "확인 중".
    final qty = t.widget<Text>(find.byKey(const ValueKey('cart-qty-ci-1')));
    expect(qty.data, '3개');
    expect(qty.style?.color, isNull);
    expect(
      t.widget<Text>(find.byKey(const ValueKey('cart-amount-ci-1'))).data,
      '8,940원',
    );
    expect(
      t.widget<Text>(find.byKey(const ValueKey('cart-total'))).data,
      '합계 확인 중',
    );
    expect(
      t
          .widget<IconButton>(find.byKey(const ValueKey('cart-inc-ci-2')))
          .onPressed,
      isNotNull,
    );

    await t.pump(const Duration(milliseconds: 600));
    await t.pumpAndSettle();
    expect(
      t.widget<Text>(find.byKey(const ValueKey('cart-total'))).data,
      '10,920원',
    );
    expect(cart.gets, gets + 1);
  });

  testWidgets('가용 불명은 이유를 나눠 보인다 — 재고 원천 장애 / 배송지 미정', (t) async {
    cart.inventoryDown = true;
    await t.pumpWidget(testApp(const [], cart: cart));
    await _openCartTab(t);
    expect(find.text('재고 정보를 받지 못했어요. 결제할 때 다시 확인해요'), findsNWidgets(2));
    expect(find.text('판매 상태를 확인하는 중이에요'), findsNothing);
    // 재고를 몰라도 판매 중이면 수량은 바꿀 수 있다(결제 때 다시 잡는다).
    expect(
      t
          .widget<IconButton>(find.byKey(const ValueKey('cart-inc-ci-1')))
          .onPressed,
      isNotNull,
    );

    final noMfc = MockCartRepository(latency: Duration.zero)..noMfc = true;
    await t.pumpWidget(testApp(const [], cart: noMfc));
    await _openCartTab(t);
    expect(find.text('배송지를 정하면 재고를 확인해요'), findsNWidgets(2));
  });

  testWidgets('1개에서 -는 삭제를 확인한다', (t) async {
    await t.pumpWidget(testApp(const [], cart: cart));
    await _openCartTab(t);

    await t.tap(find.byKey(const ValueKey('cart-dec-ci-2')));
    await t.pumpAndSettle();
    expect(find.text('상품을 뺄까요?'), findsOneWidget);

    await t.tap(find.text('취소'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('cart-line-ci-2')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('cart-dec-ci-2')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('cart-remove-confirm')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('cart-line-ci-2')), findsNothing);
  });

  testWidgets('결과 불명이면 확인 중 띠가 뜨고 변경 버튼이 막힌다', (t) async {
    cart
      ..loseNextResponse = true
      ..lookupFailures = 100;
    await t.pumpWidget(
      testApp(cart: cart, [
        cartResolvePolicyProvider.overrideWithValue((
          interval: Duration.zero,
          attempts: 2,
        )),
      ]),
    );
    await _openCartTab(t);

    await t.tap(find.byKey(const ValueKey('cart-inc-ci-1')));
    // 확인 중에는 진행 표시가 계속 돌아서 pumpAndSettle 을 쓰지 않는다.
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 10));
    }

    expect(find.byKey(const ValueKey('cart-change-unknown')), findsOneWidget);
    final inc = t.widget<IconButton>(
      find.byKey(const ValueKey('cart-inc-ci-2')),
    );
    expect(inc.onPressed, isNull);

    cart.lookupFailures = 0;
    await t.tap(find.byKey(const ValueKey('cart-check-again')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('cart-change-unknown')), findsNothing);
    expect(
      t.widget<Text>(find.byKey(const ValueKey('cart-qty-ci-1'))).data,
      '3개',
    );
  });

  testWidgets('상세에서 담으면 장바구니에 반영된다', (t) async {
    await t.pumpWidget(testApp(const [], cart: cart));
    await t.pumpAndSettle();
    await tapTile(t, 'P-0002');

    await t.tap(find.byKey(const ValueKey('add-inc')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('add-to-cart')));
    await t.pumpAndSettle();

    expect(find.text('장바구니에 담았어요'), findsOneWidget);
    expect(find.text('장바구니에 2개 있어요'), findsOneWidget);

    // "장바구니 보기" 버튼이 있어도 알림은 잠시 뒤 스스로 닫힌다.
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    expect(find.text('장바구니에 담았어요'), findsNothing);
  });

  testWidgets('상세에서 상한 초과는 서버 상한으로 안내한다', (t) async {
    await t.pumpWidget(testApp(const [], cart: cart));
    await t.pumpAndSettle();
    await tapTile(t, 'P-0001');

    // 이미 2개 담겨 있으므로 2개에서 시작한다(절대 수량).
    expect(find.text('장바구니에 2개 있어요'), findsOneWidget);
    for (var i = 0; i < 9; i++) {
      await t.tap(find.byKey(const ValueKey('add-inc')));
      await t.pump();
    }
    await t.tap(find.byKey(const ValueKey('add-to-cart')));
    await t.pumpAndSettle();

    expect(find.textContaining('낱개 기준 10개까지'), findsOneWidget);
    expect(find.text('장바구니에 2개 있어요'), findsOneWidget);
  });
}
