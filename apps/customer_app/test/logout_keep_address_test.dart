import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/address/data/guest_address_store.dart';
import 'package:customer_app/features/address/data/mock_address_repository.dart';
import 'package:customer_app/features/auth/domain/auth.dart';
import 'package:customer_app/features/auth/presentation/auth_controller.dart';

import 'support/app_harness.dart';

/// 로그아웃 때 "지금 주소로 계속 둘러볼까요?"(customer 0.14.0 — 백엔드 요청 2026-11-20 logout-keep-browsing-address).
void main() {
  setUpAll(initPmartFormatting);

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<({MemoryKeyValueStore secure, MockAddressRepository address})> login(
    WidgetTester t,
  ) async {
    t.view
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final secure = MemoryKeyValueStore();
    final address = MockAddressRepository(latency: Duration.zero);
    await t.pumpWidget(testApp(const [], secure: secure, address: address));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(key('my-login'));
    await t.pumpAndSettle();
    await t.tap(key('login-kakao'));
    await t.pumpAndSettle();
    await t.ensureVisible(key('logout'));
    return (secure: secure, address: address);
  }

  bool member(WidgetTester t) =>
      ProviderScope.containerOf(t.element(find.byType(Scaffold).first))
              .read(sessionProvider)
          is MemberSession;

  testWidgets(
    '[예]: 로그아웃하고 그 주소의 도로명·상세 주소를 비회원 배송지로 옮겨 고른다(받는 분·연락처는 옮기지 않음)',
    (t) async {
      final (:secure, :address) = await login(t);
      await t.tap(key('logout'));
      await t.pumpAndSettle();
      expect(find.text('지금 주소로 계속 둘러볼까요?'), findsOneWidget);

      await t.tap(key('logout-keep-address-yes'));
      await t.pumpAndSettle();
      expect(member(t), isFalse);
      final store = GuestAddressStore(secure);
      final ids = await store.ids();
      expect(ids, hasLength(1));
      expect(await store.selected(), ids.single);
      final guest = (await t.runAsync(() => address.guest(ids.single)))!;
      // 상세 주소도 옮긴다 — 다시 로그인할 때 그대로 회원 주소로(사용자 2026-11-25).
      expect(guest.detailAddress, '전포 한빛아파트 103동 1203호');
      expect(guest.roadAddress, isNotEmpty);
    },
  );

  testWidgets('[아니요]: 로그아웃만 — 비회원 배송지를 만들지 않는다', (t) async {
    final (:secure, address: _) = await login(t);
    await t.tap(key('logout'));
    await t.pumpAndSettle();
    await t.tap(key('logout-keep-address-no'));
    await t.pumpAndSettle();
    expect(member(t), isFalse);
    expect(await GuestAddressStore(secure).ids(), isEmpty);
  });

  testWidgets('창을 닫으면 로그아웃하지 않는다', (t) async {
    await login(t);
    await t.tap(key('logout'));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    expect(find.text('지금 주소로 계속 둘러볼까요?'), findsNothing);
    expect(member(t), isTrue);
  });

  testWidgets('이미 이 기기에 비회원 배송지가 있으면 묻지 않고 로그아웃한다', (t) async {
    final (:secure, address: _) = await login(t);
    await GuestAddressStore(secure).add('guest-old');
    await t.tap(key('logout'));
    await t.pumpAndSettle();
    expect(find.text('지금 주소로 계속 둘러볼까요?'), findsNothing);
    expect(member(t), isFalse);
  });
  // 사용자 2026-11-21: "로그아웃하고 나서 비회원 주소 저장이 안 돼서 주소 입력창이 뜸" — 로그아웃 직후 주소록이
  // 잠깐 비는 사이 처음 실행 단계가 주소 입력으로 보냈다. 처음 실행 단계를 켠 채로 확인한다.
  testWidgets('[예]: 옮기는 동안에도 주소 입력 화면으로 가지 않는다(처음 실행 단계 켬)', (t) async {
    t.view
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final secure = MemoryKeyValueStore();
    await secure.write('pmart.start.welcome', 'at=x');
    // 느린 서버 — 로그아웃과 비회원 배송지 만들기 사이에 틈이 생긴다.
    final address = MockAddressRepository(
      latency: const Duration(milliseconds: 200),
    );
    await t.pumpWidget(
      testApp(const [], startGate: true, secure: secure, address: address),
    );
    await t.pumpAndSettle();
    await t.tap(key('login-kakao'));
    await t.pumpAndSettle();
    expect(key('start-address'), findsNothing);

    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.ensureVisible(key('logout'));
    await t.tap(key('logout'));
    await t.pumpAndSettle();
    await t.tap(key('logout-keep-address-yes'));
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 50));
      expect(key('start-address'), findsNothing, reason: '${i * 50}ms');
    }
    await t.pumpAndSettle();
    expect(member(t), isFalse);
    expect(key('start-address'), findsNothing);
    expect(await GuestAddressStore(secure).ids(), hasLength(1));
  });
}
