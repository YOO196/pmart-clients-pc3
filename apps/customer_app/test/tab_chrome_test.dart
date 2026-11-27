import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_ui/pmart_ui.dart' show initPmartFormatting;

import 'support/app_harness.dart';

/// 내리면 주소 막대가 접히고 올리면 펴진다, 아래 탭 막대는 늘 고정, 탭 줄은 위에 붙는다(사용자 2026-11-26).
void main() {
  setUpAll(initPmartFormatting);
  Finder key(String k) => find.byKey(ValueKey(k));

  testWidgets('홈을 내리면 머리줄만 접히고(하단 탭은 고정), 조금 올리면 다시 펴진다', (t) async {
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    final nav = find.byType(NavigationBar).hitTestable();
    final bell = key('home-notifications').hitTestable();
    expect(nav, findsOneWidget);
    expect(bell, findsOneWidget);

    final scroll = key('home-scroll');
    await t.drag(scroll, const Offset(0, -900));
    await t.pumpAndSettle();
    expect(nav, findsOneWidget, reason: '하단 탭은 고정(사용자 2026-11-26)');
    expect(bell, findsNothing, reason: '내리면 주소 막대 접힘');
    // 탭 줄은 위에 남는다
    expect(key('home-tabs').hitTestable(), findsOneWidget);

    await t.drag(scroll, const Offset(0, 120));
    await t.pumpAndSettle();
    expect(nav, findsOneWidget, reason: '올리면 펴짐');
    expect(bell, findsOneWidget);
  });
}
