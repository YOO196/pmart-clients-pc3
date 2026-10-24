import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../domain/delivery.dart';
import 'delivery_controller.dart';

String executionText(AppLocalizations l10n, ExecutionState s) => switch (s) {
  ExecutionState.assigned => l10n.exAssigned,
  ExecutionState.arrivedAtStore => l10n.exAtStore,
  ExecutionState.pickedUp => l10n.exPickedUp,
  ExecutionState.arrivedAtCustomer => l10n.exAtCustomer,
  ExecutionState.completed => l10n.exCompleted,
  ExecutionState.failed => l10n.exFailed,
  ExecutionState.cancelled => l10n.exCancelled,
  _ => l10n.exOther,
};

String handoverText(AppLocalizations l10n, PackageHandover h) =>
    switch (h.phase) {
      HandoverPhase.waiting => l10n.hoWaiting,
      HandoverPhase.authorizing || HandoverPhase.committing => l10n.hoWorking,
      HandoverPhase.handedOver => l10n.hoDone,
      HandoverPhase.checking => l10n.hoChecking,
      HandoverPhase.rejected => handoverRejectText(l10n, h.rejectCode),
      HandoverPhase.stopped => l10n.hoStopped,
    };

String handoverRejectText(AppLocalizations l10n, String? code) =>
    switch (code) {
      HandoverProblemCode.alreadyHandedOver => l10n.hoAlready,
      HandoverProblemCode.packageInvalidated => l10n.hoInvalidated,
      HandoverProblemCode.deliveryMismatch => l10n.hoMismatch,
      HandoverProblemCode.fenceActive => l10n.hoFenceActive,
      'FORBIDDEN' => l10n.hoForbidden,
      _ => l10n.hoRejected,
    };

String queueText(AppLocalizations l10n, QueueItemState s) => switch (s) {
  QueueItemState.queued => l10n.qQueued,
  QueueItemState.awaitingConfirm => l10n.qAwaiting,
  QueueItemState.applied => l10n.qApplied,
  QueueItemState.rejected => l10n.qRejected,
  QueueItemState.checking => l10n.qChecking,
};

/// 배송 수행: 가게 도착 → QR 인계 → 픽업 완료 → 고객 도착 → 전달 완료. 화면 상태는 서버 확정으로만 바꾼다.
class DeliveryScreen extends ConsumerStatefulWidget {
  const DeliveryScreen({super.key, required this.deliveryId});

  final String deliveryId;

