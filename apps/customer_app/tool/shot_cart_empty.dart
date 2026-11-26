// 빈 장바구니를 사용자 폰 폭(1080px = 411dp, S23)으로 찍는다.
//   flutter test tool/shot_cart_empty.dart --update-goldens --dart-define=SHOT_DIR=<절대 경로>
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/app.dart';
import 'package:customer_app/features/cart/data/mock_cart_repository.dart';

import '../test/support/app_harness.dart';

const _dir = String.fromEnvironment('SHOT_DIR');

Future<void> _fonts() async {
  final loader = FontLoader('Roboto');
  for (final p in [
    'C:/Windows/Fonts/malgun.ttf',
    'C:/Windows/Fonts/malgunbd.ttf',
  ]) {
    loader.addFont(
      Future.value(ByteData.sublistView(File(p).readAsBytesSync())),
    );
  }
  await loader.load();
}

void main() {
  setUpAll(initPmartFormatting);

  testWidgets('cart empty', (t) async {
    if (_dir.isEmpty) fail('SHOT_DIR 필요');
    await t.runAsync(_fonts);
    t.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 1080 / 411
      ..padding = const FakeViewPadding(top: 99, bottom: 48)
      ..viewPadding = const FakeViewPadding(top: 99, bottom: 48);
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp(
        const [],
        cart: MockCartRepository(latency: Duration.zero, seeded: false),
      ),
    );
    await t.pumpAndSettle();
    GoRouter.of(t.element(find.byType(Scaffold).first)).push('/cart');
    await t.pumpAndSettle();
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(Uri.file('$_dir/cart_empty.png')),
    );
  });
}
