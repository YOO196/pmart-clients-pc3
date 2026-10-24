import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart';
import '../data/mock_task_repository.dart';
import '../data/task_repository.dart';
import '../domain/task_list.dart';

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockTaskRepository(),
    PmartEnv.local => ApiTaskRepository(ref.watch(dioProvider)),
  },
);

/// 근무 센터. 점원 로그인(BR-02) 뒤 세션의 centerScope 로 바꾼다.
final currentMfcIdProvider = Provider<String>((_) => 'MFC-MOCK-01');

/// 작업자 ID. BR-02(점원 로그인·직원 ID 바코드) 전에는 목 작업자다.
final currentWorkerIdProvider = Provider<String>(
  (_) => MockTaskRepository.workerId,
);

/// 현장 실적 내구 큐(앱이 꺼져도 남는다).
final fieldQueueProvider = Provider<FieldQueue>(
  (ref) => FieldQueue(ref.watch(secureStoreProvider), name: 'mfc'),
);

/// 시작 결과 불명일 때 같은 키로 자동 재전송하는 횟수.
final startResendAttemptsProvider = Provider<int>((_) => 2);

final myTasksProvider = FutureProvider.autoDispose<TaskList>(
  (ref) => ref
      .watch(taskRepositoryProvider)
      .myTasks(ref.watch(currentMfcIdProvider)),
);

/// 막힌 작업은 기본 조회에 없어서 따로 조회한다(BR-05 회신).
final blockedTasksProvider = FutureProvider.autoDispose<TaskList>(
  (ref) => ref
      .watch(taskRepositoryProvider)
      .myTasks(ref.watch(currentMfcIdProvider), blocked: true),
);

final taskDetailProvider = FutureProvider.autoDispose
    .family<TaskDetailView, String>(
      (ref, taskId) => ref.watch(taskRepositoryProvider).task(taskId),
    );

/// 이 작업의 큐 항목(전송 상태 표시용).
final taskQueueProvider = FutureProvider.autoDispose
    .family<List<QueueItem>, String>((ref, taskId) async {
      final items = await ref.watch(fieldQueueProvider).items();
      return [
        for (final i in items)
          if (i.targetId == taskId) i,
      ];
    });

// ---------------------------------------------------------------------------
// 작업 시작(§3-1)

enum StartPhase {
  idle,
  starting,
  applied,
  rejected,
  notStarted,
  unknown,
  clientError,
}

@immutable
class StartFlow {
  const StartFlow(this.phase, {this.rejectCode});

  final StartPhase phase;
  final String? rejectCode;
}

final startFlowProvider = NotifierProvider.autoDispose
    .family<StartController, StartFlow, String>(StartController.new);

class StartController extends Notifier<StartFlow> {
  StartController(this.taskId);

  final String taskId;

  /// 확정 전까지 같은 키를 쓴다(503·불명·처리 중 모두 같은 키로 다시 보낸다).
  IdempotencyKey? _key;

  @override
  StartFlow build() => const StartFlow(StartPhase.idle);

  Future<void> start(TaskDetailView task) async {
    if (state.phase == StartPhase.starting) return;
    state = const StartFlow(StartPhase.starting);
    final key = _key ??= IdempotencyKey.generate();
    final repo = ref.read(taskRepositoryProvider);
    final worker = ref.read(currentWorkerIdProvider);
    final device = await ref.read(deviceIdProvider).get();
    var outcome = await repo.start(
      taskId,
      workerId: worker,
      assignmentVersion: task.assignmentVersion ?? 0,
      deviceId: device,
      key: key,
    );
    final resend = ref.read(startResendAttemptsProvider);
    for (var i = 0; i < resend && outcome is StartUnknown; i++) {
      if (!ref.mounted) return;
      outcome = await repo.start(
        taskId,
        workerId: worker,
        assignmentVersion: task.assignmentVersion ?? 0,
        deviceId: device,
        key: key,
      );
    }
    if (!ref.mounted) return;
    switch (outcome) {
      case StartApplied():
        _key = null;
        state = const StartFlow(StartPhase.applied);
        ref.invalidate(taskDetailProvider(taskId));
      case StartRejected(:final code):
        _key = null;
        state = StartFlow(StartPhase.rejected, rejectCode: code);
        // 거절이면 최신 상태를 다시 본다.
        ref.invalidate(taskDetailProvider(taskId));
      case StartNotStarted():
        // 시작 안 됨 확정. 같은 키로 다시 시도할 수 있다.
        state = const StartFlow(StartPhase.notStarted);
      case StartUnknown():
        state = const StartFlow(StartPhase.unknown);
      case StartClientError():
        _key = null;
        state = const StartFlow(StartPhase.clientError);
    }
  }
}

