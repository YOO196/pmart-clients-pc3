// 산 상품 한 번에 담기 화면을 사용자 폰 폭(1080px = 411dp, S23)으로 찍는다.
//   flutter test tool/shot_bought.dart --update-goldens --dart-define=SHOT_DIR=<절대 경로>
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/app.dart';
import 'package:customer_app/features/orders/data/mock_orders_repository.dart';
import 'package:customer_app/features/orders/domain/orders.dart';

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

  testWidgets('bought', (t) async {
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
        orders: MockOrdersRepository(latency: Duration.zero)
          ..frequent = const [
            FrequentItem(
              sku: 'E-00000001',
              productId: 'P-0001',
              productName: '서울우유 1L',
              orderCount: 1,
            ),
            FrequentItem(
              sku: 'E-00000002',
              productId: 'P-0002',
              productName: '감자칩 오리지널 110g',
              orderCount: 1,
            ),
            FrequentItem(
              sku: 'E-00000003',
              productId: 'P-0003',
              productName: '제주 감귤 1kg',
              orderCount: 2,
            ),
          ],
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    GoRouter.of(t.element(find.byType(Scaffold).first))
        .push('/me/bought-items');
    await t.pumpAndSettle();
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(Uri.file('$_dir/bought.png')),
    );
  });
}
