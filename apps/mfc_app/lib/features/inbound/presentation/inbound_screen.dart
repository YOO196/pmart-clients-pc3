import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/scanner/scan_input.dart';
import '../../../shared/scanner/scanner.dart';
import '../../work/domain/work.dart';
import '../../work/presentation/work_screens.dart' show backToSession;
import '../domain/inbound.dart';
import 'inbound_controller.dart';

/// 입고(받기): 도착 등록·하차 → 상품별 수령 계수(정상/격리/미판정) → 확인·수령 등록 → 재고 반영 확인.
class InboundReceiveScreen extends ConsumerWidget {
  const InboundReceiveScreen({super.key, required this.trfId});

  final String trfId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(inboundFlowProvider(trfId));
    final ctl = ref.read(inboundFlowProvider(trfId).notifier);
    final step = switch (s.phase) {
      InboundPhase.arrival => 0,
      InboundPhase.counting => 1,
      InboundPhase.review => 2,
      InboundPhase.applying ||
      InboundPhase.applied ||
      InboundPhase.applyRejected => 3,
      _ => -1,
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.inboundTitle(trfId))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (step >= 0) _Steps(current: step),
              const SizedBox(height: 12),
              Expanded(
                child: switch (s.phase) {
                  InboundPhase.loading => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  InboundPhase.loadError => _Message(
                    text: l10n.inboundLoadError,
                    action: l10n.retry,
                    onAction: ctl.load,
                  ),
                  InboundPhase.cancelled => _Message(
                    text: l10n.inboundCancelled,
                    action: l10n.nextTask,
                    onAction: () async =>
                        backToSession(context, WorkArea.inbound),
                  ),
                  InboundPhase.arrival => _ArrivalStep(trfId: trfId),
                  InboundPhase.counting => _CountStep(trfId: trfId),
                  InboundPhase.review => _ReviewStep(trfId: trfId),
                  InboundPhase.applying => _Message(
                    key: const ValueKey('inbound-applying'),
                    text: l10n.inboundApplying,
                    busy: s.busy,
                    action: l10n.checkAgain,
                    onAction: ctl.pollApply,
                  ),
                  InboundPhase.applied => _Message(
                    key: const ValueKey('inbound-applied'),
                    icon: Icons.check_circle,
                    text: l10n.inboundApplied,
                    action: l10n.nextTask,
                    onAction: () async =>
                        backToSession(context, WorkArea.inbound),
                  ),
                  InboundPhase.applyRejected => _Message(
                    key: const ValueKey('inbound-apply-rejected'),
                    icon: Icons.error_outline,
                    text: l10n.inboundApplyRejected,
                    action: l10n.nextTask,
                    onAction: () async =>
                        backToSession(context, WorkArea.inbound),
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final names = [
      l10n.inboundStepArrival,
      l10n.inboundStepCount,
      l10n.inboundStepReview,
      l10n.inboundStepApply,
    ];
    return Row(
      key: ValueKey('inbound-step-$current'),
      children: [
        for (final (i, n) in names.indexed)
          Expanded(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: i <= current
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  foregroundColor: i <= current
                      ? scheme.onPrimary
                      : scheme.onSurfaceVariant,
                  child: Text('${i + 1}'),
                ),
                const SizedBox(height: 4),
                Text(
                  n,
                  style: TextStyle(
                    fontWeight: i == current ? FontWeight.bold : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    super.key,
    required this.text,
    required this.action,
    required this.onAction,
    this.icon,
    this.busy = false,
  });

  final String text;
  final String action;
  final Future<void> Function() onAction;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (busy)
        const Center(child: CircularProgressIndicator())
      else if (icon != null)
        Icon(icon, size: 64),
      const SizedBox(height: 16),
      Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 24),
      CommandButton(
        key: const ValueKey('inbound-message-action'),
        label: action,
        busy: busy,
        onPressed: onAction,
      ),
    ],
  );
}

class _ArrivalStep extends ConsumerWidget {
  const _ArrivalStep({required this.trfId});

  final String trfId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = ref.watch(inboundFlowProvider(trfId));
    final ctl = ref.read(inboundFlowProvider(trfId).notifier);
    final p = s.promise!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.trfId, style: theme.textTheme.headlineSmall),
                if (p.eta ?? p.plannedArrivalAt case final t?)
                  Text(l10n.inboundPlannedAt(formatSeoulTime(t))),
                Text(l10n.inboundLinesSummary(p.lines.length, p.expectedTotal)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(l10n.inboundArrivalHelp, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ScanInput(
          id: 'trf-scan',
          label: l10n.inboundTrfScanHint,
          cameraTitle: l10n.inboundTrfScanHint,
          continuous: false,
          autofocus: false,
          onScan: (code) {
            if (code.trim() != trfId) {
              return ScanFeedback.error(l10n.inboundTrfMismatch);
            }
            ctl.arrive();
            return const ScanFeedback.ok();
          },
        ),
        if (s.code case final c?)
          Text(
            c == 'VERSION_CONFLICT'
                ? l10n.inboundVersionConflict
                : l10n.inboundArrivalRejected,
            key: const ValueKey('inbound-arrival-rejected'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        if (s.unknown)
          Text(
            l10n.inboundArrivalUnknown,
            key: const ValueKey('inbound-unknown'),
          ),
        const Spacer(),
        CommandButton(
          key: const ValueKey('inbound-arrive'),
          busy: s.busy,
          label: s.unknown ? l10n.checkAgain : l10n.inboundArrive,
          onPressed: ctl.arrive,
        ),
      ],
    );
  }
}

class _CountStep extends ConsumerWidget {
  const _CountStep({required this.trfId});

  final String trfId;

  Future<void> _edit(
    BuildContext context,
    String title,
    int value,
    ValueChanged<int> onSet,
  ) async {
    final v = await showDialog<int>(
      context: context,
      builder: (_) => _QtyDialog(title: title, initial: value),
    );
    if (v != null) onSet(v);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = ref.watch(inboundFlowProvider(trfId));
    final ctl = ref.read(inboundFlowProvider(trfId).notifier);
    final p = s.promise!;
    final l = s.line!;
    final c = s.countOf(l);
    final reason = c.reasonFor(l.expectedQty);
    final diff = c.total != l.expectedQty;

    Widget counter(
      String key,
      String label,
      int value,
      ReceiptCount Function(int) set,
    ) => Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.titleMedium)),
        IconButton.outlined(
          key: ValueKey('$key-minus'),
          onPressed: value > 0 ? () => ctl.setCount(l, set(value - 1)) : null,
          icon: const Icon(Icons.remove),
        ),
        InkWell(
          key: ValueKey('$key-value'),
          onTap: () =>
              _edit(context, label, value, (v) => ctl.setCount(l, set(v))),
          child: SizedBox(
            width: 64,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
          ),
        ),
        IconButton.filledTonal(
          key: ValueKey('$key-plus'),
          onPressed: () => ctl.setCount(l, set(value + 1)),
          icon: const Icon(Icons.add),
        ),
      ],
    );

    return Column(
      key: ValueKey('count-${l.key}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.inboundLineOf(s.index + 1, p.lines.length),
          style: theme.textTheme.labelLarge,
        ),
        Text(l.productName ?? l.sku, style: theme.textTheme.headlineSmall),
        Text([l.sku, if (l.lotId case final lot?) l10n.lot(lot)].join(' · ')),
        Text(
          l10n.inboundExpected(l.expectedQty),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ScanInput(
          id: 'inbound-scan',
          label: l10n.inboundScanHint,
          cameraTitle: l10n.inboundCameraTitle,
          autofocus: false,
          onScan: (code) => switch (ctl.scan(code)) {
            InboundScan.counted => const ScanFeedback.ok(),
            InboundScan.otherLine => ScanFeedback.error(l10n.inboundOtherLine),
            InboundScan.unknownCode => ScanFeedback.error(
              l10n.inboundUnknownCode,
            ),
          },
        ),
        if (s.lastScan case final r? when r != InboundScan.counted)
          Text(
            r == InboundScan.otherLine
                ? l10n.inboundOtherLine
                : l10n.inboundUnknownCode,
            key: const ValueKey('inbound-scan-error'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        const SizedBox(height: 8),
        counter(
          'normal',
          l10n.qtyNormal,
          c.normal,
          (v) => c.copyWith(normal: v),
        ),
        counter(
          'quarantined',
          l10n.qtyQuarantined,
          c.quarantined,
          (v) => c.copyWith(quarantined: v),
        ),
        counter(
          'pending',
          l10n.qtyPending,
          c.pending,
          (v) => c.copyWith(pending: v),
        ),
        const Divider(),
        Text(
          l10n.inboundTotal(c.total, l.expectedQty),
          key: const ValueKey('inbound-total'),
          style: theme.textTheme.titleMedium?.copyWith(
            color: diff ? theme.colorScheme.error : null,
          ),
        ),
        if (diff && reason != null)
          Text(
            reasonText(l10n, reason),
            key: const ValueKey('inbound-diff-reason'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        if (c.quarantined > 0) ...[
          Text(l10n.inboundQuarantineReason),
          Wrap(
            spacing: 8,
            children: [
              for (final r in [
                DiscrepancyReason.damaged,
                DiscrepancyReason.temperature,
              ])
                ChoiceChip(
                  key: ValueKey('reason-${r.name}'),
                  label: Text(reasonText(l10n, r)),
                  selected: c.quarantineReason == r,
                  onSelected: (_) =>
                      ctl.setCount(l, c.copyWith(quarantineReason: () => r)),
                ),
            ],
          ),
        ],
        const Spacer(),
        Row(
          children: [
            if (s.index > 0) ...[
              OutlinedButton(
                key: const ValueKey('inbound-back'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(96, 56),
                ),
                onPressed: ctl.back,
                child: Text(l10n.prev),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: FilledButton(
                key: const ValueKey('inbound-next'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed: c.complete ? ctl.next : null,
                child: Text(
                  s.index + 1 < p.lines.length
                      ? l10n.nextProduct
                      : l10n.inboundToReview,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String reasonText(AppLocalizations l10n, DiscrepancyReason r) => switch (r) {
  DiscrepancyReason.notReceived => l10n.reasonNotReceived,
  DiscrepancyReason.short => l10n.reasonShort,
  DiscrepancyReason.over => l10n.reasonOver,
  DiscrepancyReason.damaged => l10n.reasonDamaged,
  DiscrepancyReason.temperature => l10n.reasonTemperature,
};

class _ReviewStep extends ConsumerWidget {
  const _ReviewStep({required this.trfId});

  final String trfId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = ref.watch(inboundFlowProvider(trfId));
    final ctl = ref.read(inboundFlowProvider(trfId).notifier);
    final p = s.promise!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.inboundReviewTitle, style: theme.textTheme.titleLarge),
        Expanded(
          child: ListView(
            children: [
              for (final l in p.lines)
                Builder(
                  builder: (context) {
                    final c = s.countOf(l);
                    final r = c.reasonFor(l.expectedQty);
                    return ListTile(
                      key: ValueKey('review-${l.key}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(l.productName ?? l.sku),
                      subtitle: Text(
                        [
                          l10n.inboundReviewLine(
                            l.expectedQty,
                            c.normal,
                            c.quarantined,
                            c.pending,
                          ),
                          if (r != null) reasonText(l10n, r),
                        ].join('\n'),
                      ),
                      trailing: c.total == l.expectedQty
                          ? const Icon(Icons.check)
                          : Icon(
                              Icons.warning_amber,
                              color: theme.colorScheme.error,
                            ),
                    );
                  },
                ),
            ],
          ),
        ),
        if (s.code case final c?)
          Text(
            switch (c) {
              'VERSION_CONFLICT' => l10n.inboundVersionConflict,
              'INVALID_STATE' => l10n.inboundReceiptInvalidState,
              _ => l10n.inboundReceiptRejected,
            },
            key: const ValueKey('inbound-receipt-rejected'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        if (s.unknown)
          Text(
            l10n.inboundReceiptUnknown,
            key: const ValueKey('inbound-unknown'),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton(
              key: const ValueKey('inbound-back'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(96, 56)),
              onPressed: s.busy || s.unknown ? null : ctl.back,
              child: Text(l10n.prev),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CommandButton(
                key: const ValueKey('inbound-submit'),
                busy: s.busy,
                label: s.unknown ? l10n.checkAgain : l10n.inboundSubmit,
                onPressed: ctl.submit,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 수량 직접 입력. 컨트롤러는 다이얼로그가 닫힌 뒤(애니메이션 끝) 해제한다.
class _QtyDialog extends StatefulWidget {
  const _QtyDialog({required this.title, required this.initial});

  final String title;
  final int initial;

  @override
  State<_QtyDialog> createState() => _QtyDialogState();
}

class _QtyDialogState extends State<_QtyDialog> {
  late final _c = TextEditingController(text: '${widget.initial}');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('qty-input'),
        controller: _c,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('qty-ok'),
          onPressed: () =>
              Navigator.of(context).pop(int.tryParse(_c.text.trim())),
          child: Text(l10n.confirmOk),
        ),
      ],
    );
  }
}