  @override
  ConsumerState<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends ConsumerState<DeliveryScreen> {
  final _scan = TextEditingController();
  final _focus = FocusNode();
  CompletionMethod _method = CompletionMethod.contactless;
  Placement _placement = Placement.frontDoor;
  bool _hydrated = false;

  @override
  void dispose() {
    _scan.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final provider = deliveryProvider(widget.deliveryId);
    final flow = ref.watch(deliveryFlowProvider(widget.deliveryId));
    final ctl = ref.read(deliveryFlowProvider(widget.deliveryId).notifier);
    final queue =
        ref.watch(deliveryQueueProvider(widget.deliveryId)).value ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.deliveryNumber(widget.deliveryId)),
        actions: [
          IconButton(
            key: const ValueKey('sync'),
            onPressed: ctl.sync,
            icon: const Icon(Icons.sync),
            tooltip: l10n.sync,
          ),
        ],
      ),
      body: UiStateView<DeliveryView>(
        state: uiStateOf(ref.watch(provider)),
        onRetry: () => ref.invalidate(provider),
        ready: (context, d) {
          if (!_hydrated) {
            _hydrated = true;
            Future.microtask(() => ctl.hydrate(d));
          }
          final done = d.packageIds
              .where((p) => flow.phaseOf(p).phase == HandoverPhase.handedOver)
              .length;
          final allHanded =
              d.packageIds.isNotEmpty && done == d.packageIds.length;
          final busyQueue = queue.any((q) => q.isOpen);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                executionText(l10n, d.state),
                key: const ValueKey('execution-state'),
                style: theme.textTheme.headlineSmall,
              ),
              if (queue.any((q) => q.state == QueueItemState.checking))
                Text(l10n.doNotRepeat, key: const ValueKey('do-not-repeat')),
              for (final q in queue)
                Text(
                  '${queueText(l10n, q.state)}${q.rejectCode == null ? '' : ' · ${q.rejectCode}'}',
                  key: ValueKey('queue-${q.id}'),
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: 12),
              ...switch (d.state) {
                ExecutionState.assigned => [
                  FilledButton(
                    key: const ValueKey('arrive-store'),
                    onPressed: busyQueue ? null : ctl.arriveAtStore,
                    child: Text(l10n.arriveStore),
                  ),
                ],
                ExecutionState.arrivedAtStore => [
                  Text(
                    l10n.handoverProgress(done, d.packageIds.length),
                    key: const ValueKey('handover-progress'),
                    style: theme.textTheme.titleMedium,
                  ),
                  TextField(
                    key: const ValueKey('qr-scan'),
                    controller: _scan,
                    focusNode: _focus,
                    autofocus: true,
                    decoration: InputDecoration(labelText: l10n.scanQr),
                    onSubmitted: (v) async {
                      if (v.trim().isEmpty) return;
                      _scan.clear();
                      await ctl.scan(d, v);
                      _focus.requestFocus();
                    },
                  ),
                  if (flow.lastScan case final s?
                      when s != ScanVerdict.accepted)
                    Text(
                      switch (s) {
                        ScanVerdict.otherDelivery => l10n.scanOtherDelivery,
                        ScanVerdict.duplicate => l10n.scanDuplicate,
                        _ => l10n.scanUnreadable,
                      },
                      key: const ValueKey('scan-error'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  for (final pkg in d.packageIds)
                    ListTile(
                      key: ValueKey('pkg-$pkg'),
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        flow.phaseOf(pkg).phase == HandoverPhase.handedOver
                            ? Icons.check_circle
                            : Icons.qr_code_2,
                      ),
                      title: Text(l10n.packageLabel(pkg)),
                      subtitle: Text(handoverText(l10n, flow.phaseOf(pkg))),
                      trailing:
                          flow.phaseOf(pkg).phase == HandoverPhase.checking
                          ? TextButton(
                              key: ValueKey('check-$pkg'),
                              onPressed: () => ctl.checkAgain(pkg),
                              child: Text(l10n.checkAgain),
                            )
                          : null,
                    ),
                  if (!allHanded && done > 0)
                    Text(
                      l10n.partialHandover,
                      key: const ValueKey('partial-handover'),
                    ),
                  FilledButton(
                    key: const ValueKey('pickup'),
                    // 모든 포장의 인계가 서버에서 확정돼야 픽업 완료를 보낼 수 있다.
                    onPressed: (allHanded && !busyQueue) ? ctl.pickup : null,
                    child: Text(l10n.pickupDone),
                  ),
                ],
                ExecutionState.pickedUp => [
                  _DropInfo(deliveryId: d.deliveryId),
                  FilledButton(
                    key: const ValueKey('arrive-customer'),
                    onPressed: busyQueue ? null : ctl.arriveAtCustomer,
                    child: Text(l10n.arriveCustomer),
                  ),
                  _FailureButton(onReport: ctl.reportFailure),
                ],
                ExecutionState.arrivedAtCustomer => [
                  _DropInfo(deliveryId: d.deliveryId),
                  SegmentedButton<CompletionMethod>(
                    segments: [
                      ButtonSegment(
                        value: CompletionMethod.face,
                        label: Text(l10n.methodFace),
                      ),
                      ButtonSegment(
                        value: CompletionMethod.contactless,
                        label: Text(l10n.methodContactless),
                      ),
                    ],
                    selected: {_method},
                    onSelectionChanged: (v) => setState(() {
                      _method = v.first;
                      _placement = _method == CompletionMethod.face
                          ? Placement.handedToCustomer
                          : Placement.frontDoor;
                    }),
                  ),
                  DropdownButton<Placement>(
                    key: const ValueKey('placement'),
                    value: _placement,
                    onChanged: (p) =>
                        setState(() => _placement = p ?? _placement),
                    items: [
                      for (final p in Placement.values)
                        DropdownMenuItem(
                          value: p,
                          child: Text(switch (p) {
                            Placement.handedToCustomer => l10n.plHanded,
                            Placement.frontDoor => l10n.plDoor,
                            Placement.securityOffice => l10n.plSecurity,
                            Placement.deliveryBox => l10n.plBox,
                            Placement.other => l10n.plOther,
                          }),
                        ),
                    ],
                  ),
                  Text(l10n.photoGuide, style: theme.textTheme.bodySmall),
                  OutlinedButton(
                    key: const ValueKey('upload-photo'),
                    onPressed: flow.uploading ? null : ctl.uploadPhoto,
                    child: Text(
                      flow.photoRef == null
                          ? l10n.takePhoto
                          : l10n.photoUploaded,
                    ),
                  ),
                  if (flow.uploadFailed)
                    Text(
                      l10n.uploadFailed,
                      key: const ValueKey('upload-failed'),
                    ),
                  FilledButton(
                    key: const ValueKey('complete'),
                    // 사진 업로드 성공 후에만 전달 완료를 누를 수 있다.
                    onPressed: (flow.photoRef != null && !busyQueue)
                        ? () => ctl.complete(_method, _placement)
                        : null,
                    child: Text(l10n.completeDelivery),
                  ),
                  _FailureButton(onReport: ctl.reportFailure),
                ],
                ExecutionState.completed => [
                  Text(l10n.deliveryDone, key: const ValueKey('delivery-done')),
                ],
                _ => [Text(l10n.contactSupport)],
              },
            ],
          );
        },
      ),
    );
  }
}

class _DropInfo extends ConsumerWidget {
  const _DropInfo({required this.deliveryId});

  final String deliveryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final info = ref.watch(dropInfoProvider(deliveryId)).value;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.place_outlined),
        title: Text(info?.addressSummary ?? l10n.dropInfoUnavailable),
        subtitle: info?.requestNote == null ? null : Text(info!.requestNote!),
      ),
    );
  }
}

class _FailureButton extends StatelessWidget {
  const _FailureButton({required this.onReport});

  final Future<void> Function(FailureReason) onReport;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextButton(
      key: const ValueKey('report-failure'),
      onPressed: () async {
        final reason = await showDialog<FailureReason>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(l10n.failureTitle),
            children: [
              for (final r in [
                FailureReason.customerAbsent,
                FailureReason.addressError,
                FailureReason.unreachable,
                FailureReason.refused,
                FailureReason.damaged,
                FailureReason.riderIncident,
                FailureReason.other,
              ])
                SimpleDialogOption(
                  key: ValueKey('failure-${r.name}'),
                  onPressed: () => Navigator.of(context).pop(r),
                  child: Text(switch (r) {
                    FailureReason.customerAbsent => l10n.frAbsent,
                    FailureReason.addressError => l10n.frAddress,
                    FailureReason.unreachable => l10n.frUnreachable,
                    FailureReason.refused => l10n.frRefused,
                    FailureReason.damaged => l10n.frDamaged,
                    FailureReason.riderIncident => l10n.frIncident,
                    FailureReason.other => l10n.frOther,
                  }),
                ),
            ],
          ),
        );
        if (reason != null) await onReport(reason);
      },
      child: Text(l10n.reportFailure),
    );
  }
}
