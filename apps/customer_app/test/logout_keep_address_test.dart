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

  testWidgets('[예]: 로그아웃하고 그 주소의 도로명만 비회원 배송지로 옮겨 고른다(상세 주소는 옮기지 않음)', (
    t,
  ) async {
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
    expect(guest.detailAddress, isEmpty);
    expect(guest.roadAddress, isNotEmpty);
  });

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
}
