import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/printer/label.dart';
import '../../../shared/printer/printer_ui.dart';
import '../../../shared/scanner/scan_input.dart';
import '../../../shared/scanner/scanner.dart';
import '../../../shared/ui_state_of.dart';
import '../../tasks/domain/task_list.dart';
import '../../tasks/presentation/task_controllers.dart';
import '../domain/packing.dart';
import 'packing_controller.dart';

String packageStateText(AppLocalizations l10n, PackageState s) => switch (s) {
  PackageState.open => l10n.pkgOpen,
  PackageState.sealed => l10n.pkgSealed,
  PackageState.handedOver => l10n.pkgHandedOver,
  PackageState.invalidated => l10n.pkgInvalidated,
  PackageState.voided => l10n.pkgVoided,
  PackageState.unknown => l10n.tsUnknown,
};

String dispatchStateText(AppLocalizations l10n, DispatchState s) => switch (s) {
  DispatchState.searching => l10n.dspSearching,
  DispatchState.offering => l10n.dspOffering,
  DispatchState.assigned => l10n.dspAssigned,
  DispatchState.failed => l10n.dspFailed,
  DispatchState.cancelled => l10n.dspCancelled,
  DispatchState.unknown => l10n.tsUnknown,
};

/// 패킹(WK-07). 유효 포장 합계 = 확정 피킹량이어야 준비 완료다(서버 판정).
class PackingScreen extends ConsumerStatefulWidget {
  const PackingScreen({super.key, required this.taskId});

  final String taskId;

  @override
  ConsumerState<PackingScreen> createState() => _PackingScreenState();
}