// ---------------------------------------------------------------------------
// 피킹

enum ScanResult { matched, wrongItem, overRemaining, noTarget }

@immutable
class PickingState {
  const PickingState({
    this.captured = const {},
    this.lastScan,
    this.syncing = false,
  });

  /// 이번에 스캔해 모은 수량(서버 미전송·미확정). orderLineId → 수량.
  final Map<String, int> captured;
  final ScanResult? lastScan;
  final bool syncing;

  int capturedFor(String orderLineId) => captured[orderLineId] ?? 0;

  PickingState copyWith({
    Map<String, int>? captured,
    ScanResult? lastScan,
    bool? syncing,
  }) => PickingState(
    captured: captured ?? this.captured,
    lastScan: lastScan ?? this.lastScan,
    syncing: syncing ?? this.syncing,
  );
}

final pickingProvider = NotifierProvider.autoDispose
    .family<PickingController, PickingState, String>(PickingController.new);

class PickingController extends Notifier<PickingState> {
  PickingController(this.taskId);

  final String taskId;

  @override
  PickingState build() => const PickingState();

  /// 지금 피킹할 행: 아직 보내지 않은 잔량이 있는 첫 행(서버 순서 = 지시 순서).
  /// 이번 스캔으로 다 채워도 실적을 보낼 때까지 그 행에 머문다.
  static TaskLineView? currentLine(TaskDetailView task, PickingState s) =>
      task.lines.where((l) => l.remainingQty - l.pendingQty > 0).firstOrNull;

  /// 상품 바코드 스캔. 다른 상품·잔량 초과는 수량 0 + 원인 안내(실적에 넣지 않는다).
  ScanResult scan(TaskDetailView task, String code) {
    final target = currentLine(task, state);
    final ScanResult result;
    if (target == null) {
      result = ScanResult.noTarget;
    } else if (target.barcode != code.trim()) {
      result = ScanResult.wrongItem;
    } else {
      final room =
          target.remainingQty -
          target.pendingQty -
          state.capturedFor(target.orderLineId);
      if (room <= 0) {
        result = ScanResult.overRemaining;
      } else {
        state = state.copyWith(
          captured: {
            ...state.captured,
            target.orderLineId: state.capturedFor(target.orderLineId) + 1,
          },
          lastScan: ScanResult.matched,
        );
        return ScanResult.matched;
      }
    }
    state = state.copyWith(lastScan: result);
    return result;
  }

  /// 행 실적을 큐에 넣고 보낸다. [shortage] 는 결품·파손·차단 보고.
  Future<void> submitLine(
    TaskDetailView task,
    TaskLineView line, {
    ({int qty, ShortageReason reason, String? note})? shortage,
  }) async {
    final picked = state.capturedFor(line.orderLineId);
    if (picked == 0 && shortage == null) return;
    await ref
        .read(fieldQueueProvider)
        .enqueue(
          kind: FieldCommandKind.pickExecution,
          targetId: taskId,
          payload: pickPayload(
            workerId: ref.read(currentWorkerIdProvider),
            assignmentVersion: task.assignmentVersion,
            line: line,
            pickedQty: picked,
            shortage: shortage,
          ),
        );
    if (!ref.mounted) return;
    state = state.copyWith(
      captured: {...state.captured}..remove(line.orderLineId),
    );
    await sync();
  }

  /// 전송 대기·확인 중을 같은 키로 보내고, 확정 대기를 조회한다.
  Future<void> sync() async {
    if (state.syncing) return;
    state = state.copyWith(syncing: true);
    final repo = ref.read(taskRepositoryProvider);
    final queue = ref.read(fieldQueueProvider);
    await queue.flush(repo.sendExecution);
    await queue.confirm(
      (item) => item.resultId == null
          ? Future.value(ConfirmResult.unknown)
          : repo.execution(item.targetId, item.resultId!),
    );
    if (!ref.mounted) return;
    state = state.copyWith(syncing: false);
    ref
      ..invalidate(taskQueueProvider(taskId))
      ..invalidate(taskDetailProvider(taskId));
  }
}
