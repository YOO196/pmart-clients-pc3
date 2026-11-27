import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/pda_theme.dart';
import '../../../shared/product_hints.dart';
import '../../../shared/ui_state_of.dart';
import '../../inbound/presentation/inbound_controller.dart'
    show inboundRepositoryProvider;
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
/// 입고 기록(taskId = trfId)의 TRF 화면 번호 — 입고 예정 조회(mfc-inbound 0.25.0 `trfNumber`). 모르면 null.
final trfNumberProvider = FutureProvider.autoDispose.family<String?, String>((
  ref,
  trfId,
) async {
  try {
    return (await ref.watch(inboundRepositoryProvider).promise(trfId))
        .trfNumber;
  } on Object {
    return null;
  }
});

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
      resizeToAvoidBottomInset: false,
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

class _MyWorkList extends ConsumerStatefulWidget {
  const _MyWorkList({required this.a});

  final WorkActivities a;

  @override
  ConsumerState<_MyWorkList> createState() => _MyWorkListState();
}

class _MyWorkListState extends ConsumerState<_MyWorkList> {
  /// 거르기(참고 화면 "전체·피킹·패킹·적치") — null 이면 전체
  String? _type;

  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hints = ref.watch(productHintsProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (a.unavailableSources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              l10n.myWorkPartial(a.unavailableSources.join(', ')),
              key: const ValueKey('my-work-partial'),
              style: TextStyle(color: scheme.error),
            ),
          ),
        // 오늘 합계 — 옅은 보라 상자에 종류별 칸을 폭에 고르게(왼쪽으로 몰리지 않게, 사용자 2026-11-20).
        Container(
          key: const ValueKey('my-work-summary'),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: PdaColors.softer,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: PdaColors.lilac),
          ),
          child: a.totals.isEmpty
              ? Center(child: Text(l10n.myWorkNoTotals))
              : LayoutBuilder(
                  builder: (context, c) {
                    final per = a.totals.length < 3 ? a.totals.length : 3;
                    final w = c.maxWidth / per;
                    return Wrap(
                      runSpacing: 12,
                      children: [
                        for (final t in a.totals)
                          SizedBox(
                            width: w,
                            child: Column(
                              key: ValueKey('my-work-total-${t.type}'),
                              children: [
                                Text(
                                  activityTypeText(l10n, t.type),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: PdaColors.onNotice,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  l10n.myWorkCount(t.count),
                                  style: theme.textTheme.headlineMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: PdaColors.primary,
                                      ),
                                ),
                                Text(
                                  l10n.myWorkTotalQty(t.qty),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: PdaColors.body,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
        const SizedBox(height: 12),
        if (a.items.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (t, label) in [
                  (null, l10n.myWorkFilterAll(a.items.length)),
                  for (final type in {for (final i in a.items) i.type})
                    (
                      type,
                      l10n.myWorkFilterType(
                        activityTypeText(l10n, type),
                        a.items.where((i) => i.type == type).length,
                      ),
                    ),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6, bottom: 10),
                    child: ChoiceChip(
                      key: ValueKey('my-work-filter-${t ?? 'ALL'}'),
                      label: Text(label),
                      selected: _type == t,
                      showCheckmark: false,
                      selectedColor: PdaColors.primary,
                      labelStyle: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _type == t ? Colors.white : PdaColors.body,
                      ),
                      onSelected: (_) => setState(() => _type = t),
                    ),
                  ),
              ],
            ),
          ),
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
        // 한 건 = 한 상자. 결과는 색 칩(반영 초록·거절 빨강·그 밖 회색) — 오른쪽 작은 글씨로는 안 보였다.
        for (final i in a.items.where((i) => _type == null || i.type == _type))
          Container(
            key: ValueKey('my-work-${i.refId}'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x145E3BB2),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: PdaColors.softer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              activityTypeText(l10n, i.type),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: PdaColors.primary,
                              ),
                            ),
                          ),
                          if (i.sku case final s?) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                hints.bySku(s)?.name ?? s,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      const SizedBox(height: 2),
                      // 어떤 건을 작업했는지 — 작업 번호(입고는 TRF, 실사는 실사 번호 등)·기록 번호(사용자 2026-11-27)
                      // 긴 내부 id(TRF-SR-uuid·RCV-TRF-uuid)는 내지 않는다 — 입고는 TRF 화면 번호(T…)를 찾아서(사용자 2026-11-27 "뭘 바꾼 거야")
                      Text(
                        [
                          if (i.type == 'RECEIVE' && i.taskId != null)
                            switch (ref
                                .watch(trfNumberProvider(i.taskId!))
                                .value) {
                              final n? => l10n.myWorkTrfNo(n),
                              _ => l10n.myWorkTrfLoading,
                            }
                          else if (i.taskId case final t? when t.length <= 16)
                            l10n.myWorkTaskNo(t),
                          if (i.refId.length <= 16) l10n.myWorkRefNo(i.refId),
                        ].join(' · '),
                        key: ValueKey('my-work-no-${i.refId}'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: PdaColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          formatSeoulTime(i.at),
                          if (i.qty case final q?) l10n.myWorkItemQty(q),
                        ].join(' · '),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: PdaColors.body,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (activityResultText(l10n, i.result) case final r?)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: switch (i.result) {
                        'APPLIED' => PdaColors.okSoft,
                        'REJECTED' => PdaColors.dangerSoft,
                        _ => PdaColors.soft,
                      },
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      r,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: switch (i.result) {
                          'APPLIED' => PdaColors.okInk,
                          'REJECTED' => scheme.error,
                          _ => PdaColors.body,
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Text(
          l10n.myWorkScopeNote,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
