import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
          'locationCode': 'CDC01-C-5-12-03-0-1',
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

  testWidgets('작업 받기 → 시작 → 전량 피킹 → 서버가 끝냈다고 하면 끝', (t) async {
    await pump(t);
    expect(find.text('T261126001'), findsOneWidget);
    expect(find.byKey(const ValueKey('cdc-start')), findsOneWidget);
    await tap(t, 'cdc-start');
    // 기본값은 남은 수량 전부
    expect(find.byKey(const ValueKey('cdc-picked-SKU-1001')), findsOneWidget);
    await tap(t, 'cdc-report');
    expect(find.byKey(const ValueKey('cdc-done')), findsOneWidget);
    expect(find.text('작업이 끝났어요.'), findsOneWidget);
    expect(find.text('계획 24 · 집음 24 · 부족 0'), findsOneWidget);
    // 다음 작업
    await tap(t, 'cdc-pull');
    expect(find.text('T261126002'), findsOneWidget);
  });

  testWidgets('부족이 있으면 사유를 골라야 보낼 수 있고, 끝나면 부족 수를 보인다', (t) async {
    await pump(t);
    await tap(t, 'cdc-start');
    await t.enterText(find.byKey(const ValueKey('cdc-picked-SKU-1001')), '20');
    await t.pumpAndSettle();
    final report = find.byKey(const ValueKey('cdc-report'));
    expect(t.widget<FilledButton>(report).onPressed, isNull);
    await t.ensureVisible(find.byKey(const ValueKey('cdc-reason-SKU-1001')));
    await t.tap(find.byKey(const ValueKey('cdc-reason-SKU-1001')));
    await t.pumpAndSettle();
    await t.tap(find.text('못 찾음').last);
    await t.pumpAndSettle();
    expect(t.widget<FilledButton>(report).onPressed, isNotNull);
    await tap(t, 'cdc-report');
    expect(find.textContaining('부족 4개'), findsOneWidget);
  });

  testWidgets('받을 작업이 없으면 안내하고, 다시 받기를 누를 수 있다', (t) async {
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
    expect(find.byKey(const ValueKey('cdc-no-task')), findsOneWidget);
    expect(find.byKey(const ValueKey('cdc-pull')), findsOneWidget);
  });

  testWidgets('들고 있던 작업이 있으면 들어올 때 그 작업을 이어서 보인다', (t) async {
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
    expect(find.text('T261126001'), findsOneWidget);
    expect(find.byKey(const ValueKey('cdc-report')), findsOneWidget);
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
              'locationCode': 'CDC01-C-5-12-03-0-1',
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
