import 'package:dio/dio.dart' show Dio;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_api_order/pmart_api_order.dart' as api;
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/cart/data/mock_cart_repository.dart';
import 'package:customer_app/features/cart/domain/cart.dart';
import 'package:customer_app/features/checkout/data/mock_checkout_repository.dart';
import 'package:customer_app/features/checkout/domain/checkout.dart'
    show OutOfStockPreference;
import 'package:customer_app/features/orders/data/mock_orders_repository.dart';
import 'package:customer_app/features/orders/data/orders_repository.dart';
import 'package:customer_app/features/payment/data/payment_repository.dart';
import 'package:customer_app/shared/order_status.dart';
import 'package:customer_app/shared/providers.dart' show sourceSystem;

import 'support/app_harness.dart';

/// 주문 목록 상태 필터·주문 상세 결제 수단/배달 정보·같은 상품 담기(고객앱 레퍼런스 반영 A, 2026-11-04).
void main() {
  setUpAll(initPmartFormatting);

  Future<void> openOrders(
    WidgetTester t, {
    MockOrdersRepository? orders,
    MockCartRepository? cart,
    MockCheckoutRepository? checkout,
  }) async {
    t.view
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp(const [], orders: orders, cart: cart, checkout: checkout),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-orders')));
    await t.pumpAndSettle();
  }

  Dio dioWith(FakeAdapter adapter) => createPmartDio(
    baseUrl: 'http://test.invalid/api/v1',
    sourceSystem: sourceSystem,
    tokens: TokenStore(MemoryKeyValueStore()),
    refresher: (_) async => null,
    adapter: adapter,
    delay: (_) async {},
  );

  group('주문 목록 상태 필터', () {
    testWidgets('필터는 서버에 status 로 묻고, 결과가 없으면 "이 상태의 주문 없음"', (t) async {
      final orders = MockOrdersRepository(latency: Duration.zero);
      await openOrders(t, orders: orders);
      expect(orders.listStatuses.last, isNull);
      expect(find.byKey(const ValueKey('order-order-seed-3')), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('orders-status')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('orders-filter-cancelled')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('orders-sheet-apply')));
      await t.pumpAndSettle();
      expect(orders.listStatuses.last, OrderStatus.cancelled);
      expect(find.byKey(const ValueKey('order-order-seed-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('order-order-seed-1')), findsNothing);

      await t.tap(find.byKey(const ValueKey('orders-status')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('orders-filter-inDelivery')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('orders-sheet-apply')));
      await t.pumpAndSettle();
      expect(orders.listStatuses.last, OrderStatus.inDelivery);
      expect(
        find.byKey(const ValueKey('orders-empty-filtered')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('orders-empty')), findsNothing);

      await t.tap(find.byKey(const ValueKey('orders-status')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('orders-filter-all')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('orders-sheet-apply')));
      await t.pumpAndSettle();
      expect(orders.listStatuses.last, isNull);
      expect(find.byKey(const ValueKey('order-order-seed-1')), findsOneWidget);
    });

    test('API: 상태 필터는 생성 enum 값으로 status 쿼리에 싣고, 전체면 싣지 않는다', () async {
      final adapter = FakeAdapter(
        (_, _) async => const FakeReply(
          200,
          body: {
            'items': <Object?>[],
            'page': {'size': 50},
          },
        ),
      );
      final repo = ApiOrdersRepository(dioWith(adapter));
      await repo.list(status: OrderStatus.partiallyHandedOver);
      expect(adapter.requests.last.uri.path, '/api/v1/orders');
      expect(
        adapter.requests.last.uri.queryParameters['status'],
        'PARTIALLY_HANDED_OVER',
      );
      await repo.list();
      expect(
        adapter.requests.last.uri.queryParameters.containsKey('status'),
        isFalse,
      );
    });
  });

  group('주문 상세 결제 수단·배달 정보', () {
    testWidgets('결제 수단(서버 값)·요청사항·품절 시 처리를 보인다', (t) async {
      await openOrders(t);
      await t.tap(find.byKey(const ValueKey('order-order-seed-4')));
      await t.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('order-payment-method')),
          matching: find.text('카드'),
        ),
        findsOneWidget,
      );
      expect(find.text('문 앞에 두고 벨은 누르지 말아 주세요'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('order-oos')),
          matching: find.text('품절 상품만 빼고 받기'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('요청사항·품절 처리가 없는 주문은 그 줄을 두지 않는다', (t) async {
      await openOrders(t);
      await t.tap(find.byKey(const ValueKey('order-order-seed-1')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('order-note')), findsNothing);
      expect(find.byKey(const ValueKey('order-oos')), findsNothing);
    });

    testWidgets('결제 수단 조회 실패는 "정보 없음"이 아니라 실패 + 다시 확인', (t) async {
      final checkout = MockCheckoutRepository(
        latency: Duration.zero,
        now: () => DateTime.utc(2026, 10, 24, 3),
      )..paymentLookupFails = true;
      await openOrders(
        t,
        checkout: checkout,
        orders: MockOrdersRepository(
          checkout: checkout,
          latency: Duration.zero,
        ),
      );
      await t.tap(find.byKey(const ValueKey('order-order-seed-4')));
      await t.pumpAndSettle();

      final failed = find.byKey(const ValueKey('order-payment-method-failed'));
      expect(failed, findsOneWidget);
      expect(find.text('정보 없음'), findsNothing);

      checkout.paymentLookupFails = false;
      await t.tap(find.descendant(of: failed, matching: find.text('다시 확인')));
      await t.pumpAndSettle();
      expect(failed, findsNothing);
      expect(find.text('카드'), findsOneWidget);
    });

    test('변환: 결제 시도 ID·요청사항·품절 처리를 옮긴다(공백 요청사항은 없음)', () {
      final o = orderFromContract(
        api.Order.fromJson({
          'orderId': 'o-1',
          'outOfStockPreference': 'CANCEL_ALL',
          'deliveryNote': '  ',
          'payment': {'paymentAttemptId': 'pa-9', 'state': 'APPROVED'},
        }),
      );
      expect(o.paymentAttemptId, 'pa-9');
      expect(o.outOfStock, OutOfStockPreference.cancelAll);
      expect(o.deliveryNote, isNull);
    });

    test('API: 결제 수단은 GET /payments/{paymentAttemptId} 의 method', () async {
      final adapter = FakeAdapter(
        (_, _) async => const FakeReply(
          200,
          body: {
            'orderId': 'pa-9',
            'state': 'APPROVED',
            'stage': 'APPROVED',
            'amount': 21040,
            'method': '간편결제',
          },
        ),
      );
      final p = await ApiPaymentRepository(dioWith(adapter)).payment('pa-9');
      expect(adapter.requests.single.uri.path, '/api/v1/payments/pa-9');
      expect(p.method, '간편결제');
    });
  });

  group('같은 상품 담기', () {
    testWidgets('품목 담기는 현재 조건의 새 담기(AddItem)이고 서버 결과를 그 줄에 보인다', (t) async {
      final cart = MockCartRepository(latency: Duration.zero);
      await openOrders(t, cart: cart);
      await t.tap(find.byKey(const ValueKey('order-order-seed-4')));
      await t.pumpAndSettle();
      final sent = cart.changes.length;

      await t.tap(find.byKey(const ValueKey('reorder-ol-5')));
      await t.pumpAndSettle();

      expect(
        cart.changes.sublist(sent).single,
        isA<AddItem>()
            .having((c) => c.sku, 'sku', 'E-00000002')
            .having((c) => c.quantity, 'quantity', 3),
      );
      expect(
        t.widget<Text>(find.byKey(const ValueKey('reorder-result-ol-5'))).data,
        '장바구니에 담았어요',
      );
      // 담긴 줄은 다시 보내지 않는다.
      expect(
        t
            .widget<TextButton>(find.byKey(const ValueKey('reorder-ol-5')))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const ValueKey('reorder-go-cart')), findsOneWidget);
    });

    testWidgets('전체 다시 담기: 차례로 보내고 거절은 사유, 이미 담긴 상품은 수량을 바꾸지 않는다', (t) async {
      final cart = MockCartRepository(latency: Duration.zero);
      final orders = MockOrdersRepository(latency: Duration.zero);
      final base = orders.orderJson('order-seed-2')!;
      orders.overrides['order-mix'] = {
        ...base,
        'orderId': 'order-mix',
        'lines': [
          {
            'orderLineId': 'm-1',
            'sku': 'E-00000004',
            'productName': '품절 상품',
            'originalQty': 1,
          },
          {
            'orderLineId': 'm-2',
            'sku': 'E-00000002',
            'productName': '그릭요거트',
            'originalQty': 2,
          },
          {
            'orderLineId': 'm-3',
            'sku': 'E-00000001',
            'productName': '서울우유 1L',
            'originalQty': 5,
          },
        ],
        'shipments': <Object?>[],
      };
      await openOrders(t, cart: cart, orders: orders);
      await t.tap(find.byKey(const ValueKey('order-order-mix')));
      await t.pumpAndSettle();
      final sent = cart.changes.length;

      await t.tap(find.byKey(const ValueKey('reorder-all')));
      await t.pumpAndSettle();

      List<String> sentSkus() => [
        for (final c in cart.changes.sublist(sent)) (c as AddItem).sku,
      ];
      expect(sentSkus(), ['E-00000004', 'E-00000002']);
      String result(String id) =>
          t.widget<Text>(find.byKey(ValueKey('reorder-result-$id'))).data!;
      expect(result('m-1'), '지금 살 수 없는 상품이에요');
      expect(result('m-2'), '장바구니에 담았어요');
      // 우유는 이미 2개 담겨 있다. 담기는 절대 수량 설정이라 보내지 않고 담긴 수량을 알린다.
      expect(result('m-3'), '장바구니에 2개 있어요');

      // 다시 누르면 담기지 않은(거절된) 줄만 다시 보낸다.
      await t.tap(find.byKey(const ValueKey('reorder-all')));
      await t.pumpAndSettle();
      expect(sentSkus(), ['E-00000004', 'E-00000002', 'E-00000004']);
    });

    testWidgets('결과 불명이면 거기서 멈추고 다음 품목을 보내지 않는다', (t) async {
      final cart = MockCartRepository(latency: Duration.zero)
        ..loseNextResponse = true
        ..lookupFailures = 100;
      final orders = MockOrdersRepository(latency: Duration.zero);
      final base = orders.orderJson('order-seed-2')!;
      orders.overrides['order-two'] = {
        ...base,
        'orderId': 'order-two',
        'lines': [
          {'orderLineId': 't-1', 'sku': 'E-00000002', 'originalQty': 1},
          {'orderLineId': 't-2', 'sku': 'E-00000003', 'originalQty': 1},
        ],
        'shipments': <Object?>[],
      };
      await openOrders(t, cart: cart, orders: orders);
      await t.tap(find.byKey(const ValueKey('order-order-two')));
      await t.pumpAndSettle();
      final sent = cart.changes.length;

      await t.tap(find.byKey(const ValueKey('reorder-all')));
      // 원결과 조회 간격(기본 2초 × 5회)을 넘길 만큼 진행한다.
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(seconds: 1));
      }

      expect(cart.changes.sublist(sent), hasLength(1));
      expect(
        t.widget<Text>(find.byKey(const ValueKey('reorder-result-t-1'))).data,
        '변경이 반영됐는지 확인하는 중이에요',
      );
      expect(find.byKey(const ValueKey('reorder-result-t-2')), findsNothing);
    });
  });
}
