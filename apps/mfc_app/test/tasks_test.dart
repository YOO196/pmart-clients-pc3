import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:mfc_app/app.dart';
import 'package:mfc_app/features/tasks/data/mock_task_repository.dart';
import 'package:mfc_app/features/tasks/data/task_repository.dart';
import 'package:mfc_app/features/tasks/domain/task_list.dart';
import 'package:mfc_app/features/tasks/presentation/task_controllers.dart';
import 'package:mfc_app/shared/providers.dart';

List<Override> _base(MockTaskRepository repo, SecureKeyValueStore store) => [
  envProvider.overrideWithValue(PmartEnv.mock),
  taskRepositoryProvider.overrideWithValue(repo),
  secureStoreProvider.overrideWithValue(store),
];

Widget _app(MockTaskRepository repo, SecureKeyValueStore store) =>
    ProviderScope(
      retry: (_, _) => null,
      overrides: _base(repo, store),
      child: const MfcApp(),
    );

TaskRepository _repoWith(FakeAdapter adapter) => ApiTaskRepository(
  createPmartDio(
    baseUrl: 'http://test.invalid/api/v1',
    sourceSystem: sourceSystem,
    tokens: TokenStore(MemoryKeyValueStore()),
    refresher: (_) async => null,
    adapter: adapter,
    delay: (_) async {},
  ),
);

const _listBody = {
  'items': [
    {
      'taskId': 'task-mock-1',
      'taskType': 'PICK',
      'state': 'ASSIGNED',
      'remainingQty': 4,
    },
  ],
  'page': {'nextCursor': null, 'size': 50},
  'asOf': {'asOf': '2026-10-24T06:05:00Z', 'freshness': 'CURRENT'},
};

