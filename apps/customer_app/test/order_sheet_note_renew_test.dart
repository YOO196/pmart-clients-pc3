import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/checkout/data/mock_checkout_repository.dart';
import 'package:customer_app/features/checkout/presentation/checkout_controller.dart';

import 'support/app_harness.dart';

/// 주문서에서 라이더 요청사항을 바꾸면 새 초안을 받는 동안 주문서가 그대로 있다(사용자 2026-11-20:
/// "라이더 요청사항을 업데이트했을 때 전체적으로 화면 업데이트가 되더라").
void main() {
  setUpAll(initPmartFormatting);
  final now = DateTime.utc(2026, 10, 24, 3);

  testWidgets('요청사항을 바꾸면 로딩 화면으로 바뀌지 않고, 주문서를 막은 채 새 초안(서버 값)으로 바뀐다', (
    t,
  ) async {
    final checkout = MockCheckoutRepository(
      latency: const Duration(milliseconds: 300),
      now: () => now,
    );
    t.view
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp(checkout: checkout, [
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
    for (var i = 0; i < 3; i++) {
      await t.tap(find.byKey(const ValueKey('cart-inc-ci-1')));
      await t.pumpAndSettle();
    }
    await t.tap(find.byKey(const ValueKey('cart-order')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('mode-single')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('mode-single')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('cart-order')));
    await t.pumpAndSettle();

    final note = find.byKey(const ValueKey('change-note'));
    final sheet = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_Sheet',
    );
    await t.ensureVisible(note);
    await t.pumpAndSettle();
    final sheetBefore = t.state(sheet);
    await t.tap(note);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('note-input')), '문 앞에 두세요');
    await t.tap(find.byKey(const ValueKey('note-done')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));

    // 받는 중: 로딩 화면이 아니라 주문서 그대로 + 진행 막대, 누르기는 막힘.
    expect(find.byKey(const ValueKey('draft-renewing')), findsOneWidget);
    expect(note, findsOneWidget);
    expect(
      t
          .widget<AbsorbPointer>(
            find.ancestor(of: note, matching: find.byType(AbsorbPointer)).first,
          )
          .absorbing,
      isTrue,
    );

    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('draft-renewing')), findsNothing);
    expect(find.text('문 앞에 두세요'), findsOneWidget);
    // 같은 주문서가 이어진다(다시 만들어지지 않음).
    expect(t.state(sheet), same(sheetBefore));
  });
}
