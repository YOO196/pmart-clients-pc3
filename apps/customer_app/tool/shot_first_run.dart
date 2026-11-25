// 앱 처음 실행 화면(약관·마케팅 안내·로그인)과 주소 편집·주소 상세를 사용자 폰 폭(1080px = 411dp)으로 찍는다.
//   flutter test tool/shot_first_run.dart --update-goldens --dart-define=SHOT_DIR=<절대 경로>
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/app.dart';
import 'package:customer_app/features/address/data/current_location.dart';
import 'package:customer_app/features/start/presentation/current_location_flow.dart';

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
  const f = 'assets/fonts';
  await _font('Pretendard', [
    '$f/Pretendard-Regular.otf',
    '$f/Pretendard-Medium.otf',
    '$f/Pretendard-SemiBold.otf',
    '$f/Pretendard-Bold.otf',
    '$f/Pretendard-ExtraBold.otf',
  ]);
  // 앱은 폰 기본 글꼴을 쓴다(2026-11-26). 시험에는 폰 글꼴이 없어 맑은 고딕으로 대신 그린다.
  await _font('Roboto', [
    'C:/Windows/Fonts/malgun.ttf',
    'C:/Windows/Fonts/malgunbd.ttf',
  ]);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
  await _font('MaterialIcons', [
    '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  ]);
}

void _view(WidgetTester t) {
  t.view
    ..physicalSize = const Size(1080, 2340)
    ..devicePixelRatio = 1080 / 411
    // 사용자 폰 상태 막대(레퍼런스 캡처에서 약 99px)·아래 제스처 막대(약 48px)
    ..padding = const FakeViewPadding(top: 99, bottom: 48)
    ..viewPadding = const FakeViewPadding(top: 99, bottom: 48);
  addTearDown(t.view.reset);
}

Future<void> _shot(WidgetTester t, String name) async {
  await t.pumpAndSettle();
  await t.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
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

  testWidgets('start', (t) async {
    if (_dir.isEmpty) fail('SHOT_DIR 필요');
    await t.runAsync(_fonts);
    _view(t);
    await t.pumpWidget(
      testApp([
        currentLocationSourceProvider.overrideWithValue(
          MockCurrentLocationSource(fix: const LocationDenied(forever: true)),
        ),
      ], startGate: true),
    );
    await _shot(t, '1-welcome');
    // 필수만 동의 → 시작하기 → 마케팅 거부 안내
    await t.tap(find.byKey(const ValueKey('start-agree-location')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('start-begin')));
    await _shot(t, '2-marketing-refused');
    await t.tap(find.byKey(const ValueKey('start-marketing-result-ok')));
    await _shot(t, '3-entry');
  });

  testWidgets('address', (t) async {
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
    GoRouter.of(t.element(find.byType(Scaffold).first)).go('/addresses/edit');
    await _shot(t, '4-address-edit');
    await t.tap(
      find
          .byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith(
                  'address-modify-',
                ),
          )
          .first,
    );
    await _shot(t, '5-address-form');
  });
}
