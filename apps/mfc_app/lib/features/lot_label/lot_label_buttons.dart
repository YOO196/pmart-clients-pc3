import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../shared/field_repositories.dart';
import '../../shared/ui_state_of.dart';
import '../quality/domain/quality.dart';
import '../tasks/presentation/task_controllers.dart' show currentMfcIdProvider;
import 'lot_label.dart';

/// 품질검사가 만든 적치 작업(= 나뉜 정상 LOT) — 센터의 적치 대기 목록에서 그 작업만 고른다.
final createdPutawaysProvider = FutureProvider.autoDispose
    .family<List<InboundTaskView>, String>((ref, joinedIds) async {
      final ids = joinedIds.split(',').toSet();
      final all = await ref
          .watch(qualityRepositoryProvider)
          .inboundTasks(
            ref.watch(currentMfcIdProvider),
            kind: InboundTaskKind.putaway,
          );
      return [
        for (final t in all)
          if (ids.contains(t.taskId)) t,
      ];
    });

/// 품질검사 뒤 "LOT 라벨 N장 출력"(N = 그 LOT 적치 작업 수량). 라벨 값·인쇄 정보는 서버 LOT 라벨 조회.
class LotLabelButtons extends ConsumerWidget {
  const LotLabelButtons({super.key, required this.taskIds});

  final List<String> taskIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final provider = createdPutawaysProvider(taskIds.join(','));
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: UiStateView<List<InboundTaskView>>(
        state: uiStateOf(ref.watch(provider), isEmpty: (l) => l.isEmpty),
        onRetry: () => ref.invalidate(provider),
        empty: (_) => Text(l10n.lotLabelsLoadError),
        ready: (context, tasks) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.lotLabelsTitle),
            const SizedBox(height: 8),
            for (final t in tasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton.icon(
                  key: ValueKey('lot-label-${t.lotId}'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: const Icon(Icons.print_outlined),
                  label: Text(l10n.lotLabelPrint(t.lotId, t.plannedQty)),
                  onPressed: () => printLotLabels(
                    context,
                    ref,
                    t.lotId,
                    copies: t.plannedQty,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
