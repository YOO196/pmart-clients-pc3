import 'dart:convert';

import 'package:dio/dio.dart' show Dio;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/orders/data/mock_orders_repository.dart';
import 'package:customer_app/features/orders/presentation/order_help_screen.dart';
import 'package:customer_app/features/support/data/inquiries_repository.dart';
import 'package:customer_app/features/support/data/mock_inquiries_repository.dart';
import 'package:customer_app/features/support/domain/inquiry.dart';
import 'package:customer_app/features/support/presentation/inquiry_controller.dart';
import 'package:customer_app/shared/order_status.dart';
import 'package:customer_app/shared/providers.dart' show sourceSystem;

import 'support/app_harness.dart';

/// 배송 신고(지연·못 받음·다른 곳) — 주문 문의하기 → 무엇을 도와드릴까요? → 문의(case 0.16.0·0.23.0 `deliveryIssue`). 목 모드.
void main() {
  setUpAll(initPmartFormatting);

  late MockInquiriesRepository inquiries;
  setUp(() => inquiries = MockInquiriesRepository(latency: Duration.zero));

  Future<void> openHelp(WidgetTester t, String orderId) async {
    t.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp([
        inquiriesRepositoryProvider.overrideWithValue(inquiries),
      ], orders: MockOrdersRepository(latency: Duration.zero)),
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
      t.getTopLeft(find.byKey(ValueKey('order-$orderId'))) +
          const Offset(24, 24),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('order-inquiry')));
    await t.tap(find.byKey(const ValueKey('order-inquiry')));
    await t.pumpAndSettle();
  }

  testWidgets('진행 중 주문: "배달이 늦어지고 있어요" → 문의(배송 · 지연 · 배송 ID)', (t) async {
    await openHelp(t, 'order-seed-4');
    expect(find.text('무엇을 도와드릴까요?'), findsOneWidget);
    expect(find.byKey(const ValueKey('order-help-notReceived')), findsNothing);
    await t.tap(find.byKey(const ValueKey('order-help-delayed')));
    await t.pumpAndSettle();
    // 레퍼런스 9-1 5: 먼저 "진행 중인 주문을 확인해주세요" 안내 → "그래도 문의 남기기"
    expect(find.byKey(const ValueKey('help-delayed-guide')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('help-guide-inquiry')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('inq-issue')), findsOneWidget);
    // 종류는 배송으로 고정 — 다른 종류를 고를 수 없다.
    expect(
      t
          .widget<ChoiceChip>(find.byKey(const ValueKey('inq-cat-order')))
          .onSelected,
      isNull,
    );
    await t.enterText(find.byKey(const ValueKey('inq-body')), '30분째 안 와요');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('inq-submit')));
    await t.pumpAndSettle();

    expect(inquiries.lastCategory, InquiryCategory.delivery);
    expect(inquiries.lastDeliveryIssue, DeliveryIssue.delayed);
    expect(inquiries.lastOrderId, 'order-seed-4');
    expect(inquiries.lastDeliveryId, 'dlv-1');
  });

  testWidgets('서버가 진행 중 아님(422 ORDER_NOT_IN_PROGRESS)이면 그 안내, 접수됐다고 하지 않는다', (
    t,
  ) async {
    inquiries.failNextCreate = const ProblemFailure(
      Problem(status: 422, code: InquiryProblemCode.orderNotInProgress),
    );
    await openHelp(t, 'order-seed-4');
    await t.tap(find.byKey(const ValueKey('order-help-delayed')));
    await t.pumpAndSettle();
    // 레퍼런스 9-1 5: 먼저 "진행 중인 주문을 확인해주세요" 안내 → "그래도 문의 남기기"
    expect(find.byKey(const ValueKey('help-delayed-guide')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('help-guide-inquiry')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('inq-body')), '늦어요');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('inq-submit')));
    await t.pumpAndSettle();
    expect(
      t.widget<Text>(find.byKey(const ValueKey('inq-message'))).data,
      contains('진행 중인 주문만'),
    );
    expect(inquiries.created, 0);
  });

  testWidgets('"그 외 문의"는 배송 신고 없이 주문 문의', (t) async {
    await openHelp(t, 'order-seed-4');
    await t.tap(find.byKey(const ValueKey('order-help-other')));
    await t.pumpAndSettle();
    // 레퍼런스 9-1 5 그 외: "다른 도움이 필요하신가요?" → "그래도 문의 남기기"
    expect(find.byKey(const ValueKey('help-other-guide')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('help-guide-inquiry')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('inq-issue')), findsNothing);
    await t.enterText(find.byKey(const ValueKey('inq-body')), '질문');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('inq-submit')));
    await t.pumpAndSettle();
    expect(inquiries.lastDeliveryIssue, isNull);
    expect(inquiries.lastDeliveryId, isNull);
    expect(inquiries.lastCategory, InquiryCategory.order);
  });

  test('주문 상태 → 고를 수 있는 신고 종류', () {
    expect(deliveryIssuesFor(OrderStatus.inDelivery), [DeliveryIssue.delayed]);
    expect(deliveryIssuesFor(OrderStatus.completed), [
      DeliveryIssue.notReceived,
      DeliveryIssue.misdelivered,
    ]);
    expect(deliveryIssuesFor(OrderStatus.cancelled), isEmpty);
  });

  test(
    'API: POST /inquiries 에 category DELIVERY·deliveryIssue·deliveryId',
    () async {
      final adapter = FakeAdapter(
        (o, _) async => FakeReply(
          201,
          body: {
            'inquiryId': 'inq-1',
            'category': 'DELIVERY',
            'status': 'RECEIVED',
            'version': 1,
            'caseId': 'case-1',
            'body': '늦어요',
            'createdAt': '2026-11-18T03:00:00Z',
            'replies': <Object?>[],
          },
        ),
      );
      final Dio dio = createPmartDio(
        baseUrl: 'http://test.invalid/api/v1',
        sourceSystem: sourceSystem,
        tokens: TokenStore(MemoryKeyValueStore()),
        refresher: (_) async => null,
        adapter: adapter,
        delay: (_) async {},
      );
      await ApiInquiriesRepository(dio).create(
        const InquiryDraft(
          category: InquiryCategory.delivery,
          body: '늦어요',
          orderId: 'o-1',
          deliveryIssue: DeliveryIssue.delayed,
          deliveryId: 'dlv-1',
        ),
        key: IdempotencyKey.generate(),
      );
      final sent = jsonDecode(
        adapter.requests.single.data as String,
      ) as Map<String, dynamic>;
      expect(sent['category'], 'DELIVERY');
      expect(sent['deliveryIssue'], 'DELAYED');
      expect(sent['deliveryId'], 'dlv-1');
      expect(sent['orderId'], 'o-1');
    },
  );
}
