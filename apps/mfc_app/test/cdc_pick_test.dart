import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_api_cdc_outbound/pmart_api_cdc_outbound.dart' as co;
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:mfc_app/app.dart';
import 'package:mfc_app/features/auth/data/auth_repository.dart';
import 'package:mfc_app/features/auth/domain/employee_auth.dart';
import 'package:mfc_app/features/auth/presentation/auth_controller.dart';
import 'package:mfc_app/features/cdc/data/cdc_task_repository.dart';
import 'package:mfc_app/features/cdc/domain/cdc_task.dart';
import 'package:mfc_app/features/cdc/presentation/cdc_pick_screen.dart';
import 'package:mfc_app/shared/field_widgets.dart';
import 'package:mfc_app/shared/providers.dart';

const _worker = EmployeeSession(
  operatorId: 'OP-cdcw-fc-01',
  roles: [EmployeeSession.cdcWorkerRole],
  centers: ['CDC01'],
);

Dio _dio(FakeAdapter a) => createPmartDio(
  baseUrl: 'http://test.invalid/api/v1',
  sourceSystem: sourceSystem,
  tokens: TokenStore(MemoryKeyValueStore()),
  refresher: (_) async => null,
  adapter: a,
  delay: (_) async {},
);

Map<String, Object?> _taskJson(String state, {int picked = 0, int short = 0}) =>
    {
      'taskId': 'CTK-1',
      'taskNumber': 'T001',
      'kind': 'PICK',
      'state': state,
      'version': 3,
      'lines': [
        {
          'sku': 'SKU-1001',
          'lot': 'L1',
          'locationCode': 'CDC01-C-5-61-03-2-1',
          'plannedQty': 10,
          'pickedQty': picked,
          'shortQty': short,
        },
      ],
    };

