import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:mfc_app/app.dart';
import 'package:mfc_app/features/inbound/data/mock_inbound_repository.dart';
import 'package:mfc_app/features/inbound/presentation/inbound_controller.dart';
import 'package:mfc_app/features/packing/data/mock_packing_repository.dart';
import 'package:mfc_app/features/packing/presentation/packing_controller.dart';
import 'package:mfc_app/features/quality/data/mock_quality_repository.dart';
import 'package:mfc_app/features/quality/domain/quality.dart';
import 'package:mfc_app/features/quality/presentation/quality_controllers.dart';
import 'package:mfc_app/features/stock_move/data/mock_stock_move_repository.dart';
import 'package:mfc_app/features/tasks/data/mock_task_repository.dart';
import 'package:mfc_app/features/tasks/presentation/task_controllers.dart';
import 'package:mfc_app/shared/field_repositories.dart';
import 'package:mfc_app/shared/providers.dart';

void main() {
  setUpAll(initPmartFormatting);

  group('판정 규칙', () {
    final today = DateTime(2026, 11, 10);
    const yogurt = InspectCriteria(minRemainingDays: 5, zone: TempZone.chilled);
    const tofu = InspectCriteria(
      minRemainingDays: 3,
      maxDaysSinceManufacture: 3,
      zone: TempZone.chilled,
    );

    test('기준 미달은 격리로 고정 — 기한 부족·제조일 초과·온도 이탈', () {
      expect(
        forcedReason(
          const InspectRow(expiry: '2026-11-12'),
          yogurt,
          today,
          temperatureBad: false,
        ),
        QuarantineReason.expiry,
      ); // 2일 남음 < 5
      expect(
        forcedReason(
          const InspectRow(expiry: '2026-11-30'),
          yogurt,
          today,
          temperatureBad: false,
        ),
        isNull,
      );
      expect(
        forcedReason(
          const InspectRow(expiry: '2026-11-20', manufacture: '2026-11-05'),
          tofu,
          today,
          temperatureBad: false,
        ),
        QuarantineReason.manufacture,
      ); // 제조 5일 > 3
      expect(
        forcedReason(
          const InspectRow(expiry: '2026-11-30'),
          yogurt,
          today,
          temperatureBad: true,
        ),
        QuarantineReason.temperature,
      );
    });

    test('판정 기본값 없음, 격리는 사유·사진, 정상은 LOT 표기, 기준이 요구하면 제조일', () {
      expect(
        inspectRowIssues(
          const InspectRow(qty: 1, expiry: '2026-11-30'),
          yogurt,
          today,
        ),
        {InspectIssue.needVerdict},
      );
      expect(
        inspectRowIssues(
          const InspectRow(qty: 1, expiry: '2026-11-30', quarantined: true),
          yogurt,
          today,
        ),
        {InspectIssue.needReason, InspectIssue.needEvidence},
      );
      expect(
        inspectRowIssues(
          const InspectRow(qty: 1, expiry: '2026-11-30', quarantined: false),
          yogurt,
          today,
        ),
        {InspectIssue.needLot},
      );
      expect(
        inspectRowIssues(
          const InspectRow(
            qty: 1,
            expiry: '2026-11-30',
            quarantined: false,
            noLot: true,
          ),
          tofu,
          today,
        ),
        {InspectIssue.needManufacture},
      );
    });

    test('반품: 온도대·신선은 상품 정보, 판정은 자동, 폐기는 사진', () {
      const ambient = ReturnDecision(zone: TempZone.ambient, fresh: false);
      expect(ambient.verdict, ReturnVerdict.resale);
      expect(ambient.complete, isTrue);
      expect(
        ambient.copyWith(opened: true).disposeReason,
        DisposeReason.opened,
      );
      const chilled = ReturnDecision(zone: TempZone.chilled, fresh: false);
      expect(chilled.disposeReason, DisposeReason.temperatureZone);
      expect(chilled.complete, isFalse); // 사진 필요
      expect(chilled.copyWith(evidence: () => 'EVD-1').complete, isTrue);
      expect(const ReturnDecision().complete, isFalse); // 상품 정보 없음
    });
  });

  late MockStockMoveRepository stockMove;
  late MockQualityRepository quality;

  setUp(() {
    stockMove = MockStockMoveRepository(latency: Duration.zero);
    quality = MockQualityRepository(latency: Duration.zero, returns: stockMove);
  });

  Future<void> pumpApp(WidgetTester t) async {
    t.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          envProvider.overrideWithValue(PmartEnv.mock),
          taskRepositoryProvider.overrideWithValue(
            MockTaskRepository(latency: Duration.zero),
          ),
          packingRepositoryProvider.overrideWithValue(
            MockPackingRepository(latency: Duration.zero),
          ),
          inboundRepositoryProvider.overrideWithValue(
            MockInboundRepository(latency: Duration.zero),
          ),
          qualityRepositoryProvider.overrideWithValue(quality),
          stockMoveRepositoryProvider.overrideWithValue(stockMove),
          applyPollPolicyProvider.overrideWithValue((
            interval: Duration.zero,
            attempts: 3,
          )),
          mfcClockProvider.overrideWithValue(() => DateTime(2026, 11, 10, 9)),
          secureStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        ],
        child: const MfcApp(),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    // 가운데로 — 아래 고정 줄("합계") 밑에 숨지 않게.
    await t.ensureVisible(find.byKey(ValueKey(key)));
    await Scrollable.ensureVisible(
      t.element(find.byKey(ValueKey(key))),
      alignment: 0.5,
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(ValueKey(key)));
    await t.pumpAndSettle();
  }

  Future<void> testScan(WidgetTester t, String id, String value) async {
    await tapKey(t, '$id-test');
    await t.tap(find.byKey(ValueKey('$id-test-$value')));
    await t.pumpAndSettle();
  }

  Future<void> pickDay(WidgetTester t, String key, String day) async {
    await tapKey(t, key);
    await t.tap(find.text(day));
    await t.tap(find.text('확인'));
    await t.pumpAndSettle();
  }

  Future<void> verdict(WidgetTester t, int i, String label) async {
    final f = find.descendant(
      of: find.byKey(ValueKey('verdict-$i')),
      matching: find.text(label),
    );
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pumpAndSettle();
  }

  bool enabled(WidgetTester t, String key) =>
      t
          .widget<FilledButton>(
            find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed !=
      null;

  Future<void> open(WidgetTester t, String taskId) async {
    await pumpApp(t);
    await tapKey(t, 'area-inspection');
    await tapKey(t, 'guide-ok');
    expect(find.byKey(ValueKey('assigned-$taskId')), findsOneWidget);
    await tapKey(t, 'run-task');
  }

  testWidgets(
    '입고 품질검사: 위치 스캔 → 상품 대조 → 기준 표시 → 정상 10(LOT) + 기한 부족 2(자동 격리·사진) → 등록 → 다음 검사',
    (t) async {
      await open(t, 'TSK-INS-mock-1');

      // 1단계 위치: 틀린 위치는 거절.
      await testScan(t, 'inspect-loc-scan', 'RCV-C-09');
      expect(find.byKey(const ValueKey('inspect-scan-error')), findsOneWidget);
      await testScan(t, 'inspect-loc-scan', 'RCV-C-01');

      // 2단계 상품: 다른 상품은 거절.
      await testScan(t, 'inspect-product-scan', '8801115114154');
      expect(find.text('지시한 상품이 아니에요'), findsWidgets);
      await testScan(t, 'inspect-product-scan', '8801115220015');

      // 3단계 판정: 기준이 보이고, 판정 기본값이 없다.
      expect(find.text('소비기한 5일 이상 남아야 정상'), findsOneWidget);
      expect(enabled(t, 'inspect-submit'), isFalse);
      await t.tap(find.text('온도 정상'));
      await t.pumpAndSettle();

      await t.enterText(find.byKey(const ValueKey('qty-0')), '10');
      await t.pump();
      await pickDay(t, 'exp-0', '30');
      await verdict(t, 0, '정상');
      await testScan(t, 'lot-scan-0', 'L2611A');

      await tapKey(t, 'inspect-add-row'); // 남은 2개
      await pickDay(t, 'exp-1', '12'); // 2일 남음 → 기한 부족, 격리 고정
      expect(find.byKey(const ValueKey('forced-1')), findsOneWidget);
      expect(enabled(t, 'inspect-submit'), isFalse); // 사진 필요
      await tapKey(t, 'evidence-1');
      expect(t.takeException(), isNull);
      expect(enabled(t, 'inspect-submit'), isTrue);

      await tapKey(t, 'inspect-submit');
      expect(find.byKey(const ValueKey('inspect-applied')), findsOneWidget);
      expect(quality.task('TSK-INS-mock-1')!.completed, isTrue);

      // 나뉜 정상 LOT 마다 라벨 — 적치 작업 수량(10)만큼. 격리분(2)은 라벨 없음.
      await t.pumpAndSettle();
      expect(find.textContaining('라벨 10장 출력'), findsOneWidget);
      await t.tap(find.textContaining('라벨 10장 출력'));
      await t.pumpAndSettle();
      expect(find.text('LOT 라벨 미리보기 (10장)'), findsOneWidget);
      await t.tap(find.text('확인').last);
      await t.pumpAndSettle();

      await tapKey(t, 'result-action'); // 다음 작업
      expect(
        find.byKey(const ValueKey('assigned-TSK-INS-mock-2')),
        findsOneWidget,
      );
    },
  );

  testWidgets('두부: 제조일 필수, 온도 이탈이면 전부 격리(사진) — 응답을 잃어도 같은 키로 한 번', (t) async {
    await t.runAsync(
      () => quality.inspect('TSK-INS-mock-1', const [
        InspectionResult(qty: 12, quarantined: true),
      ], key: IdempotencyKey('pre')),
    );
    quality.loseNextResponse = true;
    await open(t, 'TSK-INS-mock-2');
    await testScan(t, 'inspect-loc-scan', 'RCV-C-02');
    await testScan(t, 'inspect-product-scan', '8801007001101');
    expect(find.text('제조 3일 이내만 정상 — 제조일 필수'), findsOneWidget);

    await t.tap(find.text('온도 이탈'));
    await t.pumpAndSettle();
    await pickDay(t, 'exp-0', '20');
    expect(find.text('이 상품은 제조일이 필요해요'), findsOneWidget);
    await pickDay(t, 'mfg-0', '9');
    expect(find.byKey(const ValueKey('forced-0')), findsOneWidget); // 온도 이탈
    await tapKey(t, 'evidence-0');
    await tapKey(t, 'inspect-submit');
    expect(find.byKey(const ValueKey('inspect-unknown')), findsOneWidget);
    await tapKey(t, 'inspect-submit'); // 다시 확인
    expect(find.byKey(const ValueKey('inspect-applied')), findsOneWidget);
    expect(quality.inspectCalls, 3); // pre 1 + 2
    expect(quality.task('TSK-INS-mock-2')!.doneQty, 16);
  });

  testWidgets('반품 검사: 상품 정보로 자동 판정 — 상온은 재판매, 냉장은 폐기(사진 필수)', (t) async {
    await t.runAsync(() async {
      for (final (id, qty) in [
        ('TSK-INS-mock-1', 12),
        ('TSK-INS-mock-2', 16),
      ]) {
        await quality.inspect(id, [
          InspectionResult(qty: qty, quarantined: true),
        ], key: IdempotencyKey('pre-$id'));
      }
    });
    await open(t, 'RRC-mock-1');

    expect(find.text('상품 정보: 상온 · 신선 아님'), findsOneWidget);
    expect(find.text('상품 정보: 냉장 · 신선 아님'), findsOneWidget);
    expect(find.text('재판매'), findsOneWidget);
    expect(find.text('폐기 · 냉장·냉동'), findsOneWidget);
    expect(enabled(t, 'return-submit'), isFalse); // 폐기 사진 필요

    await tapKey(t, 'evidence-1');
    expect(t.takeException(), isNull);
    await tapKey(t, 'return-submit');
    expect(find.byKey(const ValueKey('return-applied')), findsOneWidget);
    final sent = quality.inspectedReturns['RRC-mock-1']!;
    expect(sent[0].verdict, ReturnVerdict.resale);
    expect(sent[1].verdict, ReturnVerdict.dispose);
    expect(sent[1].disposeReason, DisposeReason.temperatureZone);
    expect(sent[1].evidenceRef, isNotNull);
  });
}
