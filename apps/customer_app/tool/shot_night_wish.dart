// 찜(빈 상태)·홈 예약배달만(심야) 첫 화면·배달 안내 시트를 사용자 폰 폭(1080px = 411dp)으로 찍는다.
//   flutter test tool/shot_night_wish.dart --update-goldens --dart-define=SHOT_DIR=<절대 경로>
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/app.dart';
import 'package:customer_app/features/checkout/data/mock_checkout_repository.dart';
import 'package:customer_app/features/checkout/domain/checkout.dart'
    show DeliveryMode;
import 'package:customer_app/features/wishlist/data/wishlist_repository.dart';

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

Future<void> _fonts() async {
  // 앱은 폰 기본 글꼴 — 시험에는 없어 맑은 고딕으로 대신.
  await _font('Roboto', [
    'C:/Windows/Fonts/malgun.ttf',
    'C:/Windows/Fonts/malgunbd.ttf',
  ]);
}

void _view(WidgetTester t) {
  t.view
    ..physicalSize = const Size(1080, 2340)
    ..devicePixelRatio = 1080 / 411
    ..padding = const FakeViewPadding(top: 99, bottom: 48)
    ..viewPadding = const FakeViewPadding(top: 99, bottom: 48);
  addTearDown(t.view.reset);
}

Future<void> _shot(WidgetTester t, String name) async {
  await t.pumpAndSettle();
  await t.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      try {
        await precacheImage((e.widget as Image).image, e);
      } on Object {
        // 네트워크 그림은 시험에서 못 읽는다.
      }
    }
  });
  await t.pump();
  await expectLater(
    find.byType(CustomerApp),
    matchesGoldenFile(Uri.file('$_dir/$name.png')),
  );
}

void main() {
  setUpAll(initPmartFormatting);

  testWidgets('wish', (t) async {
    if (_dir.isEmpty) fail('SHOT_DIR 필요');
    await t.runAsync(_fonts);
    _view(t);
    await t.pumpWidget(
      testApp(
        const [],
        wishlist: MockWishlistRepository(latency: Duration.zero, seed: []),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    await t.tap(find.text('찜').last);
    await _shot(t, 'w-empty');
  });

  testWidgets('night', (t) async {
    if (_dir.isEmpty) fail('SHOT_DIR 필요');
    await t.runAsync(_fonts);
    _view(t);
    final checkout =
        MockCheckoutRepository(
            latency: Duration.zero,
            now: () => DateTime.utc(2026, 10, 24, 3),
          )
          ..unavailable = {
            DeliveryMode.single: 'NIGHT_TIME',
            DeliveryMode.bundled: 'NIGHT_TIME',
          };
    await t.pumpWidget(testApp(const [], checkout: checkout));
    await _shot(t, 'n-home');
    await t.pump(const Duration(seconds: 3));
    await _shot(t, 'n-home-bar');
    await t.tap(find.byKey(const ValueKey('home-delivery-guide')));
    await _shot(t, 'n-guide');
  });

  testWidgets('member home', (t) async {
    if (_dir.isEmpty) fail('SHOT_DIR 필요');
    await t.runAsync(_fonts);
    _view(t);
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    await t.tap(find.text('홈').last);
    await t.pumpAndSettle();
    await t.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await _shot(t, 'm-home');
  });

  testWidgets('tabs', (t) async {
    if (_dir.isEmpty) fail('SHOT_DIR 필요');
    await t.runAsync(_fonts);
    _view(t);
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    for (var i = 1; i <= 5; i++) {
      await t.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await _shot(t, 't-home-$i');
    }
    await t.drag(find.byType(Scrollable).first, const Offset(0, 5000));
    await t.pumpAndSettle();
    await t.tap(find.text('랭킹').first);
    await _shot(t, 't-rank-0');
    for (var i = 1; i <= 3; i++) {
      await t.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await _shot(t, 't-rank-$i');
    }
    await t.drag(find.byType(Scrollable).first, const Offset(0, 5000));
    await t.pumpAndSettle();
    await t.tap(find.text('신상품').first);
    await _shot(t, 't-new-0');
  });

  testWidgets('sale and category', (t) async {
    if (_dir.isEmpty) fail('SHOT_DIR 필요');
    await t.runAsync(_fonts);
    _view(t);
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('home-tab-sale')));
    await _shot(t, 's-sale');
    await t.tap(find.text('카테고리').last);
    await t.pumpAndSettle();
    await t.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await _shot(t, 's-category');
  });
}
