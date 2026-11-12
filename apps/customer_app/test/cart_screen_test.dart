import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/cart/data/mock_cart_repository.dart';
import 'package:customer_app/features/cart/domain/cart.dart';
import 'package:customer_app/features/cart/presentation/cart_controller.dart';
import 'package:customer_app/features/catalog/presentation/home_screen.dart';
import 'package:customer_app/features/checkout/data/mock_checkout_repository.dart';

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

  testWidgets('변경 응답에 장바구니가 오면(BR-43) 그걸로 끝낸다 — 합계까지 바로, 다시 읽지 않는다', (t) async {
    cart.getLatency = const Duration(milliseconds: 500);
    await t.pumpWidget(testApp(const [], cart: cart));
    await _openCartTab(t);
    final gets = cart.gets;

    await t.tap(find.byKey(const ValueKey('cart-inc-ci-1')));
    await t.pump(const Duration(milliseconds: 50));

    expect(
      t.widget<Text>(find.byKey(const ValueKey('cart-qty-ci-1'))).data,
      '3개',
    );
    expect(
      t.widget<Text>(find.byKey(const ValueKey('cart-total'))).data,
      '10,920원',
    );
    await t.pumpAndSettle();
    expect(cart.gets, gets);
  });

  testWidgets('변경 응답에 장바구니가 없는 옛 서버면 응답 버전으로 바로 반영하고, 합계는 뒤에서 다시 읽어 채운다', (
    t,
  ) async {
    cart
      ..omitCartInResult = true
      ..getLatency = const Duration(milliseconds: 500);
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

  testWidgets('선택된 채 품절된 품목은 열자마자 선택에서 빠지고(삭제 아님) 안내가 뜬다', (t) async {
    cart.seedLine('E-00000004', 1); // 일시품절 상품(P-0004)이 선택된 채 담겨 있다
    // 세 줄이 한 화면에 다 그려지게 세로를 늘린다(목록 머리·안내 줄이 자리를 차지한다).
    t.view
      ..physicalSize = const Size(800, 1400)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const [], cart: cart));
    await _openCartTab(t);

    final box = find.byKey(const ValueKey('cart-select-ci-3'));
    await t.ensureVisible(box);
    // 서버에 선택 해제를 보내 확정된 결과로 그린다. 품목은 남아 있고 다시 고를 수 없다.
    expect(t.widget<Checkbox>(box).value, isFalse);
    expect(t.widget<Checkbox>(box).onChanged, isNull);
    expect(find.byKey(const ValueKey('cart-line-ci-3')), findsOneWidget);
    expect(
      find.text('품절·구매할 수 없는 상품 1개는 선택에서 뺐어요. 장바구니에는 남아 있어요.'),
      findsOneWidget,
    );
    // 판매 중인 다른 품목의 선택은 건드리지 않는다.
    expect(
      t.widget<Checkbox>(find.byKey(const ValueKey('cart-select-ci-1'))).value,
      isTrue,
    );
  });

  testWidgets('1개에서 -는 삭제를 확인한다', (t) async {
    await t.pumpWidget(testApp(const [], cart: cart));
    await _openCartTab(t);

    // 둘째 줄의 버튼은 낮은 시험 화면(600)에서 합계 영역에 가릴 수 있어 먼저 보이게 한다.
    await t.ensureVisible(find.byKey(const ValueKey('cart-dec-ci-2')));
    await t.pumpAndSettle();
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

  group('장바구니 구성 보강(레퍼런스 반영 A)', () {
    testWidgets('수량 1이면 - 대신 휴지통, 2 이상이면 - 이다(누르면 같은 삭제 확인)', (t) async {
      await t.pumpWidget(testApp(const [], cart: cart));
      await _openCartTab(t);

      Icon iconOf(String key) => t.widget<Icon>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Icon),
        ),
      );
      expect(iconOf('cart-dec-ci-2').icon, Icons.delete_outline);
      expect(iconOf('cart-dec-ci-1').icon, Icons.remove);

      await t.ensureVisible(find.byKey(const ValueKey('cart-dec-ci-2')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('cart-dec-ci-2')));
      await t.pumpAndSettle();
      expect(find.text('상품을 뺄까요?'), findsOneWidget);
    });

    testWidgets('주문 버튼 안에 고를 수 있는 선택 품목 수와 서버 합계, 머리에 서버 보관 기한', (t) async {
      await t.pumpWidget(testApp(const [], cart: cart));
      await _openCartTab(t);

      expect(
        t.widget<Text>(find.byKey(const ValueKey('cart-order-label'))).data,
        '2개 · 7,940원 주문하기',
      );
      // expiresAt 2026-11-23T06:00Z → 서울 2026-11-23.
      expect(
        t.widget<Text>(find.byKey(const ValueKey('cart-expires'))).data,
        '2026-11-23까지 보관돼요',
      );
    });

    testWidgets('선택 삭제는 선택 품목을 하나씩 서버에 지운다', (t) async {
      await t.pumpWidget(testApp(const [], cart: cart));
      await _openCartTab(t);
      final sent = cart.changes.length;

      await t.tap(find.byKey(const ValueKey('cart-remove-selected')));
      await t.pumpAndSettle();
      expect(find.text('선택한 상품 2개를 뺄까요?'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('cart-remove-selected-confirm')));
      await t.pumpAndSettle();

      final sentNow = cart.changes.sublist(sent);
      expect(sentNow, hasLength(2));
      expect(sentNow, everyElement(isA<RemoveItem>()));
      expect(find.byKey(const ValueKey('cart-empty')), findsOneWidget);
    });

    testWidgets('선택 삭제 중 반영되지 않은 결과(버전 충돌)가 나오면 멈추고 안내한다', (t) async {
      await t.pumpWidget(testApp(const [], cart: cart));
      await _openCartTab(t);
      final sent = cart.changes.length;
      cart.bumpVersionElsewhere();

      await t.tap(find.byKey(const ValueKey('cart-remove-selected')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('cart-remove-selected-confirm')));
      await t.pumpAndSettle();

      // 첫 품목이 충돌로 거절되면 나머지는 보내지 않는다. 두 줄 다 남아 있다.
      expect(cart.changes.sublist(sent), hasLength(1));
      expect(find.byKey(const ValueKey('cart-line-ci-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('cart-line-ci-2')), findsOneWidget);
      expect(
        find.text('다른 곳에서 장바구니가 바뀌어 최신 내용으로 다시 불러왔어요. 다시 확인해 주세요.'),
        findsOneWidget,
      );
    });

    testWidgets('선택 품목이 없으면 선택 삭제·주문을 누를 수 없다', (t) async {
      await t.pumpWidget(testApp(const [], cart: cart));
      await _openCartTab(t);
      for (final id in ['ci-1', 'ci-2']) {
        // 둘째 줄은 낮은 시험 화면에서 합계 영역에 가릴 수 있어 먼저 보이게 한다.
        await t.ensureVisible(find.byKey(ValueKey('cart-select-$id')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(ValueKey('cart-select-$id')));
        await t.pumpAndSettle();
      }
      expect(
        t
            .widget<TextButton>(
              find.byKey(const ValueKey('cart-remove-selected')),
            )
            .onPressed,
        isNull,
      );
      expect(
        t.widget<Text>(find.byKey(const ValueKey('cart-order-label'))).data,
        '주문하기',
      );
    });

    testWidgets('"상품 추가"는 홈으로 간다', (t) async {
      t.view
        ..physicalSize = const Size(800, 1400)
        ..devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(testApp(const [], cart: cart));
      await _openCartTab(t);

      await t.ensureVisible(find.byKey(const ValueKey('cart-add-more')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('cart-add-more')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('cart-add-more')), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('배달팁·봉투값 안내는 아래 시트로 정적 문구를 보인다(금액 숫자 없음)', (t) async {
      await t.pumpWidget(testApp(const [], cart: cart));
      await _openCartTab(t);

      await t.tap(find.byKey(const ValueKey('cart-fee-info')));
      await t.pumpAndSettle();
      final sheet = find.byKey(const ValueKey('cart-fee-sheet'));
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(of: sheet, matching: find.textContaining('주문마다 한 번만')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.textContaining('원')),
        findsNothing,
      );
    });

    testWidgets('첫 구매 무료배달은 회원·서버 사유 FIRST_PURCHASE 일 때만 "예정"으로 보인다', (
      t,
    ) async {
      final checkout = MockCheckoutRepository(
        latency: Duration.zero,
        now: () => DateTime.utc(2026, 10, 24, 3),
      );
      await t.pumpWidget(testApp(const [], cart: cart, checkout: checkout));
      await _openCartTab(t);
      // 비회원은 묻지 않는다.
      expect(find.byKey(const ValueKey('cart-first-purchase')), findsNothing);

      await t.tap(find.text('마이페이지').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('my-login')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('login-kakao')));
      await t.pumpAndSettle();
      await _openCartTab(t);
      // 첫 구매 대상이 아니면 줄이 없다.
      expect(find.byKey(const ValueKey('cart-first-purchase')), findsNothing);

      checkout.firstPurchase = true;
      // 서버 값이 바뀌었다고 가정하고 장바구니를 다시 받는다(합계가 바뀌면 다시 묻는다).
      await t.tap(find.byKey(const ValueKey('cart-inc-ci-1')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('cart-first-purchase')), findsOneWidget);
      expect(find.text('첫 구매 무료배달 예정(결제할 때 확정돼요)'), findsOneWidget);
    });
  });
}
