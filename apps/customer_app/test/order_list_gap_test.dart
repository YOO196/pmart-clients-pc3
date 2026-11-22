import 'package:dio/dio.dart' show Dio;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_api_order/pmart_api_order.dart' as api;
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/checkout/presentation/checkout_controller.dart'
    show clockProvider;
import 'package:customer_app/features/checkout/domain/checkout.dart'
    show DeliveryMode;
import 'package:customer_app/features/orders/data/mock_orders_repository.dart';
import 'package:customer_app/features/orders/data/orders_repository.dart';
import 'package:customer_app/features/orders/domain/orders.dart';
import 'package:customer_app/shared/providers.dart' show sourceSystem;

import 'support/app_harness.dart';

/// 주문 내역 — 대표 상품·배송 방식, 기간·상품명 검색, 숨기기(order 0.12.0, 백엔드 알림 2026-11-18 gap-a §2~4). 목 모드.
void main() {
  setUpAll(initPmartFormatting);
  final now = DateTime.utc(2026, 10, 24, 3);

  late MockOrdersRepository orders;
  setUp(
    () => orders = MockOrdersRepository(latency: Duration.zero, now: () => now),
  );

  Future<void> openOrders(WidgetTester t, {bool failList = false}) async {
    t.view
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp([clockProvider.overrideWithValue(() => now)], orders: orders),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    // 홈의 진행 중 주문 카드도 목록을 읽으므로, 실패는 주문내역을 열기 바로 전에 건다.
    if (failList) orders.failNextList = true;
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

  testWidgets('카드: 배송 방식 · 상태, "<대표 상품> 외 N개"', (t) async {
    await openOrders(t);
    // order-seed-4: 예약배달, 그릭요거트 3개(다른 상품 없음)
    expect(
      t
          .widget<Text>(find.byKey(const ValueKey('order-mode-order-seed-4')))
          .data,
      '예약배달',
    );
    // order 0.17.0(BR-68): 상품 줄(이름 / 금액·수량)과 센터 이름 — 서버 값 그대로. 줄이 있으면 요약 한 줄은 그리지 않는다.
    final line = find.byKey(const ValueKey('order-line-ol-5'));
    expect(
      find.descendant(of: line, matching: find.text('그릭요거트 플레인 400g')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: line, matching: find.textContaining('17,940원')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: line, matching: find.textContaining('3개')),
      findsOneWidget,
    );
    expect(
      t.widget<Text>(find.byKey(const ValueKey('order-mfc-order-seed-4'))).data,
      '부산진구점',
    );
    expect(
      find.byKey(const ValueKey('order-summary-order-seed-4')),
      findsNothing,
    );
    // 기본 조회는 기간·검색 없이(서버 기본 최근 3개월).
    expect(orders.listQueries.first, (from: null, q: null));
  });

  testWidgets('조회 기간을 바꾸면 from 을 보내고, 검색어는 q 로 — 결과 없음은 "조건에 맞는 주문 없음"', (
    t,
  ) async {
    await openOrders(t);
    await t.tap(find.byKey(const ValueKey('orders-period')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('orders-period-months6')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('orders-sheet-apply')));
    await t.pumpAndSettle();
    // 서울 2026-10-24 기준 6개월 전
    expect(orders.listQueries.last.from, '2026-04-24');

    await t.tap(find.byKey(const ValueKey('orders-search-open')));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('orders-search-field')),
      '  없는상품  ',
    );
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    expect(orders.listQueries.last, (from: '2026-04-24', q: '없는상품'));
    expect(find.byKey(const ValueKey('orders-empty-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('orders-empty')), findsNothing);

    await t.tap(find.byKey(const ValueKey('orders-search-close')));
    await t.pumpAndSettle();
    expect(orders.listQueries.last.q, isNull);
    expect(find.byKey(const ValueKey('order-order-seed-4')), findsOneWidget);
  });

  testWidgets('조회 실패는 "주문 없음"이 아니라 오류', (t) async {
    await openOrders(t, failList: true);
    expect(find.byKey(const ValueKey('orders-empty')), findsNothing);
    expect(find.byKey(const ValueKey('order-order-seed-4')), findsNothing);
  });

  testWidgets('목록 카드에는 [삭제]가 없다 — 삭제는 주문 상세에서만(사용자 2026-11-23)', (t) async {
    await openOrders(t);
    expect(find.byKey(const ValueKey('order-order-seed-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('order-hide-order-seed-3')), findsNothing);
    expect(find.byKey(const ValueKey('order-hide-order-seed-4')), findsNothing);
  });

  test('계약 → 앱: 상품 줄(앞 5개)·센터 이름, 나머지는 "외 N개"(전체 수량 − 보인 수량)', () {
    final page = orderPageFromContract(
      api.ListOrders200Response.fromJson({
        'items': [
          {
            'orderId': 'o-1',
            'status': 'COMPLETED',
            'itemCount': 9,
            'mfcName': '바로픽 부산동래',
            'lines': [
              {
                'orderLineId': 'l-1',
                'sku': 'S-1',
                'productName': '우유',
                'optionLabel': '1L',
                'quantity': 2,
                'lineAmount': 5960,
              },
              {
                'orderLineId': 'l-2',
                'sku': 'S-2',
                'productName': ' ',
                'optionLabel': null,
                'quantity': 3,
                'lineAmount': 9000,
              },
            ],
          },
          // 예전 서버·모름: 줄·센터 없이 온다 — 빈 목록·null(지어내지 않음)
          {'orderId': 'o-2', 'status': 'COMPLETED', 'itemCount': 3},
        ],
      }),
    );
    final o = page.items[0];
    expect(o.mfcName, '바로픽 부산동래');
    expect(o.lines.map((l) => l.orderLineId), ['l-1', 'l-2']);
    expect(o.lines[0].optionLabel, '1L');
    expect(o.lines[0].lineAmount, 5960);
    expect(o.lines[1].productName, isNull);
    expect(o.moreQty, 4); // 9 − (2 + 3)
    expect(page.items[1].lines, isEmpty);
    expect(page.items[1].mfcName, isNull);
    expect(page.items[1].moreQty, isNull);
  });

  test('계약 → 앱: 줄 사진(order 0.19.0 BR-71) — 있으면 그대로, 빈 값·없으면 null', () {
    final page = orderPageFromContract(
      api.ListOrders200Response.fromJson({
        'items': [
          {
            'orderId': 'o-1',
            'status': 'COMPLETED',
            'lines': [
              {
                'orderLineId': 'l-1',
                'sku': 'S-1',
                'quantity': 1,
                'lineAmount': 1000,
                'imageUrl': 'https://img/p1.jpg',
              },
              {
                'orderLineId': 'l-2',
                'sku': 'S-2',
                'quantity': 1,
                'lineAmount': 1000,
                'imageUrl': ' ',
              },
              {
                'orderLineId': 'l-3',
                'sku': 'S-3',
                'quantity': 1,
                'lineAmount': 1000,
              },
            ],
          },
        ],
      }),
    );
    expect(page.items.single.lines.map((l) => l.imageUrl), [
      'https://img/p1.jpg',
      null,
      null,
    ]);
  });
  test('계약 → 앱: 대표 상품 이름 없음(2026-11-02 전)·모르는 배송 방식은 null', () {
    final page = orderPageFromContract(
      api.ListOrders200Response.fromJson({
        'items': [
          {
            'orderId': 'o-1',
            'status': 'COMPLETED',
            'itemCount': 5,
            'deliveryMode': 'BUNDLED',
            'representativeItem': {
              'sku': 'S-1',
              'productName': '우유',
              'quantity': 2,
            },
          },
          {
            'orderId': 'o-2',
            'status': 'COMPLETED',
            'itemCount': 3,
            'representativeItem': {'sku': 'S-2', 'productName': ' '},
          },
        ],
      }),
    );
    expect(page.items[0].deliveryMode, DeliveryMode.bundled);
    expect(page.items[0].representativeName, '우유');
    expect(page.items[0].othersQty, 3);
    expect(page.items[1].representativeName, isNull);
    expect(page.items[1].deliveryMode, isNull);
    expect(page.items[1].othersQty, isNull);
  });

  test('기간 → from: 3개월은 보내지 않음(서버 기본), 전체는 오래전 날짜', () {
    final today = DateTime(2026, 11, 18);
    expect(orderPeriodFrom(OrderPeriod.months3, today), isNull);
    expect(orderPeriodFrom(OrderPeriod.months6, today), '2026-05-18');
    expect(orderPeriodFrom(OrderPeriod.year1, today), '2025-11-18');
    expect(orderPeriodFrom(OrderPeriod.all, today), '2020-01-01');
  });

  test(
    'API: GET /orders 에 from·q, POST /orders/{id}/hides 에 멱등 키·출처 헤더',
    () async {
      final adapter = FakeAdapter((o, _) async {
        if (o.method == 'GET') {
          return const FakeReply(200, body: {'items': <Object?>[]});
        }
        return const FakeReply(
          200,
          body: {'status': 'APPLIED', 'requestId': 'r-1'},
        );
      });
      final repo = ApiOrdersRepository(dioWith(adapter));
      await repo.list(from: '2026-05-18', q: '우유');
      final key = IdempotencyKey.generate();
      final status = await repo.hide('o-1', key: key);

      final get = adapter.requests.first;
      expect(get.uri.queryParameters['from'], '2026-05-18');
      expect(get.uri.queryParameters['q'], '우유');
      final post = adapter.requests.last;
      expect(post.method, 'POST');
      expect(post.path, endsWith('/orders/o-1/hides'));
      expect(post.headers['Idempotency-Key'], key.value);
      expect(post.headers['X-Source-System'], sourceSystem);
      expect(status, CommandStatus.applied);
    },
  );

  test('API: 숨기기 409 ORDER_NOT_FINISHED 는 그 code 로 던진다', () async {
    final adapter = FakeAdapter(
      (_, _) async => const FakeReply(
        409,
        body: {'status': 409, 'code': 'ORDER_NOT_FINISHED', 'title': 'x'},
      ),
    );
    final repo = ApiOrdersRepository(dioWith(adapter));
    await expectLater(
      repo.hide('o-1', key: IdempotencyKey.generate()),
      throwsA(
        isA<ProblemFailure>().having(
          (f) => f.problem.code,
          'code',
          orderNotFinishedCode,
        ),
      ),
    );
  });
}
