import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers.dart';
import '../../../shared/ui_state_of.dart';
import '../domain/task_list.dart';
import 'task_controllers.dart';

String taskKindText(AppLocalizations l10n, TaskKind k) => switch (k) {
  TaskKind.pick => l10n.taskTypePick,
  TaskKind.pack => l10n.taskTypePack,
  TaskKind.dispatch => l10n.taskTypeDispatch,
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

/// 내 작업. 막힌 작업은 기본 조회에 없어서 따로 본다.
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  bool _blocked = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mock = ref.watch(envProvider) == PmartEnv.mock;
    final provider = _blocked ? blockedTasksProvider : myTasksProvider;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tasksTitle),
        actions: [
          if (mock)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(label: Text(l10n.mockModeBadge)),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(l10n.tabMyTasks)),
                ButtonSegment(value: true, label: Text(l10n.tabBlockedTasks)),
              ],
              selected: {_blocked},
              onSelectionChanged: (v) => setState(() => _blocked = v.first),
            ),
          ),
          Expanded(
            child: UiStateView<TaskList>(
              state: uiStateOf(
                ref.watch(provider),
                isEmpty: (l) => l.tasks.isEmpty,
              ),
              onRetry: () => ref.invalidate(provider),
              empty: (_) => Center(child: Text(l10n.tasksEmpty)),
              ready: (context, list) => RefreshIndicator(
                onRefresh: () => ref.refresh(provider.future),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (!list.assignmentFresh)
                      ListTile(
                        key: const ValueKey('assignment-stale'),
                        leading: const Icon(Icons.info_outline),
                        title: Text(l10n.assignmentStale),
                      ),
                    for (final task in list.tasks)
                      Card(
                        key: ValueKey('task-${task.taskId}'),
                        child: ListTile(
                          title: Text(taskKindText(l10n, task.kind)),
                          subtitle: Text(
                            [
                              switch (task.remainingQty) {
                                final int q => l10n.taskRemaining(q),
                                null => l10n.taskRemainingUnknown,
                              },
                              taskStateText(l10n, task.state),
                            ].join('\n'),
                          ),
                          onTap: () => context.push('/tasks/${task.taskId}'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
        context.pushReplacement('/tasks/$taskId/pick');
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
                  onPressed: () => context.push('/tasks/$taskId/pick'),
                  child: Text(l10n.continuePicking),
                )
              else if (t.state == TaskState.assigned && t.kind == TaskKind.pick)
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
  final _scan = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _scan.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onScan(TaskDetailView task, String code) {
    if (code.trim().isEmpty) return;
    ref.read(pickingProvider(widget.taskId).notifier).scan(task, code);
    _scan.clear();
    // 하드웨어 스캐너(키보드 웨지)가 다음 입력을 계속 받게 한다.
    _focus.requestFocus();
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
                          current.locationId ?? '-',
                          style: theme.textTheme.headlineSmall,
                        ),
                        Text(
                          current.productName ?? current.sku,
                          style: theme.textTheme.titleMedium,
                        ),
                        if (current.expiresOn case final e?)
                          Text(l10n.expiresOn(e)),
                        if (current.lotId case final lot?) Text(l10n.lot(lot)),
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
                TextField(
                  key: const ValueKey('scan-field'),
                  controller: _scan,
                  focusNode: _focus,
                  autofocus: true,
                  decoration: InputDecoration(labelText: l10n.scanHint),
                  onSubmitted: (v) => _onScan(task, v),
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
              ] else
                Text(
                  task.lines.every((l) => l.done)
                      ? l10n.pickAllConfirmed
                      : l10n.pickWaitingConfirm,
                  key: const ValueKey('pick-finished'),
                ),
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
