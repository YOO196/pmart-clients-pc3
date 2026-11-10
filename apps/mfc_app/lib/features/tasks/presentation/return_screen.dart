import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/codes.dart';
import '../../../shared/field_widgets.dart';
import '../../../shared/scanner/scan_input.dart';
import '../../../shared/scanner/scanner.dart';
import '../../../shared/ui_state_of.dart';
import '../../stock_move/presentation/stock_move_controllers.dart' show LocScan;
import '../../stock_move/presentation/stock_move_screens.dart' show locScanText;
import '../../work/domain/work.dart';
import '../../work/presentation/work_screens.dart' show backToSession;
import '../data/task_repository.dart';
import '../domain/task_list.dart';
import 'task_controllers.dart';

/// 지금 옮길 한 조각(줄·LOT·포장 위치).
@immutable
class ReturnPiece {
  const ReturnPiece({
    required this.line,
    required this.lotId,
    required this.from,
    required this.left,
    this.suggested = const [],
  });

  final TaskLineView line;
  final String lotId;

  /// 복귀 대상이 놓인 포장 위치.
  final String from;

  /// 더 옮길 양(접수만 된 것 제외).
  final int left;
  final List<String> suggested;
}

/// 남은 첫 조각. 없으면 null(다 옮김 또는 확정 대기).
ReturnPiece? nextReturnPiece(TaskDetailView t) {
  for (final l in t.lines) {
    final left = l.remainingQty - l.pendingQty;
    if (left <= 0) continue;
    final p = l.picks.where((p) => (p.remainingQty ?? 0) > 0).firstOrNull;
    final from = p?.locations.where((c) => (c.qty ?? 0) > 0).firstOrNull?.code;
    final lot = p?.lotId ?? l.lotId;
    if (from == null || lot == null) continue;
    return ReturnPiece(
      line: l,
      lotId: lot,
      from: from,
      left: left,
      suggested: p?.suggestedToLocations ?? const [],
    );
  }
  return null;
}

@immutable
class ReturnFlowState {
  const ReturnFlowState({
    this.atFrom = false,
    this.to,
    this.qty,
    this.lastScan,
    this.syncing = false,
  });

  final bool atFrom;
  final String? to;

  /// 옮길 수량. null 이면 남은 양 전부.
  final int? qty;
  final LocScan? lastScan;
  final bool syncing;

  ReturnFlowState copyWith({
    bool? atFrom,
    String? Function()? to,
    int? Function()? qty,
    LocScan? Function()? lastScan,
    bool? syncing,
  }) => ReturnFlowState(
    atFrom: atFrom ?? this.atFrom,
    to: to != null ? to() : this.to,
    qty: qty != null ? qty() : this.qty,
    lastScan: lastScan != null ? lastScan() : this.lastScan,
    syncing: syncing ?? this.syncing,
  );
}

final returnFlowProvider = NotifierProvider.autoDispose
    .family<ReturnFlowController, ReturnFlowState, String>(
      ReturnFlowController.new,
    );

/// 취소품 복귀(RETURN 작업): 포장 위치 확인 → 선반 칸 스캔 → 수량 → 실적(큐에 넣고 같은 키로 보냄·확정 조회).
class ReturnFlowController extends Notifier<ReturnFlowState> {
  ReturnFlowController(this.taskId);

  final String taskId;

  @override
  ReturnFlowState build() => const ReturnFlowState();

  /// 포장 위치면 출발 확인, 선반 칸이면 도착.
  LocScan scan(ReturnPiece p, String code) {
    final c = code.trim();
    final LocScan r;
    if (!isMfcLocation(c)) {
      r = LocScan.notLocation;
    } else if (c == p.from) {
      state = state.copyWith(atFrom: true);
      r = LocScan.ok;
    } else if (!state.atFrom || c.startsWith('PAK-')) {
      r = LocScan.wrongPlace;
    } else {
      // 추천 칸이 아니어도 받는다 — 진열 규칙 판정은 서버(재고).
      state = state.copyWith(to: () => c);
      r = LocScan.ok;
    }
    state = state.copyWith(lastScan: () => r);
    return r;
  }

  void setQty(int q) => state = state.copyWith(qty: () => q);

  Future<void> submit(TaskDetailView t, ReturnPiece p) async {
    final to = state.to;
    final qty = state.qty ?? p.left;
    if (!state.atFrom || to == null || qty < 1) return;
    await ref
        .read(fieldQueueProvider)
        .enqueue(
          kind: FieldCommandKind.pickExecution,
          targetId: taskId,
          payload: returnPayload(
            workerId: ref.read(currentWorkerIdProvider),
            assignmentVersion: t.assignmentVersion,
            line: p.line,
            lotId: p.lotId,
            fromLocation: p.from,
            toLocation: to,
            qty: qty,
          ),
        );
    if (!ref.mounted) return;
    state = const ReturnFlowState();
    await sync();
  }

