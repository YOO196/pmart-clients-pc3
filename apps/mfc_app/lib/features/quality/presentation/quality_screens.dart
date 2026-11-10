import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/scanner/scan_input.dart';
import '../../../shared/scanner/scanner.dart';
import '../../work/domain/work.dart';
import '../../work/presentation/work_screens.dart' show backToSession;
import '../domain/quality.dart';
import 'quality_controllers.dart';

Widget _done(
  BuildContext context, {
  required Key key,
  required IconData icon,
  required String text,
  required String action,
  required Future<void> Function() onAction,
  bool busy = false,
}) => Column(
  key: key,
  mainAxisAlignment: MainAxisAlignment.center,
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    if (busy)
      const Center(child: CircularProgressIndicator())
    else
      Icon(icon, size: 64),
    const SizedBox(height: 16),
    Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium,
    ),
    const SizedBox(height: 24),
    CommandButton(
      key: const ValueKey('quality-message-action'),
      label: action,
      busy: busy,
      onPressed: onAction,
    ),
  ],
);

String inspectIssueText(AppLocalizations l10n, InspectIssue i) => switch (i) {
  InspectIssue.zeroQty => l10n.inspectZeroQty,
  InspectIssue.overRemaining => l10n.inspectOverRemaining,
  InspectIssue.needExpiry => l10n.inspectNeedExpiry,
  InspectIssue.badDate => l10n.inspectBadDate,
  InspectIssue.badManufacture => l10n.inspectBadManufacture,
  InspectIssue.duplicateExpiry => l10n.inspectDuplicateExpiry,
  InspectIssue.needLot => l10n.inspectNeedLot,
};

/// 입고 품질검사: 정상/격리 판정과 LOT 분리(제조 LOT 표기·소비기한·제조일).
class InspectScreen extends ConsumerWidget {
  const InspectScreen({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = ref.watch(inspectFlowProvider(taskId));
    final ctl = ref.read(inspectFlowProvider(taskId).notifier);
    Future<void> next() async => backToSession(context, WorkArea.inspection);

    final Widget body = switch (s.phase) {
      InspectPhase.loading => const Center(child: CircularProgressIndicator()),
      InspectPhase.loadError => _done(
        context,
        key: const ValueKey('inspect-load-error'),
        icon: Icons.cloud_off,
        text: l10n.inspectLoadError,
        action: l10n.retry,
        onAction: ctl.load,
      ),
      InspectPhase.notFound => _done(
        context,
        key: const ValueKey('inspect-not-found'),
        icon: Icons.search_off,
        text: l10n.inspectNotFound,
        action: l10n.nextTask,
        onAction: next,
      ),
      InspectPhase.applied => _done(
        context,
        key: const ValueKey('inspect-applied'),
        icon: Icons.check_circle,
        text: l10n.inspectApplied(s.result?.createdTaskIds.length ?? 0),
        action: l10n.nextTask,
        onAction: next,
      ),
      InspectPhase.editing => _InspectForm(taskId: taskId),
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.inspectTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: body,
        ),
      ),
      backgroundColor: theme.colorScheme.surface,
    );
  }
}

