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

  group('입력 규칙', () {
    final today = DateTime(2026, 11, 10);

    test('품질검사 줄: 정상은 LOT 표기 스캔 또는 표기 없음 확인', () {
      expect(
        inspectRowIssues(const InspectRow(qty: 1, expiry: '2026-11-30'), today),
        {InspectIssue.needLot},
      );
      expect(
        inspectRowIssues(
          const InspectRow(qty: 1, noLot: true, expiry: '2026-11-30'),
          today,
        ),
        isEmpty,
      );
    });

    test('품질검사 줄: 수량·정상 소비기한·날짜 형식·제조일', () {
      expect(
        inspectRowIssues(const InspectRow(qty: 0), today),
        containsAll([InspectIssue.zeroQty, InspectIssue.needExpiry]),
      );
      expect(
        inspectRowIssues(const InspectRow(qty: 2, quarantined: true), today),
        isEmpty,
      ); // 격리는 소비기한 없이도
      expect(
        inspectRowIssues(
          const InspectRow(qty: 1, lotRef: 'A1', expiry: '2026/11/30'),
          today,
        ),
        {InspectIssue.badDate},
      );
      expect(
        inspectRowIssues(
          const InspectRow(
            qty: 1,
            lotRef: 'A1',
            expiry: '2026-11-30',
            manufacture: '2026-11-11',
          ),
          today,
        ),
        {InspectIssue.badManufacture},
      ); // 오늘 이후 제조일
      expect(
        inspectRowIssues(
          const InspectRow(
            qty: 1,
            lotRef: 'A1',
            expiry: '2026-11-30',
            manufacture: '2026-11-01',
          ),
          today,
        ),
        isEmpty,
      );
    });

    test('반품 판정: 재판매는 상온·신선 아님·미개봉, 조건이 바뀌면 폐기로 돌리고 사유를 채운다', () {
      var d = const ReturnDecision(zone: TempZone.ambient);
      expect(d.resaleAllowed, isTrue);
      d = d.copyWith(verdict: () => ReturnVerdict.resale);
      expect(d.complete, isTrue);
      d = d.copyWith(opened: true);
      expect(d.verdict, ReturnVerdict.dispose);
      expect(d.disposeReason, DisposeReason.opened);
      expect(
        const ReturnDecision(zone: TempZone.frozen).suggestedReason,
        DisposeReason.temperatureZone,
      );
      expect(
        const ReturnDecision(verdict: ReturnVerdict.dispose).complete,
        isFalse,
      ); // 온도대를 골라야
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
    await t.ensureVisible(find.byKey(ValueKey(key)));
    await t.tap(find.byKey(ValueKey(key)));
    await t.pumpAndSettle();
  }

  Future<void> type(WidgetTester t, String key, String text) async {
    await t.ensureVisible(find.byKey(ValueKey(key)));
    await t.enterText(find.byKey(ValueKey(key)), text);
    await t.pump();
  }

  Future<void> openInspection(WidgetTester t) async {
    await pumpApp(t);
    await tapKey(t, 'area-inspection');
    await tapKey(t, 'guide-ok');
  }

  bool submitEnabled(WidgetTester t, String key) =>
      t
          .widget<FilledButton>(
            find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed !=
      null;

  testWidgets(
    '품질검사: 서버가 준 입고 검사 → 정상 10(소비기한) + 격리 2 → 등록 → 적치 작업 생성 → 다음은 반품 검사',
    (t) async {
      await openInspection(t);
      expect(
        find.byKey(const ValueKey('assigned-TSK-INS-mock-1')),
        findsOneWidget,
      );
      await tapKey(t, 'run-task');

      // 기본은 정상 한 줄 = 잔량 12. 소비기한이 없으면 등록할 수 없다.
      expect(find.text('합계 12 / 검사할 수량 12'), findsOneWidget);
      expect(submitEnabled(t, 'inspect-submit'), isFalse);
      expect(find.text('정상 판정은 소비기한을 넣어 주세요'), findsOneWidget);

      await type(t, 'qty-0', '10');
      // 포장의 LOT 표기를 스캔(입력칸 = 하드웨어 스캐너 입력).
      expect(find.text("LOT 표기를 스캔하거나 '표기 없음'을 눌러 주세요"), findsOneWidget);
      await type(t, 'lot-scan-0', 'L2611A');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('lot-value-0')), findsOneWidget);
      expect(find.text('LOT 표기 L2611A'), findsOneWidget);
      // 소비기한은 달력에서 고른다(오늘 2026-11-10 → 30일).
      await tapKey(t, 'exp-0');
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await t.tap(find.text('30'));
      await t.tap(find.text('확인'));
      await t.pumpAndSettle();
      expect(find.text('2026-11-30'), findsOneWidget);
      // 제조일 달력은 오늘 이후를 고를 수 없다.
      await tapKey(t, 'mfg-0');
      expect(
        t.widget<DatePickerDialog>(find.byType(DatePickerDialog)).lastDate,
        DateTime(2026, 11, 10),
      );
      await t.tap(find.text('1'));
      await t.tap(find.text('확인'));
      await t.pumpAndSettle();
      expect(find.text('2026-11-01'), findsOneWidget);
      await tapKey(t, 'inspect-add-row');
      // 새 줄은 남은 2개, 격리로.
      await t.tap(
        find.descendant(
          of: find.byKey(const ValueKey('verdict-1')),
          matching: find.text('격리'),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('합계 12 / 검사할 수량 12'), findsOneWidget);
      expect(t.takeException(), isNull);
      expect(submitEnabled(t, 'inspect-submit'), isTrue);

      await tapKey(t, 'inspect-submit');
      expect(find.byKey(const ValueKey('inspect-applied')), findsOneWidget);
      expect(find.textContaining('적치 작업 1개'), findsOneWidget);
      expect(quality.task('TSK-INS-mock-1')!.completed, isTrue);

      await tapKey(t, 'quality-message-action'); // 다음 작업
      expect(find.byKey(const ValueKey('assigned-RRC-mock-1')), findsOneWidget);
    },
  );

  testWidgets('반품 검사: 상온 미개봉은 재판매, 냉장은 재판매 불가 → 폐기(사유 자동) → 등록 → 반영', (
    t,
  ) async {
    // 입고 검사 작업을 먼저 끝낸 상태로.
    await t.runAsync(
      () => quality.inspect('TSK-INS-mock-1', const [
        InspectionResult(qty: 12, quarantined: true),
      ], key: IdempotencyKey('pre')),
    );
    await openInspection(t);
    expect(find.byKey(const ValueKey('assigned-RRC-mock-1')), findsOneWidget);
    await tapKey(t, 'run-task');

    expect(find.text('감자칩 오리지널 110g'), findsOneWidget);
    expect(submitEnabled(t, 'return-submit'), isFalse);

    await tapKey(t, 'zone-0-ambient');
    await tapKey(t, 'resale-0');

    await tapKey(t, 'zone-1-chilled');
    expect(
      t
          .widget<OutlinedButton>(find.byKey(const ValueKey('resale-1')))
          .onPressed,
      isNull,
    );
    await tapKey(t, 'dispose-1');
    expect(
      t
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('reason-1-temperatureZone')),
          )
          .selected,
      isTrue,
    );
    expect(t.takeException(), isNull);

    await tapKey(t, 'return-submit');
    expect(find.byKey(const ValueKey('return-applied')), findsOneWidget);
    final sent = quality.inspectedReturns['RRC-mock-1']!;
    expect(sent[0].verdict, ReturnVerdict.resale);
    expect(sent[1].verdict, ReturnVerdict.dispose);
    expect(sent[1].disposeReason, DisposeReason.temperatureZone);

    await tapKey(t, 'quality-message-action');
    expect(find.text('지금 할 작업이 없어요. 잠시 뒤 다시 받아 주세요'), findsOneWidget);
  });

  testWidgets('검사 응답을 잃으면 확인 중 — 다시 확인은 같은 키(한 번만 반영)', (t) async {
    quality.loseNextResponse = true;
    await openInspection(t);
    await tapKey(t, 'run-task');
    await t.tap(
      find.descendant(
        of: find.byKey(const ValueKey('verdict-0')),
        matching: find.text('격리'),
      ),
    );
    await t.pumpAndSettle();
    await tapKey(t, 'inspect-submit');
    expect(find.byKey(const ValueKey('inspect-unknown')), findsOneWidget);
    expect(find.byKey(const ValueKey('inspect-applied')), findsNothing);

    await tapKey(t, 'inspect-submit'); // 다시 확인
    expect(find.byKey(const ValueKey('inspect-applied')), findsOneWidget);
    expect(quality.inspectCalls, 2);
    expect(quality.task('TSK-INS-mock-1')!.doneQty, 12);
  });
}
