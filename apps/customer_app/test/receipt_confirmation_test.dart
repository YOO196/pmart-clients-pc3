import 'package:dio/dio.dart' show Dio;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/orders/data/mock_orders_repository.dart';
import 'package:customer_app/features/orders/data/orders_repository.dart';
import 'package:customer_app/features/checkout/presentation/checkout_controller.dart'
    show clockProvider;
import 'package:customer_app/shared/providers.dart' show sourceSystem;

import 'support/app_harness.dart';

/// "받았어요"(고객 수령 확인) — execution 0.20.0 `receipt-confirmations`, 백엔드 요청 2026-11-17 receipt-confirmation. 목 모드.
void main() {
  setUpAll(initPmartFormatting);
  final now = DateTime.utc(2026, 10, 24, 3);

  late MockOrdersRepository orders;

  setUp(
    () => orders = MockOrdersRepository(latency: Duration.zero, now: () => now),
  );

  // 목 주문 order-seed-1: 배송 dlv-s1 완료, dlv-s2 배송 중(도착 예상 단계 TO_CUSTOMER).
  Future<void> openOrder(WidgetTester t) async {
    t.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp(orders: orders, [clockProvider.overrideWithValue(() => now)]),
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
    await t.tapAt(
      t.getTopLeft(find.byKey(const ValueKey('order-order-seed-1'))) +
          const Offset(24, 24),
    );
    await t.pumpAndSettle();
  }

  Future<void> tapReceived(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey('receipt-dlv-s2')));
    await t.pumpAndSettle();
    expect(find.text('상품을 받으셨나요?'), findsOneWidget);
    expect(find.text('받음으로 처리하면 배송이 완료돼요'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('receipt-confirm')));
    await t.pumpAndSettle();
  }

  String message(WidgetTester t) => t
      .widget<Text>(find.byKey(const ValueKey('receipt-message-dlv-s2')))
      .data!;

  testWidgets('배송 중인 배송에만 "받았어요" — 완료된 배송에는 없다', (t) async {
    await openOrder(t);
    expect(find.byKey(const ValueKey('receipt-dlv-s2')), findsOneWidget);
    expect(find.byKey(const ValueKey('receipt-dlv-s1')), findsNothing);
  });

  testWidgets('확인 대화에서 "아직이요"면 보내지 않는다', (t) async {
    await openOrder(t);
    await t.tap(find.byKey(const ValueKey('receipt-dlv-s2')));
    await t.pumpAndSettle();
    await t.tap(find.text('아직이요'));
    await t.pumpAndSettle();
    expect(orders.receiptKeys, isEmpty);
    expect(find.byKey(const ValueKey('receipt-dlv-s2')), findsOneWidget);
  });

  testWidgets('받았어요(APPLIED) → 완료 안내, 버튼이 사라지고 배송은 완료로 다시 읽힌다', (t) async {
    await openOrder(t);
    await tapReceived(t);
    expect(orders.received, {'dlv-s2'});
    expect(message(t), '받음으로 처리했어요. 배송이 완료됐어요');
    expect(find.byKey(const ValueKey('receipt-dlv-s2')), findsNothing);
  });

  testWidgets('접수(ACCEPTED)는 완료로 보이지 않는다 — 다시 확인해 완료를 읽으면 완료', (t) async {
    orders.nextReceiptStatus = CommandStatus.accepted;
    await openOrder(t);
    await tapReceived(t);
    expect(message(t), '받음을 접수했어요. 배송 완료를 확인하고 있어요');
    expect(find.byKey(const ValueKey('receipt-dlv-s2')), findsNothing);

    await t.tap(find.byKey(const ValueKey('receipt-check-dlv-s2')));
    await t.pumpAndSettle();
    expect(message(t), '받음으로 처리했어요. 배송이 완료됐어요');
  });

  testWidgets('결과를 모르면 다시 누를 수 없고, "다시 확인"은 같은 키로 묻는다', (t) async {
    orders.failNextReceipt = const UnknownResultFailure(requestId: 'r');
    await openOrder(t);
    await tapReceived(t);
    expect(message(t), '받음 처리 결과를 아직 확인하지 못했어요');
    expect(find.byKey(const ValueKey('receipt-dlv-s2')), findsNothing);
    expect(orders.receiptKeys, isEmpty);

    await t.tap(find.byKey(const ValueKey('receipt-check-dlv-s2')));
    await t.pumpAndSettle();
    expect(orders.receiptKeys.keys, ['dlv-s2']);
    expect(message(t), '받음으로 처리했어요. 배송이 완료됐어요');
  });

  testWidgets('이미 처리된 배송(409) → 안내만, 완료로 보이지 않는다', (t) async {
    orders.failNextReceipt = const ProblemFailure(
      Problem(status: 409, code: 'CONFLICT'),
    );
    await openOrder(t);
    await tapReceived(t);
    expect(message(t), '이미 처리된 배송이에요');
    expect(find.byKey(const ValueKey('receipt-dlv-s2')), findsNothing);
  });

  testWidgets('보내지 못했으면 실패 안내와 함께 다시 누를 수 있다', (t) async {
    orders.failNextReceipt = const ProblemFailure(
      Problem(status: 404, code: ProblemCode.notFound),
    );
    await openOrder(t);
    await tapReceived(t);
    expect(message(t), '받음 처리가 되지 않았어요. 다시 시도해 주세요');
    expect(find.byKey(const ValueKey('receipt-dlv-s2')), findsOneWidget);
    expect(orders.received, isEmpty);
  });

  testWidgets('도착 예상을 못 읽으면 버튼을 두지 않는다(배송 상태를 모른다)', (t) async {
    orders.etaFails = true;
    await openOrder(t);
    expect(find.byKey(const ValueKey('receipt-dlv-s2')), findsNothing);
  });

  group('API 연동', () {
    Dio dioWith(FakeAdapter adapter) => createPmartDio(
      baseUrl: 'http://test.invalid/api/v1',
      sourceSystem: sourceSystem,
      tokens: TokenStore(MemoryKeyValueStore()),
      refresher: (_) async => null,
      adapter: adapter,
      delay: (_) async {},
    );

    test('POST /deliveries/{id}/receipt-confirmations — 본문 없음, 멱등 키·출처 헤더, APPLIED', () async {
      final adapter = FakeAdapter(
        (o, _) async =>
            const FakeReply(200, body: {'status': 'APPLIED', 'requestId': 'k'}),
      );
      final key = IdempotencyKey.generate();
      final status = await ApiOrdersRepository(dioWith(adapter))
          .confirmReceipt('dlv-1', key: key);

      final sent = adapter.requests.single;
      expect(sent.method, 'POST');
      expect(sent.path, endsWith('/deliveries/dlv-1/receipt-confirmations'));
      expect(sent.headers['Idempotency-Key'], key.value);
      expect(sent.headers['X-Source-System'], sourceSystem);
      expect(sent.data, anyOf(isNull, isEmpty));
      expect(status, CommandStatus.applied);
    });

    test('409 는 Problem 으로 던진다(완료로 보지 않는다)', () async {
      final adapter = FakeAdapter(
        (o, _) async => const FakeReply(
          409,
          body: {
            'type': 'about:blank',
            'title': 'x',
            'status': 409,
            'code': 'INVALID_STATE',
          },
        ),
      );
      await expectLater(
        ApiOrdersRepository(dioWith(adapter))
            .confirmReceipt('dlv-1', key: IdempotencyKey.generate()),
        throwsA(isA<ProblemFailure>()),
      );
    });
  });
}
