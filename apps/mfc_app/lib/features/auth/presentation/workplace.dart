import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/pda_motion.dart';
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

/// 근무 센터가 여럿인 계정의 오늘 센터(사용자 2026-11-26 "근무센터가 여러 곳이라 지금은 이 앱을 쓸 수 없다고 떠") —
/// 고르기 전에는 null, 로그인이 바뀌면 다시 고른다. 요청 경로의 mfcId 만 정한다(권한 판정은 서버).
final centerChoiceProvider = NotifierProvider<CenterChoiceController, String?>(
  CenterChoiceController.new,
);

class CenterChoiceController extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(employeeSessionProvider.select((s) => s?.operatorId));
    return null;
  }

  void choose(String? c) => state = c;
}

/// 두 권한이 다 있거나 센터가 여럿이면 상단바에 "작업장·센터 바꾸기"
class WorkplaceSwitchButton extends ConsumerWidget {
  const WorkplaceSwitchButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(employeeSessionProvider);
    final both = s?.hasBoth ?? false;
    final many = (s?.mfcCenters.length ?? 0) > 1;
    if (!both && !many) return const SizedBox.shrink();
    return IconButton(
      key: const ValueKey('switch-workplace'),
      tooltip: AppLocalizations.of(context).workplaceSwitch,
      icon: const Icon(Icons.swap_horiz),
      onPressed: () {
        ref.read(centerChoiceProvider.notifier).choose(null);
        if (both) ref.read(workplaceProvider.notifier).choose(null);
      },
    );
  }
}

/// 근무 센터 고르기(홈 본문) — 센터가 여럿일 때. 홈 업무 칸과 같은 모양(흰 카드·그림자·연보라 원·차례 등장·눌림).
class CenterChoiceView extends ConsumerWidget {
  const CenterChoiceView({super.key, required this.centers});

  final List<String> centers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final both = ref.watch(employeeSessionProvider)?.hasBoth ?? false;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          key: const ValueKey('center-choice'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (both)
              EnterFade(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _Crumb(
                    icon: Icons.storefront_outlined,
                    text: l10n.workplaceMfc,
                  ),
                ),
              ),
            EnterFade(
              index: 1,
              child: _Heading(
                title: l10n.centerChoiceTitle,
                help: l10n.centerChoiceHelp(centers.length),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: centers.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => EnterFade(
                  index: i + 2,
                  child: _CenterCard(
                    n: i + 1,
                    center: centers[i],
                    onTap: () => ref
                        .read(centerChoiceProvider.notifier)
                        .choose(centers[i]),
                  ),
                ),
              ),
            ),
            _Footnote(text: l10n.workplaceFootnote),
          ],
        ),
      ),
    );
  }
}

class _CenterCard extends StatelessWidget {
  const _CenterCard({
    required this.n,
    required this.center,
    required this.onTap,
  });

  final int n;
  final String center;
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
            side: BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('center-$center'),
            onTap: onTap,
            child: SizedBox(
              height: 78,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: PdaColors.softer,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$n',
                        style: const TextStyle(
                          color: PdaColors.primary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: PdaColors.ink,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          Text(
                            l10n.centerChoiceCardSub,
                            style: const TextStyle(
                              color: PdaColors.muted,
                              fontSize: 13,
                            ),
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
        ),
      ),
    );
  }
}

