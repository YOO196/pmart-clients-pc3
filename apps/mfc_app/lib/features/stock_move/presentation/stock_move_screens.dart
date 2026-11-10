import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/field_widgets.dart';
import '../../../shared/issue_report.dart';
import '../../../shared/scanner/scan_input.dart';
import '../../../shared/scanner/scanner.dart';
import '../../work/domain/work.dart';
import '../../work/presentation/work_screens.dart' show backToSession;
import '../domain/stock_move.dart';
import 'stock_move_controllers.dart';

String locScanText(AppLocalizations l10n, LocScan r) => switch (r) {
  LocScan.ok => '',
  LocScan.wrongPlace => l10n.moveWrongPlace,
  LocScan.notLocation => l10n.moveNotLocation,
  LocScan.needFrom => l10n.moveNeedFrom,
  LocScan.wrongItem => l10n.moveWrongItem,
  LocScan.over => l10n.moveOver,
};

Future<void> _next(BuildContext context) async =>
    backToSession(context, WorkArea.stockMove);

/// 상품 확인 줄 — 바코드를 알면 "스캔해 센 수", 모르면 확인할 수 없다는 안내.
class _ProductCheck extends StatelessWidget {
  const _ProductCheck({required this.barcodeKnown, required this.counted});

  final bool barcodeKnown;
  final int counted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Text(
      barcodeKnown ? l10n.moveScanned(counted) : l10n.moveNoBarcode,
      key: const ValueKey('product-check'),
      style: barcodeKnown
          ? theme.textTheme.titleMedium
          : TextStyle(color: theme.colorScheme.error),
    );
  }
}

/// 이동·보충 지시: 출발 칸 → 상품(1개씩 스캔) → 카트(집어 올리기) → 도착 칸(내려놓기).
class MoveScreen extends ConsumerWidget {
  const MoveScreen({super.key, required this.moveId});

  final String moveId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = ref.watch(moveFlowProvider(moveId));
    final ctl = ref.read(moveFlowProvider(moveId).notifier);
    final m = s.move;
    final title = m?.kind == MoveKind.replenish
        ? l10n.typeReplenish
        : l10n.typeMove;
    final barcode = ctl.productBarcode;

