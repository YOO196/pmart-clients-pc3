import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/pda_motion.dart';
import '../../../shared/pda_theme.dart';
import '../../auth/presentation/auth_controller.dart';

/// DC(CDC) 직원 업무 — 계약 cdc-outbound `next-tasks` 의 kind(PICK·SORT·INSPECT·LOAD)와 cdc-inbound 적치(지게차).
/// 백엔드 staff-roles.md: `CDC_WORKER` = 자기 CDC 센터의 FC 피킹·분배/라인·검품·상차·지게차 작업.
/// DC 업무(DC 시뮬레이터 요청 C-01, 사용자 2026-11-26) — 피킹·분배·패킹(묶음이면 칸으로 나누고 한 곳 몫은 바로 BOX — 사용자 "합쳐줘")·출고 검품·상차.
/// 지게차 적치·보충은 가상 설비가 `/internal` 로 받는 일이라 PDA 에 두지 않는다(cdc-inbound 0.2.x).
enum CdcWorkArea { pick, distribute, inspect, load }

String cdcAreaText(AppLocalizations l10n, CdcWorkArea a) => switch (a) {
  CdcWorkArea.pick => l10n.cdcAreaPick,
  CdcWorkArea.distribute => l10n.cdcAreaDistribute,
  CdcWorkArea.inspect => l10n.cdcAreaInspect,
  CdcWorkArea.load => l10n.cdcAreaLoad,
};

String cdcAreaDesc(AppLocalizations l10n, CdcWorkArea a) => switch (a) {
  CdcWorkArea.pick => l10n.cdcAreaPickDesc,
  CdcWorkArea.distribute => l10n.cdcAreaDistributeDesc,
  CdcWorkArea.inspect => l10n.cdcAreaInspectDesc,
  CdcWorkArea.load => l10n.cdcAreaLoadDesc,
};

IconData cdcAreaIcon(CdcWorkArea a) => switch (a) {
  CdcWorkArea.pick => Icons.shopping_basket_outlined,
  CdcWorkArea.distribute => Icons.call_split,
  CdcWorkArea.inspect => Icons.fact_check_outlined,
  CdcWorkArea.load => Icons.local_shipping_outlined,
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
                              onTap: () => context.push('/cdc/guide/${a.name}'),
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
      // 고르면 칸이 커지며 안내 화면 위 카드([CdcAreaHero])가 된다 — MFC 업무 칸과 같은 효과
      child: Hero(
        tag: cdcHeroTag(area),
        flightShuttleBuilder: cdcAreaShuttle(area),
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
      ),
    );
  }
}

String cdcHeroTag(CdcWorkArea a) => 'cdc-area-card-${a.name}';

/// 칸 → 안내 카드로 커지는 동안의 모습(MFC `_AreaFlight` 와 같은 움직임): 그림은 칸 왼쪽(44)에서 카드 오른쪽(84)으로
/// 크기와 함께 이어서 움직이고, 칸 이름은 흐려지며 카드 제목·설명이 나타난다. 돌아갈 때는 거꾸로.
HeroFlightShuttleBuilder cdcAreaShuttle(CdcWorkArea area) =>
    (_, animation, _, _, _) => _CdcAreaFlight(area: area, animation: animation);

class _CdcAreaFlight extends StatelessWidget {
  const _CdcAreaFlight({required this.area, required this.animation});

  final CdcWorkArea area;
  final Animation<double> animation;

  static const _tilePad = 16.0;
  static const _tileGap = 14.0;
  static const _tileCircle = 44.0;
  static const _tileIcon = 24.0;
  static const _cardCircle = 84.0;
  static const _cardIcon = 46.0;
  static const _cardPad = 15.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeInOutCubic.transform(animation.value);
        double lerp(double a, double b) => a + (b - a) * t;
        final tileText = (1 - t * 2).clamp(0.0, 1.0);
        final cardText = (t * 2 - 1).clamp(0.0, 1.0);
        return Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(lerp(14, 17)),
            side: BorderSide(
              color: Color.lerp(PdaColors.line, PdaColors.lilac, t)!,
              width: lerp(1, 1.5),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final h = c.maxHeight;
              final d = lerp(_tileCircle, _cardCircle);
              final cx = lerp(
                _tilePad + _tileCircle / 2,
                w - _cardPad - _cardCircle / 2,
              );
              final cy = h / 2;
              return Stack(
                children: [
                  if (tileText > 0)
                    Positioned(
                      left: _tilePad + _tileCircle + _tileGap,
                      right: _tilePad + 24,
                      top: 0,
                      bottom: 0,
                      child: Opacity(
                        opacity: tileText,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            cdcAreaText(l10n, area),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.clip,
                            style: const TextStyle(
                              color: PdaColors.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (cardText > 0)
                    Positioned(
                      left: _cardPad,
                      right: d + _cardPad * 2,
                      top: 0,
                      bottom: 0,
                      child: Opacity(
                        opacity: cardText,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cdcAreaText(l10n, area),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.clip,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              cdcAreaDesc(l10n, area),
                              maxLines: 2,
                              overflow: TextOverflow.clip,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: PdaColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    left: cx - d / 2,
                    top: cy - d / 2,
                    width: d,
                    height: d,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: PdaColors.softer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        cdcAreaIcon(area),
                        size: lerp(_tileIcon, _cardIcon),
                        color: PdaColors.primary,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