/// DC·MFC 작업장 고르기 — 두 큰 카드가 화면을 반씩. 카드마다 그곳의 업무·센터를 보여 고르기 전에 알 수 있게.
class WorkplaceChoiceScreen extends ConsumerWidget {
  const WorkplaceChoiceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(employeeSessionProvider);
    // 센터가 셋 이상이면 "첫 센터 외 N곳" — 카드 한 줄에 다 들어가게
    String join(List<String> c) => c.isEmpty
        ? '-'
        : c.length > 2
        ? l10n.workplaceCentersMore(c.first, c.length - 1)
        : c.join(' · ');
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.homeTitle,
          style: const TextStyle(
            color: PdaColors.onBarMuted,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            key: const ValueKey('workplace-choice'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EnterFade(
                child: _Heading(
                  title: l10n.workplaceTitle,
                  help: l10n.workplaceHelp,
                ),
              ),
              // 카드는 내용 높이 — 두 카드를 가운데쯤(위 여백 1 : 아래 여백 2)
              const Spacer(),
              EnterFade(
                index: 1,
                child: _PlaceCard(
                  keyName: 'workplace-dc',
                  accent: PdaColors.dark,
                  icon: Icons.warehouse_outlined,
                  title: l10n.workplaceDc,
                  tagline: l10n.workplaceDcTagline,
                  duties: l10n.workplaceDcDuties.split('·'),
                  dutyIcons: const [
                    Icons.shopping_basket_outlined,
                    Icons.call_split,
                    Icons.inventory_2_outlined,
                    Icons.fact_check_outlined,
                    Icons.local_shipping_outlined,
                  ],
                  centers: join(s?.cdcCenters ?? const []),
                  onTap: () =>
                      ref.read(workplaceProvider.notifier).choose(Workplace.dc),
                ),
              ),
              const SizedBox(height: 14),
              EnterFade(
                index: 2,
                child: _PlaceCard(
                  keyName: 'workplace-mfc',
                  accent: PdaColors.primary,
                  icon: Icons.storefront_outlined,
                  title: l10n.workplaceMfc,
                  tagline: l10n.workplaceMfcTagline,
                  duties: l10n.workplaceMfcDuties.split('·'),
                  dutyIcons: const [
                    Icons.shopping_cart_outlined,
                    Icons.local_shipping_outlined,
                    Icons.move_to_inbox_outlined,
                    Icons.verified_outlined,
                    Icons.inventory_outlined,
                  ],
                  centers: join(s?.mfcCenters ?? const []),
                  onTap: () => ref
                      .read(workplaceProvider.notifier)
                      .choose(Workplace.mfc),
                ),
              ),
              const Spacer(flex: 2),
              _Footnote(text: l10n.workplaceFootnote),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    required this.keyName,
    required this.accent,
    required this.icon,
    required this.title,
    required this.tagline,
    required this.duties,
    required this.dutyIcons,
    required this.centers,
    required this.onTap,
  });

  final String keyName;
  final Color accent;
  final IconData icon;
  final String title;
  final String tagline;
  final List<String> duties;
  final List<IconData> dutyIcons;
  final String centers;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: PdaShadows.sm,
      ),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey(keyName),
          onTap: onTap,
          child: Stack(
            children: [
              // 왼쪽 색 띠 + 오른쪽 아래 큰 그림(옅게) — 두 카드를 색·그림으로 바로 구별
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 6, color: accent),
              ),
              Positioned(
                right: -18,
                bottom: -22,
                child: Icon(
                  icon,
                  size: 120,
                  color: accent.withValues(alpha: 0.05),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(icon, color: Colors.white, size: 30),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: PdaColors.ink,
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.8,
                                ),
                              ),
                              Text(
                                tagline,
                                style: const TextStyle(
                                  color: PdaColors.muted,
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final (i, d) in duties.indexed)
                          Container(
                            padding: const EdgeInsets.fromLTRB(8, 5, 11, 5),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (i < dutyIcons.length) ...[
                                  Icon(dutyIcons[i], size: 16, color: accent),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  d.trim(),
                                  style: TextStyle(
                                    color: accent,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: PdaColors.line),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.place_outlined,
                          size: 17,
                          color: PdaColors.muted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            centers,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: PdaColors.body,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading({required this.title, required this.help});

  final String title;
  final String help;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: PdaColors.ink,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        help,
        style: const TextStyle(
          color: PdaColors.muted,
          fontSize: 14,
          height: 1.4,
        ),
      ),
    ],
  );
}

class _Crumb extends StatelessWidget {
  const _Crumb({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: PdaColors.lilac,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: PdaColors.dark),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(
            color: PdaColors.dark,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _Footnote extends StatelessWidget {
  const _Footnote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.swap_horiz, size: 16, color: PdaColors.muted),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          text,
          style: const TextStyle(color: PdaColors.muted, fontSize: 12.5),
        ),
      ),
    ],
  );
}
