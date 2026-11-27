import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
    // 회원은 마이 → 주소관리에서 바로 주소 편집(사용자 2026-11-26).
    await _openAddresses(t);

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
    // 회원은 마이 → 주소관리에서 바로 주소 편집(사용자 2026-11-26).
    await _openAddresses(t);
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
    // 회원은 마이 → 주소관리에서 바로 주소 편집(사용자 2026-11-26).
    await _openAddresses(t);

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
  Future<void> openEdit(WidgetTester t, MockAddressRepository repo) async {
    await t.pumpWidget(testApp(const [], address: repo));
    await t.pumpAndSettle();
    // 회원은 마이 → 주소관리에서 바로 주소 편집(사용자 2026-11-26).
    await _openAddresses(t);
    await t.tap(find.byKey(const ValueKey('address-modify-addr-2')));
    await t.pumpAndSettle();
  }

  Future<String?> labelOf(WidgetTester t, MockAddressRepository repo) async =>
      (await t.runAsync(repo.book))!.addresses
          .singleWhere((a) => a.addressId == 'addr-2')
          .label;

  bool selected(WidgetTester t, String alias) => t
      .widget<Semantics>(
        find.descendant(
          of: find.byKey(ValueKey('address-alias-$alias')),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.selected != null,
          ),
        ),
      )
      .properties
      .selected!;

  // 새 레퍼런스 3-1/2-5(사용자 2026-11-21): [우리집][회사][추가], [추가]를 누르면 아래 별칭 입력칸.
  testWidgets('주소 상세(고치기): 지금 별칭 "회사"면 [회사]가 골라져 있고 입력칸은 없다', (t) async {
    final repo = (await t.runAsync(_withSecond))!;
    await openEdit(t, repo);
    expect(selected(t, 'work'), isTrue);
    expect(selected(t, 'home'), isFalse);
    expect(find.byKey(const ValueKey('f-label')), findsNothing);
  });

  testWidgets('[우리집]을 고르면 "우리집"으로 저장, 목록 제목이 바뀐다', (t) async {
    final repo = (await t.runAsync(_withSecond))!;
    await openEdit(t, repo);
    await t.tap(find.byKey(const ValueKey('address-alias-home')));
    await t.pump();
    expect(selected(t, 'home'), isTrue);
    expect(selected(t, 'work'), isFalse);
    await t.tap(find.byKey(const ValueKey('address-save')));
    await t.pumpAndSettle();
    expect(await labelOf(t, repo), '우리집');
  });

  testWidgets('[추가]를 누르면 아래에 입력칸 — 적은 별칭으로 저장', (t) async {
    final repo = (await t.runAsync(_withSecond))!;
    await openEdit(t, repo);
    expect(find.byKey(const ValueKey('f-label')), findsNothing);
    await t.tap(find.byKey(const ValueKey('address-alias-custom')));
    await t.pump();
    final field = find.byKey(const ValueKey('f-label'));
    expect(field, findsOneWidget);
    // 입력칸은 알약 줄 아래
    expect(
      t.getTopLeft(field).dy,
      greaterThan(
        t.getBottomLeft(find.byKey(const ValueKey('address-alias-custom'))).dy,
      ),
    );
    await t.enterText(field, '부모님 댁');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('address-save')));
    await t.pumpAndSettle();
    expect(await labelOf(t, repo), '부모님 댁');
  });

  testWidgets('[추가]를 고르고 비워 두면 저장하지 않고 입력하라고 한다', (t) async {
    final repo = (await t.runAsync(_withSecond))!;
    await openEdit(t, repo);
    await t.tap(find.byKey(const ValueKey('address-alias-custom')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('address-save')));
    await t.pumpAndSettle();
    expect(repo.updated, isEmpty);
    expect(await labelOf(t, repo), '회사');
  });

  testWidgets('고른 알약을 다시 누르면 풀린다 — 별칭 없이 저장', (t) async {
    final repo = (await t.runAsync(_withSecond))!;
    await openEdit(t, repo);
    await t.tap(find.byKey(const ValueKey('address-alias-work')));
    await t.pump();
    expect(selected(t, 'work'), isFalse);
    await t.tap(find.byKey(const ValueKey('address-save')));
    await t.pumpAndSettle();
    expect(await labelOf(t, repo), isNull);
  });
  testWidgets('회원은 새 주소 등록에도 별칭 알약이 있다(사용자 2026-11-23)', (t) async {
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await _openAddresses(t);
    final router = GoRouter.of(t.element(find.byType(Scaffold).first));
    unawaited(router.push('/addresses/new'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('address-alias-home')), findsOneWidget);
    expect(find.byKey(const ValueKey('address-alias-work')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('address-alias-custom')));
    await t.pump();
    expect(find.byKey(const ValueKey('f-label')), findsOneWidget);
  });

  testWidgets('비회원 새 주소 등록에는 별칭 칸이 없다(회원만)', (t) async {
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    final router = GoRouter.of(t.element(find.byType(Scaffold).first));
    unawaited(router.push('/addresses/new'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('f-label')), findsNothing);
    expect(find.byKey(const ValueKey('address-alias-home')), findsNothing);
  });
  testWidgets('비회원은 주소 상세 경로로 바로 와도 별칭 칸이 없다(회원만)', (t) async {
    await t.pumpWidget(
      testApp(const [], address: (await t.runAsync(_withSecond))!),
    );
    await t.pumpAndSettle();
    final router = GoRouter.of(t.element(find.byType(Scaffold).first));
    unawaited(router.push('/addresses/edit/addr-2'));
    await t.pump();
    expect(find.byKey(const ValueKey('f-label')), findsNothing);
    await t.pumpAndSettle();
    // 주소 상세가 열렸다(경로가 틀려 오류 화면만 보고 통과하지 않게)
    expect(find.byKey(const ValueKey('f-detail')), findsOneWidget);
    expect(find.byKey(const ValueKey('f-label')), findsNothing);
    expect(find.byKey(const ValueKey('address-alias-home')), findsNothing);
  });
}
