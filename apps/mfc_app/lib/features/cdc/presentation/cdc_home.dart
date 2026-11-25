import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/pda_motion.dart';
import '../../../shared/pda_theme.dart';
import '../../auth/presentation/auth_controller.dart';

/// DC(CDC) 직원 업무 — 계약 cdc-outbound `next-tasks` 의 kind(PICK·SORT·INSPECT·LOAD)와 cdc-inbound 적치(지게차).
/// 백엔드 staff-roles.md: `CDC_WORKER` = 자기 CDC 센터의 FC 피킹·분배/라인·검품·상차·지게차 작업.
enum CdcWorkArea { pick, sort, inspect, load, putaway }

String cdcAreaText(AppLocalizations l10n, CdcWorkArea a) => switch (a) {
  CdcWorkArea.pick => l10n.cdcAreaPick,
  CdcWorkArea.sort => l10n.cdcAreaSort,
  CdcWorkArea.inspect => l10n.cdcAreaInspect,
  CdcWorkArea.load => l10n.cdcAreaLoad,
  CdcWorkArea.putaway => l10n.cdcAreaPutaway,
};

String cdcAreaDesc(AppLocalizations l10n, CdcWorkArea a) => switch (a) {
  CdcWorkArea.pick => l10n.cdcAreaPickDesc,
  CdcWorkArea.sort => l10n.cdcAreaSortDesc,
  CdcWorkArea.inspect => l10n.cdcAreaInspectDesc,
  CdcWorkArea.load => l10n.cdcAreaLoadDesc,
  CdcWorkArea.putaway => l10n.cdcAreaPutawayDesc,
};

IconData cdcAreaIcon(CdcWorkArea a) => switch (a) {
  CdcWorkArea.pick => Icons.shopping_basket_outlined,
  CdcWorkArea.sort => Icons.call_split,
  CdcWorkArea.inspect => Icons.fact_check_outlined,
  CdcWorkArea.load => Icons.local_shipping_outlined,
  CdcWorkArea.putaway => Icons.forklift,
};

/// DC 직원(`CDC_WORKER`·`CDC_SUPERVISOR`) 홈(사용자 2026-11-26 "cdc 직원도 들어가면 … 다른 메뉴 뜨도록").
/// MFC 업무(피패킹·입고·검품·이동·실사)와 MFC 도구(인계·반납·휴게)는 보이지 않는다 — MFC API 를 부르지 않는다.
class CdcHomeScreen extends ConsumerWidget {
  const CdcHomeScreen({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('logout-dialog'),
        content: Text(l10n.logoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('logout-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.logout),
          ),
        ],
      ),
    );
    if (ok ?? false) await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final session = ref.watch(employeeSessionProvider);
    final centers = session?.centers ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: Text.rich(
          key: const ValueKey('cdc-home-title'),
          TextSpan(
            children: [
              TextSpan(
                text: l10n.homeTitle,
                style: const TextStyle(
                  color: PdaColors.onBarMuted,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const TextSpan(text: '   '),
              TextSpan(
                text: l10n.cdcHomeCenter(
                  centers.length == 1 ? centers.single : '',
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            key: const ValueKey('logout'),
            tooltip: l10n.logout,
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context, ref),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            key: const ValueKey('cdc-home'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 12, 0, 8),
                child: Text(
                  l10n.chooseWork,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: PdaColors.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    const gap = 10.0;
                    const areas = CdcWorkArea.values;
                    final h =
                        ((c.maxHeight - gap * (areas.length - 1)) /
                                areas.length)
                            .clamp(44.0, 80.0);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (i, a) in areas.indexed) ...[
                          if (i > 0) const SizedBox(height: gap),
                          EnterFade(
                            index: i,
                            child: _CdcAreaTile(
                              area: a,
                              height: h,
                              onTap: () => context.push('/cdc/work/${a.name}'),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CdcAreaTile extends StatelessWidget {
  const _CdcAreaTile({
    required this.area,
    required this.height,
    required this.onTap,
  });

  final CdcWorkArea area;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Pressable(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: PdaShadows.sm,
        ),
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: PdaColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('cdc-area-${area.name}'),
            onTap: onTap,
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: PdaColors.softer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        cdcAreaIcon(area),
                        size: 24,
                        color: PdaColors.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cdcAreaText(l10n, area),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: PdaColors.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (height >= 68)
                            Text(
                              cdcAreaDesc(l10n, area),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: PdaColors.muted,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: PdaColors.muted),
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

/// DC 업무 화면 자리 — 작업 받기·실행 화면은 다음 차례(계약은 있다: cdc-outbound next-tasks·starts·pick-results 등).
class CdcWorkScreen extends StatelessWidget {
  const CdcWorkScreen({super.key, required this.area});

  final CdcWorkArea area;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(cdcAreaText(l10n, area))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.cdcWorkPreparing,
            key: const ValueKey('cdc-work-preparing'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
    );
  }
}
