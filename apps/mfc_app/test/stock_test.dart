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
import 'package:mfc_app/features/stock_count/data/mock_stock_count_repository.dart';
import 'package:mfc_app/features/stock_count/domain/stock_count.dart';
import 'package:mfc_app/features/stock_move/data/mock_stock_move_repository.dart';
import 'package:mfc_app/features/stock_move/domain/stock_move.dart';
import 'package:mfc_app/features/tasks/data/mock_task_repository.dart';
import 'package:mfc_app/features/tasks/presentation/task_controllers.dart';
import 'package:mfc_app/shared/codes.dart';
import 'package:mfc_app/shared/field_repositories.dart';
import 'package:mfc_app/shared/providers.dart';

void main() {
  setUpAll(initPmartFormatting);

  test('코드 형식(채번 지침 5장): 선반·기타 구역·카트·SKU', () {
    expect(isMfcLocation('C-S1-03-2-04'), isTrue);
    expect(isMfcLocation('RCV-C-01'), isTrue);
    expect(isMfcLocation('C01-01-101'), isFalse); // 옛 목 형식
    expect(isCartLocation('CRT-C-01'), isTrue);
    expect(isCartLocation('RCV-C-01'), isFalse);
    expect(isSku('E-00000001'), isTrue);
    expect(isSku('8801115114154'), isFalse);
  });

  late MockStockMoveRepository stockMove;
  late MockQualityRepository quality;
  late MockStockCountRepository count;

  setUp(() {
    stockMove = MockStockMoveRepository(latency: Duration.zero);
    quality = MockQualityRepository(latency: Duration.zero, returns: stockMove);
    count = MockStockCountRepository(latency: Duration.zero);
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
          stockCountRepositoryProvider.overrideWithValue(count),
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

  Future<void> scan(WidgetTester t, String field, String code) async {
    await t.enterText(find.byKey(ValueKey(field)), code);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
  }

  Future<void> setQty(WidgetTester t, String id, int v) async {
    await tapKey(t, '$id-value');
    await t.enterText(find.byKey(const ValueKey('qty-input')), '$v');
    await tapKey(t, 'qty-ok');
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

  Future<void> open(WidgetTester t, String area) async {
    await pumpApp(t);
    await tapKey(t, 'area-$area');
    await tapKey(t, 'guide-ok');
  }

  testWidgets('재고 이동(보충): 출발 칸 확인 → 카트 스캔 → 집기 → 도착 칸 확인 → 내려놓기', (t) async {
    await open(t, 'stockMove');
    expect(find.byKey(const ValueKey('assigned-MV-mock-1')), findsOneWidget);
    expect(find.text('선반 보충'), findsOneWidget);
    await tapKey(t, 'run-task');

    // 1단계: 다른 칸·칸 아닌 값은 거절.
    await scan(t, 'move-scan', 'C-S1-01-1-01');
    expect(find.text('지시한 칸이 아니에요. 화면의 칸으로 가 주세요'), findsWidgets);
    await scan(t, 'move-scan', 'hello');
    expect(find.text('칸 바코드가 아니에요'), findsWidgets);
    await scan(t, 'move-scan', 'C-R1-01-1-01');
    expect(enabled(t, 'move-submit'), isFalse); // 카트 아직
    await scan(t, 'move-scan', 'CRT-C-01');
    expect(enabled(t, 'move-submit'), isTrue);
    expect(t.takeException(), isNull);
    await tapKey(t, 'move-submit');

    // 2단계: 도착 칸.
    expect(find.byKey(const ValueKey('step-1')), findsOneWidget);
    expect((await t.runAsync(() => stockMove.move('MV-mock-1')))!.onCartQty, 6);
    await scan(t, 'move-scan', 'C-S1-02-2-05');
    await tapKey(t, 'move-submit');
    expect(find.byKey(const ValueKey('move-done')), findsOneWidget);
    expect(
      (await t.runAsync(() => stockMove.move('MV-mock-1')))!.state,
      MoveState.completed,
    );

    // 다음 작업 — 남은 이동·적치 없음.
    await tapKey(t, 'result-action');
    expect(find.text('지금 할 작업이 없어요. 잠시 뒤 다시 받아 주세요'), findsOneWidget);
  });

  testWidgets('적치: 품질검사가 만든 적치 작업 → 선반 스캔 → 나눠 놓기 → 다 놓으면 끝', (t) async {
    await t.runAsync(() async {
      // 보충을 끝내 두고, 품질검사로 적치 작업(정상 10개)을 만든다.
      await stockMove.pickUp(
        'MV-mock-1',
        cartLocation: 'CRT-C-01',
        qty: 6,
        key: IdempotencyKey('u'),
      );
      await stockMove.drop(
        'MV-mock-1',
        toLocation: 'C-S1-02-2-05',
        qty: 6,
        key: IdempotencyKey('d'),
      );
      await quality.inspect('TSK-INS-mock-1', const [
        InspectionResult(
          qty: 10,
          quarantined: false,
          sourceLotRef: 'L1',
          expiryDate: '2026-11-30',
        ),
        InspectionResult(qty: 2, quarantined: true),
      ], key: IdempotencyKey('i'));
    });
    await open(t, 'stockMove');
    expect(
      find.byKey(const ValueKey('assigned-TSK-PUT-mock-1')),
      findsOneWidget,
    );
    await tapKey(t, 'run-task');
    expect(find.text('놓을 수량 10개'), findsOneWidget);

    await scan(t, 'putaway-scan', 'nope');
    expect(find.byKey(const ValueKey('putaway-scan-error')), findsOneWidget);
    await scan(t, 'putaway-scan', 'C-S1-03-2-04');
    await setQty(t, 'putaway-qty', 6);
    await tapKey(t, 'putaway-submit');
    // 남은 4개 — 다른 칸으로.
    expect(find.text('놓을 수량 4개'), findsOneWidget);
    expect(enabled(t, 'putaway-submit'), isFalse); // 칸을 다시 찍어야
    await scan(t, 'putaway-scan', 'C-S1-03-2-05');
    await tapKey(t, 'putaway-submit');
    expect(find.byKey(const ValueKey('putaway-done')), findsOneWidget);
    expect(quality.task('TSK-PUT-mock-1')!.completed, isTrue);
  });

  testWidgets('재고 실사: 칸 확인 → 장부 없이 계수 → 확인 → 제출 → 다르면 다른 작업자 재계수', (t) async {
    await open(t, 'stockCount');
    expect(find.byKey(const ValueKey('assigned-CNT-mock-1')), findsOneWidget);
    await tapKey(t, 'run-task');

    // 1번 칸.
    await scan(t, 'count-loc-scan', 'C-S1-02-2-05');
    expect(find.byKey(const ValueKey('count-wrong-place')), findsOneWidget);
    await scan(t, 'count-loc-scan', 'A-S3-01-1-10');
    const a1 = 'A-S3-01-1-10|E-00000001|LOT-M-1022';
    const a2 = 'A-S3-01-1-10|E-00000005|LOT-C-0901';
    expect(
      t
          .widget<FilledButton>(find.byKey(const ValueKey('count-next')))
          .onPressed,
      isNull,
    ); // 다 세야
    await setQty(t, 'count-$a1', 8);
    await setQty(t, 'count-$a2', 12);
    expect(t.takeException(), isNull);
    await tapKey(t, 'count-next');

    // 2번 칸: 우유 7(장부 8과 다름), 과자 없음.
    await scan(t, 'count-loc-scan', 'C-S1-02-2-05');
    await setQty(t, 'count-C-S1-02-2-05|E-00000001|LOT-M-1022', 7);
    await tapKey(t, 'count-zero-C-S1-02-2-05|E-00000005|LOT-C-0901');
    await tapKey(t, 'count-next');

    expect(find.text('센 수량을 확인해 주세요'), findsOneWidget);
    await tapKey(t, 'count-submit');
    expect(
      find.byKey(const ValueKey('count-result-recountRequired')),
      findsOneWidget,
    );
    final s = await t.runAsync(() => count.session('M', 'CNT-mock-1'));
    expect(s!.state, CountState.recountRequired);
    expect(s.firstCounter, MockTaskRepository.workerId);

    // 같은 사람에게는 재계수를 주지 않는다.
    await tapKey(t, 'result-action');
    expect(find.text('지금 할 작업이 없어요. 잠시 뒤 다시 받아 주세요'), findsOneWidget);
  });

  testWidgets('피패킹: 폰 화면에서 서버가 준 패킹 → 이어서 패킹, 피킹 시작 → 피킹 화면(넘침 없음)', (t) async {
    await open(t, 'pickPack');
    expect(find.byKey(const ValueKey('assigned-task-mock-2')), findsOneWidget);
    await tapKey(t, 'run-task');
    await tapKey(t, 'continue-picking');
    expect(find.text('패킹'), findsOneWidget);
    expect(find.byKey(const ValueKey('pack-minutes')), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('assigned-task-mock-2')), findsOneWidget);
  });
}
