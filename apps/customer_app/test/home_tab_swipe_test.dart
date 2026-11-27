// 홈 탭 좌우 미끄럼·드래그로 탭 넘기기(사용자 2026-11-23 "탭 이동할 때 좌우 슬라이딩",
// "안 민감한 선에서 좌우로 드래그했을 때 탭바 넘어가는 기능").
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_ui/pmart_ui.dart' show initPmartFormatting;

import 'support/app_harness.dart';

void main() {
  setUpAll(initPmartFormatting);
  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> openHome(WidgetTester t) async {
    t.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    expect(key('home-tabs'), findsOneWidget);
  }

  // 배너 아래 배송 안내 칸 — 가로 목록이 아닌 곳을 끈다.
  Finder plain() => find.byKey(const ValueKey('home-delivery-card'));

  testWidgets('왼쪽으로 길게 끌면 다음 탭, 오른쪽이면 이전 탭', (t) async {
    await openHome(t);
    await t.drag(plain(), const Offset(-160, 0));
    await t.pumpAndSettle();
    // 홈 다음은 할인 탭(사용자 2026-11-26).
    expect(key('home-tab-body-sale'), findsOneWidget);

    // 탭 줄 바로 아래(할인율 칩 위 빈 자리 — 칩 줄은 가로로 넘어간다)에서 오른쪽으로.
    await t.dragFrom(
      t.getBottomLeft(key('home-tabs')) + const Offset(100, 6),
      const Offset(160, 0),
    );
    await t.pumpAndSettle();
    expect(key('home-tab-body-sale'), findsNothing);
    expect(plain(), findsOneWidget);
  });

  testWidgets('짧게 끌면 넘어가지 않는다(덜 민감)', (t) async {
    await openHome(t);
    await t.drag(plain(), const Offset(-60, 0));
    await t.pumpAndSettle();
    expect(key('home-tab-body-ranking'), findsNothing);
    expect(plain(), findsOneWidget);
  });

  testWidgets('배너 위에서 끌면 배너가 넘어가고 탭은 그대로', (t) async {
    await openHome(t);
    await t.drag(key('home-banners-top'), const Offset(-200, 0));
    await t.pumpAndSettle();
    expect(key('home-tab-body-ranking'), findsNothing);
    expect(plain(), findsOneWidget);
  });

  testWidgets('탭을 누르면 내용이 옆에서 미끄러져 들어온다', (t) async {
    await openHome(t);
    await t.tap(key('home-tab-ranking'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 60));
    // 랭킹 목록은 슬리버 묶음이라 안쪽 상자들(위 배너·붙는 줄·첫 줄들)이 미끄러진다.
    final moving = find.descendant(
      of: key('home-tab-body-ranking'),
      matching: find.byType(SlideTransition),
    );
    expect(moving, findsWidgets);
    final dx = t.widget<SlideTransition>(moving.first).position.value.dx;
    expect(dx, greaterThan(0)); // 오른쪽 탭이라 오른쪽에서 들어온다
    await t.pumpAndSettle();
    expect(t.widget<SlideTransition>(moving.first).position.value.dx, 0);
  });
}
