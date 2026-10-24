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
      t.widget<Text>(find.byKey(const ValueKey('cart-total'))).data,
      '10,920원',
    );
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
