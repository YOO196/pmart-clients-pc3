import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'support/app_harness.dart';

/// 폰 아래 시스템 막대(홈·뒤로 버튼) 위까지만 그린다(사용자 2026-11-20).
void main() {
  setUpAll(initPmartFormatting);

  testWidgets('아래 탭 막대가 시스템 막대 위에서 끝나고, 안쪽은 아래 여백을 두 번 받지 않는다', (t) async {
    t.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(bottom: 48)
      ..viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();

    final nav = t.getRect(find.byType(NavigationBar));
    expect(nav.bottom, 800 - 48);
    // 안쪽 화면에는 아래 시스템 막대가 없는 것으로 보인다.
    final inner = MediaQuery.of(t.element(find.byType(NavigationBar)));
    expect(inner.viewPadding.bottom, 0);
    expect(inner.padding.bottom, 0);
  });

  testWidgets('키보드가 올라오면 막대 높이만큼 빼서 겹치지 않게 한다', (t) async {
    t.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(bottom: 48)
      ..viewPadding = const FakeViewPadding(bottom: 48)
      ..viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    final inner = MediaQuery.of(t.element(find.byType(NavigationBar)));
    expect(inner.viewInsets.bottom, 300 - 48);
  });
}
