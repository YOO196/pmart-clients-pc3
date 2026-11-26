import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_ui/pmart_ui.dart' show initPmartFormatting;

import 'package:customer_app/features/catalog/data/mock_catalog_repository.dart';
import 'package:customer_app/features/catalog/presentation/catalog_providers.dart'
    show homeClockProvider;

import 'support/app_harness.dart';

/// 홈 "지금 바로픽 TOP 30" 상자·일일특가 한 번만·할인 탭 "오늘만특가"(사용자 폰 캡처 2026-11-26).
void main() {
  setUpAll(initPmartFormatting);
  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> open(WidgetTester t, MockCatalogRepository catalog) async {
    final now = DateTime.utc(2026, 11, 21, 3);
    t.view
      ..physicalSize = const Size(800, 5000)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp([
        homeClockProvider.overrideWithValue(() => now),
      ], catalog: catalog),
    );
    await t.pumpAndSettle();
  }

  testWidgets('띠형 타이머가 둘이면 맨 위 하나만 일일특가 모양, TOP 30 은 그 바로 아래', (t) async {
    final now = DateTime.utc(2026, 11, 21, 3);
    final catalog = MockCatalogRepository(latency: Duration.zero)
      ..timedSections['S-NEW'] = now.add(const Duration(hours: 5))
      ..timedSections['S-WEEKLY'] = now.add(const Duration(hours: 5))
      ..bandTimerSections.addAll(['S-NEW', 'S-WEEKLY']);
    await open(t, catalog);

    expect(key('section-timer-band-S-NEW'), findsOneWidget);
    expect(key('section-timer-band-S-WEEKLY'), findsNothing);
    expect(key('section-timer-S-WEEKLY'), findsOneWidget); // 보통 영역 + 남은 시간

    expect(key('home-top30'), findsOneWidget);
    expect(find.text('지금 바로픽 TOP 30'), findsOneWidget);
    final deal = t.getTopLeft(key('section-S-NEW')).dy;
    final top = t.getTopLeft(key('home-top30')).dy;
    final weekly = t.getTopLeft(key('section-S-WEEKLY')).dy;
    expect(deal < top && top < weekly, isTrue);
  });

  testWidgets('TOP 30: 전체 칩이 골라져 있고, 칩을 누르면 그 카테고리 인기순', (t) async {
    await open(t, MockCatalogRepository(latency: Duration.zero));
    expect(key('home-top30-chip-all'), findsOneWidget);
    expect(key('home-top30-grid-all'), findsOneWidget);
    final chips = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('home-top30-chip-') &&
          (w.key! as ValueKey<String>).value != 'home-top30-chip-all',
    );
    expect(chips, findsWidgets);
    final k = (t.widget(chips.first).key! as ValueKey<String>).value;
    await t.tap(chips.first);
    await t.pump(const Duration(milliseconds: 10));
    await t.pumpAndSettle();
    final id = k.substring('home-top30-chip-'.length);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key == ValueKey('home-top30-grid-$id') ||
            w.key == const ValueKey('home-top30-empty'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('할인 탭 이름 위에 "오늘만특가"', (t) async {
    await open(t, MockCatalogRepository(latency: Duration.zero));
    expect(key('home-tab-sale-tag'), findsOneWidget);
    expect(find.text('오늘만특가'), findsOneWidget);
    expect(
      t.getTopLeft(key('home-tab-sale-tag')).dy <
          t.getTopLeft(find.text('할인').first).dy,
      isTrue,
    );
  });

  testWidgets('맨 아래 카테고리별 상품: 첫 카테고리 칩 골라짐·총 N개·2칸 목록, 칩 누르면 바뀜, 끝 여백은 작다', (
    t,
  ) async {
    await open(t, MockCatalogRepository(latency: Duration.zero));
    final scroll = find.byType(Scrollable).first;
    await t.scrollUntilVisible(
      key('home-feed-total'),
      400,
      scrollable: find
          .descendant(of: key('home-scroll'), matching: find.byType(Scrollable))
          .first,
    );
    await t.pump(const Duration(milliseconds: 10));
    await t.pumpAndSettle();
    expect(scroll, findsWidgets);
    expect(key('home-feed-chip-C-RICE'), findsOneWidget);
    // 첫 카테고리(목에서 상품 없음)는 "없어요" — 실패·빈 칸으로 숨기지 않는다.
    expect(key('home-feed-empty'), findsOneWidget);
    expect(
      (t.widget<Text>(key('home-feed-total')).data ?? '').startsWith('총 '),
      isTrue,
    );
    await t.tap(key('home-feed-chip-C-FV'));
    await t.pump(const Duration(milliseconds: 10));
    await t.pumpAndSettle();
    expect(key('home-feed-grid-C-FV'), findsOneWidget);
    // 떠 있는 막대가 없으면 끝 여백은 28(예전 170).
    await t.scrollUntilVisible(
      key('home-end-space'),
      600,
      scrollable: find
          .descendant(
            of: key('home-scroll'),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(t.getSize(key('home-end-space')).height, lessThan(120));
  });
}