void main() {
  setUpAll(initPmartFormatting);

  Future<MockCdcTaskRepository> pump(
    WidgetTester t, {
    Future<void> Function(MockCdcTaskRepository)? before,
  }) async {
    t.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = MockCdcTaskRepository(latency: Duration.zero);
    await before?.call(repo);
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          envProvider.overrideWithValue(PmartEnv.mock),
          authRepositoryProvider.overrideWithValue(
            MockAuthRepository(session: _worker),
          ),
          cdcTaskRepositoryProvider.overrideWithValue(repo),
          secureStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        ],
        child: const MfcApp(),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('cdc-area-pick')));
    await t.pumpAndSettle();
    return repo;
  }

  Future<void> tap(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(ValueKey(key)));
    await t.tap(find.byKey(ValueKey(key)));
    await t.pumpAndSettle();
  }

  Future<void> scan(WidgetTester t, String id, String code) async {
    await t.enterText(find.byKey(ValueKey(id)), code);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
  }

  Future<void> setQty(WidgetTester t, String n) async {
    await t.enterText(find.byKey(const ValueKey('cdc-pick-qty')), n);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
  }

  testWidgets('안내 → 작업 받기 → 위치 스캔 → 상품 스캔·수량 → 다 차면 보내고 서버가 끝내면 완료 → 다음 작업', (
    t,
  ) async {
    await pump(t);
    expect(find.byKey(const ValueKey('cdc-guide')), findsOneWidget);
    await tap(t, 'cdc-guide-ok');
    // 받자마자 착수 — 첫 줄 위치
    expect(find.textContaining('T261126001'), findsOneWidget);
    expect(find.byKey(const ValueKey('step-0')), findsOneWidget);
    // 피킹 방식마다 담는 곳 안내(C-01) — DPS 는 불 켜진 칸
    expect(find.text('DPS — 불 켜진 칸에서 숫자만큼 집어요'), findsOneWidget);
    await scan(t, 'cdc-loc-scan', 'CDC01-Z-9-99-99-9-9');
    expect(find.byKey(const ValueKey('cdc-scan-error')), findsOneWidget);
    await scan(t, 'cdc-loc-scan', 'CDC01-C-5-61-03-2-1');
    expect(find.byKey(const ValueKey('step-1')), findsOneWidget);
    await scan(t, 'cdc-item-scan', 'SKU-9999');
    expect(find.text('이 상품이 아니에요. 화면의 상품을 스캔하세요'), findsOneWidget);
    await scan(t, 'cdc-item-scan', 'SKU-1001');
    expect(find.text('집음 1'), findsOneWidget);
    await setQty(t, '24');
    // 다음 줄은 다시 위치부터
    expect(find.byKey(const ValueKey('step-0')), findsOneWidget);
    await scan(t, 'cdc-loc-scan', 'CDC01-C-5-61-04-1-2');
    await scan(t, 'cdc-item-scan', 'SKU-1002');
    await setQty(t, '12');
    expect(find.byKey(const ValueKey('cdc-done')), findsOneWidget);
    expect(find.byKey(const ValueKey('done-title')), findsOneWidget);
    // 피킹이 끝나면 10초 뒤 분배·패킹으로 — 다음 피킹을 저절로 받지 않는다
    expect(find.text('10초 뒤 분배·패킹으로 가요'), findsOneWidget);
    await t.pump(const Duration(seconds: 11));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('cdc-done')), findsNothing);
    expect(find.text('분배·패킹'), findsWidgets);
    // 다음 피킹은 홈의 피킹에서
    GoRouter.of(t.element(find.byType(Scaffold).first)).go('/');
    await t.pumpAndSettle();
    await tap(t, 'cdc-area-pick');
    await tap(t, 'cdc-guide-ok');
    expect(find.textContaining('T261126002'), findsOneWidget);
    expect(
      find.text('라인용 — 상품 박스에 Wave 안 모든 MFC 몫을 담아요(라인에서 나눠요)'),
      findsOneWidget,
    );
    await scan(t, 'cdc-loc-scan', 'CDC01-G-5-63-01-3-1');
    await scan(t, 'cdc-item-scan', 'SKU-2001');
    await setQty(t, '6');
    await tap(t, 'result-action');
    GoRouter.of(t.element(find.byType(Scaffold).first)).go('/');
    await t.pumpAndSettle();
    await tap(t, 'cdc-area-pick');
    await tap(t, 'cdc-guide-ok');
    // 지역 묶음 — 지역 카트 바코드부터
    expect(find.textContaining('T261126003'), findsOneWidget);
    expect(find.text('지역 카트 바코드를 스캔하세요'), findsOneWidget);
    await scan(t, 'cdc-region-scan', 'SEOUL');
    expect(find.text('이 작업 지역의 카트가 아니에요.'), findsOneWidget);
    await scan(t, 'cdc-region-scan', 'JEONNAM');
    expect(find.byKey(const ValueKey('cdc-pick-location')), findsOneWidget);
  });

  testWidgets('틀린 스캔: 문구는 스캔 칸 바로 위(아래 고정 칸), 스캔 칸은 빨갛게 빛나고 흔들린다', (t) async {
    await pump(t);
    await tap(t, 'cdc-guide-ok');
    await t.enterText(
      find.byKey(const ValueKey('cdc-loc-scan')),
      'CDC01-Z-9-99-99-9-9',
    );
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump(const Duration(milliseconds: 100));
    final box = t.widget<DecoratedBox>(
      find.byKey(const ValueKey('cdc-loc-scan-flash')),
    );
    final border = (box.decoration as BoxDecoration).border! as Border;
    expect(border.top.color.a, greaterThan(0));
    expect(border.top.color.r, greaterThan(border.top.color.g)); // 빨강 쪽
    await t.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(ActionBar),
        matching: find.byKey(const ValueKey('cdc-scan-error')),
      ),
      findsOneWidget,
    );
    // 맞는 스캔은 초록으로
    await t.enterText(
      find.byKey(const ValueKey('cdc-loc-scan')),
      'CDC01-C-5-61-03-2-1',
    );
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump(const Duration(milliseconds: 50));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('cdc-scan-error')), findsNothing);
  });

  testWidgets('부족 보고 — 큰 사유 칸을 고르면 그 줄은 끝, 완료 화면에 부족 수', (t) async {
    await pump(t);
    await tap(t, 'cdc-guide-ok');
    await scan(t, 'cdc-loc-scan', 'CDC01-C-5-61-03-2-1');
    await scan(t, 'cdc-item-scan', 'SKU-1001');
    await setQty(t, '20');
    await tap(t, 'cdc-short');
    expect(find.text('4개가 모자라요 — 사유를 고르세요'), findsOneWidget);
    await tap(t, 'cdc-short-NOT_FOUND');
    await scan(t, 'cdc-loc-scan', 'CDC01-C-5-61-04-1-2');
    await tap(t, 'cdc-short');
    await tap(t, 'cdc-short-DAMAGED');
    expect(find.byKey(const ValueKey('cdc-done')), findsOneWidget);
    expect(find.textContaining('부족 16개'), findsOneWidget);
  });

  testWidgets('받을 작업이 없으면 안내하고 다시 받기', (t) async {
    await pump(
      t,
      before: (repo) async {
        for (var i = 0; i < 3; i++) {
          await repo.nextPick(
            cdcId: 'CDC01',
            workerId: 'OP-other-$i',
            key: IdempotencyKey.generate(),
          );
        }
      },
    );
    await tap(t, 'cdc-guide-ok');
    expect(find.byKey(const ValueKey('cdc-no-task')), findsOneWidget);
    expect(find.byKey(const ValueKey('cdc-pull')), findsOneWidget);
  });

  testWidgets('들고 있던 작업이 있으면 그 작업을 이어서 — 위치 단계부터', (t) async {
    await pump(
      t,
      before: (repo) async {
        final r = await repo.nextPick(
          cdcId: 'CDC01',
          workerId: _worker.operatorId,
          key: IdempotencyKey.generate(),
        );
        await repo.start(
          cdcId: 'CDC01',
          task: (r as CdcGotTask).task,
          key: IdempotencyKey.generate(),
        );
      },
    );
    await tap(t, 'cdc-guide-ok');
    expect(find.textContaining('T261126001'), findsOneWidget);
    expect(find.byKey(const ValueKey('cdc-pick-location')), findsOneWidget);
  });

  group('실서버 요청(cdc-outbound)', () {
    test(
      '다음 작업 받기: 경로·kind PICK·멱등 키, 409 NO_TASK_AVAILABLE 은 작업 없음',
      () async {
        final a = FakeAdapter(
          (_, i) async => i == 0
              ? FakeReply(201, body: _taskJson('ACCEPTED'))
              : const FakeReply(
                  409,
                  contentType: 'application/problem+json',
                  body: {
                    'status': 409,
                    'code': 'NO_TASK_AVAILABLE',
                    'type': 'about:blank',
                  },
                ),
        );
        final repo = ApiCdcTaskRepository(_dio(a));
        final key = IdempotencyKey.generate();
        final r = await repo.nextPick(
          cdcId: 'CDC01',
          workerId: 'OP-1',
          key: key,
        );
        expect((r as CdcGotTask).task.accepted, isTrue);
        final o = a.requests.first;
        expect(o.path, endsWith('/cdcs/CDC01/workers/OP-1/next-tasks'));
        expect(o.headers['Idempotency-Key'], key.value);
        expect(o.headers['X-Source-System'], 'mfc-app');
        expect(jsonDecode(o.data as String), {'kind': 'PICK'});
        expect(
          await repo.nextPick(
            cdcId: 'CDC01',
            workerId: 'OP-1',
            key: IdempotencyKey.generate(),
          ),
          isA<CdcNoTask>(),
        );
      },
    );

    test(
      '피킹 결과: X-Expected-Version·줄(SKU·LOT·위치)·부족 사유, 202 는 접수일 뿐',
      () async {
        final a = FakeAdapter(
          (_, _) async => const FakeReply(
            202,
            body: {'requestId': 'r-1', 'status': 'ACCEPTED'},
          ),
        );
        final repo = ApiCdcTaskRepository(_dio(a));
        final task = cdcTaskFromContract(
          co.Task.fromJson(_taskJson('IN_PROGRESS')),
        );
        await repo.reportPick(
          cdcId: 'CDC01',
          task: task,
          workerId: 'OP-1',
          lines: [
            CdcPickLine(
              line: task.lines.single,
              pickedQty: 7,
              shortQty: 3,
              shortReason: 'DAMAGED',
            ),
          ],
          key: IdempotencyKey.generate(),
        );
        final o = a.requests.single;
        expect(o.path, endsWith('/cdcs/CDC01/tasks/CTK-1/pick-results'));
        expect(o.headers['X-Expected-Version'], '3');
        expect(jsonDecode(o.data as String), {
          'workerId': 'OP-1',
          'lines': [
            {
              'sku': 'SKU-1001',
              'lot': 'L1',
              'locationCode': 'CDC01-C-5-61-03-2-1',
              'pickedQty': 7,
              'shortQty': 3,
              'shortReason': 'DAMAGED',
            },
          ],
        });
      },
    );
  });
}
