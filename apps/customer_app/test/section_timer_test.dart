import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_api_storefront/pmart_api_storefront.dart' as sf;
import 'package:pmart_ui/pmart_ui.dart' show initPmartFormatting;

import 'package:customer_app/features/catalog/data/catalog_repository.dart';
import 'package:customer_app/features/catalog/data/mock_catalog_repository.dart';
import 'package:customer_app/features/catalog/domain/catalog.dart'
    show HomeSection, TimerStyle;
import 'package:customer_app/features/catalog/presentation/catalog_providers.dart'
    show homeClockProvider;
import 'package:customer_app/features/catalog/presentation/home_screen.dart'
    show remainingClock;

import 'support/app_harness.dart';

/// 타이머 테마(storefront 0.9.0 Section.endsAt·showTimer — 백엔드 요청서 2026-11-21 ③):
/// 제목 옆 남은 시간(레퍼런스 "일일 특가" 빨간 시계 알약), 0 이 되면 영역을 숨긴다.
void main() {
  setUpAll(initPmartFormatting);
  Finder key(String k) => find.byKey(ValueKey(k));

  test('남은 시간 HH:MM:SS(24시간 넘으면 그대로, 음수는 0)', () {
    expect(
      remainingClock(const Duration(hours: 2, minutes: 13, seconds: 5)),
      '02:13:05',
    );
    expect(remainingClock(const Duration(hours: 30)), '30:00:00');
    expect(remainingClock(const Duration(seconds: -5)), '00:00:00');
  });

  test('계약: showTimer 인데 endsAt 이 없으면 타이머 없음', () {
    final h = homeFromContract(
      sf.HomeLayout.fromJson({
        'layoutVersion': 1,
        'tabs': ['HOME'],
        'sections': [
          {
            'sectionId': 'S-1',
            'kind': 'THEME',
            'title': 'a',
            'state': 'OK',
            'showTimer': true,
          },
          {
            'sectionId': 'S-2',
            'kind': 'THEME',
            'title': 'b',
            'state': 'OK',
            'showTimer': true,
            'endsAt': '2026-11-21T09:00:00Z',
          },
        ],
      }),
    );
    expect(h.sections[0].showTimer, isFalse);
    expect(h.sections[1].showTimer, isTrue);
    expect(h.sections[1].endsAt, DateTime.utc(2026, 11, 21, 9));
  });

  Future<void> open(
    WidgetTester t,
    MockCatalogRepository catalog,
    DateTime Function() clock,
  ) async {
    t.view
      ..physicalSize = const Size(800, 3000)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp([homeClockProvider.overrideWithValue(clock)], catalog: catalog),
    );
    await t.pumpAndSettle();
  }

  testWidgets('제목 옆에 남은 시간, 1초마다 줄고 0 이 되면 영역을 숨긴다', (t) async {
    var now = DateTime.utc(2026, 11, 21, 3);
    final catalog = MockCatalogRepository(latency: Duration.zero)
      ..timedSections['S-NEW'] = now.add(const Duration(seconds: 3));
    await open(t, catalog, () => now);
    String text() => t
        .widget<Text>(
          find.descendant(
            of: key('section-timer-S-NEW'),
            matching: find.byType(Text),
          ),
        )
        .data!;
    expect(text(), '00:00:03 남음');
    expect(key('section-S-NEW'), findsOneWidget);
    now = now.add(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    expect(text(), '00:00:02 남음');
    now = now.add(const Duration(seconds: 2));
    await t.pump(const Duration(seconds: 2));
    expect(key('section-timer-S-NEW'), findsNothing);
    expect(find.text('새로 들어왔어요'), findsNothing);
    // 다른 영역은 그대로
    expect(find.text('지금 많이 사는 상품'), findsOneWidget);
  });

  testWidgets('이미 끝 시각이 지난 영역은 처음부터 숨긴다', (t) async {
    final now = DateTime.utc(2026, 11, 21, 3);
    final catalog = MockCatalogRepository(latency: Duration.zero)
      ..timedSections['S-NEW'] = now.subtract(const Duration(seconds: 1));
    await open(t, catalog, () => now);
    expect(find.text('새로 들어왔어요'), findsNothing);
  });

  // BR-84(storefront 0.12.0 timerStyle): LABEL(기본) = 제목 위 분홍 글자, BAND = 연분홍 띠 + 시·분·초 칸.
  test('계약: timerStyle BAND 는 띠형, 없거나 LABEL 이면 라벨형', () {
    HomeSection of(Object? style) => homeFromContract(
      sf.HomeLayout.fromJson({
        'layoutVersion': 1,
        'tabs': ['HOME'],
        'sections': [
          {
            'sectionId': 'S-1',
            'kind': 'THEME',
            'title': 'a',
            'state': 'OK',
            'showTimer': true,
            'endsAt': '2026-11-21T09:00:00Z',
            'timerStyle': ?style,
          },
        ],
      }),
    ).sections.single;
    expect(of('BAND').timerStyle, TimerStyle.band);
    expect(of('LABEL').timerStyle, TimerStyle.label);
    expect(of(null).timerStyle, TimerStyle.label);
  });

  testWidgets('띠형: 시·분·초 칸이 1초마다 줄고, 0 이 되면 영역을 숨긴다', (t) async {
    var now = DateTime.utc(2026, 11, 21, 3);
    final catalog = MockCatalogRepository(latency: Duration.zero)
      ..timedSections['S-NEW'] = now.add(
        const Duration(hours: 5, minutes: 12, seconds: 30),
      )
      ..bandTimerSections.add('S-NEW');
    await open(t, catalog, () => now);
    final band = key('section-timer-band-S-NEW');
    expect(band, findsOneWidget);
    expect(key('section-timer-S-NEW'), findsNothing);
    expect(find.text('남은 시간'), findsOneWidget);
    String sec() => t
        .widgetList<Text>(
          find.descendant(of: band, matching: find.byType(Text)),
        )
        .map((w) => w.data)
        .where((d) => d != null && RegExp(r'^\d\d$').hasMatch(d))
        .last!;
    expect(sec(), '30');
    now = now.add(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    expect(sec(), '29');
    now = now.add(const Duration(hours: 6));
    await t.pump(const Duration(hours: 6));
    expect(band, findsNothing);
  });

  // search 0.10.0·storefront 0.13.0 목록 availability(백엔드 회신 2026-11-23 §1): SOLD_OUT 만 품절, UNKNOWN·없음은 표시 없음.
  test('목록 카드 품절: SOLD_OUT 이면 품절·담기 숨김, UNKNOWN·없음은 그대로', () {
    List<bool> soldOf(List<Object?> states) => [
      for (final tile in homeFromContract(
        sf.HomeLayout.fromJson({
          'layoutVersion': 1,
          'tabs': ['HOME'],
          'sections': [
            {
              'sectionId': 'S-1',
              'kind': 'THEME',
              'title': 'a',
              'state': 'OK',
              'items': [
                for (final (i, st) in states.indexed)
                  {
                    'productId': 'P-$i',
                    'name': 'n$i',
                    'saleState': 'ON_SALE',
                    'carried': true,
                    'availability': ?st,
                  },
              ],
            },
          ],
        }),
      ).sections.single.items)
        tile.soldOut && !tile.canOfferAdd,
    ];
    expect(soldOf(['SOLD_OUT', 'AVAILABLE', 'UNKNOWN', null]), [
      true,
      false,
      false,
      false,
    ]);
  });

  testWidgets('타이머가 없는 영역에는 알약이 없다', (t) async {
    await open(
      t,
      MockCatalogRepository(latency: Duration.zero),
      () => DateTime.utc(2026, 11, 21, 3),
    );
    // "N개 남음"(재고 적음, BR-100 R7)은 타이머가 아니다 — 타이머 알약 키로만 본다.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('section-timer-'),
      ),
      findsNothing,
    );
  });
}