  /// 전송 대기·확인 중을 같은 키로 보내고, 확정 대기를 조회한다(피킹과 같은 큐).
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

class ReturnShelfScreen extends ConsumerWidget {
  const ReturnShelfScreen({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = ref.watch(returnFlowProvider(taskId));
    final ctl = ref.read(returnFlowProvider(taskId).notifier);
    final queue = ref.watch(taskQueueProvider(taskId)).value ?? const [];
    final waiting = queue.where(
      (q) =>
          q.state == QueueItemState.queued ||
          q.state == QueueItemState.awaitingConfirm ||
          q.state == QueueItemState.checking,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.typeReturn),
        actions: [
          IconButton(
            key: const ValueKey('return-sync'),
            tooltip: l10n.sync,
            onPressed: s.syncing ? null : ctl.sync,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: UiStateView<TaskDetailView>(
            state: uiStateOf(ref.watch(taskDetailProvider(taskId))),
            onRetry: () => ref.invalidate(taskDetailProvider(taskId)),
            ready: (context, t) {
              final p = nextReturnPiece(t);
              final allDone = t.lines.every((l) => l.done);
              if (p == null) {
                return allDone
                    ? ResultView(
                        key: const ValueKey('return-done'),
                        icon: Icons.check_circle,
                        text: l10n.returnShelfDone,
                        action: l10n.nextTask,
                        onAction: () async =>
                            backToSession(context, WorkArea.stockMove),
                      )
                    : ResultView(
                        key: const ValueKey('return-waiting'),
                        icon: Icons.hourglass_top,
                        busy: s.syncing,
                        text: waiting.isEmpty
                            ? l10n.returnShelfWaiting
                            : l10n.doNotRedo,
                        action: l10n.checkAgain,
                        onAction: ctl.sync,
                      );
              }
              final qty = s.qty ?? p.left;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StepHeader(
                    names: [l10n.returnShelfStepFrom, l10n.returnShelfStepTo],
                    current: s.atFrom ? 1 : 0,
                  ),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.line.productName ?? p.line.sku,
                            style: theme.textTheme.titleLarge,
                          ),
                          Text(l10n.lot(p.lotId)),
                          Text(l10n.returnShelfLeft(p.left)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TargetLine(
                    key: const ValueKey('return-from'),
                    label: l10n.moveFrom,
                    code: p.from,
                    confirmed: s.atFrom,
                  ),
                  TargetLine(
                    key: const ValueKey('return-to'),
                    label: l10n.moveTo,
                    code: s.to ?? l10n.returnShelfScanShelf,
                    confirmed: s.to != null,
                  ),
                  if (p.suggested.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        l10n.returnShelfSuggested(p.suggested.join(', ')),
                        key: const ValueKey('return-suggested'),
                      ),
                    ),
                  if (s.to case final to?
                      when p.suggested.isNotEmpty && !p.suggested.contains(to))
                    Text(
                      l10n.returnShelfNotSuggested,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  const SizedBox(height: 8),
                  ScanInput(
                    id: 'return-scan',
                    label: s.atFrom
                        ? l10n.returnShelfScanShelf
                        : l10n.returnShelfScanFrom,
                    cameraTitle: l10n.typeReturn,
                    autofocus: false,
                    onScan: (code) => switch (ctl.scan(p, code)) {
                      LocScan.ok => const ScanFeedback.ok(),
                      final r => ScanFeedback.error(locScanText(l10n, r)),
                    },
                  ),
                  if (s.lastScan case final r? when r != LocScan.ok)
                    Text(
                      locScanText(l10n, r),
                      key: const ValueKey('return-scan-error'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  QtyStepper(
                    id: 'return-qty',
                    label: l10n.moveQtyDrop,
                    value: qty,
                    max: p.left,
                    onChanged: ctl.setQty,
                  ),
                  const Spacer(),
                  if (waiting.isNotEmpty)
                    Text(
                      l10n.returnShelfPending(waiting.length),
                      key: const ValueKey('return-pending'),
                    ),
                  const SizedBox(height: 8),
                  CommandButton(
                    key: const ValueKey('return-submit'),
                    busy: s.syncing,
                    label: l10n.returnShelfSubmit,
                    onPressed: s.atFrom && s.to != null && qty > 0
                        ? () => ctl.submit(t, p)
                        : null,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
