import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../work/domain/work.dart';
import '../../work/presentation/work_screens.dart' show backToSession;
import '../../../shared/field_widgets.dart';
import '../../../shared/scanner/scan_input.dart';
import '../../../shared/scanner/scanner.dart';
import '../../../shared/ui_state_of.dart';
import '../domain/task_list.dart';
import 'task_controllers.dart';

String taskKindText(AppLocalizations l10n, TaskKind k) => switch (k) {
  TaskKind.pick => l10n.taskTypePick,
  TaskKind.pack => l10n.taskTypePack,
  TaskKind.dispatch => l10n.taskTypeDispatch,
  TaskKind.returnToShelf => l10n.taskTypeReturn,
};

String taskStateText(AppLocalizations l10n, TaskState s) => switch (s) {
  TaskState.waiting => l10n.tsWaiting,
  TaskState.ready => l10n.tsReady,
  TaskState.assigned => l10n.tsAssigned,
  TaskState.inProgress => l10n.tsInProgress,
  TaskState.completed => l10n.tsCompleted,
  TaskState.blocked => l10n.tsBlocked,
  TaskState.failed => l10n.tsFailed,
  TaskState.cancelled => l10n.tsCancelled,
  TaskState.closedPartial => l10n.tsClosedPartial,
  TaskState.unknown => l10n.tsUnknown,
};

/// 작업 종류별 실행 화면 경로(작업 상세 아래).
String taskRoute(TaskKind? k) => switch (k) {
  TaskKind.pack => 'pack',
  TaskKind.returnToShelf => 'return',
  _ => 'pick',
};

String startRejectText(AppLocalizations l10n, String? code) => switch (code) {
  TaskProblemCode.alreadyStarted => l10n.startAlreadyStarted,
  TaskProblemCode.notAssignee => l10n.startNotAssignee,
  TaskProblemCode.predecessorNotCompleted => l10n.startPredecessor,
  TaskProblemCode.versionConflict => l10n.startVersionConflict,
  _ => l10n.startInvalidState,
};

/// 작업 상세·시작. 시작 확정 전에는 피킹 화면으로 가지 않는다.
class TaskDetailScreen extends ConsumerWidget {
  const TaskDetailScreen({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final provider = taskDetailProvider(taskId);
    final flow = ref.watch(startFlowProvider(taskId));
    final me = ref.watch(currentWorkerIdProvider);
    ref.listen(startFlowProvider(taskId), (_, next) {
      if (next.phase == StartPhase.applied) {
        final kind = ref.read(provider).value?.kind;
        // 교체하지 않고 쌓는다 — 뒤로 가면 작업 상세, 그다음 근무 화면(다시 받기).
        context.push('/tasks/$taskId/${taskRoute(kind)}');
      }
    });
    return Scaffold(
      appBar: AppBar(title: Text(l10n.taskDetailTitle)),
      body: UiStateView<TaskDetailView>(
        state: uiStateOf(ref.watch(provider)),
        onRetry: () => ref.invalidate(provider),
        ready: (context, t) {
          final startedByMe =
              t.state == TaskState.inProgress && t.activeStartWorkerId == me;
          final message = switch (flow.phase) {
            StartPhase.rejected => startRejectText(l10n, flow.rejectCode),
            StartPhase.notStarted => l10n.startNotStarted,
            StartPhase.unknown => l10n.startUnknown,
            StartPhase.clientError => l10n.startClientError,
            _ => null,
          };
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${taskKindText(l10n, t.kind)} · ${taskStateText(l10n, t.state)}',
                key: const ValueKey('task-state'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(l10n.taskProgress(t.totalCompleted, t.totalPlanned)),
              if (t.blockReason case final r?)
                Text(l10n.taskBlocked(r), key: const ValueKey('block-reason')),
              if (t.assignmentVersion case final v?)
                Text(l10n.assignmentVersion(v)),
              const SizedBox(height: 12),
              for (final l in t.lines)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.productName ?? l.sku),
                  subtitle: Text(
                    [
                      ?l.locationId,
                      l10n.lineQty(
                        l.plannedQty,
                        l.completedQty,
                        l.remainingQty,
                      ),
                    ].join(' · '),
                  ),
                ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    message,
                    key: const ValueKey('start-message'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              if (startedByMe)
                // 키를 잃었어도 활성 시작이 본인이면 이어서 한다(새 키로 다시 시작하지 않는다).
                FilledButton(
                  key: const ValueKey('continue-picking'),
                  onPressed: () =>
                      context.push('/tasks/$taskId/${taskRoute(t.kind)}'),
                  child: Text(switch (t.kind) {
                    TaskKind.pack => l10n.continuePacking,
                    TaskKind.returnToShelf => l10n.continueReturn,
                    _ => l10n.continuePicking,
                  }),
                )
              else if (t.state == TaskState.assigned &&
                  t.kind != TaskKind.dispatch)
                CommandButton(
                  key: const ValueKey('start'),
                  busy: flow.phase == StartPhase.starting,
                  label: switch (flow.phase) {
                    StartPhase.unknown => l10n.checkAgain,
                    StartPhase.notStarted => l10n.retry,
                    _ => l10n.startTask,
                  },
                  onPressed: flow.phase == StartPhase.clientError
                      ? null
                      : () => ref
                            .read(startFlowProvider(taskId).notifier)
                            .start(t),
                ),
            ],
          );
        },
      ),
    );
  }
}