class _InspectForm extends ConsumerWidget {
  const _InspectForm({required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = ref.watch(inspectFlowProvider(taskId));
    final ctl = ref.read(inspectFlowProvider(taskId).notifier);
    final t = s.task!;
    final issues = ctl.issues();
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
                Text(t.sku, style: theme.textTheme.titleLarge),
                Text(l10n.inspectFrom(t.locationCode)),
                Text(l10n.inspectLotByServer, style: theme.textTheme.bodySmall),
                Text(
                  l10n.inspectTotal(s.total, t.remainingQty),
                  key: const ValueKey('inspect-total'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: s.total == t.remainingQty
                        ? null
                        : theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            children: [
              for (final (i, r) in s.rows.indexed)
                _InspectRowCard(
                  key: ValueKey('inspect-row-${r.id}'),
                  index: i,
                  row: r,
                  removable: s.rows.length > 1 && !s.unknown,
                  issues: inspectRowIssues(r, ctl.today),
                  today: ctl.today,
                  onChanged: (v) => ctl.setRow(i, v),
                  onRemove: () => ctl.removeRow(i),
                ),
              TextButton.icon(
                key: const ValueKey('inspect-add-row'),
                onPressed: s.unknown ? null : ctl.addRow,
                icon: const Icon(Icons.call_split),
                label: Text(l10n.inspectAddRow),
              ),
            ],
          ),
        ),
        if (issues.contains(InspectIssue.overRemaining))
          Text(
            l10n.inspectOverRemaining,
            key: const ValueKey('inspect-over'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        if (issues.contains(InspectIssue.duplicateExpiry))
          Text(
            l10n.inspectDuplicateExpiry,
            key: const ValueKey('inspect-duplicate'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        if (s.code case final c?)
          Text(
            l10n.inspectRejected(c),
            key: const ValueKey('inspect-rejected'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        if (s.unknown)
          Text(l10n.inspectUnknown, key: const ValueKey('inspect-unknown')),
        const SizedBox(height: 8),
        CommandButton(
          key: const ValueKey('inspect-submit'),
          busy: s.busy,
          label: s.unknown ? l10n.checkAgain : l10n.inspectSubmit,
          onPressed: s.unknown || issues.isEmpty ? ctl.submit : null,
        ),
      ],
    );
  }
}

class _InspectRowCard extends StatelessWidget {
  const _InspectRowCard({
    super.key,
    required this.index,
    required this.row,
    required this.removable,
    required this.issues,
    required this.today,
    required this.onChanged,
    required this.onRemove,
  });

  final DateTime today;
  final int index;
  final InspectRow row;
  final bool removable;
  final Set<InspectIssue> issues;
  final ValueChanged<InspectRow> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    InputDecoration deco(String label, [String? hint]) =>
        InputDecoration(labelText: label, hintText: hint, isDense: true);
    final rowIssues = issues.difference({
      InspectIssue.overRemaining,
      InspectIssue.duplicateExpiry,
    });
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    key: ValueKey('verdict-$index'),
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(l10n.qtyNormal),
                        icon: const Icon(Icons.check),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(l10n.qtyQuarantined),
                        icon: const Icon(Icons.block),
                      ),
                    ],
                    selected: {row.quarantined},
                    onSelectionChanged: (v) =>
                        onChanged(row.copyWith(quarantined: v.first)),
                  ),
                ),
                if (removable)
                  IconButton(
                    key: ValueKey('remove-row-$index'),
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: ValueKey('qty-$index'),
              initialValue: '${row.qty}',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: deco(l10n.inspectQty),
              onChanged: (v) =>
                  onChanged(row.copyWith(qty: int.tryParse(v) ?? 0)),
            ),
            const SizedBox(height: 8),
            if (row.lotRef.isNotEmpty)
              InputChip(
                key: ValueKey('lot-value-$index'),
                avatar: const Icon(Icons.qr_code_2),
                label: Text(l10n.inspectLotScanned(row.lotRef)),
                onDeleted: () => onChanged(row.copyWith(lotRef: '')),
              )
            else if (row.noLot)
              InputChip(
                key: ValueKey('lot-none-$index'),
                avatar: const Icon(Icons.block),
                label: Text(l10n.inspectNoLot),
                onDeleted: () => onChanged(row.copyWith(noLot: false)),
              )
            else ...[
              ScanInput(
                id: 'lot-scan-$index',
                label: l10n.inspectLotScan,
                cameraTitle: l10n.inspectLotScan,
                continuous: false,
                autofocus: false,
                onScan: (code) {
                  final v = code.trim();
                  if (v.isEmpty) return ScanFeedback.error(l10n.inspectLotScan);
                  onChanged(row.copyWith(lotRef: v, noLot: false));
                  return const ScanFeedback.ok();
                },
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: ValueKey('lot-none-btn-$index'),
                  onPressed: () => onChanged(row.copyWith(noLot: true)),
                  icon: const Icon(Icons.block),
                  label: Text(l10n.inspectNoLot),
                ),
              ),
            ],
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    key: ValueKey('exp-$index'),
                    label: l10n.inspectExpiry,
                    value: row.expiry,
                    // 기한 지난 상품도 격리로 검사할 수 있게 과거도 고를 수 있다.
                    first: DateTime(today.year - 2),
                    last: DateTime(today.year + 5, 12, 31),
                    initial: today,
                    onPicked: (v) => onChanged(row.copyWith(expiry: v)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DateField(
                    key: ValueKey('mfg-$index'),
                    label: l10n.inspectManufacture,
                    value: row.manufacture,
                    // 제조일은 오늘·소비기한보다 늦을 수 없다 — 달력에서 아예 막는다.
                    first: DateTime(today.year - 5),
                    last: switch (DateTime.tryParse(row.expiry)) {
                      final e? when e.isBefore(today) => e,
                      _ => today,
                    },
                    initial: today,
                    onPicked: (v) => onChanged(row.copyWith(manufacture: v)),
                    onClear: row.manufacture.isEmpty
                        ? null
                        : () => onChanged(row.copyWith(manufacture: '')),
                  ),
                ),
              ],
            ),
            for (final i in rowIssues)
              Text(
                inspectIssueText(l10n, i),
                style: TextStyle(color: theme.colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}

String zoneText(AppLocalizations l10n, TempZone z) => switch (z) {
  TempZone.ambient => l10n.zoneAmbient,
  TempZone.chilled => l10n.zoneChilled,
  TempZone.frozen => l10n.zoneFrozen,
};

String disposeReasonText(AppLocalizations l10n, DisposeReason r) => switch (r) {
  DisposeReason.temperatureZone => l10n.disposeTemperatureZone,
  DisposeReason.fresh => l10n.disposeFresh,
  DisposeReason.opened => l10n.disposeOpened,
  DisposeReason.damaged => l10n.disposeDamaged,
  DisposeReason.expired => l10n.disposeExpired,
  DisposeReason.other => l10n.disposeOther,
};

/// 회수품(반품·불량) 검수: 줄마다 온도대·신선·개봉 → 재판매/폐기.
class ReturnInspectScreen extends ConsumerWidget {
  const ReturnInspectScreen({super.key, required this.returnReceiptId});

  final String returnReceiptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = ref.watch(returnInspectFlowProvider(returnReceiptId));
    final ctl = ref.read(returnInspectFlowProvider(returnReceiptId).notifier);
    Future<void> next() async => backToSession(context, WorkArea.inspection);

    final Widget body = switch (s.phase) {
      ReturnPhase.loading => const Center(child: CircularProgressIndicator()),
      ReturnPhase.loadError => _done(
        context,
        key: const ValueKey('return-load-error'),
        icon: Icons.cloud_off,
        text: l10n.inspectLoadError,
        action: l10n.retry,
        onAction: ctl.load,
      ),
      ReturnPhase.alreadyInspected => _done(
        context,
        key: const ValueKey('return-already'),
        icon: Icons.task_alt,
        text: l10n.returnAlreadyInspected,
        action: l10n.nextTask,
        onAction: next,
      ),
      ReturnPhase.applying => _done(
        context,
        key: const ValueKey('return-applying'),
        icon: Icons.hourglass_top,
        busy: s.busy,
        text: s.code == 'APPLY_REJECTED'
            ? l10n.returnApplyRejected
            : l10n.returnApplying,
        action: l10n.checkAgain,
        onAction: ctl.pollApply,
      ),
      ReturnPhase.applied => _done(
        context,
        key: const ValueKey('return-applied'),
        icon: Icons.check_circle,
        text: l10n.returnApplied,
        action: l10n.nextTask,
        onAction: next,
      ),
      ReturnPhase.editing => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.returnHeader(
              s.receipt!.returnReceiptId,
              s.receipt!.claimId ?? '-',
            ),
            style: theme.textTheme.titleMedium,
          ),
          Text(l10n.returnHelp, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                for (final (i, l) in s.receipt!.lines.indexed)
                  _ReturnLineCard(
                    index: i,
                    title: l.productName ?? l.sku,
                    subtitle: [
                      l.sku,
                      l10n.qtyUnit(l.qty),
                      ?l.conditionNote,
                    ].join(' · '),
                    d: s.decisions[i],
                    locked: s.unknown,
                    onChanged: (d) => ctl.decide(i, d),
                  ),
              ],
            ),
          ),
          if (s.code case final c?)
            Text(
              c == QualityProblemCode.resaleNotAllowed
                  ? l10n.returnResaleNotAllowed
                  : l10n.inspectRejected(c),
              key: const ValueKey('return-rejected'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          if (s.unknown)
            Text(l10n.inspectUnknown, key: const ValueKey('return-unknown')),
          const SizedBox(height: 8),
          CommandButton(
            key: const ValueKey('return-submit'),
            busy: s.busy,
            label: s.unknown ? l10n.checkAgain : l10n.returnSubmit,
            onPressed: s.unknown || s.complete ? ctl.submit : null,
          ),
        ],
      ),
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.returnTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: body,
        ),
      ),
    );
  }
}

