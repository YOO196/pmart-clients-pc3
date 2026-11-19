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

/// BR-60(customer 0.8.0): 레퍼런스 주소 상세에는 받는 분·연락처가 없다. 회원·비회원 모두 묻지도 보내지도 않는다 —
/// 주문 초안이 프로필 값을 쓰고, 없으면 주문서가 "내 연락처"를 받는다(checkout_contact_test).
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

  for (final member in [true, false]) {
    testWidgets('${member ? '회원' : '비회원'}: 받는 분·연락처 칸이 없고 보내지 않는다', (t) async {
      final addresses = _RecordingAddresses();
      final profile = MockProfileRepository(latency: Duration.zero);
      await openForm(t, addresses: addresses, profile: profile, member: member);

      expect(key('f-name'), findsNothing);
      expect(key('f-phone'), findsNothing);
      await t.tap(key('address-save'));
      await t.pumpAndSettle();

      expect(addresses.drafts.last.receiverName, isNull);
      expect(addresses.drafts.last.receiverPhone, isNull);
      // 주소 입력에서는 프로필을 바꾸지 않는다.
      expect(profile.changeKeys, isEmpty);
    });
  }
}
