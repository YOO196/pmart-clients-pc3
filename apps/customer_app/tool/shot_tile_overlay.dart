// 서버 상품 사진(그림 속 + 동그라미·"일시품절")과 앱이 덮는 것이 겹치는지 — 실제 LAN 사진으로 찍는다.
//   flutter test tool/shot_tile_overlay.dart --update-goldens --dart-define=SHOT_DIR=<절대 경로>
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/app.dart';
import 'package:customer_app/features/catalog/domain/catalog.dart';
import 'package:customer_app/features/catalog/presentation/widgets/product_tile_card.dart';
import 'package:customer_app/l10n/gen/app_localizations.dart';

import '../test/support/app_harness.dart';

const _dir = String.fromEnvironment('SHOT_DIR');
const _img = 'https://192.168.0.40:8443/api/v1/content-images';

class _LanHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? c) =>
      super.createHttpClient(c)..badCertificateCallback = (_, _, _) => true;
}

void main() {
  setUpAll(initPmartFormatting);

  testWidgets('tile overlay', (t) async {
    if (_dir.isEmpty) fail('SHOT_DIR 필요');
    // 시험 기본은 모든 HTTP 가 400 — 이 캡처만 LAN 사진을 실제로 받는다.
    HttpOverrides.global = _LanHttp();
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
    });
    t.view
      ..physicalSize = const Size(1080, 900)
      ..devicePixelRatio = 2.8125;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    final container = ProviderScope.containerOf(
      t.element(find.byType(CustomerApp)),
    );
    const tiles = [
      ProductTile(
        productId: 'P1',
        name: '친환경 대추방울토마토 500g',
        saleState: SaleState.onSale,
        representativeSku: 'E-1',
        basePrice: 7990,
        imageUrl: '$_img/IMG-1094f449-f433-4d2d-a315-2fe6f901fef7',
      ),
      ProductTile(
        productId: 'P2',
        name: '[2개 묶음] 친환경 대추방울토마토 500g',
        saleState: SaleState.temporarilySoldOut,
        representativeSku: 'B-1',
        basePrice: 15560,
        imageUrl: '$_img/IMG-1f88326d-0d1e-4d8e-8d35-2c41665d6a90',
      ),
    ];
    final page = UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ko'),
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Padding(
            // 할인 탭 2칸(폰 캡처: 사진 480px, 좌우 42px, 사이 32px).
            padding: const EdgeInsets.fromLTRB(14.9, 20, 14.9, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, tile) in tiles.indexed) ...[
                  if (i > 0) const SizedBox(width: 11.4),
                  SizedBox(
                    width: 170.7,
                    height: 260,
                    child: ProductTileCard(tile: tile, rail: true),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    // 실제 사진은 진짜 비동기에서 받는다(가짜 시계에서는 HTTP 가 끝나지 않는다).
    await t.runAsync(() async {
      await t.pumpWidget(page);
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await t.pump();
      }
    });
    await t.pump();
    await expectLater(
      find.byType(MaterialApp).last,
      matchesGoldenFile(Uri.file('$_dir/tile_overlay.png')),
    );
  });
}
