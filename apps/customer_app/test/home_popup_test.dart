import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';
import 'package:pmart_ui/pmart_ui.dart' show initPmartFormatting;

import 'package:customer_app/features/catalog/data/catalog_repository.dart';
import 'package:customer_app/features/catalog/data/mock_catalog_repository.dart';
import 'package:customer_app/features/catalog/presentation/catalog_providers.dart'
    show homeClockProvider;
import 'package:customer_app/features/catalog/presentation/home_popup.dart';
import 'package:customer_app/shared/providers.dart' show sourceSystem;

import 'support/app_harness.dart';

/// 홈 팝업(storefront 0.9.0 POPUP — 백엔드 요청서 2026-11-21 ②). 사용자 결정: 가운데 카드,
/// "오늘 그만 보기" = 오늘(서울) 동안, "닫기" = 이번 실행 동안.
void main() {
  setUpAll(initPmartFormatting);
  Finder key(String k) => find.byKey(ValueKey(k));

  MockCatalogRepository catalogWithPopups() =>
      MockCatalogRepository(latency: Duration.zero)
        ..placementBannersJson['POPUP'] = [
          {
            'bannerId': 'PU-2',
            'placement': 'POPUP',
            'altText': '둘째 팝업',
            'linkType': 'NONE',
            'sortOrder': 2,
          },
          {
            'bannerId': 'PU-1',
            'placement': 'POPUP',
            'altText': '첫째 팝업 — 우유 보러 가기',
            'linkType': 'PRODUCT',
            'linkRef': 'P-0001',
            'sortOrder': 1,
          },
        ];

  Future<void> open(
    WidgetTester t,
    MockCatalogRepository catalog, {
    MemoryKeyValueStore? secure,
    DateTime? now,
  }) async {
    t.view
      ..physicalSize = const Size(800, 1600)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp(
        [if (now != null) homeClockProvider.overrideWithValue(() => now)],
        catalog: catalog,
        secure: secure,
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('홈에 들어가면 서버 순서대로 팝업(1 / 2), 닫기는 이번 실행 동안 다시 안 뜬다', (t) async {
    await open(t, catalogWithPopups());
    expect(key('home-popup'), findsOneWidget);
    expect(t.widget<Text>(key('home-popup-count')).data, '1 / 2');
    expect(find.text('첫째 팝업 — 우유 보러 가기'), findsOneWidget);
    await t.tap(key('home-popup-close'));
    await t.pumpAndSettle();
    expect(key('home-popup'), findsNothing);
    // 다른 탭에 갔다가 홈으로 와도 다시 뜨지 않는다
    await t.tap(find.text('장바구니').last);
    await t.pumpAndSettle();
    await t.tap(find.text('홈').last);
    await t.pumpAndSettle();
    expect(key('home-popup'), findsNothing);
  });

  testWidgets('오늘 그만 보기: 다시 켜도 오늘은 안 뜨고, 다음 날에는 뜬다', (t) async {
    final secure = MemoryKeyValueStore();
    final today = DateTime.utc(2026, 11, 21, 3); // 서울 12:00
    await open(t, catalogWithPopups(), secure: secure, now: today);
    await t.tap(key('home-popup-hide-today'));
    await t.pumpAndSettle();
    expect(key('home-popup'), findsNothing);

    // 앱을 다시 켠다(같은 기기 저장소) — 오늘(서울 23:59)
    await t.pumpWidget(const SizedBox());
    await open(
      t,
      catalogWithPopups(),
      secure: secure,
      now: DateTime.utc(2026, 11, 21, 14, 59),
    );
    expect(key('home-popup'), findsNothing);

    // 다음 날(서울 00:00)
    await t.pumpWidget(const SizedBox());
    await open(
      t,
      catalogWithPopups(),
      secure: secure,
      now: DateTime.utc(2026, 11, 21, 15),
    );
    expect(key('home-popup'), findsOneWidget);
  });

  testWidgets('이미지를 누르면 닫고 배너가 가리키는 상품으로', (t) async {
    await open(t, catalogWithPopups());
    await t.tap(key('home-popup-image-PU-1'));
    await t.pumpAndSettle();
    expect(key('home-popup'), findsNothing);
    expect(key('product-price'), findsOneWidget);
    expect(find.text('서울우유 1L'), findsWidgets);
    // 상세에서 돌아와도 다시 뜨지 않는다
    GoRouter.of(t.element(find.byType(Scaffold).last)).pop();
    await t.pumpAndSettle();
    expect(key('home-popup'), findsNothing);
  });

  testWidgets('걸린 팝업이 없으면 띄우지 않는다', (t) async {
    await open(t, MockCatalogRepository(latency: Duration.zero));
    expect(key('home-popup'), findsNothing);
  });

  test('API: placement=POPUP 으로 묻고 sortOrder 순', () async {
    final adapter = FakeAdapter(
      (_, _) async => const FakeReply(
        200,
        body: {
          'layoutVersion': 4,
          'items': [
            {'bannerId': 'B', 'placement': 'POPUP', 'sortOrder': 2},
            {'bannerId': 'A', 'placement': 'POPUP', 'sortOrder': 1},
          ],
        },
      ),
    );
    final repo = ApiCatalogRepository(
      createPmartDio(
        baseUrl: 'http://test.invalid/api/v1',
        sourceSystem: sourceSystem,
        tokens: TokenStore(MemoryKeyValueStore()),
        refresher: (_) async => null,
        adapter: adapter,
        delay: (_) async {},
      ),
    );
    final list = await repo.banners(placement: 'POPUP');
    expect(adapter.requests.single.uri.path, '/api/v1/storefront/banners');
    expect(adapter.requests.single.uri.queryParameters['placement'], 'POPUP');
    expect([for (final b in list) b.bannerId], ['A', 'B']);
  });

  test('서울 날짜: UTC 15:00 은 다음 날', () {
    expect(seoulDay(DateTime.utc(2026, 11, 21, 14, 59)), '2026-11-21');
    expect(seoulDay(DateTime.utc(2026, 11, 21, 15)), '2026-11-22');
  });

  test('오늘 그만 보기 기록은 날짜가 바뀌면 무시한다', () async {
    final store = PopupHiddenStore(MemoryKeyValueStore());
    await store.hide('2026-11-21', ['PU-1']);
    expect(await store.hiddenOn('2026-11-21'), {'PU-1'});
    expect(await store.hiddenOn('2026-11-22'), isEmpty);
  });
}
