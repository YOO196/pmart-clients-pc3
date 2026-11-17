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

import 'support.dart';

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

Future<void> scanTo(WidgetTester t, String id, String code) async {
  await t.enterText(find.byKey(ValueKey(id)), code);
  await t.testTextInput.receiveAction(TextInputAction.done);
  await t.pumpAndSettle();
}

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
          toLocation: 'CRT-A-01',
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
      expect(body['toLocation'], 'CRT-A-01', reason: '집품 도착지 = 장바구니');
    });

    test(
      '실행 전송: 재고가 거절(REJECTED)하면 실행을 한 번 조회해 거절 코드(E1) — 조회가 안 되면 일반 거절',
      () async {
        QueueItem item() => QueueItem(
          id: 'k-r',
          kind: FieldCommandKind.pickExecution,
          targetId: 'task-1',
          payload: const {'workerId': 'w', 'lines': []},
          state: QueueItemState.queued,
          createdAt: DateTime.utc(2026),
        );
        const rejected = FakeReply(
          202,
          body: {
            'status': 'REJECTED',
            'requestId': 'k-r',
            'resultId': 'exe-r',
            'nextAction': 'QUERY_RESULT',
          },
        );
        final adapter = FakeAdapter((o, _) async {
          if (o.method == 'POST') return rejected;
          return const FakeReply(
            200,
            body: {
              'executionId': 'exe-r',
              'taskId': 'task-1',
              'state': 'REJECTED',
              'rejectCode': 'LOT_MISMATCH',
              'rejectReason': '지시 LOT 이 아닙니다',
            },
          );
        });
        expect(
          await _repoWith(adapter).sendExecution(item()),
          isA<SendRejected>().having(
            (r) => r.code,
            'code',
            TaskProblemCode.lotMismatch,
          ),
        );
        expect(
          adapter.requests.last.uri.path,
          '/api/v1/tasks/task-1/executions/exe-r',
        );

        final failing = FakeAdapter((o, _) async {
          if (o.method == 'POST') return rejected;
          return const FakeReply.transport(DioExceptionType.receiveTimeout);
        });
        expect(
          await _repoWith(failing).sendExecution(item()),
          isA<SendRejected>().having(
            (r) => r.code,
            'code',
            ProblemCode.domainRejected,
          ),
        );
      },
    );

    test('거절 칸: 옛 기록(REJECTED)·빈 코드는 일반 거절, 서버 문장은 그대로', () {
      expect(
        executionRejectOf('REJECTED', null).code,
        ProblemCode.domainRejected,
      );
      expect(executionRejectOf(' ', ' ').reason, isNull);
      final r = executionRejectOf('INSUFFICIENT_STOCK', ' 재고 부족 ');
      expect(r.code, 'INSUFFICIENT_STOCK');
      expect(r.reason, '재고 부족');
    });

    test('실행 전송: 장바구니 없음 400·다른 장바구니 409 는 거절(코드 그대로)', () async {
      Future<SendResult> send(FakeReply reply) =>
          _repoWith(FakeAdapter((_, _) async => reply)).sendExecution(
            QueueItem(
              id: 'k-1',
              kind: FieldCommandKind.pickExecution,
              targetId: 'task-1',
              payload: const {'workerId': 'w', 'lines': []},
              state: QueueItemState.queued,
              createdAt: DateTime.utc(2026),
            ),
          );
      expect(
        await send(FakeReply.problem(400, problemBody('TO_LOCATION_REQUIRED'))),
        isA<SendRejected>().having(
          (r) => r.code,
          'code',
          TaskProblemCode.toLocationRequired,
        ),
      );
      expect(
        await send(FakeReply.problem(409, problemBody('CART_MISMATCH'))),
        isA<SendRejected>().having(
          (r) => r.code,
          'code',
          TaskProblemCode.cartMismatch,
        ),
      );
    });
  });

  test(
    '다음 칸은 서버 방문 순서(visitSeq) — 한 줄의 조각 사이에 다른 줄이 끼면 그 줄 먼저(시뮬레이터 바코드 판과 같게)',
    () {
      PickInstruction piece(
        String lot,
        int seq,
        String loc, {
        bool done = false,
      }) => PickInstruction(
        lotId: lot,
        remainingQty: done ? 0 : 1,
        visitSeq: seq,
        status: done ? PickStatus.done : PickStatus.ok,
        locations: [
          PickLocation(code: loc, qty: 5, allocatedQty: done ? 0 : 1),
        ],
      );
      TaskLineView line(String id, List<PickInstruction> picks) => TaskLineView(
        taskLineId: 'tl-$id',
        orderLineId: id,
        sku: 'E-0000000$id',
        plannedQty: picks.length,
        completedQty: 0,
        cancelledQty: 0,
        remainingQty: picks.where((p) => p.status != PickStatus.done).length,
        picks: picks,
      );
      TaskDetailView task(List<TaskLineView> lines) => TaskDetailView(
        taskId: 't',
        kind: TaskKind.pick,
        state: TaskState.inProgress,
        version: 1,
        lines: lines,
      );
      // 줄 1: 1번째·3번째 칸, 줄 2: 2번째 칸.
      final first = task([
        line('1', [
          piece('L1', 1, 'C-B1-01-1-01'),
          piece('L2', 3, 'C-B3-01-1-01'),
        ]),
        line('2', [piece('L3', 2, 'C-B2-06-3-01')]),
      ]);
      expect(nextPickStop(first)!.location, 'C-B1-01-1-01');
      final second = task([
        line('1', [
          piece('L1', 1, 'C-B1-01-1-01', done: true),
          piece('L2', 3, 'C-B3-01-1-01'),
        ]),
        line('2', [piece('L3', 2, 'C-B2-06-3-01')]),
      ]);
      final s = nextPickStop(second)!;
      expect(s.location, 'C-B2-06-3-01');
      expect(s.line.orderLineId, '2');
      expect(s.lotId, 'L3');
    },
  );

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
      final ctl = c.read(p.notifier);
      ctl.scanCart('CRT-C-01');
      return ctl;
    }

    /// 지금 칸(요거트 C-S1-01-1-01)을 확인한 피킹.
    Future<(PickingController, TaskDetailView)> atStop() async {
      final pick = await startedPicking();
      final task = await detail('task-mock-1');
      expect(pick.scanLocation(task, 'C-S1-01-1-01'), PickLocScan.ok);
      return (pick, task);
    }

    test('칸을 먼저 — 칸 확인 전 상품 스캔·다른 칸은 받지 않는다', () async {
      final pick = await startedPicking();
      final task = await detail('task-mock-1');
      expect(
        pick.scan(task, MockTaskRepository.yogurtBarcode),
        ScanResult.needLocation,
      );
      expect(
        pick.scanLocation(task, 'C-S1-02-2-05'),
        PickLocScan.wrongPlace,
        reason: '우유 칸 — 지금은 요거트 칸',
      );
      expect(pick.scanLocation(task, 'hello'), PickLocScan.notLocation);
      expect(pick.scanLocation(task, 'C-S1-01-1-01'), PickLocScan.ok);
    });

    test('칸 몫을 다 담으면 바로 보낸다 — 실행 본문은 스캔한 칸·지시 LOT, 다음 칸으로', () async {
      final (pick, task) = await atStop();
      pick.scan(task, MockTaskRepository.yogurtBarcode);
      await pick.submitIfFull(task);
      await pick.sync();

      final sent = repo.sentPayloads.single;
      expect(sent['fromLocation'], 'C-S1-01-1-01');
      expect(sent['toLocation'], 'CRT-C-01', reason: '집품 도착지 = 찍은 장바구니(0.8.0)');
      expect((sent['lines']! as List).single['lotId'], 'LOT-Y-1024');

      // 다음은 우유 — 배정 칸 C-S1-02-2-05 에서 1개, 같은 LOT 다른 칸 안내.
      final next = nextPickStop(await detail('task-mock-1'))!;
      expect(next.line.orderLineId, 'ol-2');
      expect(next.location, 'C-S1-02-2-05');
      expect(next.qty, 1);
      expect(next.otherLocations, ['C-S2-04-1-10']);
      expect(c.read(pickingProvider('task-mock-1')).at, isNull);
    });

    test('수량: 첫 개는 스캔, 그다음 스캔·+·수기 — 지시 수량에 닿으면 보낸다', () async {
      // 요거트 줄을 3개로(이 시험만).
      final line =
          ((repo.taskJson('task-mock-1')['lines']! as List).first
              as Map<String, Object?>);
      line['plannedQty'] = 3;
      line['remainingQty'] = 3;
      final pickJson = (line['picks']! as List).first as Map<String, Object?>;
      pickJson['remainingQty'] = 3;
      ((pickJson['locations']! as List).first
              as Map<String, Object?>)['allocatedQty'] =
          3;
      final (pick, task) = await atStop();
      final state = pickingProvider('task-mock-1');
      expect(nextPickStop(task)!.qty, 3);

      await pick.setCount(task, 2);
      expect(c.read(state).capturedFor('ol-1'), 0, reason: '첫 개는 스캔해야');

      expect(
        pick.scan(task, MockTaskRepository.yogurtBarcode),
        ScanResult.matched,
      );
      expect(c.read(state).capturedFor('ol-1'), 1);
      await pick.addOne(task);
      expect(c.read(state).capturedFor('ol-1'), 2);
      await pick.setCount(task, 0);
      expect(c.read(state).capturedFor('ol-1'), 1, reason: '1 아래로는 안 간다');
      expect(repo.sentPayloads, isEmpty);

      await pick.setCount(task, 99); // 최대 3으로 맞춰지고 다 찼으니 보낸다
      await pick.sync();
      expect(
        (repo.sentPayloads.single['lines']! as List).single['pickedQty'],
        3,
      );
    });

    test('칸 몫을 채운 뒤 같은 상품을 또 찍으면 수량 초과 안내만 — 칸 단계로 튕기지 않는다', () async {
      final (pick, task) = await atStop();
      expect(
        pick.scan(task, MockTaskRepository.yogurtBarcode),
        ScanResult.matched,
      );
      await pick.submitIfFull(task);
      await pick.sync();
      final after = await detail('task-mock-1');

      // 카메라 중복 인식·스캐너 연타 — 상품 스캔 자리로 와도, 칸 스캔 자리로 와도 "수량 초과".
      expect(
        pick.scan(after, MockTaskRepository.yogurtBarcode),
        ScanResult.overRemaining,
      );
      expect(
        pick.scanLocation(after, MockTaskRepository.yogurtBarcode),
        PickLocScan.overScan,
      );
      expect(repo.sentPayloads, hasLength(1), reason: '실적은 한 번만');

      // 다음 칸을 찍으면 평소대로.
      expect(pick.scanLocation(after, 'C-S1-02-2-05'), PickLocScan.ok);
      expect(c.read(pickingProvider('task-mock-1')).lastDoneLine, isNull);
    });

    test('상품 바코드가 여럿이면 어느 것을 찍어도 같은 상품(점포 299…)', () async {
      final (pick, task) = await atStop();
      expect(
        pick.scan(task, MockTaskRepository.yogurtStoreBarcode),
        ScanResult.matched,
      );
      expect(pick.scan(task, '0000000000000'), ScanResult.wrongItem);
    });

    test('장바구니를 안 찍고 보낸 실적은 목도 실서버처럼 거절 — 화면에 사유', () async {
      await startTask('task-mock-1');
      final res = await repo.sendExecution(
        QueueItem(
          id: 'k-no-cart',
          kind: FieldCommandKind.pickExecution,
          targetId: 'task-mock-1',
          payload: const {
            'workerId': 'w',
            'assignmentVersion': 2,
            'fromLocation': 'C-S1-01-1-01',
            'lines': [
              {'orderLineId': 'ol-1', 'sku': 'E-00000002', 'pickedQty': 1},
            ],
          },
          state: QueueItemState.queued,
          createdAt: DateTime.utc(2026),
        ),
      );
      expect(
        res,
        isA<SendRejected>().having(
          (r) => r.code,
          'code',
          TaskProblemCode.toLocationRequired,
        ),
      );
    });

    test('우유: 배정 칸 1개를 집으면 남은 1개는 같은 LOT 의 다른 칸으로 지시가 바뀐다', () async {
      final pick = await startedPicking();
      var task = await detail('task-mock-1');
      pick.scanLocation(task, 'C-S1-01-1-01');
      pick.scan(task, MockTaskRepository.yogurtBarcode);
      await pick.submitIfFull(task);
      await pick.sync();
      task = await detail('task-mock-1');
      pick.scanLocation(task, 'C-S1-02-2-05');
      pick.scan(task, MockTaskRepository.milkBarcode);
      expect(
        pick.scan(task, MockTaskRepository.milkBarcode),
        ScanResult.overRemaining,
        reason: '이 칸 몫은 1개',
      );
      await pick.submitIfFull(task);
      await pick.sync();
      final next = nextPickStop(await detail('task-mock-1'))!;
      expect(next.line.orderLineId, 'ol-2');
      expect(next.location, 'C-S2-04-1-10');
    });

    test('다른 상품·잔량 초과 스캔은 실적에 넣지 않는다', () async {
      final (pick, task) = await atStop();

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
      final (pick, task) = await atStop();
      pick.scan(task, MockTaskRepository.yogurtBarcode);

      await pick.submitStop(task);

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
      final (pick, task) = await atStop();
      pick.scan(task, MockTaskRepository.yogurtBarcode);
      await pick.submitStop(task);

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
      final (pick, task) = await atStop();
      pick.scan(task, MockTaskRepository.yogurtBarcode);
      await pick.submitStop(task);

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
      final (pick, task) = await atStop();
      pick.scan(task, MockTaskRepository.yogurtBarcode);
      (repo.taskJson('task-mock-1')['assignment']!
              as Map)['assignmentVersion'] =
          3;

      await pick.submitStop(task);

      final item = (await c.read(fieldQueueProvider).items()).single;
      expect(item.state, QueueItemState.rejected);
      expect(item.rejectCode, TaskProblemCode.versionConflict);
    });

    test('결품 보고는 실적 0 + 부족 수량으로 보내고 작업이 막힌다', () async {
      final pick = await startedPicking();
      final task = await detail('task-mock-1');

      await pick.submitStop(
        task,
        shortage: (qty: 1, reason: ShortageReason.short, note: null),
      );
      await pick.sync();

      expect(repo.taskJson('task-mock-1')['state'], 'BLOCKED');
    });
  });

  testWidgets('작업 시작 한 번 → 피킹 스캔 → 실적 전송·확정', (t) async {
    t.view
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = MockTaskRepository(latency: Duration.zero)..confirmPolls = 2;
    final store = MemoryKeyValueStore();
    await t.pumpWidget(_app(repo, store));
    await t.pumpAndSettle();

    // 작업 상세 없이 — 열면 시작 판정을 받고 바로 피킹.
    await openRoute(t, '/tasks/task-mock-1');

    expect(find.text('피킹'), findsOneWidget);
    await scanTo(t, 'cart-scan', 'CRT-C-01');
    await scanTo(t, 'pick-loc-scan', 'C-S1-02-2-05');
    expect(find.byKey(const ValueKey('pick-loc-error')), findsOneWidget);
    await scanTo(t, 'pick-loc-scan', 'C-S1-01-1-01');
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
    // 칸 몫(1개)을 채우면 버튼 없이 바로 보낸다.
    await t.pumpAndSettle();
    // 접수만 됨(확정 대기) — 확정 수는 그대로, 다음 칸 지시로 넘어간다.
    expect(find.textContaining('확정 0 / 지시 5'), findsOneWidget);
    expect(find.text('C-S1-02-2-05'), findsOneWidget, reason: '다음 칸 지시');
    final queued = (await t.runAsync(
      () => FieldQueue(store, name: 'mfc').items(),
    ))!;
    expect(queued.single.state, QueueItemState.awaitingConfirm);

    await t.tap(find.byKey(const ValueKey('sync')));
    await t.pumpAndSettle();
    expect(find.textContaining('확정 1 / 지시 5'), findsOneWidget);
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
    // 작업 상세 없이 — 열면 시작 판정을 받고 바로 피킹.
    await openRoute(t, '/tasks/task-mock-1');
    await scanTo(t, 'cart-scan', 'CRT-C-01');
    await scanTo(t, 'pick-loc-scan', 'C-S1-01-1-01');
    await t.enterText(
      find.byKey(const ValueKey('scan-field')),
      MockTaskRepository.yogurtBarcode,
    );
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('do-not-redo')), findsOneWidget);
  });
}