void main() {
  setUpAll(initPmartFormatting);

  group('연동', () {
    test('GET /tasks 에 mfcId·assignee=me 를 보내고 응답을 domain 으로 바꾼다', () async {
      final adapter = FakeAdapter(
        (_, _) async => const FakeReply(200, body: _listBody),
      );
      final list = await _repoWith(adapter).myTasks('MFC-MOCK-01');

      expect(list.tasks.single.state, TaskState.assigned);
      expect(list.assignmentFresh, isTrue);
      final uri = adapter.requests.single.uri;
      expect(uri.path, '/api/v1/tasks');
      expect(uri.queryParameters['assignee'], 'me');
      expect(adapter.requests.single.headers['X-Source-System'], 'mfc-app');
    });

    test('막힌 작업은 state=BLOCKED 로 따로 조회한다', () async {
      final adapter = FakeAdapter(
        (_, _) async => const FakeReply(200, body: _listBody),
      );
      await _repoWith(adapter).myTasks('MFC-MOCK-01', blocked: true);
      expect(adapter.requests.single.uri.queryParameters['state'], 'BLOCKED');
    });

    test('담당자 사본이 STALE 이면 최신 아님으로 표시한다', () async {
      final adapter = FakeAdapter(
        (_, _) async => FakeReply(
          200,
          body: {
            ..._listBody,
            'asOf': {'asOf': '2026-10-24T06:05:00Z', 'freshness': 'STALE'},
          },
        ),
      );
      expect(
        (await _repoWith(adapter).myTasks('MFC-MOCK-01')).assignmentFresh,
        isFalse,
      );
    });

    test('계약에 없는 작업 유형은 조용히 넘기지 않는다', () async {
      final adapter = FakeAdapter(
        (_, _) async => const FakeReply(
          200,
          body: {
            'items': [
              {'taskId': 't', 'taskType': 'LOAD', 'state': 'READY'},
            ],
          },
        ),
      );
      await expectLater(
        _repoWith(adapter).myTasks('MFC-MOCK-01'),
        throwsA(isA<ContractViolationFailure>()),
      );
    });

    Future<StartOutcome> start(FakeReply reply) =>
        _repoWith(FakeAdapter((_, _) async => reply)).start(
          'task-1',
          workerId: 'w',
          assignmentVersion: 2,
          key: IdempotencyKey('k-1'),
        );

    test('작업 시작 판정 분류(§3-1)', () async {
      expect(
        await start(
          FakeReply.problem(
            503,
            problemBody('DEPENDENCY_UNAVAILABLE', status: 503),
          ),
        ),
        isA<StartNotStarted>(),
        reason: '503 은 시작 안 됨 확정',
      );
      expect(
        await start(const FakeReply.transport(DioExceptionType.receiveTimeout)),
        isA<StartUnknown>(),
      );
      expect(
        await start(
          FakeReply.problem(
            409,
            problemBody('IDEMPOTENCY_CONFLICT', retryable: true),
          ),
        ),
        isA<StartUnknown>(),
        reason: '같은 키 앞선 요청 처리 중',
      );
      expect(
        await start(
          FakeReply.problem(409, problemBody('IDEMPOTENCY_CONFLICT')),
        ),
        isA<StartClientError>(),
      );
      expect(
        await start(FakeReply.problem(409, problemBody('ALREADY_STARTED'))),
        isA<StartRejected>().having((r) => r.code, 'code', 'ALREADY_STARTED'),
      );
    });

    test('실행 전송: 연결 불가는 전송 대기, 응답 없음은 확인 중, 본문에 배정 버전', () async {
      final item = QueueItem(
        id: 'k-9',
        kind: FieldCommandKind.pickExecution,
        targetId: 'task-1',
        payload: pickPayload(
          workerId: 'w',
          assignmentVersion: 2,
          line: const TaskLineView(
            taskLineId: 'tl',
            orderLineId: 'ol-1',
            sku: 'E-00000001',
            plannedQty: 2,
            completedQty: 0,
            cancelledQty: 0,
            remainingQty: 2,
          ),
          pickedQty: 2,
        ),
        state: QueueItemState.queued,
        createdAt: DateTime.utc(2026),
      );
      var i = 0;
      final adapter = FakeAdapter((_, _) async {
        i++;
        return switch (i) {
          1 => const FakeReply.transport(DioExceptionType.connectionError),
          2 => const FakeReply.transport(DioExceptionType.receiveTimeout),
          _ => const FakeReply(
            202,
            body: {
              'status': 'ACCEPTED',
              'requestId': 'k-9',
              'resultId': 'exe-1',
            },
          ),
        };
      });
      final repo = _repoWith(adapter);

      expect(await repo.sendExecution(item), isA<SendOffline>());
      expect(await repo.sendExecution(item), isA<SendUnknown>());
      expect(
        await repo.sendExecution(item),
        isA<SendAccepted>().having((a) => a.resultId, 'resultId', 'exe-1'),
      );
      final req = adapter.requests.last;
      expect(req.headers['Idempotency-Key'], 'k-9');
      expect(req.headers.containsKey('X-Expected-Version'), isFalse);
      final body = jsonDecode(req.data as String) as Map<String, dynamic>;
      expect(body['assignmentVersion'], 2);
      expect((body['lines'] as List).single['pickedQty'], 2);
    });
  });

  group('시작·피킹', () {
    late MockTaskRepository repo;
    late MemoryKeyValueStore store;
    late ProviderContainer c;

    setUp(() {
      repo = MockTaskRepository(latency: Duration.zero);
      store = MemoryKeyValueStore();
      c = ProviderContainer(
        retry: (_, _) => null,
        overrides: _base(repo, store),
      );
      addTearDown(c.dispose);
    });

    Future<TaskDetailView> detail(String id) =>
        c.read(taskDetailProvider(id).future);

    Future<StartFlow> startTask(String id) async {
      final p = startFlowProvider(id);
      c.listen(p, (_, _) {});
      await c.read(p.notifier).start(await detail(id));
      return c.read(p);
    }

    test('시작 응답을 잃어도 같은 키 재전송으로 시작 확정을 받는다', () async {
      repo.loseNextStartResponse = true;
      final flow = await startTask('task-mock-1');

      expect(flow.phase, StartPhase.applied);
      expect(repo.taskJson('task-mock-1')['state'], 'IN_PROGRESS');
    });

    test('503 은 시작 안 됨 확정이고, 다시 시도는 같은 키로 판정받는다', () async {
      repo.startUnavailable = 1;
      expect((await startTask('task-mock-1')).phase, StartPhase.notStarted);
      expect(repo.taskJson('task-mock-1')['state'], 'ASSIGNED');

      await c
          .read(startFlowProvider('task-mock-1').notifier)
          .start(await detail('task-mock-1'));
      expect(
        c.read(startFlowProvider('task-mock-1')).phase,
        StartPhase.applied,
      );
    });

    test('다른 작업자가 먼저 시작했으면 거절이 확정된다', () async {
      final flow = await startTask('task-mock-4');
      expect(flow.phase, StartPhase.rejected);
      expect(flow.rejectCode, TaskProblemCode.alreadyStarted);
    });

    Future<PickingController> startedPicking() async {
      await startTask('task-mock-1');
      final p = pickingProvider('task-mock-1');
      c
        ..listen(p, (_, _) {})
        ..listen(taskQueueProvider('task-mock-1'), (_, _) {});
      return c.read(p.notifier);
    }

    test('다른 상품·잔량 초과 스캔은 실적에 넣지 않는다', () async {
      final pick = await startedPicking();
      final task = await detail('task-mock-1');

      expect(
        pick.scan(task, MockTaskRepository.milkBarcode),
        ScanResult.wrongItem,
      );
      expect(
        pick.scan(task, MockTaskRepository.yogurtBarcode),
        ScanResult.matched,
      );
      // 요거트 지시 1개를 이미 채웠다. 또 찍으면 잔량 초과다.
      expect(
        pick.scan(task, MockTaskRepository.yogurtBarcode),
        ScanResult.overRemaining,
      );
      expect(c.read(pickingProvider('task-mock-1')).capturedFor('ol-1'), 1);
    });

    test('보낸 실적은 확정 대기 → 재고 반영 확정 뒤에만 완료 수량이 된다', () async {
      repo.confirmPolls = 2;
      final pick = await startedPicking();
      final task = await detail('task-mock-1');
      pick.scan(task, MockTaskRepository.yogurtBarcode);

      await pick.submitLine(task, task.lines.first);

      var items = await c.read(fieldQueueProvider).items();
      expect(items.single.state, QueueItemState.awaitingConfirm);
      var line = (await detail('task-mock-1')).lines.first;
      expect(line.completedQty, 0);
      expect(line.pendingQty, 1);

      await pick.sync();

      items = await c.read(fieldQueueProvider).items();
      expect(items.single.state, QueueItemState.applied);
      line = (await detail('task-mock-1')).lines.first;
      expect(line.completedQty, 1);
      expect(line.remainingQty, 0);
    });

    test('오프라인 실적은 저장됐다가 연결되면 같은 키로 보낸다(앱을 다시 켜도 남는다)', () async {
      repo.offline = true;
      final pick = await startedPicking();
      final task = await detail('task-mock-1');
      pick.scan(task, MockTaskRepository.yogurtBarcode);
      await pick.submitLine(task, task.lines.first);

      final saved = await FieldQueue(store, name: 'mfc').items();
      expect(saved.single.state, QueueItemState.queued);

      repo.offline = false;
      await pick.sync();

      expect(repo.sentExecutionKeys, [saved.single.id, saved.single.id]);
      expect(
        (await c.read(fieldQueueProvider).items()).single.state,
        QueueItemState.applied,
      );
    });

    test('실행 결과를 모르면 확인 중이고, 같은 키 재전송으로 한 번만 반영된다', () async {
      repo.loseNextExecutionResponse = true;
      final pick = await startedPicking();
      final task = await detail('task-mock-1');
      pick.scan(task, MockTaskRepository.yogurtBarcode);
      await pick.submitLine(task, task.lines.first);

      expect(
        (await c.read(fieldQueueProvider).items()).single.state,
        QueueItemState.checking,
      );

      await pick.sync();
      await pick.sync();

      final items = await c.read(fieldQueueProvider).items();
      expect(items.single.state, QueueItemState.applied);
      expect((await detail('task-mock-1')).lines.first.completedQty, 1);
    });

    test('재배정 뒤 옛 배정 버전의 실적은 거절된다', () async {
      final pick = await startedPicking();
      final task = await detail('task-mock-1');
      pick.scan(task, MockTaskRepository.yogurtBarcode);
      (repo.taskJson('task-mock-1')['assignment']!
              as Map)['assignmentVersion'] =
          3;

      await pick.submitLine(task, task.lines.first);

      final item = (await c.read(fieldQueueProvider).items()).single;
      expect(item.state, QueueItemState.rejected);
      expect(item.rejectCode, TaskProblemCode.versionConflict);
    });

    test('결품 보고는 실적 0 + 부족 수량으로 보내고 작업이 막힌다', () async {
      final pick = await startedPicking();
      final task = await detail('task-mock-1');

      await pick.submitLine(
        task,
        task.lines.first,
        shortage: (qty: 1, reason: ShortageReason.short, note: null),
      );
      await pick.sync();

      expect(repo.taskJson('task-mock-1')['state'], 'BLOCKED');
    });
  });

  testWidgets('작업 목록 → 시작 확정 → 피킹 스캔 → 실적 전송 상태', (t) async {
    t.view
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = MockTaskRepository(latency: Duration.zero)..confirmPolls = 2;
    await t.pumpWidget(_app(repo, MemoryKeyValueStore()));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('task-task-mock-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-task-mock-3')), findsNothing);
    await t.tap(find.text('막힌 작업'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-task-mock-3')), findsOneWidget);
    await t.tap(
      find.descendant(
        of: find.byType(SegmentedButton<bool>),
        matching: find.text('내 작업'),
      ),
    );
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('task-task-mock-1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('start')));
    await t.pumpAndSettle();

    expect(find.text('피킹'), findsOneWidget);
    await t.enterText(
      find.byKey(const ValueKey('scan-field')),
      MockTaskRepository.milkBarcode,
    );
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(find.byKey(const ValueKey('scan-error')), findsOneWidget);

    await t.enterText(
      find.byKey(const ValueKey('scan-field')),
      MockTaskRepository.yogurtBarcode,
    );
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(find.textContaining('이번 스캔 1'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('line-done')));
    await t.pumpAndSettle();
    expect(find.text('확정 대기'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('sync')));
    await t.pumpAndSettle();
    expect(find.text('반영'), findsOneWidget);
    expect(find.textContaining('확정 1 / 지시 4'), findsOneWidget);
  });

  testWidgets('결과 불명인 실적이 있으면 다시 집지 말라고 안내한다', (t) async {
    t.view
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = MockTaskRepository(latency: Duration.zero)
      ..loseNextExecutionResponse = true;
    await t.pumpWidget(_app(repo, MemoryKeyValueStore()));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('task-task-mock-1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('start')));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('scan-field')),
      MockTaskRepository.yogurtBarcode,
    );
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    await t.tap(find.byKey(const ValueKey('line-done')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('do-not-redo')), findsOneWidget);
    expect(find.text('확인 중'), findsOneWidget);
  });
}