String queueStateText(AppLocalizations l10n, QueueItemState s) => switch (s) {
  QueueItemState.queued => l10n.qQueued,
  QueueItemState.awaitingConfirm => l10n.qAwaiting,
  QueueItemState.applied => l10n.qApplied,
  QueueItemState.rejected => l10n.qRejected,
  QueueItemState.checking => l10n.qChecking,
};

/// 피킹: 장바구니 → [칸 스캔 → 상품 스캔 × 수량] 을 칸마다. 한 칸 몫을 다 집으면 바로 보낸다.
/// 스캔 수량은 "이번 칸"이고, 서버 확정분만 완료로 보인다.
class PickingScreen extends ConsumerStatefulWidget {
  const PickingScreen({super.key, required this.taskId});

  final String taskId;

  @override
  ConsumerState<PickingScreen> createState() => _PickingScreenState();
}

String pickScanText(AppLocalizations l10n, ScanResult r) => switch (r) {
  ScanResult.matched => '',
  ScanResult.wrongItem => l10n.scanWrongItem,
  ScanResult.overRemaining => l10n.scanOver,
  ScanResult.noTarget => l10n.scanNoTarget,
  ScanResult.needLocation => l10n.pickNeedLocation,
};

String pickLocText(AppLocalizations l10n, PickLocScan r) => switch (r) {
  PickLocScan.ok => '',
  PickLocScan.wrongPlace => l10n.moveWrongPlace,
  PickLocScan.notLocation => l10n.moveNotLocation,
};

class _PickingScreenState extends ConsumerState<PickingScreen> {
  PickingController get _ctl =>
      ref.read(pickingProvider(widget.taskId).notifier);

  ScanFeedback _onScan(TaskDetailView task, String code) {
    final l10n = AppLocalizations.of(context);
    final r = _ctl.scan(task, code);
    if (r == ScanResult.matched) {
      _ctl.submitIfFull(task);
      return const ScanFeedback.ok();
    }
    return ScanFeedback.error(pickScanText(l10n, r));
  }

