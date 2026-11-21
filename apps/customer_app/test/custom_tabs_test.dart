import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';
import 'package:pmart_ui/pmart_ui.dart' show initPmartFormatting;

import 'package:customer_app/features/catalog/data/catalog_repository.dart';
import 'package:customer_app/features/catalog/data/mock_catalog_repository.dart';
import 'package:customer_app/features/catalog/presentation/catalog_providers.dart'
    show homeClockProvider;
import 'package:customer_app/shared/providers.dart' show sourceSystem;

import 'support/app_harness.dart';

/// MD 탭(storefront 0.9.0 customTabs — 백엔드 요청서 2026-11-21 ⑤): 고정 탭 뒤에 서버 순서로,
/// 내용은 GET /storefront/custom-tabs/{tabKey}, 기간이 끝나면(시각·404 TAB_NOT_FOUND) 탭을 지우고 홈으로.
void main() {
  setUpAll(initPmartFormatting);
  Finder key(String k) => find.byKey(ValueKey(k));

  MockCatalogRepository catalogWithTabs(DateTime now) =>
      MockCatalogRepository(latency: Duration.zero)
        ..customTabs['X-AUTUMN'] = (
          title: '가을 나들이',
          endsAt: null,
          showTimer: false,
          sections: [('S-X-1', 'THEME', '가을 나들이 필수템')],
        )
        ..customTabs['X-DEAL'] = (
          title: '5일장',
          endsAt: now.add(const Duration(seconds: 5)),
          showTimer: true,
          sections: [('S-X-2', 'THEME', '오일장 특가')],
        );

  Future<void> open(
    WidgetTester t,
    MockCatalogRepository catalog,
    DateTime Function() clock,
  ) async {
    t.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp([homeClockProvider.overrideWithValue(clock)], catalog: catalog),
    );
    await t.pumpAndSettle();
  }

  testWidgets('고정 탭 뒤에 서버 순서로 붙고, 누르면 그 탭 내용을 서버에 묻는다', (t) async {
    final now = DateTime.utc(2026, 11, 21, 3);
    final catalog = catalogWithTabs(now);
    await open(t, catalog, () => now);
    final xs = [
      t.getTopLeft(key('home-tab-isNew')).dx,
      t.getTopLeft(key('home-tab-X-AUTUMN')).dx,
      t.getTopLeft(key('home-tab-X-DEAL')).dx,
    ];
    expect(xs[1], greaterThan(xs[0]));
    expect(xs[2], greaterThan(xs[1]));
    await t.tap(key('home-tab-X-AUTUMN'));
    await t.pumpAndSettle();
    expect(catalog.customTabCalls, 1);
    expect(find.text('가을 나들이 필수템'), findsOneWidget);
    // 홈 탭으로 돌아가면 배너·검색이 다시
    await t.tap(key('home-tab-home'));
    await t.pumpAndSettle();
    expect(key('home-banners-top'), findsOneWidget);
  });

  testWidgets('타이머 탭은 이름 위에 남은 시간, 끝나면 탭을 지우고 보던 중이면 홈으로', (t) async {
    var now = DateTime.utc(2026, 11, 21, 3);
    final catalog = catalogWithTabs(now);
    await open(t, catalog, () => now);
    expect(
      find.descendant(
        of: key('home-tab-timer-X-DEAL'),
        matching: find.text('00:00:05'),
      ),
      findsOneWidget,
    );
    await t.tap(key('home-tab-X-DEAL'));
    await t.pumpAndSettle();
    expect(find.text('오일장 특가'), findsOneWidget);
    now = now.add(const Duration(seconds: 5));
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    expect(key('home-tab-X-DEAL'), findsNothing);
    expect(find.text('오일장 특가'), findsNothing);
    expect(key('home-banners-top'), findsOneWidget);
    expect(key('home-tab-X-AUTUMN'), findsOneWidget);
  });

  testWidgets('내용 조회가 404 TAB_NOT_FOUND 면 탭을 지우고 홈으로', (t) async {
    final now = DateTime.utc(2026, 11, 21, 3);
    final catalog = catalogWithTabs(now)..goneTabs.add('X-AUTUMN');
    await open(t, catalog, () => now);
    await t.tap(key('home-tab-X-AUTUMN'));
    await t.pumpAndSettle();
    expect(key('home-tab-X-AUTUMN'), findsNothing);
    expect(key('home-banners-top'), findsOneWidget);
    expect(key('home-tab-failed'), findsNothing);
  });

  testWidgets('MD 탭이 없으면 고정 탭만', (t) async {
    final now = DateTime.utc(2026, 11, 21, 3);
    await open(t, MockCatalogRepository(latency: Duration.zero), () => now);
    expect(key('home-tab-home'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-tab-X-AUTUMN')), findsNothing);
  });

  group('API(storefront 0.9.0)', () {
    late FakeAdapter adapter;
    ApiCatalogRepository api(FakeReply reply) {
      adapter = FakeAdapter((_, _) async => reply);
      return ApiCatalogRepository(
        createPmartDio(
          baseUrl: 'http://test.invalid/api/v1',
          sourceSystem: sourceSystem,
          tokens: TokenStore(MemoryKeyValueStore()),
          refresher: (_) async => null,
          adapter: adapter,
          delay: (_) async {},
        ),
      );
    }

    test('홈 응답 customTabs → 탭(타이머는 endsAt 이 있을 때만)', () async {
      final home = await api(
        const FakeReply(
          200,
          body: {
            'layoutVersion': 3,
            'tabs': ['HOME'],
            'sections': <Object?>[],
            'customTabs': [
              {'tabKey': 'X-A', 'title': '가', 'showTimer': true},
              {
                'tabKey': 'X-B',
                'title': '나',
                'showTimer': true,
                'endsAt': '2026-11-21T09:00:00Z',
              },
            ],
          },
        ),
      ).home();
      expect([for (final c in home.customTabs) c.tabKey], ['X-A', 'X-B']);
      expect(home.customTabs[0].showTimer, isFalse);
      expect(home.customTabs[1].showTimer, isTrue);
    });

    test('내용은 GET /storefront/custom-tabs/{tabKey}?mfcId=', () async {
      final view = await api(
        const FakeReply(
          200,
          body: {
            'layoutVersion': 3,
            'tab': {'tabKey': 'X-A', 'title': '가'},
            'sections': [
              {
                'sectionId': 'S-1',
                'kind': 'THEME',
                'title': '테마',
                'state': 'OK',
                'items': <Object?>[],
              },
            ],
          },
        ),
      ).customTab('X-A', mfcId: 'MFC-1');
      final r = adapter.requests.single;
      expect(r.uri.path, '/api/v1/storefront/custom-tabs/X-A');
      expect(r.uri.queryParameters['mfcId'], 'MFC-1');
      expect(view.sections.single.title, '테마');
    });

    test('기간이 지난 탭은 404 TAB_NOT_FOUND 를 code 로 받는다', () async {
      await expectLater(
        api(FakeReply.problem(404, problemBody('TAB_NOT_FOUND', status: 404)))
            .customTab('X-A'),
        throwsA(
          isA<ProblemFailure>().having(
            (f) => f.problem.code,
            'code',
            'TAB_NOT_FOUND',
          ),
        ),
      );
    });
  });
}
