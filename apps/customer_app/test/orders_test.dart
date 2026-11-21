import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_api_delivery_tracking/pmart_api_delivery_tracking.dart'
    as trk;
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/orders/data/mock_orders_repository.dart';
import 'package:customer_app/features/orders/data/orders_repository.dart';
import 'package:customer_app/features/orders/domain/orders.dart';

import 'package:customer_app/shared/order_status.dart';

import 'support/app_harness.dart';

base class _ListDown extends MockOrdersRepository {
  _ListDown() : super(latency: Duration.zero);

  @override
  Future<OrderPage> list({
    String? cursor,
    OrderStatus? status,
    String? from,
    String? q,
  }) async => throw const NetworkFailure(DioExceptionType.connectionError);
}

void main() {
  setUpAll(initPmartFormatting);

  group('변환', () {
    test('위치 확인 중이면 남아 있는 도착 시각이 있어도 쓰지 않는다', () {
      final e = etaFromContract(
        'd',
        trk.DeliveryEta.fromJson({
          'stage': 'TO_CUSTOMER',
          'dropEta': {
            'status': 'LOCATING',
            'etaAt': '2026-10-24T03:10:00Z',
            'remainingSeconds': 300,
          },
        }),
      );
      expect(e.status, EtaStatus.locating);
      expect(e.etaAt, isNull);
      expect(e.remainingSeconds, isNull);
    });
  });

  Future<void> openOrders(
    WidgetTester t, {
    MockOrdersRepository? orders,
  }) async {
    t.view
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const [], orders: orders));
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

  testWidgets('비회원은 주문 내역 대신 로그인 안내를 본다', (t) async {
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-orders')));
    await t.pumpAndSettle();

    expect(find.text('주문 내역을 보려면 로그인이 필요해요'), findsOneWidget);
    expect(find.byKey(const ValueKey('orders-empty')), findsNothing);
  });

  testWidgets('주문 목록 조회 실패는 "주문 없음"이 아니다', (t) async {
    await openOrders(t, orders: _ListDown());

    expect(find.byKey(const ValueKey('orders-empty')), findsNothing);
    expect(find.text('화면을 불러오지 못했어요'), findsOneWidget);
  });

  testWidgets('분할배송 주문은 배송별 상태·품목과 늦은 원천을 보인다', (t) async {
    await openOrders(t);
    expect(find.byKey(const ValueKey('order-order-seed-1')), findsOneWidget);
    expect(find.text('일부 전달'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('order-order-seed-1')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('shipment-sh-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('shipment-sh-2')), findsOneWidget);
    expect(find.textContaining('배송 1 · 배송 완료'), findsOneWidget);
    expect(find.textContaining('배송 2 · 배송 중'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('stale-delivery-execution-service')),
      findsOneWidget,
    );
  });

  testWidgets('주문 상세의 받는 곳은 주문 당시 배송지 사본이다(BR-37)', (t) async {
    await openOrders(t);
    await t.tap(find.byKey(const ValueKey('order-order-seed-4')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('shipping-address')), findsOneWidget);
    expect(find.textContaining('전포대로 210'), findsOneWidget);
    expect(find.text('김피마 · 010-0000-0000'), findsOneWidget);
  });

  testWidgets('사본이 없는 주문(배포 전)은 "배송지 정보 없음"이고 현재 주소로 대신하지 않는다', (t) async {
    await openOrders(t);
    await t.tap(find.byKey(const ValueKey('order-order-seed-1')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('shipping-address-none')), findsOneWidget);
    expect(find.text('배송지 정보 없음'), findsOneWidget);
    expect(find.textContaining('올림픽로'), findsNothing);
  });

  testWidgets('취소 주문은 서버가 준 총 환불금액을 보인다', (t) async {
    await openOrders(t);
    await t.tap(find.byKey(const ValueKey('order-order-seed-3')));
    await t.pumpAndSettle();

    expect(find.text('주문 취소'), findsOneWidget);
    expect(find.byKey(const ValueKey('refunded')), findsOneWidget);
    // 줄마다 "취소 N개" 문구는 두지 않는다(사용자 2026-11-21) — 환불 금액·처리 내역으로 보인다.
    expect(find.textContaining('취소 2개'), findsNothing);
  });

  testWidgets('배송 조회: 도착 예정·지연은 서버 값, 위치 실패는 배송 실패가 아니다', (t) async {
    final orders = MockOrdersRepository(latency: Duration.zero);
    await openOrders(t, orders: orders);
    await t.tap(find.byKey(const ValueKey('order-order-seed-1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('track-dlv-s2')));
    await t.pumpAndSettle();

    // 레퍼런스 8-5: "N분 남음" + 도착 시각(서버 값) + 한 줄 설명(주문상세·홈 현황판과 같은 단계 문구).
    expect(find.text('주문하신 주소로 가고 있어요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('track-sheet-remaining')), findsOneWidget);
    expect(find.byKey(const ValueKey('eta-delayed')), findsOneWidget);

    orders.etaFails = true;
    await t.tap(
      find.byWidgetPredicate(
        (w) => w is BackButton || w.key == const ValueKey('track-close'),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('track-dlv-s2')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('eta-failed')), findsOneWidget);
    expect(find.text('배송하지 못함'), findsNothing);
  });
}