  Future<void> _shortage(TaskDetailView task, PickStop stop) async {
    final l10n = AppLocalizations.of(context);
    final picking = ref.read(pickingProvider(widget.taskId));
    final missing =
        stop.line.remainingQty -
        stop.line.pendingQty -
        picking.capturedFor(stop.line.orderLineId);
    if (missing <= 0) return;
    final reason = await showDialog<ShortageReason>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.shortageTitle(missing)),
        children: [
          for (final r in ShortageReason.values)
            SimpleDialogOption(
              key: ValueKey('shortage-${r.name}'),
              onPressed: () => Navigator.of(context).pop(r),
              child: Text(switch (r) {
                ShortageReason.short => l10n.shortageShort,
                ShortageReason.damaged => l10n.shortageDamaged,
                ShortageReason.blocked => l10n.shortageBlocked,
              }),
            ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    await _ctl.submitStop(
      task,
      shortage: (qty: missing, reason: reason, note: null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final detail = ref.watch(taskDetailProvider(widget.taskId));
    final picking = ref.watch(pickingProvider(widget.taskId));
    final queue = ref.watch(taskQueueProvider(widget.taskId)).value ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.pickingTitle),
        actions: [
          IconButton(
            key: const ValueKey('sync'),
            tooltip: l10n.sync,
            onPressed: picking.syncing ? null : _ctl.sync,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: UiStateView<TaskDetailView>(
        state: uiStateOf(detail),
        onRetry: () => ref.invalidate(taskDetailProvider(widget.taskId)),
        ready: (context, task) {
          final stop = nextPickStop(task);
          final checking = queue.any((q) => q.state == QueueItemState.checking);
          final step = picking.cart == null
              ? 0
              : picking.at == null
              ? 1
              : 2;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (stop != null)
                StepHeader(
                  names: [
                    l10n.pickStepCart,
                    l10n.pickStepLocation,
                    l10n.pickStepItem,
                  ],
                  current: step,
                ),
              const SizedBox(height: 8),
              Text(
                l10n.taskProgress(task.totalCompleted, task.totalPlanned),
                key: const ValueKey('pick-progress'),
                style: theme.textTheme.titleMedium,
              ),
              if (checking)
                Card(
                  key: const ValueKey('do-not-redo'),
                  color: theme.colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber_rounded),
                    title: Text(l10n.doNotRedo),
                  ),
                ),
              if (stop != null && picking.cart == null) ...[
                // 1. 장바구니 — 주문과 장바구니를 잇는다(업무 문서 §7-6).
                TargetLine(
                  key: const ValueKey('target-cart'),
                  label: l10n.moveCart,
                  code: l10n.moveCartScan,
                  confirmed: false,
                ),
                ScanInput(
                  id: 'cart-scan',
                  testValues: [
                    TestScan(l10n.tsCart, 'CRT-C-01'),
                    TestScan(l10n.tsWrong, 'C-S1-01-1-01'),
                  ],
                  label: l10n.moveCartScan,
                  cameraTitle: l10n.pickCameraTitle,
                  continuous: false,
                  autofocus: false,
                  onScan: (code) => _ctl.scanCart(code)
                      ? const ScanFeedback.ok()
                      : ScanFeedback.error(l10n.pickNotCart),
                ),
              ] else if (stop != null) ...[
                if (picking.cart case final cart?)
                  TargetLine(label: l10n.moveCart, code: cart, confirmed: true),
                Card(
                  key: ValueKey('current-${stop.line.orderLineId}'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          picking.at ?? stop.location,
                          key: const ValueKey('pick-location'),
                          style: theme.textTheme.headlineSmall,
                        ),
                        Text(
                          stop.line.productName ?? stop.line.sku,
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          [
                            if (stop.pick?.visitSeq case final n?)
                              l10n.pickVisit(n),
                            if (stop.lotId case final lot?) l10n.lot(lot),
                            if (stop.expiresOn case final e?) l10n.expiresOn(e),
                          ].join(' · '),
                        ),
                        Text(
                          l10n.pickStopQty(
                            stop.qty,
                            picking.capturedFor(stop.line.orderLineId),
                          ),
                          key: const ValueKey('pick-counts'),
                          style: theme.textTheme.titleLarge,
                        ),
                        if (stop.pick case final p?) ...[
                          if (switch (p.status) {
                                PickStatus.partial => l10n.pickStatusPartial,
                                PickStatus.notFound => l10n.pickStatusNotFound,
                                _ => null,
                              }
                              case final w?)
                            Text(
                              w,
                              key: const ValueKey('pick-status-warning'),
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          if (p.notice case final n?)
                            Text(n, key: const ValueKey('pick-notice')),
                        ],
                        if (stop.otherLocations.isNotEmpty)
                          Text(
                            l10n.pickOtherLocations(
                              stop.otherLocations.join(', '),
                            ),
                            key: const ValueKey('pick-other-locations'),
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ),
                if (picking.at == null) ...[
                  // 2. 칸 — 같은 상품이 여러 칸·LOT 에 있어도 지시 LOT 을 집게(IV-07 오로트 차단).
                  ScanInput(
                    id: 'pick-loc-scan',
                    testValues: [
                      TestScan(l10n.tsLocation, stop.location),
                      for (final o in stop.otherLocations)
                        TestScan(l10n.tsOtherLocation, o),
                      TestScan(l10n.tsWrong, 'A-S9-09-9-99'),
                    ],
                    label: l10n.pickScanLocation,
                    cameraTitle: l10n.pickCameraTitle,
                    continuous: false,
                    autofocus: false,
                    onScan: (code) => switch (_ctl.scanLocation(task, code)) {
                      PickLocScan.ok => const ScanFeedback.ok(),
                      final r => ScanFeedback.error(pickLocText(l10n, r)),
                    },
                  ),
                  if (picking.lastLocScan case final r?
                      when r != PickLocScan.ok)
                    Text(
                      pickLocText(l10n, r),
                      key: const ValueKey('pick-loc-error'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                ] else ...[
                  // 3. 상품 — 한 번에 하나씩. 다 차면 바로 보낸다.
                  ScanInput(
                    id: 'scan-field',
                    testValues: [
                      for (final l in task.lines)
                        if (l.barcode case final bc?)
                          TestScan(l.productName ?? l.sku, bc),
                      TestScan(l10n.tsWrong, '0000000000000'),
                    ],
                    label: l10n.scanHint,
                    cameraTitle: l10n.pickCameraTitle,
                    onScan: (code) => _onScan(task, code),
                  ),
                  if (picking.lastScan case final s?
                      when s != ScanResult.matched)
                    Text(
                      pickScanText(l10n, s),
                      key: const ValueKey('scan-error'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const ValueKey('report-shortage'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () => _shortage(task, stop),
                    child: Text(l10n.reportShortage),
                  ),
                ],
              ] else ...[
                Text(
                  task.lines.every((l) => l.done)
                      ? l10n.pickAllConfirmed
                      : l10n.pickWaitingConfirm,
                  key: const ValueKey('pick-finished'),
                ),
                const SizedBox(height: 8),
                // 다음 작업은 서버가 정한다 — 근무 화면으로 돌아가 다시 받는다.
                FilledButton(
                  key: const ValueKey('next-task'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  onPressed: () => backToSession(context, WorkArea.pickPack),
                  child: Text(l10n.nextTask),
                ),
              ],
              const Divider(height: 32),
              Text(l10n.queueTitle, style: theme.textTheme.titleMedium),
              for (final q in queue)
                ListTile(
                  key: ValueKey('queue-${q.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(queueStateText(l10n, q.state)),
                  subtitle: q.rejectCode == null ? null : Text(q.rejectCode!),
                ),
              const Divider(height: 32),
              for (final l in task.lines)
                ListTile(
                  key: ValueKey('line-${l.orderLineId}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    l.done ? Icons.check_circle : Icons.radio_button_unchecked,
                  ),
                  title: Text(l.productName ?? l.sku),
                  subtitle: Text(
                    l10n.lineQty(l.plannedQty, l.completedQty, l.remainingQty),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 지금 갈 칸: 남은 첫 지시의 배정 칸(없으면 첫 칸), 지시가 없으면 줄의 지시 로케이션.
String? firstPickLocation(TaskLineView l) {
  for (final p in l.picks) {
    if (p.status == PickStatus.done) continue;
    final allocated = p.locations
        .where((c) => (c.allocatedQty ?? 0) > 0)
        .firstOrNull;
    final c = allocated ?? p.locations.firstOrNull;
    if (c != null) return c.code;
  }
  return l.locationId;
}

/// LOT 조각 하나의 피킹 지시. 칸 상태·안내는 서버 값 그대로 보인다.
class PickInstructionTile extends StatelessWidget {
  const PickInstructionTile({super.key, required this.pick});

  final PickInstruction pick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final warn = switch (pick.status) {
      PickStatus.partial => l10n.pickStatusPartial,
      PickStatus.notFound => l10n.pickStatusNotFound,
      PickStatus.unknown => l10n.tsUnknown,
      _ => null,
    };
    return Padding(
      key: ValueKey('pick-${pick.lotId ?? pick.visitSeq}'),
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              if (pick.visitSeq case final n?) l10n.pickVisit(n),
              if (pick.lotId case final lot?) l10n.lot(lot),
              if (pick.expiresOn case final e?) l10n.expiresOn(e),
              if (pick.remainingQty case final q?) l10n.pickLotRemaining(q),
            ].join(' · '),
            style: theme.textTheme.bodyLarge,
          ),
          if (warn != null)
            Text(
              warn,
              key: const ValueKey('pick-status-warning'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          if (pick.notice case final n?)
            Text(n, key: const ValueKey('pick-notice')),
          for (final c in pick.locations)
            Text(
              (c.allocatedQty ?? 0) > 0
                  ? l10n.pickLocationAllocated(c.code, c.allocatedQty!)
                  : l10n.pickLocationOther(c.code, c.qty ?? 0),
              style: (c.allocatedQty ?? 0) > 0
                  ? theme.textTheme.titleMedium
                  : theme.textTheme.bodyMedium,
            ),
        ],
      ),
    );
  }
}
