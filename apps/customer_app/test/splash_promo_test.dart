import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';

import 'package:customer_app/features/start/data/splash_promo.dart';
import 'package:customer_app/features/start/presentation/start_controller.dart';
import 'package:customer_app/shared/providers.dart' show sourceSystem;

import 'support/app_harness.dart';

/// 처음 로딩 화면 프로모션(storefront 0.9.0 SPLASH — 백엔드 요청서 2026-11-21 ①).
/// 사용자 결정: 받아 둔 이미지를 다음 실행에 보이고(뒤에서 새로 받기), 있으면 최소 1.5초(누르면 바로 넘김).
void main() {
  Finder key(String k) => find.byKey(ValueKey(k));
  final png = Uint8List.fromList(_onePixelPng);

  group('뒤에서 맞추기(refreshSplashPromo)', () {
    test('서버에 새 배너 → 받아서 저장, 같은 배너면 다시 받지 않는다', () async {
      final source = MockSplashBannerSource(
        banner: const SplashBannerRef(bannerId: 'BN-1', imageUrl: '/img/1'),
        bytes: png,
      );
      final store = MemorySplashPromoStore();
      await refreshSplashPromo(source, store);
      expect(store.promo?.bannerId, 'BN-1');
      expect(source.downloads, ['/img/1']);
      await refreshSplashPromo(source, store);
      expect(source.downloads, hasLength(1));
    });

    test('같은 배너라도 이미지가 바뀌면 새로 받는다(백엔드 요청 2026-11-21 R1)', () async {
      final source = MockSplashBannerSource(
        banner: const SplashBannerRef(
          bannerId: 'B-SPLASH',
          imageUrl: '/storefront/banner-images/IMG-1',
        ),
        bytes: png,
      );
      final store = MemorySplashPromoStore();
      await refreshSplashPromo(source, store);
      source.banner = const SplashBannerRef(
        bannerId: 'B-SPLASH',
        imageUrl: '/storefront/banner-images/IMG-2',
      );
      await refreshSplashPromo(source, store);
      expect(source.downloads, [
        '/storefront/banner-images/IMG-1',
        '/storefront/banner-images/IMG-2',
      ]);
      expect(store.promo?.imageUrl, '/storefront/banner-images/IMG-2');
      // 예전 앱이 저장한 것(이미지 주소 없음)도 한 번 다시 받는다.
      store.promo = SplashPromo(bannerId: 'B-SPLASH', bytes: png);
      await refreshSplashPromo(source, store);
      expect(source.downloads, hasLength(3));
    });

    // storefront 0.13.0 Banner.endsAt(백엔드 회신 2026-11-23 §2): 받을 때 끝 시각도 저장, 기간만 바뀌면 다시 받지 않고 고친다.
    test('끝 시각을 함께 저장하고, 기간만 바뀌면 그림은 다시 받지 않는다', () async {
      final ends = DateTime.utc(2026, 11, 30, 15);
      final source = MockSplashBannerSource(
        banner: SplashBannerRef(
          bannerId: 'BN-1',
          imageUrl: '/img/1',
          endsAt: ends,
        ),
        bytes: png,
      );
      final store = MemorySplashPromoStore();
      await refreshSplashPromo(source, store);
      expect(store.promo?.endsAt, ends);
      final later = DateTime.utc(2026, 12, 5, 15);
      source.banner = SplashBannerRef(
        bannerId: 'BN-1',
        imageUrl: '/img/1',
        endsAt: later,
      );
      await refreshSplashPromo(source, store);
      expect(store.promo?.endsAt, later);
      expect(source.downloads, hasLength(1));
      expect(store.promo!.liveAt(DateTime.utc(2026, 12, 5, 14)), isTrue);
      expect(store.promo!.liveAt(later), isFalse);
    });

    test('서버에 걸린 것이 없으면 지운다(다음 실행은 기본 로딩 화면)', () async {
      final store = MemorySplashPromoStore(
        SplashPromo(bannerId: 'BN-1', bytes: png),
      );
      await refreshSplashPromo(MockSplashBannerSource(), store);
      expect(store.promo, isNull);
    });

    test('조회 실패는 "없음"이 아니다 — 받아 둔 것을 그대로 둔다', () async {
      final store = MemorySplashPromoStore(
        SplashPromo(bannerId: 'BN-1', bytes: png),
      );
      final source = MockSplashBannerSource()
        ..failNext = const NetworkFailure(DioExceptionType.connectionError);
      await refreshSplashPromo(source, store);
      expect(store.promo?.bannerId, 'BN-1');
    });
  });

  group('API(storefront 0.9.0)', () {
    test('placement=SPLASH 로 묻고 정렬 순서 첫째, 이미지는 게이트웨이 주소로 받는다', () async {
      final adapter = FakeAdapter((o, i) async {
        if (o.path.contains('/storefront/banners')) {
          return const FakeReply(
            200,
            body: {
              'layoutVersion': 3,
              'items': [
                {
                  'bannerId': 'BN-2',
                  'placement': 'SPLASH',
                  'imageUrl': '/api/v1/storefront/banner-images/I-2',
                  'linkType': 'NONE',
                  'sortOrder': 2,
                },
                {
                  'bannerId': 'BN-1',
                  'placement': 'SPLASH',
                  'imageUrl': '/api/v1/storefront/banner-images/I-1',
                  'linkType': 'NONE',
                  'sortOrder': 1,
                },
              ],
            },
          );
        }
        return const FakeReply(200, body: 'img', contentType: 'image/png');
      });
      final source = ApiSplashBannerSource(
        createPmartDio(
          baseUrl: 'http://test.invalid/api/v1',
          sourceSystem: sourceSystem,
          tokens: TokenStore(MemoryKeyValueStore()),
          refresher: (_) async => null,
          adapter: adapter,
          delay: (_) async {},
        ),
        resolveUrl: (u) => 'http://img.invalid$u',
      );
      final now = await source.current();
      expect(adapter.requests.first.uri.queryParameters['placement'], 'SPLASH');
      expect(now?.bannerId, 'BN-1');
      final bytes = await source.download(now!.imageUrl);
      expect(
        adapter.requests.last.uri.toString(),
        'http://img.invalid/api/v1/storefront/banner-images/I-1',
      );
      expect(bytes, isNotEmpty);
    });
  });

  group('로딩 화면', () {
    Future<void> start(WidgetTester t, SplashPromoStore store) async {
      final secure = MemoryKeyValueStore();
      // 환영·둘러보기는 지난 실행에 마쳤다.
      await secure.write('pmart.start.welcome', 'at=2026-11-20T00:00:00Z');
      await secure.write('pmart.start.entry', '1');
      await t.pumpWidget(
        testApp(
          [splashPromoStoreProvider.overrideWithValue(store)],
          startGate: true,
          secure: secure,
        ),
      );
      await t.pump();
      await t.pump();
    }

    testWidgets('받아 둔 이미지가 있으면 화면 가득, 1.5초 뒤에 넘어간다', (t) async {
      await start(
        t,
        MemorySplashPromoStore(SplashPromo(bannerId: 'BN-1', bytes: png)),
      );
      expect(key('start-splash-promo'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 1200));
      expect(key('start-splash-promo'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      expect(key('start-splash-promo'), findsNothing);
    });

    testWidgets('누르면 1.5초를 기다리지 않고 넘어간다', (t) async {
      await start(
        t,
        MemorySplashPromoStore(SplashPromo(bannerId: 'BN-1', bytes: png)),
      );
      expect(key('start-splash-promo'), findsOneWidget);
      await t.tap(key('start-splash-promo'));
      await t.pumpAndSettle();
      expect(key('start-splash-promo'), findsNothing);
    });

    testWidgets('그림은 다 보이고(contain) 남는 위·아래는 받아 둔 가장자리 색', (t) async {
      await start(
        t,
        MemorySplashPromoStore(
          SplashPromo(
            bannerId: 'BN-1',
            bytes: png,
            top: const Color(0xFFFF8800),
            bottom: const Color(0xFF113355),
          ),
        ),
      );
      final image = t.widget<Image>(key('start-splash-promo-BN-1'));
      expect(image.fit, BoxFit.contain);
      final box = t.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.byWidget(image),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final g = (box.decoration as BoxDecoration).gradient! as LinearGradient;
      expect(g.colors, [const Color(0xFFFF8800), const Color(0xFF113355)]);
    });

    testWidgets('받을 때 그림 위·아래 가장자리 색을 계산해 둔다', (t) async {
      // 위 절반 주황, 아래 절반 남색인 2x4 그림
      final bytes = (await t.runAsync(() async {
        final rec = ui.PictureRecorder();
        Canvas(rec)
          ..drawRect(
            const Rect.fromLTWH(0, 0, 2, 2),
            Paint()..color = const Color(0xFFFF8800),
          )
          ..drawRect(
            const Rect.fromLTWH(0, 2, 2, 2),
            Paint()..color = const Color(0xFF113355),
          );
        final img = await rec.endRecording().toImage(2, 4);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      }))!;
      final source = MockSplashBannerSource(
        banner: const SplashBannerRef(bannerId: 'BN-1', imageUrl: '/img/1'),
        bytes: bytes,
      );
      final store = MemorySplashPromoStore();
      await t.runAsync(() => refreshSplashPromo(source, store));
      expect(store.promo?.top, const Color(0xFFFF8800));
      expect(store.promo?.bottom, const Color(0xFF113355));
    });

    testWidgets('받아 둔 배너의 끝 시각이 지났으면 그리지 않는다', (t) async {
      await start(
        t,
        MemorySplashPromoStore(
          SplashPromo(bannerId: 'BN-1', bytes: png, endsAt: DateTime.utc(2000)),
        ),
      );
      expect(key('start-splash-promo'), findsNothing);
      await t.pumpAndSettle();
    });

    testWidgets('받아 둔 것이 없으면 프로모션 없이 지금처럼', (t) async {
      await start(t, MemorySplashPromoStore());
      expect(key('start-splash-promo'), findsNothing);
      await t.pumpAndSettle();
      expect(key('start-splash'), findsNothing);
    });
  });
}

/// 1x1 투명 PNG.
const _onePixelPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
];
