import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/address/data/mock_address_repository.dart';
import 'package:customer_app/features/address/domain/address.dart';
import 'package:customer_app/features/profile/data/mock_profile_repository.dart';

import 'support/app_harness.dart';

/// 저장 요청(초안)을 남기는 목.
final class _RecordingAddresses extends MockAddressRepository {
  _RecordingAddresses() : super(latency: Duration.zero);

  final drafts = <AddressDraft>[];

  @override
  Future<Address> add(AddressDraft draft, {required IdempotencyKey key}) {
    drafts.add(draft);
    return super.add(draft, key: key);
  }

  @override
  Future<Address> addGuest(AddressDraft draft, {required IdempotencyKey key}) {
    drafts.add(draft);
    return super.addGuest(draft, key: key);
  }
}

/// BR-60: 레퍼런스 주소 상세에는 받는 분·연락처가 없다. 회원은 프로필 값으로 채우고 없는 것만 묻는다.
void main() {
  setUpAll(initPmartFormatting);

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> openForm(
    WidgetTester t, {
    required _RecordingAddresses addresses,
    MockProfileRepository? profile,
    bool member = true,
  }) async {
    t.view
      ..physicalSize = const Size(800, 1800)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp(
        const [],
        address: addresses,
        profile: profile,
        addressPicker: FakeAddressPicker(),
      ),
    );
    await t.pumpAndSettle();
    if (member) {
      await t.tap(find.text('마이페이지').last);
      await t.pumpAndSettle();
      await t.tap(key('my-login'));
      await t.pumpAndSettle();
      await t.tap(key('login-kakao'));
      await t.pumpAndSettle();
      await t.tap(find.text('홈').last);
      await t.pumpAndSettle();
    }
    await t.tap(key('home-address'));
    await t.pumpAndSettle();
    await t.tap(key('address-add'));
    await t.pumpAndSettle();
    await t.tap(key('address-search'));
    await t.pumpAndSettle();
    await t.enterText(key('f-detail'), '1층');
  }

  testWidgets('프로필에 이름·연락처가 있으면 칸 없이 그 값으로 저장한다', (t) async {
    final addresses = _RecordingAddresses();
    final profile = MockProfileRepository(latency: Duration.zero)
      ..nickname = '김피마'
      ..phone = '01012345678';
    await openForm(t, addresses: addresses, profile: profile);

    expect(key('f-name'), findsNothing);
    expect(key('f-phone'), findsNothing);
    await t.tap(key('address-save'));
    await t.pumpAndSettle();

    expect(addresses.drafts.single.receiverName, '김피마');
    expect(addresses.drafts.single.receiverPhone, '010-1234-5678');
    expect(profile.changeKeys, isEmpty);
  });

  testWidgets('연락처가 없으면 "내 연락처"만 묻고 프로필에도 저장한다', (t) async {
    final addresses = _RecordingAddresses();
    final profile = MockProfileRepository(latency: Duration.zero)..name = '김구글';
    await openForm(t, addresses: addresses, profile: profile);

    expect(key('f-name'), findsNothing);
    expect(
      find.descendant(of: key('f-phone'), matching: find.text('내 연락처')),
      findsOneWidget,
    );
    await t.enterText(key('f-phone'), '01098765432');
    await t.tap(key('address-save'));
    await t.pumpAndSettle();

    expect(addresses.drafts.single.receiverName, '김구글');
    expect(addresses.drafts.single.receiverPhone, '010-9876-5432');
    expect(profile.phone, '01098765432');
  });

  testWidgets('프로필에 연락처를 못 남겨도 주소는 입력한 번호로 저장한다', (t) async {
    final addresses = _RecordingAddresses();
    final profile = MockProfileRepository(latency: Duration.zero)
      ..nickname = '김피마'
      ..rejectPhone = true;
    await openForm(t, addresses: addresses, profile: profile);

    await t.enterText(key('f-phone'), '01098765432');
    await t.tap(key('address-save'));
    await t.pumpAndSettle();

    expect(addresses.drafts.single.receiverPhone, '010-9876-5432');
    expect(profile.phone, isNull);
  });

  testWidgets('비회원은 프로필이 없어 받는 분·연락처를 묻는다', (t) async {
    final addresses = _RecordingAddresses();
    await openForm(t, addresses: addresses, member: false);

    expect(key('f-name'), findsOneWidget);
    expect(
      find.descendant(of: key('f-phone'), matching: find.text('연락처')),
      findsOneWidget,
    );
  });
}
