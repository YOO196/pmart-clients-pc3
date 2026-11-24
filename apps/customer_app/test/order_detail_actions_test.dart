import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_ui/pmart_ui.dart' show initPmartFormatting;

import 'package:customer_app/features/claims/presentation/return_request_screens.dart';

import 'support/app_harness.dart';

/// 주문상세(사용자 2026-11-21, 레퍼런스 9-1·9-2): 상태마다 다른 버튼, 예약시간 변경 진입, 배달 정보 칸, 줄 수량 문구 없음.
void main() {
  setUpAll(initPmartFormatting);
  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> openDetail(WidgetTester t, String orderId) async {
    t.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(key('my-login'));
    await t.pumpAndSettle();
    await t.tap(key('login-kakao'));
    await t.pumpAndSettle();
    await t.tap(key('my-orders'));
    await t.pumpAndSettle();
    await t.tapAt(t.getTopLeft(key('order-$orderId')) + const Offset(24, 24));
    await t.pumpAndSettle();
  }

  testWidgets('예약 확정(준비 전): [주문취소][예약시간 변경] + [문의하기][배달 현황]', (t) async {
    await openDetail(t, 'order-seed-4');
    expect(key('cancel-order'), findsOneWidget);
    expect(key('reschedule'), findsOneWidget);
    expect(key('order-inquiry'), findsOneWidget);
    // 배송현황은 배달이 끝나기 전까지 늘 들어갈 수 있다(레퍼런스 8-4, 사용자 2026-11-21).
    expect(key('order-track'), findsOneWidget);
    expect(key('order-return-exchange'), findsNothing);
    // 예약시간 변경은 아래 시트로 열린다(레퍼런스 9-1 4)
    await t.tap(key('reschedule'));
    await t.pumpAndSettle();
    expect(find.text('예약배달 도착 시간'), findsOneWidget);
  });

  testWidgets('배달 중: [문의하기][배달 현황]', (t) async {
    await openDetail(t, 'order-seed-1');
    expect(key('order-inquiry'), findsOneWidget);
    expect(key('order-track'), findsOneWidget);
    expect(key('order-return-exchange'), findsNothing);
    expect(key('reschedule'), findsNothing);
  });

  testWidgets('배송 완료: [반품·교환][문의하기] — 반품·교환은 신청 화면으로(레퍼런스 12)', (t) async {
    await openDetail(t, 'order-seed-2');
    expect(key('order-track'), findsNothing);
    expect(key('order-inquiry'), findsOneWidget);
    await t.tap(key('order-return-exchange'));
    await t.pumpAndSettle();
    final entry = t.widget<ReturnExchangeEntryScreen>(
      find.byType(ReturnExchangeEntryScreen),
    );
    expect(entry.orderId, 'order-seed-2');
  });

  testWidgets('취소된 주문: 버튼 없음', (t) async {
    await openDetail(t, 'order-seed-3');
    expect(key('order-inquiry'), findsNothing);
    expect(key('order-track'), findsNothing);
    expect(key('order-return-exchange'), findsNothing);
    expect(key('cancel-order'), findsNothing);
  });

  testWidgets('주문 상품 줄에 "전달 N개·취소 N개" 문구를 두지 않는다', (t) async {
    await openDetail(t, 'order-seed-1');
    expect(find.textContaining(RegExp(r'^(전달|취소|반품) \d+개')), findsNothing);
  });

  testWidgets('배달 정보: 항목마다 제목 + 값(배달 주소·받는 분·출입 방법·라이더님께·품절 시 처리)', (t) async {
    await openDetail(t, 'order-seed-4');
    expect(find.text('배달 주소'), findsOneWidget);
    expect(find.text('받는 분'), findsOneWidget);
    expect(find.text('출입 방법'), findsOneWidget);
    expect(key('shipping-address'), findsOneWidget);
  });
}
