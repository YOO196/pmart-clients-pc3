// 카테고리·배너 그림을 한 장에 모아 눈으로 확인하는 도구.
//   flutter test tool/art_sheet.dart --update-goldens --dart-define=SHOT_DIR=<절대 경로>
import 'package:customer_app/features/catalog/presentation/widgets/category_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_ui/pmart_ui.dart';

const _dir = String.fromEnvironment('SHOT_DIR');

/// 종류마다 그 그림이 골라지는 이름 하나.
const _names = [
  '과일·채소',
  '우유·유제품',
  '과자·간식',
  '정육·수산·계란',
  '음료·커피·생수',
  '라면·면',
  '빵·떡·잼',
  '아이스크림',
  '쌀·잡곡·견과',
  '양념·장류·오일',
  '국·탕·찌개',
  '세제·방향·탈취',
  '뷰티·클렌징',
  '주류',
  '기타',
];

void main() {
  testWidgets('art sheet', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    t.view
      ..physicalSize = const Size(1080, 1200)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: PmartCustomerTheme.light(),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final n in _names) CategoryArt(name: n, size: 60),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                height: 110,
                decoration: BoxDecoration(
                  color: PmartBrand.lavender,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(width: 130, height: 104, child: BannerArt()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('$_dir/art-sheet.png'),
    );
  });
}
