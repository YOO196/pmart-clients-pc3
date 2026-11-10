import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/field_widgets.dart';
import '../../../shared/scanner/scan_input.dart';
import '../../../shared/scanner/scanner.dart';
import '../../work/domain/work.dart';
import '../../work/presentation/work_screens.dart' show backToSession;
import '../domain/stock_count.dart';
import 'stock_count_controller.dart';

/// 재고 실사: 칸마다 칸 바코드 → 줄별로 센 수량(장부는 안 보임) → 확인 → 제출 → 서버 판정.
class CountScreen extends ConsumerWidget {
  const CountScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = ref.watch(countFlowProvider(sessionId));
    final ctl = ref.read(countFlowProvider(sessionId).notifier);
    Future<void> next() async => backToSession(context, WorkArea.stockCount);

    Widget header() => Text(
      l10n.countLocationOf(s.locIndex + 1, s.locations.length),
      style: theme.textTheme.labelLarge,
    );

    final Widget body = switch (s.phase) {
      CountPhase.loading => const Center(child: CircularProgressIndicator()),
      CountPhase.loadError => ResultView(
        icon: Icons.cloud_off,
        text: l10n.countLoadError,
        action: l10n.retry,
        onAction: ctl.load,
      ),
      CountPhase.notMine => ResultView(
        key: const ValueKey('count-not-mine'),
        icon: Icons.people_outline,
        text: l10n.countNotMine,
        action: l10n.nextTask,
        onAction: next,
      ),
      CountPhase.result => ResultView(
        key: ValueKey('count-result-${s.session!.state.name}'),
        icon: switch (s.session!.state) {
          CountState.matched || CountState.adjusted => Icons.check_circle,
          _ => Icons.hourglass_top,
        },
        text: switch (s.session!.state) {
          CountState.matched => l10n.countMatched,
          CountState.recountRequired => l10n.countRecountRequired,
          CountState.pendingApproval => l10n.countPendingApproval,
          CountState.adjusted => l10n.countAdjusted,
          CountState.rejected => l10n.countRejected,
          _ => l10n.countSubmitted,
        },
        action: l10n.nextTask,
        onAction: next,
      ),
      CountPhase.goTo => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header(),
          const SizedBox(height: 8),
          TargetLine(
            key: const ValueKey('count-target'),
            label: l10n.countGoTo,
            code: s.location!,
            confirmed: false,
          ),
          const SizedBox(height: 12),
          ScanInput(
            id: 'count-loc-scan',
            label: l10n.countScanLocation,
            cameraTitle: l10n.areaStockCount,
            continuous: false,
            autofocus: false,
            onScan: (code) => ctl.scanLocation(code)
                ? const ScanFeedback.ok()
                : ScanFeedback.error(l10n.moveWrongPlace),
          ),
          if (s.wrongPlace)
            Text(
              l10n.moveWrongPlace,
              key: const ValueKey('count-wrong-place'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          const Spacer(),
          Text(l10n.countBlindHelp, style: theme.textTheme.bodySmall),
        ],
      ),
      CountPhase.counting => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header(),
          TargetLine(label: l10n.countAt, code: s.location!, confirmed: true),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                for (final l in s.linesAt(s.location!))
                  Card(
                    key: ValueKey('count-line-${l.key}'),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.sku, style: theme.textTheme.titleMedium),
                          Text(
                            [
                              l10n.lot(l.lotId),
                              if (l.expiryDate case final e?) l10n.expiresOn(e),
                            ].join(' · '),
                            style: theme.textTheme.bodySmall,
                          ),
                          QtyStepper(
                            id: 'count-${l.key}',
                            label: s.counts.containsKey(l.key)
                                ? l10n.countCounted
                                : l10n.countNotYet,
                            value: s.counts[l.key] ?? 0,
                            enabled: !s.unknown,
                            onChanged: (v) => ctl.setCount(l, v),
                          ),
                          if (!s.counts.containsKey(l.key))
                            TextButton(
                              key: ValueKey('count-zero-${l.key}'),
                              onPressed: () => ctl.setCount(l, 0),
                              child: Text(l10n.countNone),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          FilledButton(
            key: const ValueKey('count-next'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: s.locationDone ? ctl.nextLocation : null,
            child: Text(
              s.locIndex + 1 < s.locations.length
                  ? l10n.countNextLocation
                  : l10n.inboundToReview,
            ),
          ),
        ],
      ),
      CountPhase.review => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.countReviewTitle, style: theme.textTheme.titleLarge),
          Expanded(
            child: ListView(
              children: [
                for (final l in s.session!.sheet)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('${l.locationCode} · ${l.sku}'),
                    subtitle: Text(l10n.lot(l.lotId)),
                    trailing: Text(
                      '${s.counts[l.key] ?? 0}',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
              ],
            ),
          ),
          if (s.code case final c?)
            Text(
              l10n.inspectRejected(c),
              key: const ValueKey('count-rejected'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          if (s.unknown)
            Text(l10n.inspectUnknown, key: const ValueKey('count-unknown')),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(96, 56),
                ),
                onPressed: s.busy || s.unknown ? null : ctl.back,
                child: Text(l10n.prev),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CommandButton(
                  key: const ValueKey('count-submit'),
                  busy: s.busy,
                  label: s.unknown ? l10n.checkAgain : l10n.countSubmit,
                  onPressed: ctl.submit,
                ),
              ),
            ],
          ),
        ],
      ),
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.areaStockCount)),
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(16), child: body),
      ),
    );
  }
}
