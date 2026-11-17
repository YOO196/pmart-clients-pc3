import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/product_hints.dart';
import '../../../shared/ui_state_of.dart';
import '../../tasks/presentation/task_controllers.dart';
import '../data/my_work_repository.dart';

/// 내 오늘 업무 내역(사용자 2026-11-17 "작업자마다 본인의 금일 작업내용을 체크").
/// mfc-capacity `GET /mfcs/{mfcId}/workers/me/activities`(0.17.0) — 피킹·포장·복귀·입고·품질검사·적치·이동·
/// 회수품 반입·실사·품질 판정을 서버가 모아 준다. 오늘은 서버가 정한다(Asia/Seoul). 합계는 서버 값.
final myTodayWorkProvider = FutureProvider.autoDispose<WorkActivities>(
  (ref) => ref
      .watch(myWorkRepositoryProvider)
      .today(ref.watch(currentMfcIdProvider)),
);

String activityTypeText(AppLocalizations l10n, String type) => switch (type) {
  'PICK' => l10n.typePick,
  'PACK' => l10n.typePack,
  'RETURN' => l10n.typeReturn,
  'RECEIVE' => l10n.typeReceive,
  'INSPECT' => l10n.typeInspect,
  'PUTAWAY' => l10n.typePutaway,
  'MOVE' => l10n.typeMove,
  'RETURN_RECEIPT' => l10n.typeReturnReceipt,
  'COUNT' => l10n.actCount,
  'RECOUNT' => l10n.actRecount,
  'QUARANTINE' => l10n.actQuarantine,
  'RELEASE' => l10n.actRelease,
  'DISPOSE' => l10n.actDispose,
  'RETURN_INSPECTION' => l10n.typeReturnInspect,
  _ => type,
};

String? activityResultText(AppLocalizations l10n, String? r) => switch (r) {
  null => null,
  'APPLIED' => l10n.actApplied,
  'REJECTED' => l10n.actRejected,
  'RECORDED' || 'INVENTORY_PENDING' => l10n.actPending,
  'UNKNOWN_RESULT' => l10n.actUnknown,
  _ => r,
};

/// 업무 고르기·업무 진행 화면 맨 위의 작은 바 — "업무 내역" 칩을 누르면 오늘 업무 내역.
/// AppBar `bottom` 에 둔다. 조회 실패는 칩에 건수를 빼고 보일 뿐(내역 화면에서 오류를 보인다).
class MyWorkBar extends ConsumerWidget implements PreferredSizeWidget {
  const MyWorkBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final n = ref.watch(myTodayWorkProvider).value?.items.length;
    return SizedBox(
      height: preferredSize.height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: Row(
          children: [
            ActionChip(
              key: const ValueKey('my-work-chip'),
              avatar: const Icon(Icons.history, size: 18),
              visualDensity: VisualDensity.compact,
              label: Text(
                n == null ? l10n.myWorkChip : l10n.myWorkChipCount(n),
              ),
              onPressed: () => context.push('/my-work'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 오늘 업무 내역 화면.
class MyWorkScreen extends ConsumerWidget {
  const MyWorkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.myWorkTitle)),
      body: SafeArea(
        child: UiStateView<WorkActivities>(
          state: uiStateOf(ref.watch(myTodayWorkProvider)),
          onRetry: () => ref.invalidate(myTodayWorkProvider),
          ready: (context, a) => RefreshIndicator(
            onRefresh: () => ref.refresh(myTodayWorkProvider.future),
            child: _MyWorkList(a: a),
          ),
        ),
      ),
    );
  }
}

class _MyWorkList extends ConsumerWidget {
  const _MyWorkList({required this.a});

  final WorkActivities a;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hints = ref.watch(productHintsProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (a.unavailableSources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l10n.myWorkPartial(a.unavailableSources.join(', ')),
              key: const ValueKey('my-work-partial'),
              style: TextStyle(color: scheme.error),
            ),
          ),
        Card(
          key: const ValueKey('my-work-summary'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: a.totals.isEmpty
                ? Text(l10n.myWorkNoTotals)
                : Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      for (final t in a.totals)
                        Column(
                          key: ValueKey('my-work-total-${t.type}'),
                          children: [
                            Text(
                              activityTypeText(l10n, t.type),
                              style: theme.textTheme.labelLarge,
                            ),
                            Text(
                              l10n.myWorkCount(t.count),
                              style: theme.textTheme.headlineSmall,
                            ),
                            Text(
                              l10n.myWorkTotalQty(t.qty),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 8),
        if (a.items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              l10n.myWorkEmpty,
              key: const ValueKey('my-work-empty'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
        for (final i in a.items)
          ListTile(
            key: ValueKey('my-work-${i.refId}'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              [
                activityTypeText(l10n, i.type),
                if (i.sku case final s?) hints.bySku(s)?.name ?? s,
              ].join(' · '),
            ),
            subtitle: Text(
              [
                formatSeoulTime(i.at),
                if (i.qty case final q?) l10n.myWorkItemQty(q),
                ?i.taskId,
              ].join(' · '),
            ),
            trailing: switch (activityResultText(l10n, i.result)) {
              final r? => Text(
                r,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: i.result == 'REJECTED'
                      ? scheme.error
                      : i.result == 'APPLIED'
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
              ),
              null => null,
            },
          ),
        const SizedBox(height: 16),
        Text(
          l10n.myWorkScopeNote,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
