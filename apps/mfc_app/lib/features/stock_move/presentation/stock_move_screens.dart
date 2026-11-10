import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/field_widgets.dart';
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
};

Future<void> _next(BuildContext context) async =>
    backToSession(context, WorkArea.stockMove);

/// 이동·보충 지시: 출발 칸 → 카트(집어 올리기) → 도착 칸(내려놓기).
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
                        child: Text(m!.sku, style: theme.textTheme.titleLarge),
                      ),
                      if (m.urgent) Chip(label: Text(l10n.urgent)),
                    ],
                  ),
                  Text(l10n.lot(m.lotId)),
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
            label: s.phase == MovePhase.pickUp
                ? l10n.moveScanPick
                : l10n.moveScanDrop,
            cameraTitle: title,
            autofocus: false,
            onScan: (code) => switch (ctl.scan(code)) {
              LocScan.ok => const ScanFeedback.ok(),
              final r => ScanFeedback.error(locScanText(l10n, r)),
            },
          ),
          if (s.lastScan case final r? when r != LocScan.ok)
            Text(
              locScanText(l10n, r),
              key: const ValueKey('move-scan-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          const SizedBox(height: 8),
          QtyStepper(
            id: 'move-qty',
            label: s.phase == MovePhase.pickUp
                ? l10n.moveQtyPick
                : l10n.moveQtyDrop,
            value: s.qty,
            max: s.phase == MovePhase.pickUp ? m.toPick : m.onCartQty,
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
          const SizedBox(height: 8),
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

/// 적치: 도착 선반 스캔 → 수량 → 적치(이때부터 판매 가능).
class PutawayScreen extends ConsumerWidget {
  const PutawayScreen({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = ref.watch(putawayFlowProvider(taskId));
    final ctl = ref.read(putawayFlowProvider(taskId).notifier);

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
      PutawayPhase.done => ResultView(
        key: const ValueKey('putaway-done'),
        icon: Icons.check_circle,
        text: l10n.putawayDone,
        action: l10n.nextTask,
        onAction: () => _next(context),
      ),
      PutawayPhase.editing => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.task!.sku, style: theme.textTheme.titleLarge),
                  Text(l10n.inspectFrom(s.task!.locationCode)),
                  Text(l10n.putawayRemaining(s.task!.remainingQty)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TargetLine(
            key: const ValueKey('target-putaway'),
            label: l10n.moveTo,
            code: s.to ?? l10n.putawayScanShelf,
            confirmed: s.to != null,
          ),
          const SizedBox(height: 8),
          ScanInput(
            id: 'putaway-scan',
            label: l10n.putawayScanShelf,
            cameraTitle: l10n.typePutaway,
            autofocus: false,
            onScan: (code) => switch (ctl.scan(code)) {
              LocScan.ok => const ScanFeedback.ok(),
              final r => ScanFeedback.error(locScanText(l10n, r)),
            },
          ),
          if (s.lastScan case final r? when r != LocScan.ok)
            Text(
              locScanText(l10n, r),
              key: const ValueKey('putaway-scan-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          const SizedBox(height: 8),
          QtyStepper(
            id: 'putaway-qty',
            label: l10n.putawayQty,
            value: s.qty,
            max: s.task!.remainingQty,
            enabled: !s.unknown,
            onChanged: ctl.setQty,
          ),
          Text(l10n.putawayHelp, style: theme.textTheme.bodySmall),
          const Spacer(),
          if (s.code case final c?)
            Text(
              l10n.inspectRejected(c),
              key: const ValueKey('putaway-rejected'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          if (s.unknown)
            Text(l10n.inspectUnknown, key: const ValueKey('putaway-unknown')),
          const SizedBox(height: 8),
          CommandButton(
            key: const ValueKey('putaway-submit'),
            busy: s.busy,
            label: s.unknown ? l10n.checkAgain : l10n.putawaySubmit,
            onPressed: s.unknown || (s.to != null && s.qty > 0)
                ? ctl.submit
                : null,
          ),
        ],
      ),
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.typePutaway)),
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(16), child: body),
      ),
    );
  }
}
