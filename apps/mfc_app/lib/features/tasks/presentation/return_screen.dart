import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/codes.dart';
import '../../../shared/field_widgets.dart';
import '../../../shared/issue_report.dart';
import '../../../shared/product_hints.dart';
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
    this.qty = 0,
    this.coldOk,
    this.reported = false,
    this.lastScan,
    this.syncing = false,
  });

  final bool atFrom;
  final String? to;

  /// 옮길 수량 — 상품을 스캔해 센다(0부터). 바코드를 모르면 직접 넣는다.
  final int qty;

  /// 냉장·냉동 취소품이 포장대에서 온도를 지켰는지(작업자 답). 상온이면 묻지 않는다.
  /// 기준은 업무 문서에 없다(BR-52 R19 8).
  final bool? coldOk;

  /// 문제를 보고했다(복귀하지 않음).
  final bool reported;
  final LocScan? lastScan;
  final bool syncing;

  ReturnFlowState copyWith({
    bool? atFrom,
    String? Function()? to,
    int? qty,
    bool? Function()? coldOk,
    bool? reported,
    LocScan? Function()? lastScan,
    bool? syncing,
  }) => ReturnFlowState(
    atFrom: atFrom ?? this.atFrom,
    to: to != null ? to() : this.to,
    qty: qty ?? this.qty,
    coldOk: coldOk != null ? coldOk() : this.coldOk,
    reported: reported ?? this.reported,
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

  ReturnFlowState get current => state;

  /// 줄 상품 바코드(작업 줄 → 상품 정보). 모르면 null.
  String? barcodeOf(TaskLineView l) =>
      l.barcode ?? ref.read(productHintsProvider).bySku(l.sku)?.barcode;

  /// 냉장·냉동이면 온도 확인을 묻는다(상품 정보 온도대). 모르면 묻지 않는다.
  bool needsCold(TaskLineView l) =>
      switch (ref.read(productHintsProvider).bySku(l.sku)?.zone) {
        StorageZone.chilled || StorageZone.frozen => true,
        _ => false,
      };

  void setCold(bool ok) => state = state.copyWith(coldOk: () => ok);

  void reported() => state = state.copyWith(reported: true);

  /// 포장 위치 → 상품(1개씩) → 선반 칸.
  LocScan scan(ReturnPiece p, String code) {
    final c = code.trim();
    final bc = barcodeOf(p.line);
    final LocScan r;
    if (bc != null && !isMfcLocation(c)) {
      if (!state.atFrom) {
        r = LocScan.needFrom;
      } else if (c != bc) {
        r = LocScan.wrongItem;
      } else if (state.qty >= p.left) {
        r = LocScan.over;
      } else {
        state = state.copyWith(qty: state.qty + 1);
        r = LocScan.ok;
      }
    } else if (!isMfcLocation(c)) {
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

  void setQty(int q) => state = state.copyWith(qty: q);

  /// 복귀할 수 있는지 — 칸·수량, 냉장·냉동이면 온도 확인 "예".
  bool canSubmit(ReturnPiece p) =>
      state.atFrom &&
      state.to != null &&
      state.qty > 0 &&
      (!needsCold(p.line) || state.coldOk == true);

  Future<void> submit(TaskDetailView t, ReturnPiece p) async {
    final to = state.to;
    final qty = state.qty;
    if (!canSubmit(p) || to == null) return;
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
              if (s.reported) {
                return ResultView(
                  key: const ValueKey('return-reported'),
                  icon: Icons.report_problem_outlined,
                  text: l10n.issueReported,
                  action: l10n.nextTask,
                  onAction: () async =>
                      backToSession(context, WorkArea.stockMove),
                );
              }
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
              final qty = s.qty;
              final bc = ctl.barcodeOf(p.line);
              final cold = ctl.needsCold(p.line);
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
                    testValues: [
                      TestScan(l10n.tsFrom, p.from),
                      if (bc != null) TestScan(l10n.tsProduct, bc),
                      TestScan(l10n.tsWrongProduct, '0000000000000'),
                      for (final x in p.suggested) TestScan(l10n.tsShelf, x),
                      TestScan(l10n.tsWrong, 'A-S9-09-9-99'),
                    ],
                    testActions: [
                      if (bc != null)
                        TestAction('fill', l10n.testFillMove, () {
                          while (ctl.current.qty < p.left &&
                              ctl.scan(p, bc) == LocScan.ok) {}
                        }),
                    ],
                    label: s.atFrom
                        ? l10n.returnShelfScanItemOrShelf
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
                  Text(
                    bc != null ? l10n.moveScanned(qty) : l10n.moveNoBarcode,
                    key: const ValueKey('product-check'),
                  ),
                  QtyStepper(
                    id: 'return-qty',
                    label: l10n.moveQtyDrop,
                    value: qty,
                    max: bc != null ? qty : p.left,
                    enabled: s.atFrom,
                    onChanged: ctl.setQty,
                  ),
                  if (cold) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.returnColdQuestion,
                      style: theme.textTheme.titleSmall,
                    ),
                    SegmentedButton<bool>(
                      key: const ValueKey('return-cold'),
                      emptySelectionAllowed: true,
                      segments: [
                        ButtonSegment(
                          value: true,
                          label: Text(l10n.returnColdYes),
                        ),
                        ButtonSegment(
                          value: false,
                          label: Text(l10n.returnColdNo),
                        ),
                      ],
                      selected: {?s.coldOk},
                      onSelectionChanged: (v) {
                        if (v.isNotEmpty) ctl.setCold(v.first);
                      },
                    ),
                    if (s.coldOk == false)
                      Text(
                        l10n.returnColdNoHelp,
                        key: const ValueKey('return-cold-no'),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                  ],
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IssueButton(
                      id: 'return-issue',
                      area: 'return',
                      targetId: taskId,
                      location: p.from,
                      qty: p.left,
                      issues: const [
                        FieldIssue.temperature,
                        FieldIssue.damaged,
                        FieldIssue.sourceEmpty,
                        FieldIssue.targetUnusable,
                      ],
                      onReported: (_) => ctl.reported(),
                    ),
                  ),
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
                    onPressed: ctl.canSubmit(p) ? () => ctl.submit(t, p) : null,
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
