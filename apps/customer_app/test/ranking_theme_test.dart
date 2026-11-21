import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_ui/pmart_ui.dart' show initPmartFormatting;

import 'package:customer_app/features/catalog/data/mock_catalog_repository.dart';
import 'package:customer_app/features/catalog/domain/catalog.dart';

import 'support/app_harness.dart';

/// 자동 랭킹 테마(storefront 0.9.0 RANKING_AUTO → 홈 영역 kind RANKING, 항목 rank·badge RANK, 다음 묶음 없음).
/// 레퍼런스 "3-2. 16. 지금 TOP 30": 순위 숫자를 단 3칸 × 2줄, 전체 보기는 받은 목록 그대로.
void main() {
  setUpAll(initPmartFormatting);
  Finder key(String k) => find.byKey(ValueKey(k));

  Future<MockCatalogRepository> open(WidgetTester t) async {
    t.view
      ..physicalSize = const Size(800, 3000)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final catalog = _CountingCatalog();
    await t.pumpWidget(testApp(const [], catalog: catalog));
    await t.pumpAndSettle();
    return catalog;
  }

  testWidgets('홈의 순위 진열은 3칸 격자 6개, 칸마다 순위 숫자', (t) async {
    await open(t);
    final section = key('section-S-RANK');
    final cells = find.descendant(
      of: section,
      matching: find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('rank-grid-'),
      ),
    );
    expect(cells, findsNWidgets(6));
    // 첫 줄 세 칸은 같은 높이, 넷째 칸은 다음 줄
    final tops = [
      for (final e in cells.evaluate())
        t.getTopLeft(find.byWidget(e.widget)).dy,
    ];
    expect(tops[0], tops[2]);
    expect(tops[3], greaterThan(tops[0]));
    expect(
      find.descendant(of: section, matching: find.text('1')),
      findsWidgets,
    );
  });

  testWidgets('전체 보기는 서버에 다시 묻지 않고 받은 순위 목록을 모두 보인다', (t) async {
    final catalog = await open(t) as _CountingCatalog;
    await t.tap(key('section-view-all-S-RANK'));
    await t.pumpAndSettle();
    expect(catalog.sectionCalls, 0);
    expect(key('section-items-S-RANK'), findsOneWidget);
    expect(find.text('지금 많이 사는 상품'), findsWidgets);
  });
}

final class _CountingCatalog extends MockCatalogRepository {
  _CountingCatalog() : super(latency: Duration.zero);

  int sectionCalls = 0;

  @override
  Future<HomeSection> section(
    HomeSection section, {
    required int layoutVersion,
    String? mfcId,
    String? cursor,
  }) {
    sectionCalls++;
    return super.section(
      section,
      layoutVersion: layoutVersion,
      mfcId: mfcId,
      cursor: cursor,
    );
  }
}
