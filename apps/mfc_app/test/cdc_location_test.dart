import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mfc_app/features/cdc/presentation/cdc_location.dart';
import 'package:mfc_app/l10n/gen/app_localizations.dart';

/// DC 위치 코드(백엔드 chilgok-dc.md CDC-3·4·5·7, R-22·R-25 글자)를 조각으로 — 사용자 2026-11-26 "위치 카드 DC 코드에 맞게 고쳐".
void main() {
  test('7구간 코드를 층·통로·베이·단·칸으로, 구역 글자·통로 번호로 종류', () {
    final c = CdcLocationCode.parse('CDC01-C-5-02-24-3-1')!;
    expect(
      [c.center, c.zone, c.floor, c.aisle, c.bay, c.level, c.slot],
      ['CDC01', 'C', '5', '02', '24', '3', '1'],
    );
    expect(c.isShelf, isFalse);
    expect(c.isSpot, isFalse);
    expect(CdcLocationCode.parse('CDC01-C-5-61-03-2-1')!.isShelf, isTrue);
    final dock = CdcLocationCode.parse('CDC01-G-6-90-03-0-1')!;
    expect(dock.isSpot, isTrue);
    // 오토스토어 단은 두 자리(1~16), 바닥 레인 93 은 자리가 아니라 피킹 칸
    final auto = CdcLocationCode.parse('CDC01-C-6-61-03-12-1')!;
    expect([auto.level, auto.isAutoStore, auto.isShelf], ['12', true, false]);
    final lane = CdcLocationCode.parse('CDC01-G-5-93-04-0-1')!;
    expect([lane.isLane, lane.isSpot], [true, false]);
    // 지하 접안(B1)은 R-22 로 없어졌다
    expect(CdcLocationCode.parse('CDC01-B-B1-90-03-0-1'), isNull);
    // MFC 선반 코드·엉뚱한 값은 나누지 않는다
    expect(CdcLocationCode.parse('C-S1-03-2-04'), isNull);
    expect(CdcLocationCode.parse('CDC01-Z-5-02-24-3-1'), isNull);
  });

  Future<void> pump(WidgetTester t, String code) => t.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('ko'),
      home: Scaffold(body: CdcLocationCard(code: code)),
    ),
  );

  testWidgets('선반 칸: 상온·C구역·피킹 선반 칩, 층·통로·베이·단·칸 다섯 칸', (t) async {
    await pump(t, 'CDC01-C-5-61-03-2-1');
    await t.pumpAndSettle();
    for (final s in [
      '상온',
      'C구역',
      '피킹 선반',
      '층',
      '통로',
      '베이',
      '단',
      '칸',
      '61',
      '03',
    ]) {
      expect(find.text(s), findsWidgets, reason: s);
    }
    expect(find.byKey(const ValueKey('cdc-loc-tile-4')), findsOneWidget);
  });

  testWidgets('H 냉동 팔레트 랙, G 냉장 도크는 층·자리 두 칸', (t) async {
    await pump(t, 'CDC01-H-5-07-12-4-2');
    await t.pumpAndSettle();
    expect(find.text('냉동'), findsOneWidget);
    expect(find.text('팔레트 랙'), findsOneWidget);
    await pump(t, 'CDC01-G-6-90-03-0-1');
    await t.pumpAndSettle();
    expect(find.text('냉장'), findsOneWidget);
    expect(find.text('도크'), findsOneWidget);
    expect(find.text('자리'), findsOneWidget);
    expect(find.byKey(const ValueKey('cdc-loc-tile-2')), findsNothing);
  });

  testWidgets('형식이 아니면 코드 그대로 한 칸', (t) async {
    await pump(t, 'RCV-C-01');
    await t.pumpAndSettle();
    expect(find.text('RCV-C-01'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('cdc-loc-tile-1')), findsNothing);
  });
}
