import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/pda_theme.dart';
import 'auth_controller.dart';

/// DC·MFC 두 권한이 다 있는 계정의 오늘 작업장(사용자 2026-11-26 "DC 랑 MFC 둘 다 권한 있는 계정으로 로그인하면
/// DC 랑 MFC 작업 중에 선택하게"). 고르기 전에는 null — 로그인이 바뀌면 다시 고른다. 권한 판정은 서버.
enum Workplace { dc, mfc }

final workplaceProvider = NotifierProvider<WorkplaceController, Workplace?>(
  WorkplaceController.new,
);

class WorkplaceController extends Notifier<Workplace?> {
  @override
  Workplace? build() {
    ref.watch(employeeSessionProvider.select((s) => s?.operatorId));
    return null;
  }

  void choose(Workplace? w) => state = w;
}

/// 두 권한이 다 있으면 상단바에 "DC·MFC 바꾸기"
class WorkplaceSwitchButton extends ConsumerWidget {
  const WorkplaceSwitchButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(ref.watch(employeeSessionProvider)?.hasBoth ?? false)) {
      return const SizedBox.shrink();
    }
    return IconButton(
      key: const ValueKey('switch-workplace'),
      tooltip: AppLocalizations.of(context).workplaceSwitch,
      icon: const Icon(Icons.swap_horiz),
      onPressed: () => ref.read(workplaceProvider.notifier).choose(null),
    );
  }
}

class WorkplaceChoiceScreen extends ConsumerWidget {
  const WorkplaceChoiceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(employeeSessionProvider);
    String join(List<String> c) => c.isEmpty ? '-' : c.join(' · ');
    Widget card(Workplace w, IconData icon, String title, String desc) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              key: ValueKey('workplace-${w.name}'),
              borderRadius: BorderRadius.circular(16),
              onTap: () => ref.read(workplaceProvider.notifier).choose(w),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: PdaColors.lilac, width: 1.5),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 40, color: PdaColors.primary),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            desc,
                            style: const TextStyle(color: PdaColors.muted),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: PdaColors.primary),
                  ],
                ),
              ),
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeTitle),
        actions: [
          IconButton(
            key: const ValueKey('logout'),
            tooltip: l10n.logout,
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          key: const ValueKey('workplace-choice'),
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              l10n.workplaceTitle,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.workplaceHelp,
              style: const TextStyle(color: PdaColors.muted),
            ),
            const SizedBox(height: 20),
            card(
              Workplace.dc,
              Icons.warehouse_outlined,
              l10n.workplaceDc,
              l10n.workplaceDcDesc(join(s?.cdcCenters ?? const [])),
            ),
            card(
              Workplace.mfc,
              Icons.storefront_outlined,
              l10n.workplaceMfc,
              l10n.workplaceMfcDesc(join(s?.mfcCenters ?? const [])),
            ),
          ],
        ),
      ),
    );
  }
}