class _PackingScreenState extends ConsumerState<PackingScreen> {
  Future<void> _repack(ShipmentView s, PackageView p) async {
    final l10n = AppLocalizations.of(context);
    final reason = await showDialog<RepackReason>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.repackTitle),
        children: [
          for (final r in RepackReason.values)
            SimpleDialogOption(
              key: ValueKey('repack-${r.name}'),
              onPressed: () => Navigator.of(context).pop(r),
              child: Text(switch (r) {
                RepackReason.damagedBag => l10n.repackDamaged,
                RepackReason.contentChange => l10n.repackContent,
                RepackReason.labelUnreadable => l10n.repackLabel,
                RepackReason.shortageAdjust => l10n.repackShortage,
              }),
            ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    final outcome = await ref
        .read(packingProvider(widget.taskId).notifier)
        .repack(s.shipmentId, p, reason);
    if (!mounted) return;
    if (outcome is PackRejected) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.repackRejected)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final taskValue = ref.watch(taskDetailProvider(widget.taskId));
    final packing = ref.watch(packingProvider(widget.taskId));
    final ctl = ref.read(packingProvider(widget.taskId).notifier);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.packingTitle)),
      body: UiStateView<TaskDetailView>(
        state: uiStateOf(taskValue),
        onRetry: () => ref.invalidate(taskDetailProvider(widget.taskId)),
        ready: (context, task) {
          final shipmentId = task.shipmentId;
          if (shipmentId == null) return Center(child: Text(l10n.noShipment));
          final shipmentValue = ref.watch(shipmentProvider(shipmentId));
          return UiStateView<ShipmentView>(
            state: uiStateOf(shipmentValue),
            onRetry: () => ref.invalidate(shipmentProvider(shipmentId)),
            ready: (context, s) {
              final ready = s.state == ShipmentState.ready;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    ready ? l10n.shipmentReady : l10n.shipmentPreparing,
                    key: const ValueKey('shipment-state'),
                    style: theme.textTheme.titleLarge,
                  ),
                  for (final l in task.lines)
                    ListTile(
                      key: ValueKey('pack-line-${l.orderLineId}'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(l.productName ?? l.sku),
                      subtitle: Text(
                        l10n.packCounts(
                          l.plannedQty,
                          s.packedByLine[l.orderLineId] ?? 0,
                          packing.inBag(l.orderLineId),
                        ),
                      ),
                    ),
                  if (!ready) ...[
                    SegmentedButton<TemperatureZone>(
                      segments: [
                        ButtonSegment(
                          value: TemperatureZone.chilled,
                          label: Text(l10n.zoneChilled),
                        ),
                        ButtonSegment(
                          value: TemperatureZone.frozen,
                          label: Text(l10n.zoneFrozen),
                        ),
                        ButtonSegment(
                          value: TemperatureZone.ambient,
                          label: Text(l10n.zoneAmbient),
                        ),
                      ],
                      selected: {packing.zone},
                      onSelectionChanged: (v) => ctl.setZone(v.first),
                    ),
                    ScanInput(
                      id: 'pack-scan',
                      label: l10n.scanHint,
                      cameraTitle: l10n.packCameraTitle,
                      onScan: (code) => switch (ctl.scan(task, s, code)) {
                        PackScan.matched => const ScanFeedback.ok(),
                        PackScan.wrongItem => ScanFeedback.error(
                          l10n.packWrongItem,
                        ),
                        PackScan.overExpected => ScanFeedback.error(
                          l10n.packOver,
                        ),
                      },
                    ),
                    if (packing.lastScan case final r?
                        when r != PackScan.matched)
                      Text(
                        r == PackScan.wrongItem
                            ? l10n.packWrongItem
                            : l10n.packOver,
                        key: const ValueKey('pack-scan-error'),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    if (packing.sealUnknown)
                      Text(
                        l10n.sealUnknown,
                        key: const ValueKey('seal-unknown'),
                      ),
                    if (packing.rejectCode case final c?)
                      Text(
                        c == PackProblemCode.contentMismatch
                            ? l10n.sealMismatch
                            : l10n.sealRejected,
                        key: const ValueKey('seal-rejected'),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    const SizedBox(height: 8),
                    CommandButton(
                      key: const ValueKey('seal'),
                      busy: packing.busy,
                      label: packing.sealUnknown ? l10n.checkAgain : l10n.seal,
                      onPressed: (packing.bag.isNotEmpty || packing.sealUnknown)
                          ? () => ctl.seal(task, s)
                          : null,
                    ),
                  ],
                  const Divider(height: 32),
                  Text(l10n.packagesTitle, style: theme.textTheme.titleMedium),
                  for (final p in s.packages)
                    ListTile(
                      key: ValueKey('package-${p.packageId}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${packageStateText(l10n, p.state)} · v${p.packageVersion}',
                      ),
                      // 라벨 프린터는 미정이라 QR 값을 보인다. 재출력은 같은 포장 ID.
                      subtitle: Text(p.qrCode ?? '-'),
                      // 인계 판정·라이더 픽업 예정은 포장 단위로 본다.
                      onTap:
                          p.state == PackageState.sealed ||
                              p.state == PackageState.handedOver
                          ? () => context.push(
                              '/packages/${p.packageId}/handover',
                            )
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 라벨 재출력은 같은 포장 ID·같은 QR(서버 값). 밀봉된 포장만.
                          if (p.state == PackageState.sealed &&
                              p.qrCode != null)
                            TextButton(
                              key: ValueKey('print-${p.packageId}'),
                              onPressed: () => printPackageLabel(
                                context,
                                ref,
                                PackageLabel.of(s, p),
                              ),
                              child: Text(l10n.printLabel),
                            ),
                          if (p.canRepack)
                            TextButton(
                              key: ValueKey('repack-${p.packageId}'),
                              onPressed: () => _repack(s, p),
                              child: Text(l10n.repack),
                            ),
                        ],
                      ),
                    ),
                  if (ready) ...[
                    const SizedBox(height: 16),
                    if (!packing.packingFinished)
                      FilledButton(
                        key: const ValueKey('finish-packing'),
                        onPressed: () => ctl.finish(task, s),
                        child: Text(l10n.finishPacking),
                      )
                    else
                      Text(
                        l10n.packingFinished,
                        key: const ValueKey('packing-finished'),
                      ),
                    const SizedBox(height: 8),
                    CommandButton(
                      key: const ValueKey('request-dispatch'),
                      busy: packing.busy,
                      label: l10n.requestDispatch,
                      onPressed:
                          (s.deliveryId != null &&
                              packing.dispatch?.state != DispatchState.assigned)
                          ? () => ctl.requestDispatch(s)
                          : null,
                    ),
                    if (s.deliveryId == null) Text(l10n.noDeliveryYet),
                    if (packing.dispatch case final d?)
                      Text(
                        dispatchStateText(l10n, d.state),
                        key: const ValueKey('dispatch-state'),
                      ),
                    if (packing.rejectCode == PackProblemCode.orderCancelled)
                      Text(
                        l10n.dispatchOrderCancelled,
                        key: const ValueKey('dispatch-cancelled'),
                      ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}