    final Widget body = switch (s.phase) {
      MovePhase.loading => const Center(child: CircularProgressIndicator()),
      MovePhase.loadError => ResultView(
        icon: Icons.cloud_off,
        text: l10n.moveLoadError,
        action: l10n.retry,
        onAction: ctl.load,
      ),
      MovePhase.cancelled => ResultView(
        key: const ValueKey('move-cancelled'),
        icon: Icons.cancel_outlined,
        text: l10n.moveCancelled,
        action: l10n.nextTask,
        onAction: () => _next(context),
      ),
      MovePhase.reported => ResultView(
        key: const ValueKey('move-reported'),
        icon: Icons.report_problem_outlined,
        text: l10n.issueReported,
        action: l10n.nextTask,
        onAction: () => _next(context),
      ),
      MovePhase.done => ResultView(
        key: const ValueKey('move-done'),
        icon: Icons.check_circle,
        text: l10n.moveDone(m?.droppedQty ?? 0, m?.toLocation ?? '-'),
        action: l10n.nextTask,
        onAction: () => _next(context),
      ),
      MovePhase.pickUp || MovePhase.drop => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StepHeader(
            names: [l10n.moveStepPick, l10n.moveStepDrop],
            current: s.phase == MovePhase.pickUp ? 0 : 1,
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          ctl.productName ?? m!.sku,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      if (m!.urgent) Chip(label: Text(l10n.urgent)),
                    ],
                  ),
                  Text([m.sku, l10n.lot(m.lotId)].join(' · ')),
                  Text(l10n.moveProgress(m.qty, m.pickedQty, m.droppedQty)),
                  if (m.state == MoveState.cancelPending)
                    Text(
                      l10n.moveCancelPending,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (s.phase == MovePhase.pickUp) ...[
            TargetLine(
              key: const ValueKey('target-from'),
              label: l10n.moveFrom,
              code: m.fromLocation,
              confirmed: s.atFrom,
            ),
            TargetLine(
              key: const ValueKey('target-cart'),
              label: l10n.moveCart,
              code: s.cart ?? l10n.moveCartScan,
              confirmed: s.cart != null,
            ),
          ] else
            TargetLine(
              key: const ValueKey('target-to'),
              label: m.state == MoveState.cancelPending
                  ? l10n.moveBackTo
                  : l10n.moveTo,
              code: m.dropTarget,
              confirmed: s.atTo,
            ),
          const SizedBox(height: 8),
          ScanInput(
            id: 'move-scan',
            testValues: s.phase == MovePhase.pickUp
                ? [
                    TestScan(l10n.tsFrom, m.fromLocation),
                    if (barcode != null) TestScan(l10n.tsProduct, barcode),
                    TestScan(l10n.tsWrongProduct, '0000000000000'),
                    TestScan(l10n.tsCart, 'CRT-C-01'),
                    TestScan(l10n.tsWrong, 'A-S9-09-9-99'),
                  ]
                : [
                    TestScan(l10n.tsTo, m.dropTarget),
                    TestScan(l10n.tsWrong, 'A-S9-09-9-99'),
                  ],
            testActions: [
              if (s.phase == MovePhase.pickUp && barcode != null)
                TestAction('fill', l10n.testFillMove, () {
                  while (ctl.current.qty < m.toPick &&
                      ctl.scan(barcode) == LocScan.ok) {}
                }),
            ],
            label: s.phase == MovePhase.pickUp
                ? (s.atFrom ? l10n.moveScanItemOrCart : l10n.moveScanPick)
                : l10n.moveScanDrop,
            cameraTitle: title,
            autofocus: false,
            onScan: (code) => switch (ctl.scan(code)) {
              LocScan.ok => const ScanFeedback.ok(),
              final r => ScanFeedback.error(locScanText(l10n, r)),
            },
          ),
          SizedBox(
            height: 20,
            child: s.lastScan != null && s.lastScan != LocScan.ok
                ? Text(
                    locScanText(l10n, s.lastScan!),
                    key: const ValueKey('move-scan-error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  )
                : null,
          ),
          if (s.phase == MovePhase.pickUp) ...[
            _ProductCheck(barcodeKnown: barcode != null, counted: s.qty),
            // 바코드를 알면 스캔으로만 늘린다(줄이기만 가능). 모르면 직접 넣는다.
            QtyStepper(
              id: 'move-qty',
              label: l10n.moveQtyPick,
              value: s.qty,
              max: barcode != null ? s.qty : m.toPick,
              enabled: !s.unknown && s.atFrom,
              onChanged: ctl.setQty,
            ),
          ] else
            QtyStepper(
              id: 'move-qty',
              label: l10n.moveQtyDrop,
              value: s.qty,
              max: m.onCartQty,
              enabled: !s.unknown,
              onChanged: ctl.setQty,
            ),
          const Spacer(),
          if (s.code case final c?)
            Text(
              l10n.inspectRejected(c),
              key: const ValueKey('move-rejected'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          if (s.unknown)
            Text(l10n.inspectUnknown, key: const ValueKey('move-unknown')),
          if (!s.unknown)
            Align(
              alignment: Alignment.centerLeft,
              child: IssueButton(
                id: 'move-issue',
                area: 'move',
                targetId: moveId,
                location: s.phase == MovePhase.pickUp
                    ? m.fromLocation
                    : m.dropTarget,
                qty: s.phase == MovePhase.pickUp ? m.toPick : m.onCartQty,
                issues: s.phase == MovePhase.pickUp
                    ? const [
                        FieldIssue.sourceEmpty,
                        FieldIssue.sourceShort,
                        FieldIssue.damaged,
                        FieldIssue.locationBlocked,
                      ]
                    : const [
                        FieldIssue.targetUnusable,
                        FieldIssue.locationBlocked,
                      ],
                onReported: (_) => ctl.reported(),
              ),
            ),
          CommandButton(
            key: const ValueKey('move-submit'),
            busy: s.busy,
            label: s.unknown
                ? l10n.checkAgain
                : s.phase == MovePhase.pickUp
                ? l10n.movePickUp
                : l10n.moveDrop,
            onPressed:
                (s.phase == MovePhase.pickUp ? ctl.canPickUp : ctl.canDrop)
                ? ctl.submit
                : null,
          ),
        ],
      ),
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(16), child: body),
      ),
    );
  }
}

