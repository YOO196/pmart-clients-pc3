import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/checkout/data/mock_checkout_repository.dart';
import 'package:customer_app/features/checkout/domain/checkout.dart';
import 'package:customer_app/features/checkout/presentation/checkout_controller.dart';

import 'support/app_harness.dart';

void main() {
  setUpAll(initPmartFormatting);

  final now = DateTime.utc(2026, 10, 24, 3); // 서울 12:00

  Widget app(MockCheckoutRepository checkout) => testApp(checkout: checkout, [
    clockProvider.overrideWithValue(() => now),
    draftPollPolicyProvider.overrideWithValue((
      interval: Duration.zero,
      attempts: 3,
    )),
  ]);

  Future<void> toDelivery(WidgetTester t) async {
    t.view
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpAndSettle();
    await t.tap(find.text('장바구니').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('cart-order')));
    await t.pumpAndSettle();
    // 비회원이라 주문 목적 로그인을 거친다.
    expect(find.text('주문하려면 로그인이 필요해요'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
  }

  testWidgets('비회원 주문하기 → 로그인 → 배송 방식 → 주문서(서버 금액, 최소주문 미달이면 결제 닫힘)', (
    t,
  ) async {
    final checkout = MockCheckoutRepository(
      latency: Duration.zero,
      now: () => now,
    );
    await t.pumpWidget(app(checkout));
    await toDelivery(t);

    expect(find.text('배송 방식 선택'), findsOneWidget);
    final next = find.byKey(const ValueKey('delivery-next'));
    expect(t.widget<FilledButton>(next).onPressed, isNull);

    await t.tap(find.byKey(const ValueKey('mode-single')));
    await t.pump();
    await t.tap(next);
    await t.pumpAndSettle();

    expect(find.text('주문서'), findsOneWidget);
    expect(find.byKey(const ValueKey('min-order')), findsOneWidget);
    expect(find.text('12,040원'), findsOneWidget); // 7,940 + 4,000 + 100 (목 서버)
    final pay = t.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const ValueKey('pay')),
        matching: find.byType(FilledButton),
      ),
    );
    expect(pay.onPressed, isNull);
  });

  testWidgets('예약은 고를 수 있는 슬롯만 열리고 마감·미설정은 막힌다', (t) async {
    final checkout = MockCheckoutRepository(
      latency: Duration.zero,
      now: () => now,
    );
    await t.pumpWidget(app(checkout));
    await toDelivery(t);

    await t.tap(find.byKey(const ValueKey('mode-scheduled')));
    await t.pumpAndSettle();

    ChoiceChip chip(String start) =>
        t.widget<ChoiceChip>(find.byKey(ValueKey('slot-2026-10-24-$start')));
    // 서울 12시: 13시 도착은 마감(12시 컷오프 지남), 21시는 정원 미설정.
    expect(chip('13:00').onSelected, isNull);
    expect(chip('21:00').onSelected, isNull);
    expect(find.textContaining('준비 중'), findsOneWidget);
    expect(chip('15:00').onSelected, isNotNull);

    final next = find.byKey(const ValueKey('delivery-next'));
    expect(t.widget<FilledButton>(next).onPressed, isNull);
    await t.tap(find.byKey(const ValueKey('slot-2026-10-24-15:00')));
    await t.pump();
    expect(t.widget<FilledButton>(next).onPressed, isNotNull);
  });

  testWidgets('BR-13 목: 지금 안 되는 방식은 사유와 함께 막힌다', (t) async {
    final checkout = MockCheckoutRepository(
      latency: Duration.zero,
      now: () => now,
    )..unavailable = {DeliveryMode.single: '지금은 한집배달을 할 수 없어요'};
    await t.pumpWidget(app(checkout));
    await toDelivery(t);

    final tile = t.widget<RadioListTile<DeliveryMode>>(
      find.byKey(const ValueKey('mode-single')),
    );
    expect(tile.enabled, isFalse);
    expect(find.text('지금은 한집배달을 할 수 없어요'), findsOneWidget);
  });
}
