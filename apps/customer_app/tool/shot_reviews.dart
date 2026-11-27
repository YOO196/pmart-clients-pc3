// 상품 리뷰 화면들(전체 보기 위·카드, 사진 크게 보기, 사진리뷰 상세, 모아보기)을 S23 폭(411dp)으로 찍는다.
//   flutter test tool/shot_reviews.dart --update-goldens --dart-define=SHOT_DIR=<절대 경로>
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/app.dart';

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

Future<void> _open(WidgetTester t) async {
  if (_dir.isEmpty) fail('SHOT_DIR 필요');
  await t.runAsync(_fonts);
  t.view
    ..physicalSize = const Size(1080, 2340)
    ..devicePixelRatio = 1080 / 411
    ..padding = const FakeViewPadding(top: 99, bottom: 48)
    ..viewPadding = const FakeViewPadding(top: 99, bottom: 48);
  addTearDown(t.view.reset);
  await t.pumpWidget(testApp(const []));
  await t.pumpAndSettle();
  GoRouter.of(t.element(find.byType(Scaffold).first))
      .push('/products/P-0001/reviews');
  await t.pumpAndSettle();
  await t.pump(const Duration(seconds: 3));
  await t.pumpAndSettle();
}

Future<void> _shot(WidgetTester t, String name) async {
  await t.pump(const Duration(seconds: 2));
  await t.pumpAndSettle();
  await expectLater(
    find.byType(CustomerApp),
    matchesGoldenFile(Uri.file('$_dir/$name.png')),
  );
}

void main() {
  setUpAll(initPmartFormatting);

  testWidgets('list-top', (t) async {
    await _open(t);
    await _shot(t, 'reviews-top');
  });

  testWidgets('list-cards', (t) async {
    await _open(t);
    await t.drag(
      find.byKey(const ValueKey('product-reviews-list')),
      const Offset(0, -330),
    );
    await _shot(t, 'reviews-cards');
  });

  testWidgets('viewer', (t) async {
    await _open(t);
    final photo = find.byKey(const ValueKey('review-photo-rv-gen-P-0001-0-0'));
    await t.scrollUntilVisible(
      photo,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(photo);
    await _shot(t, 'reviews-viewer');
  });

  testWidgets('grid', (t) async {
    await _open(t);
    final more = find.byKey(const ValueKey('review-photos-more'));
    await t.scrollUntilVisible(
      more,
      300,
      scrollable: find.byType(Scrollable).at(1),
    );
    await _shot(t, 'reviews-strip-end');
    await t.tap(more);
    await _shot(t, 'reviews-grid');
    await t.tap(find.byKey(const ValueKey('review-photos-grid-0')));
    await _shot(t, 'reviews-photo-detail');
  });
}