/// 적치: 출발 위치 → 상품(1개씩 스캔) → 도착 선반(추천) → 적치(이때부터 판매 가능).
class PutawayScreen extends ConsumerWidget {
  const PutawayScreen({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = ref.watch(putawayFlowProvider(taskId));
    final ctl = ref.read(putawayFlowProvider(taskId).notifier);
    final barcode = ctl.productBarcode;

    final Widget body = switch (s.phase) {
      PutawayPhase.loading => const Center(child: CircularProgressIndicator()),
      PutawayPhase.loadError => ResultView(
        icon: Icons.cloud_off,
        text: l10n.moveLoadError,
        action: l10n.retry,
        onAction: ctl.load,
      ),
      PutawayPhase.notFound => ResultView(
        key: const ValueKey('putaway-not-found'),
        icon: Icons.search_off,
        text: l10n.inspectNotFound,
        action: l10n.nextTask,
        onAction: () => _next(context),
      ),
      PutawayPhase.reported => ResultView(
        key: const ValueKey('putaway-reported'),
        icon: Icons.report_problem_outlined,
        text: l10n.issueReported,
        action: l10n.nextTask,
        onAction: () => _next(context),
      ),
      PutawayPhase.done => ResultView(
        key: const ValueKey('putaway-done'),
        icon: Icons.check_circle,
        text: l10n.putawayDone,
        action: l10n.nextTask,
        onAction: () => _next(context),
      ),
      PutawayPhase.editing => () {
        final t = s.task!;
        final suggested = t.suggestedLocations;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.productName ?? t.sku,
                      style: theme.textTheme.titleLarge,
                    ),
                    Text('${t.sku} · ${l10n.lot(t.lotId)}'),
                    Text(l10n.putawayRemaining(t.remainingQty)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TargetLine(
              key: const ValueKey('target-putaway-from'),
              label: l10n.moveFrom,
              code: t.locationCode,
              confirmed: s.atFrom,
            ),
            TargetLine(
              key: const ValueKey('target-putaway'),
              label: l10n.moveTo,
              code:
                  s.to ??
                  (suggested.isNotEmpty
                      ? suggested.first
                      : l10n.putawayScanShelf),
              confirmed: s.to != null,
            ),
            if (suggested.isNotEmpty)
              Text(
                l10n.returnShelfSuggested(suggested.join(', ')),
                key: const ValueKey('putaway-suggested'),
              )
            else
              Text(
                l10n.putawayNoSuggestion,
                key: const ValueKey('putaway-no-suggestion'),
                style: theme.textTheme.bodySmall,
              ),
            if (s.to case final to?
                when suggested.isNotEmpty && !suggested.contains(to))
              Text(
                l10n.returnShelfNotSuggested,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            const SizedBox(height: 8),
            ScanInput(
              id: 'putaway-scan',
              testValues: [
                TestScan(l10n.tsFrom, t.locationCode),
                if (barcode != null) TestScan(l10n.tsProduct, barcode),
                TestScan(l10n.tsWrongProduct, '0000000000000'),
                for (final x in suggested) TestScan(l10n.tsShelf, x),
                TestScan(l10n.tsShelf, 'C-S1-03-2-05'),
                TestScan(l10n.tsWrong, 'hello'),
              ],
              testActions: [
                if (barcode != null)
                  TestAction('fill', l10n.testFillMove, () {
                    while (ctl.current.qty < t.remainingQty &&
                        ctl.scan(barcode) == LocScan.ok) {}
                  }),
              ],
              label: !s.atFrom
                  ? l10n.putawayScanFrom
                  : l10n.putawayScanItemOrShelf,
              cameraTitle: l10n.typePutaway,
              autofocus: false,
              onScan: (code) => switch (ctl.scan(code)) {
                LocScan.ok => const ScanFeedback.ok(),
                final r => ScanFeedback.error(locScanText(l10n, r)),
              },
            ),
            SizedBox(
              height: 20,
              child: s.lastScan != null && s.lastScan != LocScan.ok
                  ? Text(
                      locScanText(l10n, s.lastScan!),
                      key: const ValueKey('putaway-scan-error'),
                      style: TextStyle(color: theme.colorScheme.error),
                    )
                  : null,
            ),
            _ProductCheck(barcodeKnown: barcode != null, counted: s.qty),
            QtyStepper(
              id: 'putaway-qty',
              label: l10n.putawayQty,
              value: s.qty,
              max: barcode != null ? s.qty : t.remainingQty,
              enabled: !s.unknown && s.atFrom,
              onChanged: ctl.setQty,
            ),
            const Spacer(),
            if (s.code case final c?)
              Text(
                l10n.inspectRejected(c),
                key: const ValueKey('putaway-rejected'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            if (s.unknown)
              Text(l10n.inspectUnknown, key: const ValueKey('putaway-unknown')),
            if (!s.unknown)
              Align(
                alignment: Alignment.centerLeft,
                child: IssueButton(
                  id: 'putaway-issue',
                  area: 'putaway',
                  targetId: taskId,
                  location: s.to ?? t.locationCode,
                  qty: t.remainingQty,
                  issues: const [
                    FieldIssue.targetUnusable,
                    FieldIssue.sourceShort,
                    FieldIssue.damaged,
                  ],
                  onReported: (_) => ctl.reported(),
                ),
              ),
            CommandButton(
              key: const ValueKey('putaway-submit'),
              busy: s.busy,
              label: s.unknown ? l10n.checkAgain : l10n.putawaySubmit,
              onPressed: s.unknown || (s.to != null && s.qty > 0)
                  ? ctl.submit
                  : null,
            ),
          ],
        );
      }(),
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.typePutaway)),
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(16), child: body),
      ),
    );
  }
}
