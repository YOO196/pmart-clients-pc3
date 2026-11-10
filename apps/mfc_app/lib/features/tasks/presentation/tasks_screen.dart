import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../work/domain/work.dart';
import '../../work/presentation/work_screens.dart' show backToSession;
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
        context.pushReplacement(
          '/tasks/$taskId/${kind == TaskKind.pack ? 'pack' : 'pick'}',
        );
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
              if (t.kind == TaskKind.returnToShelf)
                Text(
                  l10n.returnTaskNotYet,
                  key: const ValueKey('return-not-yet'),
                )
              else if (startedByMe)
                // 키를 잃었어도 활성 시작이 본인이면 이어서 한다(새 키로 다시 시작하지 않는다).
                FilledButton(
                  key: const ValueKey('continue-picking'),
                  onPressed: () => context.push(
                    '/tasks/$taskId/${t.kind == TaskKind.pack ? 'pack' : 'pick'}',
                  ),
                  child: Text(
                    t.kind == TaskKind.pack
                        ? l10n.continuePacking
                        : l10n.continuePicking,
                  ),
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

/// 피킹. 스캔 수량은 "이번 스캔"이고, 서버 확정분만 완료로 보인다.
class PickingScreen extends ConsumerStatefulWidget {
  const PickingScreen({super.key, required this.taskId});

  final String taskId;

  @override
  ConsumerState<PickingScreen> createState() => _PickingScreenState();
}

class _PickingScreenState extends ConsumerState<PickingScreen> {
  ScanFeedback _onScan(TaskDetailView task, String code) {
    final l10n = AppLocalizations.of(context);
    final r = ref
        .read(pickingProvider(widget.taskId).notifier)
        .scan(task, code);
    return switch (r) {
      ScanResult.matched => const ScanFeedback.ok(),
      ScanResult.wrongItem => ScanFeedback.error(l10n.scanWrongItem),
      ScanResult.overRemaining => ScanFeedback.error(l10n.scanOver),
      ScanResult.noTarget => ScanFeedback.error(l10n.scanNoTarget),
    };
  }

  Future<void> _shortage(TaskDetailView task, TaskLineView line) async {
    final l10n = AppLocalizations.of(context);
    final picking = ref.read(pickingProvider(widget.taskId));
    final missing =
        line.remainingQty -
        line.pendingQty -
        picking.capturedFor(line.orderLineId);
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
    await ref
        .read(pickingProvider(widget.taskId).notifier)
        .submitLine(
          task,
          line,
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
    final ctl = ref.read(pickingProvider(widget.taskId).notifier);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.pickingTitle),
        actions: [
          IconButton(
            key: const ValueKey('sync'),
            tooltip: l10n.sync,
            onPressed: picking.syncing ? null : ctl.sync,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: UiStateView<TaskDetailView>(
        state: uiStateOf(detail),
        onRetry: () => ref.invalidate(taskDetailProvider(widget.taskId)),
        ready: (context, task) {
          final current = PickingController.currentLine(task, picking);
          final checking = queue.any((q) => q.state == QueueItemState.checking);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
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
              if (current != null) ...[
                Card(
                  key: ValueKey('current-${current.orderLineId}'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          firstPickLocation(current) ?? '-',
                          key: const ValueKey('pick-location'),
                          style: theme.textTheme.headlineSmall,
                        ),
                        Text(
                          current.productName ?? current.sku,
                          style: theme.textTheme.titleMedium,
                        ),
                        if (current.picks.isEmpty) ...[
                          if (current.expiresOn case final e?)
                            Text(l10n.expiresOn(e)),
                          if (current.lotId case final lot?)
                            Text(l10n.lot(lot)),
                        ] else
                          for (final p in current.picks)
                            if (p.status != PickStatus.done)
                              PickInstructionTile(pick: p),
                        Text(
                          l10n.pickCounts(
                            current.remainingQty,
                            current.pendingQty,
                            picking.capturedFor(current.orderLineId),
                          ),
                          key: const ValueKey('pick-counts'),
                        ),
                      ],
                    ),
                  ),
                ),
                ScanInput(
                  id: 'scan-field',
                  label: l10n.scanHint,
                  cameraTitle: l10n.pickCameraTitle,
                  onScan: (code) => _onScan(task, code),
                ),
                if (picking.lastScan case final s? when s != ScanResult.matched)
                  Text(
                    switch (s) {
                      ScanResult.wrongItem => l10n.scanWrongItem,
                      ScanResult.overRemaining => l10n.scanOver,
                      _ => l10n.scanNoTarget,
                    },
                    key: const ValueKey('scan-error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('line-done'),
                        onPressed: picking.capturedFor(current.orderLineId) > 0
                            ? () => ctl.submitLine(task, current)
                            : null,
                        child: Text(l10n.lineSubmit),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      key: const ValueKey('report-shortage'),
                      onPressed: () => _shortage(task, current),
                      child: Text(l10n.reportShortage),
                    ),
                  ],
                ),
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
