// 배송현황 시트·지도 핀만 빠르게 찍는다(사용자 레퍼런스 비교용, 1080px = 411dp).
//   flutter test tool/shot_tracking.dart --update-goldens --dart-define=SHOT_DIR=<절대 경로>
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/app.dart';
import 'package:customer_app/features/checkout/data/mock_checkout_repository.dart';
import 'package:customer_app/features/checkout/presentation/checkout_controller.dart';
import 'package:customer_app/features/orders/data/mock_orders_repository.dart';
import 'package:customer_app/features/orders/presentation/orders_screens.dart';
import 'package:customer_app/features/orders/presentation/tracking_map.dart';

import '../test/support/app_harness.dart';

const _dir = String.fromEnvironment('SHOT_DIR');

Future<void> _font(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    final f = File(p);
    if (!f.existsSync()) continue;
    loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  }
  await loader.load();
}

/// 그림 파일은 진짜 비동기로 풀린다 — 화면의 Image 를 모두 미리 읽고 다시 그린다.
Future<void> _images(WidgetTester t) async {
  await t.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await t.pump();
}

void main() {
  setUpAll(initPmartFormatting);

  testWidgets('tracking', (t) async {
    if (_dir.isEmpty) fail('SHOT_DIR 필요');
    await t.runAsync(() async {
      const f = 'assets/fonts';
      await _font('Pretendard', [
        '$f/Pretendard-Regular.otf',
        '$f/Pretendard-Medium.otf',
        '$f/Pretendard-SemiBold.otf',
        '$f/Pretendard-Bold.otf',
        '$f/Pretendard-ExtraBold.otf',
      ]);
      await _font('Roboto', ['C:/Windows/Fonts/malgun.ttf']);
    });
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    t.view
      ..physicalSize = const Size(1080, 2337)
      ..devicePixelRatio = 1080 / 411;
    addTearDown(t.view.reset);
    final orders = MockOrdersRepository(latency: Duration.zero);
    await t.pumpWidget(testApp(const [], orders: orders));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-orders')));
    await t.pumpAndSettle();
    await t.tapAt(
      t.getTopLeft(find.byKey(const ValueKey('order-order-seed-1'))) +
          const Offset(24, 24),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('track-dlv-s2')));
    await t.tap(find.byKey(const ValueKey('track-dlv-s2')));
    await t.pumpAndSettle();
    expect(find.byType(TrackingScreen), findsOneWidget);
    await _images(t);
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(Uri.file('$_dir/track-sheet.png')),
    );
    await t.tap(find.byKey(const ValueKey('track-delivery-info')));
    await t.pumpAndSettle();
    await _images(t);
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(Uri.file('$_dir/track-sheet-open.png')),
    );

    // 지도 핀(목 모드는 카카오 지도를 그리지 않는다 — 옅은 지도색 위에 핀만).
    await t.pumpWidget(
      MaterialApp(
        theme: PmartCustomerTheme.light(),
        home: Scaffold(
          backgroundColor: const Color(0xFFF3F0EA),
          body: Center(
            child: RepaintBoundary(
              key: const ValueKey('pins'),
              child: Container(
                color: const Color(0xFFF3F0EA),
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const RiderMarker(),
                    const SizedBox(width: 32),
                    const HomeMarker(),
                    const SizedBox(width: 32),
                    const RiderMarker(stale: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await _images(t);
    await expectLater(
      find.byKey(const ValueKey('pins')),
      matchesGoldenFile(Uri.file('$_dir/track-pins.png')),
    );
  });

  // 주문 완료 화면(사용자 레퍼런스 2026-11-25).
  testWidgets('order done', (t) async {
    if (_dir.isEmpty) fail('SHOT_DIR 필요');
    await t.runAsync(() async {
      const f = 'assets/fonts';
      await _font('Pretendard', [
        '$f/Pretendard-Regular.otf',
        '$f/Pretendard-Medium.otf',
        '$f/Pretendard-SemiBold.otf',
        '$f/Pretendard-Bold.otf',
        '$f/Pretendard-ExtraBold.otf',
      ]);
    });
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    t.view
      ..physicalSize = const Size(1080, 2337)
      ..devicePixelRatio = 1080 / 411;
    addTearDown(t.view.reset);
    final now = DateTime.utc(2026, 10, 24, 3);
    final checkout = MockCheckoutRepository(
      latency: Duration.zero,
      now: () => now,
    );
    await t.pumpWidget(
      testApp(
        checkout: checkout,
        orders: MockOrdersRepository(
          checkout: checkout,
          latency: Duration.zero,
        ),
        [
          clockProvider.overrideWithValue(() => now),
          draftPollPolicyProvider.overrideWithValue((
            interval: Duration.zero,
            attempts: 3,
          )),
        ],
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('장바구니').last);
    await t.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await t.tap(find.byKey(const ValueKey('cart-inc-ci-1')));
      await t.pumpAndSettle();
    }
    await t.tap(find.byKey(const ValueKey('cart-order')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('mode-single')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('mode-single')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('cart-order')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('pay')));
    // 완료 화면이 뜰 때까지(움직임은 아직 끝내지 않는다)
    for (var i = 0; i < 400; i++) {
      await t.pump(const Duration(milliseconds: 16));
      if (find.byKey(const ValueKey('pay-done-close')).evaluate().isNotEmpty) {
        break;
      }
    }
    await t.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    var at = 0;
    for (final ms in const [250, 500, 900, 1300, 2500]) {
      await t.pump(Duration(milliseconds: ms - at));
      at = ms;
      await expectLater(
        find.byType(CustomerApp),
        matchesGoldenFile(Uri.file('$_dir/order-done-$ms.png')),
      );
    }
    await t.pumpAndSettle();
  });
}