class _ReturnLineCard extends StatelessWidget {
  const _ReturnLineCard({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.d,
    required this.locked,
    required this.onChanged,
  });

  final int index;
  final String title;
  final String subtitle;
  final ReturnDecision d;
  final bool locked;
  final ValueChanged<ReturnDecision> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    void set(ReturnDecision v) {
      if (!locked) onChanged(v);
    }

    return Card(
      key: ValueKey('return-line-$index'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            Text(subtitle, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final z in TempZone.values)
                  ChoiceChip(
                    key: ValueKey('zone-$index-${z.name}'),
                    label: Text(zoneText(l10n, z)),
                    selected: d.zone == z,
                    onSelected: (_) => set(d.copyWith(zone: z)),
                  ),
              ],
            ),
            Wrap(
              spacing: 6,
              children: [
                FilterChip(
                  key: ValueKey('fresh-$index'),
                  label: Text(l10n.returnFresh),
                  selected: d.fresh,
                  onSelected: (v) => set(d.copyWith(fresh: v)),
                ),
                FilterChip(
                  key: ValueKey('opened-$index'),
                  label: Text(l10n.returnOpened),
                  selected: d.opened,
                  onSelected: (v) => set(d.copyWith(opened: v)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: ValueKey('resale-$index'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: d.verdict == ReturnVerdict.resale
                          ? theme.colorScheme.primaryContainer
                          : null,
                    ),
                    onPressed: d.zone != null && d.resaleAllowed
                        ? () => set(
                            d.copyWith(
                              verdict: () => ReturnVerdict.resale,
                              disposeReason: () => null,
                            ),
                          )
                        : null,
                    icon: const Icon(Icons.storefront),
                    label: Text(l10n.returnResale),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: ValueKey('dispose-$index'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: d.verdict == ReturnVerdict.dispose
                          ? theme.colorScheme.errorContainer
                          : null,
                    ),
                    onPressed: d.zone == null
                        ? null
                        : () => set(
                            d.copyWith(
                              verdict: () => ReturnVerdict.dispose,
                              disposeReason: () =>
                                  d.disposeReason ?? d.suggestedReason,
                            ),
                          ),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l10n.returnDispose),
                  ),
                ),
              ],
            ),
            if (d.zone != null && !d.resaleAllowed)
              Text(
                l10n.returnResaleBlocked,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            if (d.verdict == ReturnVerdict.dispose)
              Wrap(
                spacing: 6,
                children: [
                  for (final r in DisposeReason.values)
                    ChoiceChip(
                      key: ValueKey('reason-$index-${r.name}'),
                      label: Text(disposeReasonText(l10n, r)),
                      selected: d.disposeReason == r,
                      onSelected: (_) =>
                          set(d.copyWith(disposeReason: () => r)),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// 날짜 고르기(달력). 값은 yyyy-MM-dd. 손으로 적지 않아 형식 오류가 없다.
class _DateField extends StatelessWidget {
  const _DateField({
    super.key,
    required this.label,
    required this.value,
    required this.first,
    required this.last,
    required this.initial,
    required this.onPicked,
    this.onClear,
  });

  final String label;
  final String value;
  final DateTime first;
  final DateTime last;
  final DateTime initial;
  final ValueChanged<String> onPicked;
  final VoidCallback? onClear;

  static String ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _pick(BuildContext context) async {
    DateTime clamp(DateTime d) =>
        d.isBefore(first) ? first : (d.isAfter(last) ? last : d);
    final picked = await showDatePicker(
      context: context,
      helpText: label,
      initialDate: clamp(DateTime.tryParse(value) ?? initial),
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) onPicked(ymd(picked));
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => _pick(context),
    child: InputDecorator(
      isEmpty: value.isEmpty,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        suffixIcon: onClear != null
            ? IconButton(
                tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                onPressed: onClear,
                icon: const Icon(Icons.clear),
              )
            : const Icon(Icons.calendar_month),
      ),
      child: Text(value),
    ),
  );
}
