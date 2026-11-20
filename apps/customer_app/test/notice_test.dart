import 'package:customer_app/shared/notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 알림(스낵바) 공통 규칙 — 사용자 2026-11-20 "팝업창이 버튼을 가리는데 늦게 사라져".
void main() {
  // 탭 화면처럼: 아래 버튼이 Scaffold 의 bottomNavigationBar 가 아니라 본문 안 아래에 붙어 있다.
  Widget app({SnackBarAction? action, bool clearance = true}) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showNotice(context, '알림', action: action),
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
          if (clearance)
            const NoticeClearance(
              child: SizedBox(key: ValueKey('bottom-button'), height: 60),
            )
          else
            const SizedBox(key: ValueKey('bottom-button'), height: 60),
        ],
      ),
    ),
  );

  testWidgets('글만 있는 알림은 2초 뒤 스스로 닫힌다', (t) async {
    await t.pumpWidget(app());
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    expect(find.text('알림'), findsOneWidget);
    await t.pump(noticeDuration);
    await t.pumpAndSettle();
    expect(find.text('알림'), findsNothing);
  });

  testWidgets('버튼이 달린 알림도 스스로 닫힌다(4초)', (t) async {
    await t.pumpWidget(
      app(
        action: SnackBarAction(label: '보기', onPressed: () {}),
      ),
    );
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    expect(find.text('보기'), findsOneWidget);
    await t.pump(noticeDuration);
    await t.pumpAndSettle();
    expect(find.text('알림'), findsOneWidget, reason: '누를 틈은 준다');
    await t.pump(noticeWithActionDuration - noticeDuration);
    await t.pumpAndSettle();
    expect(find.text('알림'), findsNothing);
  });

  testWidgets('연달아 띄우면 밀리지 않고 마지막 것만 남는다', (t) async {
    await t.pumpWidget(app());
    for (var i = 0; i < 3; i++) {
      await t.tap(find.text('열기'));
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
    expect(find.text('알림'), findsOneWidget);
    await t.pump(noticeDuration);
    await t.pumpAndSettle();
    expect(find.text('알림'), findsNothing, reason: '앞의 것이 줄 서서 다시 뜨지 않는다');
  });

  testWidgets('본문 아래 버튼(NoticeClearance) 위로 띄운다', (t) async {
    await t.pumpWidget(app());
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    // SnackBar 위젯 자체는 띄운 여백까지 차지한다 — 눈에 보이는 글 위치로 잰다.
    final notice = t.getRect(find.text('알림'));
    final button = t.getRect(find.byKey(const ValueKey('bottom-button')));
    expect(notice.bottom, lessThan(button.top));
  });

  testWidgets('감싸지 않은 아래 버튼은 모른다(덮는다) — 감싸야 하는 이유', (t) async {
    await t.pumpWidget(app(clearance: false));
    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    final notice = t.getRect(find.text('알림'));
    final button = t.getRect(find.byKey(const ValueKey('bottom-button')));
    expect(notice.bottom, greaterThan(button.top));
  });
}
