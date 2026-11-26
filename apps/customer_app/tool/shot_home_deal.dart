// 홈 띠형 타이머 테마(일일특가 모양)를 폰 배율(1080px = 411dp, S23)로 찍는다.
//   flutter test tool/shot_home_deal.dart --update-goldens --dart-define=SHOT_DIR=<절대 경로>
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/app.dart';
import 'package:customer_app/features/catalog/data/mock_catalog_repository.dart';
import 'package:customer_app/features/catalog/presentation/catalog_providers.dart'
    show homeClockProvider;

import '../test/support/app_harness.dart';

const _dir = String.fromEnvironment('SHOT_DIR');

void main() {
  setUpAll(initPmartFormatting);

  testWidgets('home deal', (t) async {
    if (_dir.isEmpty) fail('SHOT_DIR 필요');
    await t.runAsync(() async {
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
      // 별점 등 Material 아이콘(시험 기본은 글꼴이 없어 네모로 그려진다).
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                r'C:/development/tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytesSync(),
            ),
          ),
        );
      await icons.load();
    });
    t.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 1080 / 411
      ..padding = const FakeViewPadding(top: 99, bottom: 48)
      ..viewPadding = const FakeViewPadding(top: 99, bottom: 48);
    addTearDown(t.view.reset);
    final now = DateTime.utc(2026, 11, 21, 3);
    final catalog = MockCatalogRepository(latency: Duration.zero)
      ..timedSections['S-NEW'] = now.add(
        const Duration(hours: 11, minutes: 27, seconds: 46),
      )
      ..bandTimerSections.add('S-NEW');
    await t.pumpWidget(
      testApp([
        homeClockProvider.overrideWithValue(() => now),
      ], catalog: catalog),
    );
    await t.pumpAndSettle();
    final band = find.byKey(const ValueKey('section-timer-band-S-NEW'));
    await t.scrollUntilVisible(
      band,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pump();
    final y = t.getTopLeft(band).dy;
    await t.drag(find.byType(Scrollable).first, Offset(0, -(y - 140)));
    await t.pump(const Duration(milliseconds: 500));
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(Uri.file('$_dir/home_deal.png')),
    );
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });
}
