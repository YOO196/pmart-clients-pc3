import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/address/data/mock_address_repository.dart';
import 'package:customer_app/features/address/domain/address.dart';

import 'support/app_harness.dart';

Future<MockAddressRepository> _withSecond() async {
  final repo = MockAddressRepository(latency: Duration.zero);
  await repo.add(
    const AddressDraft(
      label: '회사',
      roadAddress: '부산 부산진구 중앙대로 688',
      detailAddress: '6층',
    ),
    key: IdempotencyKey('seed'),
  );
  return repo;
}

Future<void> _openAddresses(WidgetTester t, {bool login = true}) async {
  await t.tap(find.text('마이페이지').last);
  await t.pumpAndSettle();
  if (login) {
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
  }
  await t.drag(find.byType(ListView).last, const Offset(0, -300));
  await t.pumpAndSettle();
  await t.tap(find.text('주소 설정'));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(initPmartFormatting);

  testWidgets('비회원 주소 관리에는 편집이 없다', (t) async {
    await t.pumpWidget(
      testApp(const [], address: (await t.runAsync(_withSecond))!),
    );
    await t.pumpAndSettle();
    await _openAddresses(t, login: false);
    expect(find.byKey(const ValueKey('address-edit')), findsNothing);
  });

  testWidgets('현재 주소는 삭제 버튼 없이 표시만, 다른 주소는 확인 뒤 지우고 서버 주소록으로 보인다', (t) async {
    final repo = (await t.runAsync(_withSecond))!;
    await t.pumpWidget(testApp(const [], address: repo));
    await t.pumpAndSettle();
    await _openAddresses(t);
    await t.tap(find.byKey(const ValueKey('address-edit')));
    await t.pumpAndSettle();

    expect(find.text('주소 편집'), findsOneWidget);
    expect(find.byKey(const ValueKey('address-current-badge')), findsOneWidget);
    expect(find.byKey(const ValueKey('address-delete-addr-1')), findsNothing);

    // 취소하면 보내지 않는다
    await t.tap(find.byKey(const ValueKey('address-delete-addr-2')));
    await t.pumpAndSettle();
    await t.tap(find.text('취소'));
    await t.pumpAndSettle();
    expect(repo.deleteKeys, isEmpty);

    await t.tap(find.byKey(const ValueKey('address-delete-addr-2')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('address-delete-confirm')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('address-edit-addr-2')), findsNothing);
    expect(find.text('주소를 삭제했어요'), findsOneWidget);
  });

  testWidgets('응답을 잃으면 같은 키로 다시 보내고, 지워졌으면 삭제로 보인다', (t) async {
    final repo = (await t.runAsync(_withSecond))!..loseNextDelete = true;
    await t.pumpWidget(testApp(const [], address: repo));
    await t.pumpAndSettle();
    await _openAddresses(t);
    await t.tap(find.byKey(const ValueKey('address-edit')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('address-delete-addr-2')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('address-delete-confirm')));
    await t.pumpAndSettle();

    expect(repo.deleteKeys.length, 2);
    expect(repo.deleteKeys.toSet().length, 1);
    expect(find.text('주소를 삭제했어요'), findsOneWidget);
    expect(find.byKey(const ValueKey('address-edit-addr-2')), findsNothing);
  });
  testWidgets('주소 편집 [수정] → 주소 상세에 지금 값이 채워지고, 고치면 서버(PATCH)에 보내 주소록이 바뀐다', (
    t,
  ) async {
    final repo = (await t.runAsync(_withSecond))!;
    await t.pumpWidget(testApp(const [], address: repo));
    await t.pumpAndSettle();
    await _openAddresses(t);
    await t.tap(find.byKey(const ValueKey('address-edit')));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('address-modify-addr-2')));
    await t.pumpAndSettle();
    final detail = t.widget<TextFormField>(
      find.byKey(const ValueKey('f-detail')),
    );
    expect(detail.controller!.text, '6층');

    await t.enterText(find.byKey(const ValueKey('f-detail')), '7층');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('address-save')));
    await t.pumpAndSettle();

    expect(repo.updated, ['addr-2']);
    final book = await t.runAsync(repo.book);
    expect(
      book!.addresses.singleWhere((a) => a.addressId == 'addr-2').detailAddress,
      '7층',
    );
  });
}
