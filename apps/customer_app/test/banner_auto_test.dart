import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_api_storefront/pmart_api_storefront.dart' as sf;
import 'package:pmart_ui/pmart_ui.dart' show initPmartFormatting;

import 'package:customer_app/features/catalog/data/catalog_repository.dart';
import 'package:customer_app/features/catalog/data/mock_catalog_repository.dart';
import 'package:customer_app/features/catalog/domain/catalog.dart';

import 'support/app_harness.dart';

/// storefront 0.10.0(백엔드 요청서 홈 프로모션 7·8번): 배너 자동 넘김(간격 bannerIntervalSeconds, 없으면 4초,
/// 1개면 넘기지 않음, 손으로 넘기면 다시 셈)·테마 사이 배너 묶음(kind BANNER, 받은 순서 그대로).
void main() {
  setUpAll(initPmartFormatting);
  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> open(WidgetTester t, MockCatalogRepository catalog) async {
    t.view
      ..physicalSize = const Size(800, 3000)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const [], catalog: catalog));
    await t.pumpAndSettle();
  }

  String page(WidgetTester t, {String scope = 'home-banners-top'}) => t
      .widget<Text>(
        find.descendant(of: key(scope), matching: key('banner-page')),
      )
      .data!;

  testWidgets('맨 위 배너는 기본 4초마다 다음 장, 마지막 다음은 첫 장', (t) async {
    await open(t, MockCatalogRepository(latency: Duration.zero));
    expect(page(t), '1 / 2');
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
    expect(page(t), '1 / 2', reason: '4초 전에는 그대로');
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(page(t), '2 / 2');
    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();
    expect(page(t), '1 / 2');
  });

  testWidgets('서버 간격(bannerIntervalSeconds)을 따른다', (t) async {
    await open(
      t,
      MockCatalogRepository(latency: Duration.zero)..bannerIntervalSeconds = 2,
    );
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(page(t), '2 / 2');
  });

  testWidgets('손으로 넘기면 그때부터 다시 센다', (t) async {
    await open(t, MockCatalogRepository(latency: Duration.zero));
    await t.pump(const Duration(seconds: 3));
    await t.fling(key('home-banners-top'), const Offset(-500, 0), 1500);
    await t.pumpAndSettle();
    expect(page(t), '2 / 2');
    // 손으로 넘긴 뒤 3초 — 아직 그대로(예전 시계였다면 이미 넘어갔다)
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
    expect(page(t), '2 / 2');
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(page(t), '1 / 2');
  });

  testWidgets('테마 사이 배너 묶음은 받은 순서 그대로 그 자리에', (t) async {
    final catalog = MockCatalogRepository(latency: Duration.zero)
      ..inlineBannerGroups[1] = [
        {
          'bannerId': 'IN-1',
          'placement': 'HOME_INLINE',
          'altText': '중간 배너 하나',
          'linkType': 'NONE',
          'sortOrder': 1,
        },
        {
          'bannerId': 'IN-2',
          'placement': 'HOME_INLINE',
          'altText': '중간 배너 둘',
          'linkType': 'NONE',
          'sortOrder': 2,
        },
      ];
    await open(t, catalog);
    final group = key('section-G-1');
    expect(group, findsOneWidget);
    final above = t.getTopLeft(key('section-S-RANK')).dy;
    final at = t.getTopLeft(group).dy;
    final below = t.getTopLeft(key('section-S-NEW')).dy;
    expect(at, greaterThan(above));
    expect(at, lessThan(below));
    expect(page(t, scope: 'section-G-1'), '1 / 2');
  });

  test('배너가 하나도 없는 배너 묶음은 그리지 않는다', () {
    final h = homeFromContract(
      sf.HomeLayout.fromJson({
        'layoutVersion': 1,
        'tabs': ['HOME'],
        'bannerIntervalSeconds': 6,
        'sections': [
          {
            'sectionId': 'G-1',
            'kind': 'BANNER',
            'banners': <Object?>[],
            'items': <Object?>[],
          },
          {
            'sectionId': 'G-2',
            'kind': 'BANNER',
            'intervalSeconds': 3,
            'banners': [
              {'bannerId': 'B-1', 'placement': 'HOME_INLINE'},
            ],
            'items': <Object?>[],
          },
        ],
      }),
    );
    expect(h.bannerIntervalSeconds, 6);
    expect([for (final s in h.sections) s.sectionId], ['G-2']);
    expect(h.sections.single.kind, SectionKind.banner);
    expect(h.sections.single.intervalSeconds, 3);
  });
}
