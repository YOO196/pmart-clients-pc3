import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/field_widgets.dart';
import '../../../shared/pda_motion.dart';
import '../../../shared/pda_theme.dart';
import '../../auth/presentation/auth_controller.dart';
import 'cdc_home.dart';

/// DC 업무 공통 — MFC 업무 화면(순서 안내 → 단계별 스캔 → 완료 → 다음)과 같은 모양을 쓴다(사용자 2026-11-26
/// "mfc 쪽 업무화면 참고해봐"). 공통 부품은 shared/field_widgets·scanner 를 그대로 쓴다.

/// 로그인 세션의 DC — 하나일 때만(여럿·없음이면 빈 값)
String cdcCenterOf(WidgetRef ref) {
  final c = ref.read(employeeSessionProvider)?.centers ?? const [];
  return c.length == 1 ? c.single : '';
}

String cdcWorkerOf(WidgetRef ref) =>
    ref.read(employeeSessionProvider)?.operatorId ?? '';

/// 업무 순서 안내 — MFC `WorkGuideScreen` 과 같은 배치(업무 카드 → 번호 단계 → 안내 띠 → "작업 받기").
class CdcGuideScreen extends StatelessWidget {
  const CdcGuideScreen({super.key, required this.area});

  final CdcWorkArea area;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final steps = switch (area) {
      CdcWorkArea.pick => [
        (Icons.assignment_turned_in_outlined, l10n.cdcGuidePick1),
        (Icons.place_outlined, l10n.cdcGuidePick2),
        (Icons.qr_code_scanner, l10n.cdcGuidePick3),
        (Icons.report_problem_outlined, l10n.cdcGuidePick4),
      ],
      CdcWorkArea.inspect => [
        (Icons.list_alt, l10n.cdcGuideInspect1),
        (Icons.qr_code_scanner, l10n.cdcGuideInspect2),
        (Icons.fact_check_outlined, l10n.cdcGuideInspect3),
        (Icons.report_problem_outlined, l10n.cdcGuideInspect4),
      ],
      CdcWorkArea.load => [
        (Icons.qr_code_scanner, l10n.cdcGuideLoad1),
        (Icons.local_shipping_outlined, l10n.cdcGuideLoad2),
        (Icons.qr_code_scanner, l10n.cdcGuideLoad3),
        (Icons.info_outline, l10n.cdcGuideLoad4),
      ],
      CdcWorkArea.distribute => [
        (Icons.list_alt, l10n.cdcGuideDistribute1),
        (Icons.qr_code_scanner, l10n.cdcGuideDistribute2),
        (Icons.grid_view, l10n.cdcGuideDistribute3),
        (Icons.inventory_2_outlined, l10n.cdcGuideDistribute4),
      ],
    };
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: Text(l10n.guideTitle(cdcAreaText(l10n, area)))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            key: const ValueKey('cdc-guide'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CdcAreaHero(area: area),
              const SizedBox(height: 12),
              EnterFade(
                delay: const Duration(milliseconds: 260),
                child: Text(
                  l10n.guideLead,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: PdaColors.muted,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Column(
                  children: [
                    // 카드가 자리 잡은 뒤(Hero 380ms) 단계가 차례로 — 날아오는 카드와 겹쳐 보이지 않게
                    for (final (i, (icon, text)) in steps.indexed)
                      Expanded(
                        child: EnterFade(
                          delay: const Duration(milliseconds: 300),
                          index: i,
                          child: _GuideStep(
                            n: i + 1,
                            icon: icon,
                            text: text,
                            last: i == steps.length - 1,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              NoticeBox(
                text: area == CdcWorkArea.pick
                    ? l10n.guideCommon
                    : l10n.cdcGuideCommon,
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('cdc-guide-ok'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(64),
                  textStyle: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onPressed: () =>
                    context.pushReplacement('/cdc/work/${area.name}'),
                child: Text(
                  area == CdcWorkArea.pick ? l10n.guideOk : l10n.cdcGuideStart,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 업무 카드(이름·설명·큰 그림) — MFC `AreaHeroCard` 와 같은 모양
class CdcAreaHero extends StatelessWidget {
  const CdcAreaHero({super.key, required this.area});

  final CdcWorkArea area;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Hero(
      tag: cdcHeroTag(area),
      flightShuttleBuilder: cdcAreaShuttle(area),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: const BorderSide(color: PdaColors.lilac, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      cdcAreaText(l10n, area),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      cdcAreaDesc(l10n, area),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: PdaColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                  color: PdaColors.softer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  cdcAreaIcon(area),
                  size: 46,
                  color: PdaColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.n,
    required this.icon,
    required this.text,
    required this.last,
  });

  final int n;
  final IconData icon;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      key: ValueKey('cdc-guide-step-$n'),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: PdaColors.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 23,
            height: 23,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: PdaColors.softer,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$n',
              style: const TextStyle(
                color: PdaColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: PdaColors.softer,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, size: 30, color: PdaColors.primary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 사유 고르기 — 장갑 낀 손으로도 누르게 큰 칸(MFC 결품 사유 창과 같은 모양)
Future<String?> showCdcReasonDialog(
  BuildContext context, {
  required String title,
  required List<(String, IconData, String)> options,
  String keyPrefix = 'cdc-reason',
}) => showDialog<String>(
  context: context,
  builder: (context) => SimpleDialog(
    title: Text(title),
    contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
    children: [
      for (final (value, icon, label) in options)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: OutlinedButton(
            key: ValueKey('$keyPrefix-$value'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(60),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(value),
            child: Row(
              children: [
                Icon(icon, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  ),
);

/// 상품 카드 — 이름, 회색 SKU·LOT, 오른쪽 큰 수량(MFC 피킹 카드와 같은 무게)
class CdcItemCard extends StatelessWidget {
  const CdcItemCard({
    super.key,
    required this.name,
    required this.sku,
    required this.lot,
    required this.qty,
    this.qtyLabel,
    this.footer,
    this.emphasize = false,
  });

  final String name;
  final String sku;
  final String? lot;
  final int qty;
  final String? qtyLabel;
  final String? footer;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 강조(지금 스캔하는 상품)는 테두리가 부드럽게 바뀐다
    return AnimatedContainer(
      duration: PdaMotion.of(context, PdaMotion.slow),
      curve: PdaMotion.standard,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: emphasize ? PdaColors.primary : PdaColors.line,
          width: emphasize ? 2 : 1,
        ),
        boxShadow: PdaShadows.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  // 상품명이 없으면(BOX 내용) 이름 자리에 SKU — 아래 줄은 LOT 만
                  name == sku
                      ? (lot == null ? '' : 'LOT $lot')
                      : (lot == null ? sku : '$sku · LOT $lot'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: PdaColors.muted,
                  ),
                ),
                if (footer case final f?)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: SwapValue(
                      value: f,
                      child: Text(
                        f,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: PdaColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 수량이 바뀌면 새 숫자가 굴러 들어온다(MFC 수량 칸과 같은 효과)
              CdcCount(
                value: qty,
                child: Text(
                  '$qty',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: PdaColors.ink,
                  ),
                ),
              ),
              if (qtyLabel case final q?)
                Text(q, style: const TextStyle(color: PdaColors.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

/// 오류 한 줄(빨강, 굵게) — MFC 스캔 오류와 같은 모양
class CdcErrorLine extends StatelessWidget {
  const CdcErrorLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => EnterFade(
    key: ValueKey(text),
    offset: 0,
    child: Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

/// 가운데 안내(아이콘·문구·버튼) — 작업 없음·불러오기 실패
class CdcCenterNotice extends StatelessWidget {
  const CdcCenterNotice({
    super.key,
    required this.icon,
    required this.text,
    this.textKey,
    this.action,
  });

  final IconData icon;
  final String text;
  final Key? textKey;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, size: 56, color: PdaColors.muted),
          const SizedBox(height: 12),
          Text(
            text,
            key: textKey,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

/// 보내기 공통 — 같은 행위 재전송은 같은 키, 결과 불명이면 "같은 내용으로 다시 보내기", 거절이면 다시 읽고 이유.
mixin CdcCommand<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool busy = false;

  /// 보낸 뒤 다시 읽는 중 — 화면은 그대로 두고 위에 얇은 진행 줄만(깜빡이지 않게)
  bool reloading = false;
  String? failText;
  IdempotencyKey? _key;
  Future<void> Function()? resend;

  Future<bool> send(
    Future<void> Function(IdempotencyKey key) call, {
    required Future<void> Function() reload,
  }) async {
    final key = _key ??= IdempotencyKey.generate();
    setState(() {
      busy = true;
      failText = null;
    });
    try {
      await call(key);
      _key = null;
      resend = null;
      await reload();
      return true;
    } on PmartFailure catch (f) {
      if (!mounted) return false;
      final l10n = AppLocalizations.of(context);
      final unknown = f is UnknownResultFailure || f is NetworkFailure;
      resend = unknown ? () => send(call, reload: reload) : null;
      if (!unknown) {
        _key = null;
        try {
          await reload();
        } on PmartFailure {
          // 다시 읽지 못하면 지금 화면을 둔다
        }
      }
      failText = switch (f) {
        _ when unknown => l10n.cdcPickUnknown,
        ProblemFailure(:final problem) => cdcProblemText(l10n, problem.code),
        _ => l10n.cdcPickFailed,
      };
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// 결과 불명이면 아래 칸에 넣을 "같은 내용으로 다시 보내기"
  Widget? resendButton(BuildContext context) => resend == null
      ? null
      : FilledButton(
          key: const ValueKey('cdc-retry'),
          onPressed: busy ? null : resend,
          child: Text(AppLocalizations.of(context).cdcPickResend),
        );
}

String cdcProblemText(AppLocalizations l10n, String code) => switch (code) {
  'LPN_ALREADY_SEALED' => l10n.cdcErrLpnSealed,
  'NOTHING_LOADED' => l10n.cdcErrNothingLoaded,
  'SORT_EXCEEDS_PICKED' => l10n.cdcErrSortExceeds,
  'LPN_NOT_PASSED' || 'LOAD_EXCEEDS_INSPECTED' => l10n.cdcErrNotPassed,
  'TRIP_MISMATCH' => l10n.cdcErrTripMismatch,
  'EXECUTION_EXCEEDS_REMAINING' ||
  'PICK_EXCEEDS_ALLOCATION' => l10n.cdcPickExceeds,
  'VERSION_CONFLICT' ||
  'INVALID_STATE' ||
  'NOT_ASSIGNEE' => l10n.cdcPickChanged,
  'NOT_FOUND' => l10n.cdcErrNotFound,
  _ => l10n.cdcPickFailed,
};

/// 스캔한 코드가 그 상품인지 — DC 작업 줄에는 바코드가 없어(계약) SKU 또는 LOT 코드로 맞춘다.
bool cdcCodeIsItem(String code, String sku, String lot) {
  final c = code.trim().toUpperCase();
  return c == sku.toUpperCase() || c == lot.toUpperCase();
}

/// 수량 숫자 — 늘면 아래에서, 줄면 위에서 새 숫자가 들어온다(MFC `_Counter` 와 같다)
class CdcCount extends StatefulWidget {
  const CdcCount({super.key, required this.value, required this.child});

  final int value;
  final Widget child;

  @override
  State<CdcCount> createState() => _CdcCountState();
}

class _CdcCountState extends State<CdcCount> {
  bool _up = true;

  @override
  void didUpdateWidget(CdcCount old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _up = widget.value > old.value;
  }

  @override
  Widget build(BuildContext context) =>
      SwapValue(value: widget.value, up: _up, child: widget.child);
}

/// 단계 화면 몸통 — 위의 단계 알약·진행 막대·안내 띠는 그대로 두고, 그 아래 단계 내용만 [step] 이 바뀔 때
/// 교차 전환한다(나가는 것은 옅어지고 들어오는 것은 살짝 올라오며, 높이도 부드럽게). 아래 고정 칸은 [actions].
Widget cdcStepBody({
  required String step,
  required List<Widget> body,
  required List<Widget> actions,
}) {
  final fixed = body
      .takeWhile((w) => w is StepHeader || w is ProgressLine || w is NoticeBox)
      .length;
  return Column(
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ...body.take(fixed),
            CdcStepSwitch(
              step: step,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: body.skip(fixed).toList(),
              ),
            ),
          ],
        ),
      ),
      ActionBar(children: actions),
    ],
  );
}

class CdcStepSwitch extends StatelessWidget {
  const CdcStepSwitch({super.key, required this.step, required this.child});

  final String step;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final d = PdaMotion.of(context, cdcStepDuration);
    return AnimatedSize(
      duration: d,
      curve: PdaMotion.standard,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: d,
        switchInCurve: PdaMotion.enter,
        switchOutCurve: PdaMotion.exit,
        // 나가는 내용은 바로 뺀다 — 둘 다 흐려지면 그 사이 화면이 비어 보였다(중간 프레임 확인). 들어오는 것만 빠르게.
        layoutBuilder: (current, previous) =>
            current ?? const SizedBox.shrink(),
        transitionBuilder: (child, a) => FadeTransition(
          opacity: CurvedAnimation(
            parent: a,
            curve: const Interval(0, 0.6, curve: Curves.easeOut),
          ),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.03),
              end: Offset.zero,
            ).animate(a),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(step), child: child),
      ),
    );
  }
}

/// [trigger] 가 바뀌면(예: 방금 스캔한 상품) 화면 안으로 부드럽게 스크롤한다 — 아래에 있던 카드의 숫자가 바뀌어도 보이게.
class CdcReveal extends StatefulWidget {
  const CdcReveal({super.key, required this.trigger, required this.child});

  final Object? trigger;
  final Widget child;

  @override
  State<CdcReveal> createState() => _CdcRevealState();
}

class _CdcRevealState extends State<CdcReveal> {
  @override
  void didUpdateWidget(CdcReveal old) {
    super.didUpdateWidget(old);
    if (widget.trigger != null && widget.trigger != old.trigger) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          duration: PdaMotion.of(context, cdcStepDuration),
          curve: PdaMotion.standard,
          alignment: 0.4,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 작업 화면 앱바의 업무 그림 — 안내 화면의 업무 카드가 여기로 줄어들며 이어진다(Hero).
class CdcBarIcon extends StatelessWidget {
  const CdcBarIcon({super.key, required this.area});

  final CdcWorkArea area;

  @override
  Widget build(BuildContext context) => Hero(
    tag: cdcHeroTag(area),
    flightShuttleBuilder: cdcIconShuttle(area),
    child: Container(
      width: 34,
      height: 34,
      margin: const EdgeInsets.only(right: 10),
      decoration: const BoxDecoration(
        color: PdaColors.softer,
        shape: BoxShape.circle,
      ),
      child: Icon(cdcAreaIcon(area), size: 20, color: PdaColors.primary),
    ),
  );
}

/// 업무 카드 ↔ 앱바 그림 사이의 모습 — 카드 바탕은 흐려지고 그림 원만 남아 줄어든다.
HeroFlightShuttleBuilder cdcIconShuttle(CdcWorkArea area) =>
    (_, animation, direction, _, _) => AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        // 0 = 카드, 1 = 앱바 그림(들어갈 때). 나올 때(pop)는 거꾸로 흐른다.
        final t = Curves.easeInOutCubic.transform(animation.value);
        return LayoutBuilder(
          builder: (context, c) {
            final d = math.min(c.maxWidth, c.maxHeight);
            return Stack(
              alignment: Alignment.centerRight,
              children: [
                if (t < 1)
                  Positioned.fill(
                    child: Opacity(
                      opacity: (1 - t * 1.6).clamp(0.0, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(17),
                          border: Border.all(
                            color: PdaColors.lilac,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                Container(
                  width: d,
                  height: d,
                  decoration: const BoxDecoration(
                    color: PdaColors.softer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    cdcAreaIcon(area),
                    size: d * 0.55,
                    color: PdaColors.primary,
                  ),
                ),
              ],
            );
          },
        );
      },
    );

/// DC 작업 화면의 단계 전환·스크롤 시간 — 공통 기준(220ms)보다 느리게(사용자 2026-11-26 "애니메이션 너무 빨라서 정신없어").
const cdcStepDuration = Duration(milliseconds: 380);
