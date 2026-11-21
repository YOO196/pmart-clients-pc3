import 'dart:async';

import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart' show initPmartFormatting;

import 'package:customer_app/features/orders/data/mock_orders_repository.dart';
import 'package:customer_app/features/orders/domain/orders.dart';
import 'package:customer_app/features/orders/presentation/orders_providers.dart';
import 'package:customer_app/features/support/domain/inquiry.dart';
import 'package:customer_app/features/support/presentation/inquiry_screens.dart';
import 'package:customer_app/l10n/gen/app_localizations_ko.dart';
import 'package:customer_app/shared/order_status.dart';

import 'support/app_harness.dart';

/// 사용자 2026-11-21: 배송 단계 문구(레퍼런스 8·10) — 큰 제목 + 한 줄 설명을 배송현황·주문상세·홈 현황판이 같이,
/// 배달이 끝난 주문은 배송현황 대신 안내(10-4), 문의하기에서 라이더의 전달 완료 사진(9-2 3-3).
void main() {
  setUpAll(initPmartFormatting);
  Finder key(String k) => find.byKey(ValueKey(k));
  GoRouter routerOf(WidgetTester t) =>
      GoRouter.of(t.element(find.byType(Scaffold).first));
  final l10n = AppLocalizationsKo();

  group('단계 문구', () {
    DeliveryPhaseText of(
      OrderStatus s, {
      String? mode,
      DeliveryStage? stage,
      String? reserved,
    }) => deliveryPhaseText(
      l10n,
      status: s,
      deliveryMode: mode,
      stage: stage,
      reservedTitle: reserved,
    );

    test('주문 확인 · 예약 · 준비 · 라이더 출발 · 배달 중 · 곧 도착 · 완료 · 취소', () {
      expect(of(OrderStatus.confirmed), (
        title: '주문을 확인했어요',
        subtitle: '곧 주문하신 상품의 준비가 시작돼요.',
      ));
      expect(
        of(
          OrderStatus.confirmed,
          mode: 'SCHEDULED',
          reserved: '11월 22일 (토)\n오전 8:00~9:00 예약',
        ),
        (
          title: '11월 22일 (토)\n오전 8:00~9:00 예약',
          subtitle: '예약시간 변경은 상품준비가 시작되기 전까지 가능해요.',
        ),
      );
      expect(of(OrderStatus.preparing).title, '상품을 준비하고 있어요');
      expect(
        of(OrderStatus.preparing, mode: 'SCHEDULED').title,
        '예약하신 주문을 준비하고 있어요',
      );
      expect(
        of(OrderStatus.preparing, stage: DeliveryStage.toStore).title,
        '라이더님이 배달을 시작했어요',
      );
      expect(of(OrderStatus.inDelivery), (
        title: '배달 중이에요',
        subtitle: '주문하신 주소로 가고 있어요.',
      ));
      expect(of(OrderStatus.inDelivery, stage: DeliveryStage.atCustomer), (
        title: '라이더님이 곧 도착해요!',
        subtitle: '배달을 받을 수 있게 준비해 주세요.',
      ));
      expect(of(OrderStatus.completed).title, '배달이 완료됐어요');
      expect(of(OrderStatus.cancelled), (title: '주문이 취소됐어요', subtitle: null));
    });

    test('일부 전달: 남은 배송이 움직이면 그 단계, 아니면 "일부 상품이 먼저 도착했어요"', () {
      expect(
        of(
          OrderStatus.partiallyDelivered,
          stage: DeliveryStage.toCustomer,
        ).title,
        '배달 중이에요',
      );
      expect(of(OrderStatus.partiallyDelivered).title, '일부 상품이 먼저 도착했어요');
    });

    test('라이더 단계 "끝남"만으로는 배달 완료라고 하지 않는다(서버 확정만)', () {
      expect(
        of(OrderStatus.inDelivery, stage: DeliveryStage.done).title,
        '배달 중이에요',
      );
    });
  });

  Future<void> login(WidgetTester t, MockOrdersRepository orders) async {
    t.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const [], orders: orders));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(key('my-login'));
    await t.pumpAndSettle();
    await t.tap(key('login-kakao'));
    await t.pumpAndSettle();
  }

  Future<void> go(WidgetTester t, String location) async {
    unawaited(routerOf(t).push(location));
    await t.pumpAndSettle();
  }

  testWidgets('주문상세 제목이 단계 문구 — 취소된 예약 주문은 예약 시간이 아니라 "주문이 취소됐어요"', (t) async {
    await login(t, MockOrdersRepository(latency: Duration.zero));
    await go(t, '/orders/order-seed-3');
    expect(t.widget<Text>(key('order-headline')).data, '주문이 취소됐어요');
    routerOf(t).pop();
    await t.pumpAndSettle();
    await go(t, '/orders/order-seed-4');
    expect(t.widget<Text>(key('order-headline')).data, endsWith('예약'));
  });

  testWidgets('이미 배달이 끝난 주문의 배송현황 → "주문내역에서 확인해주세요", [확인]은 주문 상세로', (t) async {
    await login(t, MockOrdersRepository(latency: Duration.zero));
    await go(t, '/orders/order-seed-2/tracking');
    expect(key('track-closed'), findsOneWidget);
    expect(find.textContaining('주문내역에서 확인해주세요'), findsOneWidget);
    await t.tap(key('track-closed-ok'));
    await t.pumpAndSettle();
    expect(key('track-closed'), findsNothing);
    expect(key('order-headline'), findsOneWidget);
  });

  group('문의하기 → 전달 완료 사진', () {
    Future<void> openHelp(WidgetTester t, MockOrdersRepository orders) async {
      await login(t, orders);
      await go(t, '/orders/order-seed-2/help');
      await t.tap(key('order-help-misdelivered'));
      await t.pumpAndSettle();
    }

    testWidgets('다른 곳으로 배달 → 배송지·라이더 사진·놓은 곳, [문의 남기기]는 그 신고로', (t) async {
      final orders = MockOrdersRepository(latency: Duration.zero);
      await openHelp(t, orders);
      expect(key('delivery-proof'), findsOneWidget);
      expect(find.text('입력한 주소로\n배달이 오지 않았나요?'), findsOneWidget);
      expect(
        find.descendant(
          of: key('proof-address'),
          // order-seed-2 는 배송지 사본이 없는 주문(배포 전) — 현재 주소로 대신하지 않는다.
          matching: find.text('배송지 정보 없음'),
        ),
        findsOneWidget,
      );
      expect(key('proof-photo-ph-dlv-s3-1'), findsOneWidget);
      expect(find.text('놓은 곳: 문 앞에 두었어요'), findsOneWidget);

      // 사진을 누르면 크게
      await t.tap(key('proof-photo-ph-dlv-s3-1'));
      await t.pumpAndSettle();
      expect(key('proof-photo-large'), findsOneWidget);
      await t.tap(find.byType(CloseButton).last);
      await t.pumpAndSettle();

      await t.tap(key('proof-inquiry'));
      await t.pumpAndSettle();
      final form = t.widget<InquiryFormScreen>(find.byType(InquiryFormScreen));
      expect(form.args.deliveryIssue, DeliveryIssue.misdelivered);
      expect(form.args.orderId, 'order-seed-2');
    });

    testWidgets('사진 정보를 못 읽으면 "없음"이 아니라 실패 + 다시 시도', (t) async {
      final orders = MockOrdersRepository(latency: Duration.zero)
        ..proofFailures['dlv-s3'] = const NetworkFailure(
          DioExceptionType.connectionError,
        );
      await openHelp(t, orders);
      expect(find.text('사진 정보를 불러오지 못했어요'), findsOneWidget);
      expect(find.text('라이더가 남긴 사진이 없어요'), findsNothing);
      orders.proofFailures.clear();
      await t.tap(find.text('다시 시도'));
      await t.pumpAndSettle();
      expect(key('proof-photo-ph-dlv-s3-1'), findsOneWidget);
    });

    testWidgets('사진이 없으면 그렇다고', (t) async {
      final orders = MockOrdersRepository(latency: Duration.zero)
        ..proofPhotoCount = 0;
      await openHelp(t, orders);
      expect(find.text('라이더가 남긴 사진이 없어요'), findsOneWidget);
    });
  });
}
