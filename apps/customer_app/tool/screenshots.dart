// 화면 캡처 도구(디자인 전후 비교용). 에뮬레이터 없이 목 모드 앱을 테스트 러너로 그려 PNG 로 남긴다.
//   flutter test tool/screenshots.dart --update-goldens --dart-define=SHOT_DIR=<절대 경로>
// 글꼴: 테스트 러너에는 한글 글꼴이 없어 이 PC 의 Noto Sans KR(없으면 맑은 고딕)을 읽는다(캡처에만 쓰고 앱에 넣지 않는다).
// 상품 사진은 테스트에서 네트워크를 쓰지 않아 자리표시로 나온다.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/app.dart';
import 'package:customer_app/features/checkout/data/mock_checkout_repository.dart';
import 'package:customer_app/features/checkout/presentation/checkout_controller.dart';

import '../test/support/app_harness.dart';

const _dir = String.fromEnvironment('SHOT_DIR');

Future<void> _font(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var any = false;
  for (final p in paths) {
    final f = File(p);
    if (!f.existsSync()) continue;
    final bytes = await f.readAsBytes();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
    any = true;
  }
  if (any) await loader.load();
}

/// 테스트 본문 안(runAsync)에서 불러야 적용된다.
Future<void> _loadFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
  final material = '$flutterRoot/bin/cache/artifacts/material_fonts';
  await _font('MaterialIcons', ['$material/materialicons-regular.otf']);
  const win = 'C:/Windows/Fonts';
  await _font('Roboto', ['$win/malgun.ttf', '$win/malgunbd.ttf']);
  const f = 'assets/fonts';
  await _font('Pretendard', [
    '$f/Pretendard-Regular.otf',
    '$f/Pretendard-SemiBold.otf',
    '$f/Pretendard-Bold.otf',
    '$f/Pretendard-ExtraBold.otf',
  ]);
}

void main() {
  setUpAll(initPmartFormatting);

  final now = DateTime.utc(2026, 10, 24, 3); // 서울 12:00

  testWidgets('screens', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    Directory(_dir).createSync(recursive: true);
    await t.runAsync(_loadFonts);
    // 테스트 러너는 그림자를 검은 테두리로 그린다 — 실제처럼 그리게 한다.
    debugDisableShadows = false;
    t.view
      ..physicalSize =
          const Size(1080, 2180) // 360 x 727 @3x (레퍼런스와 같은 폭)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);

    final checkout = MockCheckoutRepository(
      latency: Duration.zero,
      now: () => now,
    );
    await t.pumpWidget(
      testApp(checkout: checkout, [
        clockProvider.overrideWithValue(() => now),
        draftPollPolicyProvider.overrideWithValue((
          interval: Duration.zero,
          attempts: 3,
        )),
      ]),
    );
    await t.pumpAndSettle();

    var n = 0;
    Future<void> shot(String name) async {
      await t.pumpAndSettle();
      n += 1;
      final file = File('$_dir/${n.toString().padLeft(2, '0')}-$name.png');
      await expectLater(find.byType(CustomerApp), matchesGoldenFile(file.uri));
    }

    GoRouter router() => GoRouter.of(t.element(find.byType(Scaffold).first));
    Future<void> go(String path) async {
      router().go(path);
      await t.pumpAndSettle();
    }

    Future<void> scrollDown(double dy) async {
      await t.drag(find.byType(Scrollable).first, Offset(0, -dy));
      await t.pumpAndSettle();
    }

    await shot('home');
    await scrollDown(700);
    await shot('home-2');
    await scrollDown(900);
    await shot('home-3');

    await go('/categories');
    await shot('categories');
    await go('/search');
    await shot('search');
    await t.enterText(find.byKey(const ValueKey('search-field')), '우유');
    await t.tap(find.byKey(const ValueKey('search-submit')));
    await t.pumpAndSettle();
    await shot('search-results');
    await go('/products?categoryId=C-10&title=유제품');
    await shot('product-list');

    await go('/');
    await tapTile(t, 'P-0001');
    await shot('product-detail');
    await scrollDown(600);
    await shot('product-detail-2');

    await go('/cart');
    await shot('cart');
    await t.tap(find.byKey(const ValueKey('cart-order')));
    await t.pumpAndSettle();
    await shot('login');
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    await shot('delivery-select');
    await t.tap(find.byKey(const ValueKey('mode-single')));
    await t.pump();
    await shot('delivery-select-picked');
    unawaited(router().push('/checkout'));
    await t.pumpAndSettle();
    await shot('order-sheet');
    await scrollDown(700);
    await shot('order-sheet-2');

    await go('/my');
    await shot('my');
    await go('/orders');
    await shot('orders');
    await t.tap(
      find
          .byWidgetPredicate(
            (w) =>
                w is Material &&
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('order-'),
          )
          .first,
    );
    await t.pumpAndSettle();
    await shot('order-detail');
    await scrollDown(650);
    await shot('order-detail-2');
    await go('/reviews');
    await shot('reviews');
    await go('/addresses/new');
    await shot('address-new');
    await go('/notifications/settings');
    await shot('notice-settings');
    await go('/notifications');
    await shot('notifications');
    await go('/addresses');
    await shot('addresses');
    debugDisableShadows = true;
  });
}
