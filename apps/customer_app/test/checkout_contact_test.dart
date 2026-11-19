import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/address/data/mock_address_repository.dart';
import 'package:customer_app/features/checkout/data/mock_checkout_repository.dart';
import 'package:customer_app/features/checkout/presentation/checkout_controller.dart';
import 'package:customer_app/features/profile/data/mock_profile_repository.dart';

import 'support/app_harness.dart';

/// BR-60 R2·R3(order 0.14.0·customer 0.8.0): 주문서 "내 연락처"(레퍼런스 6-3).
/// 초안 사본 연락처는 주소 값 → 프로필. 둘 다 없으면 막힘 CONTACT_REQUIRED.
void main() {
  setUpAll(initPmartFormatting);
  final now = DateTime.utc(2026, 10, 24, 3);

  late MockCheckoutRepository checkout;
  late MockProfileRepository profile;
  late MockAddressRepository address;
  setUp(() {
    checkout = MockCheckoutRepository(latency: Duration.zero, now: () => now);
    profile = MockProfileRepository(latency: Duration.zero)..nickname = '김피마';
    address = MockAddressRepository(latency: Duration.zero);
    // 목 서버처럼: 주소에 남은 번호가 먼저, 없으면 프로필.
    checkout.contactOf = () =>
        address.clearedPhones.isEmpty ? '010-0000-0000' : profile.phone;
  });

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> toOrderSheet(WidgetTester t) async {
    t.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp(checkout: checkout, profile: profile, address: address, [
        clockProvider.overrideWithValue(() => now),
        draftPollPolicyProvider.overrideWithValue((
          interval: Duration.zero,
          attempts: 3,
        )),
      ]),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('장바구니').last);
    await t.pumpAndSettle();
    // 최소 주문 금액을 넘긴다(목 장바구니 기본은 미달).
    for (var i = 0; i < 3; i++) {
      await t.tap(key('cart-inc-ci-1'));
      await t.pumpAndSettle();
    }
    await t.tap(key('cart-order'));
    await t.pumpAndSettle();
    await t.tap(key('login-kakao'));
    await t.pumpAndSettle();
    await t.tap(key('mode-single'));
    await t.pump();
    await t.tap(key('delivery-next'));
    await t.pumpAndSettle();
  }

  testWidgets('주문서에 사본의 연락처를 보이고, 번호 변경 → 프로필 저장·주소의 옛 번호 비움·초안 다시', (t) async {
    await toOrderSheet(t);
    expect(find.text('내 연락처'), findsOneWidget);
    // 받는 곳에는 이름만 — 같은 번호가 두 번 보이지 않는다.
    expect(find.textContaining('010-0000-0000'), findsOneWidget);
    expect(find.text('김피마'), findsOneWidget);
    expect(t.widget<Text>(key('contact-phone')).data, '010-0000-0000');
    final draftsBefore = checkout.drafts.length;

    await t.ensureVisible(key('contact-change'));
    await t.tap(key('contact-change'));
    await t.pumpAndSettle();
    expect(key('contact-sheet'), findsOneWidget);
    await t.enterText(key('contact-phone-input'), '01098765432');
    expect(
      t.widget<TextField>(key('contact-phone-input')).controller!.text,
      '010-9876-5432',
    );
    await t.tap(key('contact-done'));
    await t.pumpAndSettle();

    expect(key('contact-sheet'), findsNothing);
    expect(profile.phone, '01098765432');
    expect(address.clearedPhones, ['addr-1']);
    // 같은 의도면 서버가 옛 초안을 돌려주므로 새 초안이다.
    expect(checkout.drafts.length, draftsBefore + 1);
    expect(t.widget<Text>(key('contact-phone')).data, '010-9876-5432');
  });

  testWidgets('주소·프로필 모두 연락처가 없으면 막힘 → "입력" → 저장 뒤 막힘이 풀린다', (t) async {
    checkout.contactOf = () => profile.phone;
    await toOrderSheet(t);
    expect(key('blocker-contactRequired'), findsOneWidget);
    // 안내 띠와 결제 버튼(첫 막는 사유)에 같은 문구.
    expect(find.text('받는 분 연락처를 입력해 주세요'), findsWidgets);
    expect(t.widget<Text>(key('contact-phone')).data, '연락처 없음');

    await t.tap(key('contact-enter'));
    await t.pumpAndSettle();
    await t.enterText(key('contact-phone-input'), '01012345678');
    await t.tap(key('contact-done'));
    await t.pumpAndSettle();

    expect(key('blocker-contactRequired'), findsNothing);
    expect(t.widget<Text>(key('contact-phone')).data, '010-1234-5678');
  });

  testWidgets('휴대폰 번호가 아니면 저장하지 않는다', (t) async {
    await toOrderSheet(t);
    await t.ensureVisible(key('contact-change'));
    await t.tap(key('contact-change'));
    await t.pumpAndSettle();
    await t.enterText(key('contact-phone-input'), '0212345678');
    await t.tap(key('contact-done'));
    await t.pumpAndSettle();

    expect(key('contact-sheet'), findsOneWidget);
    expect(find.text('휴대폰 번호를 확인해 주세요(010으로 시작하는 10~11자리)'), findsOneWidget);
    expect(profile.changeKeys, isEmpty);
  });

  testWidgets('프로필 저장이 안 되면 초안을 다시 만들지 않는다', (t) async {
    profile.rejectPhone = true;
    await toOrderSheet(t);
    final draftsBefore = checkout.drafts.length;
    await t.ensureVisible(key('contact-change'));
    await t.tap(key('contact-change'));
    await t.pumpAndSettle();
    await t.enterText(key('contact-phone-input'), '01098765432');
    await t.tap(key('contact-done'));
    await t.pumpAndSettle();

    expect(key('contact-sheet'), findsOneWidget);
    expect(address.clearedPhones, isEmpty);
    expect(checkout.drafts.length, draftsBefore);
  });
}
