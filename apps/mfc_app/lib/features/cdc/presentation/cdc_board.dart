import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/pda_decor.dart';
import '../../../shared/pda_motion.dart';
import '../../../shared/pda_theme.dart';
import '../../../shared/providers.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/cdc_board_repository.dart';
import 'cdc_home.dart';

/// DC 홈 현황(대기 수·오늘 내역) — 사용자 2026-11-27 "pda 에 dc 작업 대기랑 작업 내역이 안 뜨네".
final cdcBoardRepositoryProvider = Provider<CdcBoardRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockCdcBoardRepository(),
    PmartEnv.local => ApiCdcBoardRepository(ref.watch(dioProvider)),
  },
);

final cdcBoardProvider = FutureProvider.autoDispose<CdcBoard>((ref) {
  final s = ref.watch(employeeSessionProvider);
  final centers = s?.cdcCenters ?? const <String>[];
  return ref
      .watch(cdcBoardRepositoryProvider)
      .board(
        cdcId: centers.length == 1 ? centers.single : '',
        workerId: s?.operatorId ?? '',
      );
});

/// 업무 칸의 대기 수(못 읽었거나 아직이면 null)
/// 업무 칸에 보일 대기 건 번호(T…·W…) — 없으면 빈 목록
List<String> cdcWaitingNumbersOf(CdcBoard? b, CdcWorkArea a) =>
    b?.numbers[a.name] ?? const [];

int? cdcWaitingOf(CdcBoard? b, CdcWorkArea a) => switch (a) {
  CdcWorkArea.pick => b?.pick,
  CdcWorkArea.distribute => b?.distribute,
  CdcWorkArea.inspect => b?.inspect,
  CdcWorkArea.load => b?.load,
};

String cdcKindText(AppLocalizations l10n, String kind) => switch (kind) {
  'PICK' => l10n.cdcAreaPick,
  'SORT' => l10n.cdcAreaDistribute,
  'INSPECT' => l10n.cdcAreaInspect,
  'LOAD' => l10n.cdcAreaLoad,
  _ => kind,
};

/// 업무 칸 오른쪽 "대기 n" 알약 — 0 이면 흐리게, 못 읽으면 없음
class CdcWaitingPill extends StatelessWidget {
  const CdcWaitingPill({super.key, required this.area, required this.n});

  final CdcWorkArea area;
  final int? n;

  @override
  Widget build(BuildContext context) {
    final n = this.n;
    if (n == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final on = n > 0;
    return PopIn(
      child: Container(
        key: ValueKey('cdc-waiting-${area.name}'),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          gradient: on ? PdaGradients.primary : null,
          color: on ? null : PdaColors.soft,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          l10n.cdcWaiting(n),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: on ? Colors.white : PdaColors.muted,
          ),
        ),
      ),
    );
  }
}

/// DC 홈 맨 위 "오늘 작업 N건"(누르면 작업 내역) + 들고 있는 작업 한 줄
class CdcTodayCard extends ConsumerWidget {
  const CdcTodayCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final b = ref.watch(cdcBoardProvider).value;
    final n = b?.done?.length;
    final holding = b?.holding ?? const <CdcWorkItem>[];
    return Pressable(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          height: 84,
          decoration: const BoxDecoration(gradient: PdaGradients.hero),
          child: InkWell(
            key: const ValueKey('cdc-today'),
            onTap: () async {
              await context.push('/cdc/my-work');
              ref.invalidate(cdcBoardProvider);
            },
            child: CustomPaint(
              painter: const BubblesPainter(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 14, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            holding.isEmpty
                                ? l10n.homeTodayWork
                                : l10n.cdcHolding(
                                    cdcKindText(l10n, holding.first.kind),
                                    holding.first.taskNumber ??
                                        holding.first.taskId,
                                  ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.88),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            key: const ValueKey('cdc-today-count'),
                            n == null ? '—' : l10n.homeTodayCount(n),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.view_in_ar_rounded,
                      size: 40,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// DC 오늘 작업 내역 — 끝낸 작업(작업 번호·TRF 번호·Wave·수량·끝난 시각) + 지금 들고 있는 작업
class CdcMyWorkScreen extends ConsumerWidget {
  const CdcMyWorkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final board = ref.watch(cdcBoardProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.myWorkTitle)),
      body: SafeArea(
        child: switch (board) {
          AsyncData(:final value) => RefreshIndicator(
            onRefresh: () => ref.refresh(cdcBoardProvider.future),
            child: ListView(
              key: const ValueKey('cdc-my-work'),
              padding: const EdgeInsets.all(16),
              children: [
                for (final i in value.holding ?? const <CdcWorkItem>[])
                  _WorkRow(item: i, holding: true),
                if (value.done == null)
                  Text(
                    l10n.cdcMyWorkFailed,
                    key: const ValueKey('cdc-my-work-failed'),
                    style: TextStyle(color: theme.colorScheme.error),
                  )
                else if (value.done!.isEmpty &&
                    (value.holding ?? const []).isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      l10n.myWorkEmpty,
                      key: const ValueKey('cdc-my-work-empty'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  )
                else
                  for (final (k, i) in value.done!.indexed)
                    EnterFade(
                      index: k,
                      child: _WorkRow(item: i),
                    ),
              ],
            ),
          ),
          AsyncError() => Center(
            child: FilledButton(
              onPressed: () => ref.invalidate(cdcBoardProvider),
              child: Text(l10n.retry),
            ),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _WorkRow extends StatelessWidget {
  const _WorkRow({required this.item, this.holding = false});

  final CdcWorkItem item;
  final bool holding;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      key: ValueKey('cdc-work-${item.taskId}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: PdaShadows.sm,
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
                        cdcKindText(l10n, item.kind),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: PdaColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.taskNumber ?? item.taskId,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (item.trfNumbers.isNotEmpty)
                      l10n.cdcWorkTrfs(item.trfNumbers.join(', ')),
                    if (item.waveNumber case final w?) l10n.cdcWorkWave(w),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: PdaColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (item.completedAt case final at?) formatSeoulTime(at),
                    if (item.qty case final q?) l10n.myWorkItemQty(q),
                  ].join(' · '),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: PdaColors.body,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: holding ? PdaColors.lilac : PdaColors.okSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              holding ? l10n.cdcWorkHolding : l10n.cdcWorkDone,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: holding ? PdaColors.dark : PdaColors.okInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
