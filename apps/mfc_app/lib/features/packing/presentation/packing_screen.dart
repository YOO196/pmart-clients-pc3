import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../work/domain/work.dart';
import '../../work/presentation/work_screens.dart' show backToSession;
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
                  // D-5: 포장을 시작하면 예상 포장 시간과 함께 배차를 요청한다.
                  if (s.state != ShipmentState.cancelled)
                    DispatchSection(taskId: widget.taskId, shipment: s),
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
                    else ...[
                      Text(
                        l10n.packingFinished,
                        key: const ValueKey('packing-finished'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        key: const ValueKey('next-task'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                        ),
                        onPressed: () =>
                            backToSession(context, WorkArea.pickPack),
                        child: Text(l10n.nextTask),
                      ),
                    ],
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

/// 배차 요청 — 직원 요청만 쓴다(자동 요청 없음, 2026-11-10). 서버에 요청이 있으면 그것만 보이고,
/// 없으면 예상 포장 시간을 받아 요청한다. 서버가 자동 요청(AUTO_ON_READY)을 보내면 숨기지 않고 알린다.
class DispatchSection extends ConsumerStatefulWidget {
  const DispatchSection({
    super.key,
    required this.taskId,
    required this.shipment,
  });

  final String taskId;
  final ShipmentView shipment;

  @override
  ConsumerState<DispatchSection> createState() => _DispatchSectionState();
}

class _DispatchSectionState extends ConsumerState<DispatchSection> {
  final _minutes = TextEditingController();

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final packing = ref.watch(packingProvider(widget.taskId));
    final ctl = ref.read(packingProvider(widget.taskId).notifier);
    final shipmentId = widget.shipment.shipmentId;

    if (widget.shipment.dispatchRequest case final d?) {
      return Card(
        key: const ValueKey('dispatch-requested'),
        color: d.trigger == DispatchTrigger.manual
            ? null
            : theme.colorScheme.errorContainer,
        child: ListTile(
          leading: const Icon(Icons.delivery_dining),
          title: Text(
            d.trigger == DispatchTrigger.manual
                ? l10n.dispatchRequested
                : l10n.dispatchRequestedAuto,
          ),
          subtitle: Text(
            l10n.dispatchReadyAt(formatSeoulTime(d.estimatedReadyAt)),
          ),
        ),
      );
    }

    final minutes = int.tryParse(_minutes.text.trim());
    final valid = minutes != null && minutes >= 1 && minutes <= 180;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 자동 요청이 없어 직원이 잊으면 배차가 시작되지 않는다.
          if (widget.shipment.state == ShipmentState.ready &&
              !packing.dispatchUnknown)
            Text(
              l10n.dispatchMissing,
              key: const ValueKey('dispatch-missing'),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          if (!packing.dispatchUnknown)
            TextField(
              key: const ValueKey('pack-minutes'),
              controller: _minutes,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.packMinutesLabel,
                helperText: l10n.packMinutesHelp,
                errorText: _minutes.text.isNotEmpty && !valid
                    ? l10n.packMinutesInvalid
                    : null,
              ),
            ),
          if (packing.dispatchUnknown)
            Text(l10n.dispatchUnknown, key: const ValueKey('dispatch-unknown')),
          if (packing.dispatchRejectCode case final c?)
            Text(
              c == PackProblemCode.invalidState
                  ? l10n.dispatchInvalidState
                  : l10n.dispatchRejected,
              key: const ValueKey('dispatch-rejected'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          const SizedBox(height: 8),
          CommandButton(
            key: const ValueKey('request-dispatch'),
            busy: packing.dispatchBusy,
            label: packing.dispatchUnknown
                ? l10n.checkAgain
                : l10n.requestDispatch,
            onPressed: packing.dispatchUnknown
                ? () => ctl.recheckDispatch(shipmentId)
                : valid
                ? () => ctl.requestDispatch(shipmentId, minutes)
                : null,
          ),
        ],
      ),
    );
  }
}
