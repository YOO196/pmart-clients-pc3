import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../l10n/gen/app_localizations.dart';
import '../features/my_work/presentation/my_work.dart'
    show activityTypeText, myTodayWorkProvider;
import 'location_guide.dart';
import 'pda_decor.dart';
import 'pda_motion.dart';
import 'pda_theme.dart';

/// 단계 표시 — 번호 원을 선으로 잇는다(끝난 단계 ✓ 보라, 지금 단계 그라데이션 원 + 빛, 다음 단계 흰 원).
/// 사용자 2026-11-27 "PPT 처럼 각지다 — 디자인 요소·애니메이션" — 선이 차오르고 원이 커지며 바뀐다.
class StepHeader extends ConsumerWidget {
  const StepHeader({super.key, required this.names, required this.current});

  final List<String> names;
  final int current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final d = PdaMotion.of(context, PdaMotion.slow);
    const dot = 26.0;
    // 이전 작업 = 오늘 업무 내역의 마지막 건(서버 값, 못 읽으면 줄을 비운다) — 사용자 2026-11-27 "이전·다음 작업을 늘 작게"
    final acts = ref.watch(myTodayWorkProvider).value?.items;
    final last = acts == null || acts.isEmpty
        ? null
        : acts.reduce((a, b) => a.at.isAfter(b.at) ? a : b);
    final next = current + 1 < names.length ? names[current + 1] : null;
    // 단계가 바뀌면 카드가 잠깐 보라빛으로 반짝인다(넘어간 것이 확실히 보이게, 0.7초).
    return TweenAnimationBuilder<double>(
      key: ValueKey('step-flash-$current'),
      tween: Tween(begin: current == 0 ? 0 : 1, end: 0),
      duration: PdaMotion.of(context, const Duration(milliseconds: 700)),
      curve: Curves.easeOut,
      builder: (context, flash, child) => Container(
        margin: const EdgeInsets.only(top: 2, bottom: 16),
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
        decoration: BoxDecoration(
          color: Color.lerp(Colors.white, PdaColors.softer, flash),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: PdaColors.primary.withValues(alpha: 0.5 * flash),
            width: 1.5,
          ),
          boxShadow: PdaShadows.md,
        ),
        child: child,
      ),
      child: Column(
        children: [
          // 지금 단계 표시(시험·화면이 읽는 자리).
          SizedBox.shrink(key: ValueKey('step-$current')),
          SizedBox(
            height: dot,
            child: Row(
              children: [
                for (final (i, _) in names.indexed) ...[
                  if (i > 0)
                    Expanded(
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          Container(height: 3, color: PdaColors.line),
                          AnimatedFractionallySizedBox(
                            duration: d,
                            curve: PdaMotion.enter,
                            widthFactor: i <= current ? 1 : 0,
                            child: Container(
                              height: 3,
                              decoration: const BoxDecoration(
                                gradient: PdaGradients.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  AnimatedContainer(
                    duration: d,
                    curve: PdaMotion.enter,
                    width: i == current ? dot : dot - 6,
                    height: i == current ? dot : dot - 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: i <= current ? PdaGradients.primary : null,
                      color: i <= current ? null : Colors.white,
                      border: i <= current
                          ? null
                          : Border.all(color: PdaColors.line, width: 2),
                      boxShadow: i == current
                          ? [
                              BoxShadow(
                                color: PdaColors.primary.withValues(
                                  alpha: 0.35,
                                ),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: i < current
                        ? const PopIn(
                            child: Icon(
                              Icons.check_rounded,
                              size: 13,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: i == current ? 12 : 10,
                              fontWeight: FontWeight.w700,
                              color: i == current
                                  ? Colors.white
                                  : PdaColors.onBarMuted,
                            ),
                          ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final (i, n) in names.indexed)
                Expanded(
                  child: Align(
                    alignment: i == 0
                        ? Alignment.centerLeft
                        : i == names.length - 1
                        ? Alignment.centerRight
                        : Alignment.center,
                    child: AnimatedDefaultTextStyle(
                      duration: d,
                      style: theme.textTheme.labelSmall!.copyWith(
                        color: i == current
                            ? PdaColors.primary
                            : i < current
                            ? PdaColors.body
                            : PdaColors.onBarMuted,
                        fontWeight: i == current
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                      child: Text(n, maxLines: 1, overflow: TextOverflow.fade),
                    ),
                  ),
                ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Divider(height: 1),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Row(
              children: [
                const Icon(
                  Icons.history_rounded,
                  size: 14,
                  color: PdaColors.onBarMuted,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    last == null
                        ? l10n.trailNoPrevious
                        : l10n.trailPrevious(
                            activityTypeText(l10n, last.type),
                            last.taskId ?? last.refId,
                            formatSeoulTime(last.at),
                          ),
                    key: const ValueKey('trail-previous'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: PdaColors.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: PdaColors.softer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    next == null ? l10n.trailNextLast : l10n.trailNext(next),
                    key: const ValueKey('trail-next'),
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: PdaColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 지금 할 일 — 시안의 큰 제목(예 "장바구니를 스캔하세요") + 한 줄 설명(진한 글씨, 한 줄에 들어가게 짧게).
class ScanPrompt extends StatelessWidget {
  const ScanPrompt({super.key, required this.text, this.detail, this.icon});

  final String text;
  final String? detail;

  /// 제목 옆 배지 그림 — 비우면 문구로 고른다(스캔·이동·담기·세기·확인).
  final IconData? icon;

  static IconData _guess(String t) {
    if (t.contains('스캔') || t.contains('찍')) {
      return Icons.qr_code_scanner_rounded;
    }
    if (t.contains('이동') || t.contains('위치') || t.contains('칸')) {
      return Icons.place_rounded;
    }
    if (t.contains('담') || t.contains('넣')) {
      return Icons.shopping_basket_rounded;
    }
    if (t.contains('세') || t.contains('수량')) return Icons.calculate_rounded;
    if (t.contains('고르') || t.contains('선택')) return Icons.touch_app_rounded;
    if (t.contains('확인') || t.contains('검')) return Icons.fact_check_rounded;
    return Icons.auto_awesome_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      // 할 일이 바뀌면 새 제목이 살짝 올라오며 나타난다(같은 제목이면 그대로).
      child: EnterFade(
        key: ValueKey(text),
        offset: 8,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            PopIn(child: GradientBadge(icon: icon ?? _guess(text), size: 44)),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      height: 1.3,
                    ),
                  ),
                  if (detail case final d?)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      // 설명은 짧게 — 최대 2줄(사용자 2026-11-26 "긴 글 줄줄 적어 놓은 부분 없게")
                      child: Text(
                        d,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: PdaColors.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 진행 줄 — "확정 n / 지시 m" + 막대(시안 progress).
class ProgressLine extends StatelessWidget {
  const ProgressLine({
    super.key,
    required this.text,
    required this.done,
    required this.total,
    this.textKey,
  });

  final String text;
  final int done;
  final int total;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: PdaShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  key: textKey,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: PdaColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: PdaColors.softer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${(ratio * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: PdaColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          // 확정될 때마다 막대가 부드럽게 찬다(그라데이션).
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 9,
              color: PdaColors.lilac.withValues(alpha: 0.7),
              alignment: Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: ratio),
                duration: PdaMotion.of(context, PdaMotion.slow),
                curve: PdaMotion.enter,
                builder: (_, v, _) => FractionallySizedBox(
                  widthFactor: v,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: PdaGradients.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 화면 아래 고정 버튼 칸(시안 actions) — 흰 바탕, 위 선, 버튼 사이 7.
/// 스캔 칸·주 버튼·보조 버튼을 넣는다. 비면 아무것도 그리지 않는다.
class ActionBar extends StatelessWidget {
  const ActionBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    // 이 단계를 끝내는 주 단추(채운 보라)가 따로 있으면 스캔 단추는 보조(옅은 보라)로 — 같은 무게의 보라 단추 둘이
    // 겹쳐 무엇이 주 동작인지 안 보였다(사용자 2026-11-20). 스캐너는 단추를 누르지 않아도 읽는다.
    // 주 단추가 아직 눌리지 않는 상태(스캔해야 켜짐)면 스캔이 지금 할 일이라 스캔 단추를 그대로 진하게 둔다.
    final hasCommand = children.any(
      (c) => switch (c) {
        CommandButton(:final onPressed, :final busy) =>
          onPressed != null || busy,
        FilledButton(:final onPressed) => onPressed != null,
        _ => false,
      },
    );
    return ActionScope(
      secondaryScan: hasCommand,
      child: DecoratedBox(
        // 바탕 위에 단추만 — 선·흰 띠 없이(사용자 2026-11-27 "부드럽게")
        decoration: const BoxDecoration(color: PdaColors.canvas),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, c) in children.indexed) ...[
                  if (i > 0) const SizedBox(height: 7),
                  c,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 아래 버튼 칸 안의 정보 — 스캔 단추를 보조 모양으로 그릴지.
class ActionScope extends InheritedWidget {
  const ActionScope({
    super.key,
    required this.secondaryScan,
    required super.child,
  });

  final bool secondaryScan;

  static bool secondaryScanOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ActionScope>()
          ?.secondaryScan ??
      false;

  @override
  bool updateShouldNotify(ActionScope old) =>
      old.secondaryScan != secondaryScan;
}

/// 단계 화면 몸통 — 위 내용(좌우 16) + 아래 고정 버튼 칸([ActionBar]).
/// [child] 는 남은 높이를 다 받는다(안에서 `Expanded` 목록을 써도 된다).
class StepBody extends StatelessWidget {
  const StepBody({super.key, required this.child, this.actions = const []});

  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: Padding(
          // 위아래 여유(사용자 2026-11-20 "전반적으로 위아래 간격을 여유롭게").
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: child,
        ),
      ),
      ActionBar(children: actions),
    ],
  );
}

/// 작은 회색 머리줄(예 "상품 2 / 7", "칸 1 / 3").
class StepCaption extends StatelessWidget {
  const StepCaption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: PdaColors.muted, fontWeight: FontWeight.w700),
    ),
  );
}

/// 끝 표시(시안 complete) — 옅은 보라 원 안의 ✓ + 큰 제목 + 설명.
class DoneMark extends StatelessWidget {
  const DoneMark({
    super.key,
    required this.title,
    this.message,
    this.messageKey,
  });

  final String title;
  final String? message;
  final Key? messageKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const SuccessBurst(),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
            ),
          ),
          if (message case final m?)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                m,
                key: messageKey,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: PdaColors.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 안내 띠 — 보통은 옅은 보라, [warning] 이면 노랑(같은 LOT 다른 칸·입수와 다름처럼
/// 작업자가 멈춰 확인해야 하는 주의. 사용자 2026-11-19 "주의 안내만 노랑으로").
class NoticeBox extends StatelessWidget {
  const NoticeBox({
    super.key,
    required this.text,
    this.textKey,
    this.warning = false,
  });

  final String text;

  /// 안의 [Text] 키(시험·화면이 문구를 읽는 자리).
  final Key? textKey;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? PdaColors.onWarning : PdaColors.onNotice;
    // 보통 안내는 상자 없이 아이콘 + 한 줄(사용자 2026-11-26 "깔끔하게"), 주의만 노란 띠.
    return EnterFade(
      offset: 6,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
        decoration: BoxDecoration(
          color: warning ? PdaColors.warning : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: warning ? null : PdaShadows.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 26,
              margin: const EdgeInsets.only(right: 9),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: warning
                    ? PdaColors.onWarning.withValues(alpha: 0.12)
                    : PdaColors.softer,
              ),
              child: Icon(
                warning ? Icons.priority_high_rounded : Icons.lightbulb_rounded,
                size: 16,
                color: color,
              ),
            ),
            Expanded(
              child: Text(
                text,
                key: textKey,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "이동하세요" 안내 — 물건을 실은 뒤 도착 칸으로 가는 동안 보인다.
class GoBanner extends StatelessWidget {
  const GoBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return EnterFade(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.directions_walk, color: scheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 작업 하나가 끝났을 때의 완료 화면: 제목 + 한 줄 요약 + 요약 줄(무엇을·어디서·어디로) + "다음 작업".
///
/// "다음 작업"을 [autoNextAfter] 안에 누르지 않으면 누른 것과 똑같이 자동으로 다음 작업을 받는다
/// (사용자 2026-11-13: 10초). 남은 초를 버튼 위에 보인다. 서버가 끝났다고 답한 뒤에만 띄운다.
/// [autoNext] 가 false(휴게 중)면 자동으로 넘어가지 않고 버튼만 둔다(사용자 2026-11-14).
class TaskDoneView extends StatefulWidget {
  const TaskDoneView({
    super.key,
    required this.title,
    required this.message,
    required this.rows,
    required this.onNext,
    this.autoNext = true,
    this.nextLabel,
    this.autoNextText,
  });

  static const autoNextAfter = Duration(seconds: 10);

  /// "다음 작업" 대신 단추 글(예: DC 피킹 끝 → "분배·패킹으로")
  final String? nextLabel;

  /// 자동으로 넘어가기까지 안내(남은 초) — 없으면 "N초 뒤 자동으로 다음 작업을 받아요"
  final String Function(int seconds)? autoNextText;

  final String title;
  final String message;

  /// (이름, 값) 줄.
  final List<(String, String)> rows;
  final Future<void> Function() onNext;
  final bool autoNext;

  @override
  State<TaskDoneView> createState() => _TaskDoneViewState();
}

class _TaskDoneViewState extends State<TaskDoneView> {
  Timer? _tick;
  int _left = TaskDoneView.autoNextAfter.inSeconds;
  bool _going = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoNext) _startTimer();
  }

  @override
  void didUpdateWidget(TaskDoneView old) {
    super.didUpdateWidget(old);
    if (_going || old.autoNext == widget.autoNext) return;
    // 휴게가 바뀌면(또는 본인 정보가 늦게 오면) 타이머를 처음부터 다시 켜거나 끈다.
    _tick?.cancel();
    _tick = null;
    _left = TaskDoneView.autoNextAfter.inSeconds;
    if (widget.autoNext) _startTimer();
  }

  void _startTimer() {
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_left > 1) {
        setState(() => _left -= 1);
      } else {
        _next();
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// 버튼을 눌렀든 시간이 됐든 한 번만 넘어간다.
  Future<void> _next() async {
    if (_going) return;
    _tick?.cancel();
    setState(() {
      _going = true;
      _left = 0;
    });
    await widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        const PopIn(haptic: true, child: MarkCircle(icon: Icons.check)),
        const SizedBox(height: 12),
        Text(
          widget.title,
          key: const ValueKey('done-title'),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.message,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        if (widget.rows.isNotEmpty) ...[
          const SizedBox(height: 20),
          EnterFade(
            index: 2,
            child: Card(
              key: const ValueKey('done-summary'),
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    for (final (label, value) in widget.rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 72,
                              child: Text(
                                label,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                value,
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const Spacer(flex: 2),
        if (!_going)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              widget.autoNext
                  ? (widget.autoNextText?.call(_left) ??
                        l10n.moveDoneAutoNext(_left))
                  : l10n.doneAutoNextOnBreak,
              key: ValueKey(
                widget.autoNext ? 'done-auto-next' : 'done-auto-next-off',
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        CommandButton(
          key: const ValueKey('result-action'),
          label: widget.nextLabel ?? l10n.nextTask,
          busy: _going,
          onPressed: _next,
        ),
      ],
    );
  }
}

/// 끝·대기·오류 안내 + 버튼 하나.
class ResultView extends StatelessWidget {
  const ResultView({
    super.key,
    required this.icon,
    required this.text,
    required this.action,
    required this.onAction,
    this.busy = false,
    this.detail,
  });

  final IconData icon;
  final String text;

  /// 제목 아래 크게 한 줄(예 출하대기 랙 코드).
  final String? detail;
  final String action;
  final Future<void> Function() onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (busy)
        const Center(child: CircularProgressIndicator())
      else
        PopIn(
          child: MarkCircle(
            icon: icon == Icons.check_circle ? Icons.check : icon,
          ),
        ),
      const SizedBox(height: 16),
      Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      if (detail case final d?)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            d,
            key: const ValueKey('result-detail'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: PdaColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      const SizedBox(height: 24),
      CommandButton(
        key: const ValueKey('result-action'),
        label: action,
        busy: busy,
        onPressed: onAction,
      ),
    ],
  );
}

/// 이 칸에 왔는지 확인하는 줄: 지시 위치 + 스캔했으면 ✓.
class TargetLine extends StatelessWidget {
  const TargetLine({
    super.key,
    required this.label,
    required this.code,
    required this.confirmed,
  });

  final String label;
  final String code;
  final bool confirmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = Row(
      children: [
        // 칸을 찍어 맞으면 위치 그림이 ✓ 로 튀어 바뀐다.
        AnimatedSwitcher(
          duration: PdaMotion.of(context, PdaMotion.base),
          transitionBuilder: (c, a) => ScaleTransition(
            scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
            child: c,
          ),
          child: Icon(
            confirmed ? Icons.check_circle : Icons.place_outlined,
            key: ValueKey(confirmed),
            color: confirmed ? theme.colorScheme.primary : null,
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.titleMedium),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            code,
            style: theme.textTheme.headlineSmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    // 아직 가야 할 선반 칸이면 조각 색 블록을 아래에 크게(위치 스캔 화면 구성 — 사용자 2026-11-16).
    if (confirmed || ShelfCode.parse(code) == null) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        const SizedBox(height: 4),
        LocationBlocks(code: code),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// 수량 −/＋, 숫자를 누르면 직접 입력.
class QtyStepper extends StatelessWidget {
  const QtyStepper({
    super.key,
    required this.id,
    required this.label,
    required this.value,
    required this.onChanged,
    this.max,
    this.enabled = true,
    this.plusEnabled = true,
    this.typeEnabled = true,
  });

  final String id;
  final String label;
  final int value;
  final int? max;
  final bool enabled;

  /// ＋ 버튼. 스캔으로 세는 칸에서는 끈다(스캔이 +1).
  final bool plusEnabled;

  /// 숫자를 눌러 직접 넣기.
  final bool typeEnabled;
  final ValueChanged<int> onChanged;

  void _set(int v) {
    final m = max;
    onChanged(v < 0 ? 0 : (m != null && v > m ? m : v));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.titleMedium)),
        IconButton.outlined(
          key: ValueKey('$id-minus'),
          onPressed: enabled && value > 0 ? () => _set(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        InkWell(
          key: ValueKey('$id-value'),
          onTap: enabled && typeEnabled
              ? () async {
                  final v = await showDialog<int>(
                    context: context,
                    builder: (_) => QtyDialog(title: label, initial: value),
                  );
                  if (v != null) _set(v);
                }
              : null,
          child: SizedBox(
            width: 64,
            child: ClipRect(
              child: _Counter(
                value: value,
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
              ),
            ),
          ),
        ),
        IconButton.filledTonal(
          key: ValueKey('$id-plus'),
          onPressed: enabled && plusEnabled && (max == null || value < max!)
              ? () => _set(value + 1)
              : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

/// 수량 직접 입력. 컨트롤러는 다이얼로그가 닫힌 뒤 해제한다.
class QtyDialog extends StatefulWidget {
  const QtyDialog({super.key, required this.title, required this.initial});

  final String title;
  final int initial;

  @override
  State<QtyDialog> createState() => _QtyDialogState();
}

class _QtyDialogState extends State<QtyDialog> {
  late final _c = TextEditingController(text: '${widget.initial}');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('qty-input'),
        controller: _c,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('qty-ok'),
          onPressed: () =>
              Navigator.of(context).pop(int.tryParse(_c.text.trim())),
          child: Text(l10n.confirmOk),
        ),
      ],
    );
  }
}

/// 현장 명령 거절 문구. 담당 아님(409 `NOT_ASSIGNEE` — 이동 지시, 입고 작업 mfc-inbound 0.9.0)은 따로 알린다.
String fieldRejectedText(AppLocalizations l10n, String code) =>
    code == 'NOT_ASSIGNEE' ? l10n.startNotAssignee : l10n.inspectRejected(code);

/// 스캔해 센 수량 — 첫 개를 스캔한 뒤 보인다(사용자 2026-11-17, 피킹·이동·적치·복귀 같게).
/// 스캔마다 +1(화면 밖), + 버튼, 숫자 수기(완료 키·바깥 누르면 반영). 범위 판단은 [onSet] 쪽.
class CountQtyField extends StatefulWidget {
  const CountQtyField({
    super.key,
    required this.id,
    required this.label,
    required this.help,
    required this.addLabel,
    required this.value,
    required this.max,
    required this.onAdd,
    required this.onSet,
  });

  /// 입력칸 키 `id`, + 버튼 키 `id-add`.
  final String id;
  final String label;
  final String help;
  final String addLabel;
  final int value;
  final int max;
  final VoidCallback onAdd;
  final ValueChanged<int> onSet;

  @override
  State<CountQtyField> createState() => _CountQtyFieldState();
}

class _CountQtyFieldState extends State<CountQtyField> {
  late final _text = TextEditingController(text: '${widget.value}');

  @override
  void didUpdateWidget(CountQtyField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _text.text = '${widget.value}';
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _apply() {
    final n = int.tryParse(_text.text.trim());
    if (n == null) {
      _text.text = '${widget.value}';
      return;
    }
    widget.onSet(n);
    // 범위 밖이라 값이 그대로면 칸을 원래 값으로 돌린다.
    if (mounted) _text.text = '${widget.value}';
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: ValueKey(widget.id),
            controller: _text,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            style: Theme.of(context).textTheme.headlineSmall,
            decoration: InputDecoration(
              labelText: widget.label,
              helperText: widget.help,
              helperMaxLines: 2,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _apply(),
            onTapOutside: (_) {
              FocusManager.instance.primaryFocus?.unfocus();
              _apply();
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 64,
          child: FilledButton.tonalIcon(
            key: ValueKey('${widget.id}-add'),
            onPressed: widget.value < widget.max ? widget.onAdd : null,
            icon: const Icon(Icons.add),
            label: Text(widget.addLabel),
          ),
        ),
      ],
    ),
  );
}

/// 옅은 보라 원 안의 그림(시안 complete 의 ✓).
class MarkCircle extends StatelessWidget {
  const MarkCircle({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
    child: icon == Icons.check
        ? const SuccessBurst(size: 64)
        : PopIn(child: GradientBadge(icon: icon, size: 64, circle: true)),
  );
}

/// 온도대 칩(냉장 하늘·냉동 보라·상온 살구) — 봉투·상품의 온도대처럼 놓치면 안 되는 값을 크게.
/// [code] 는 C·F·A 또는 CHILLED·FROZEN·AMBIENT.
class ZoneChip extends StatelessWidget {
  const ZoneChip({
    super.key,
    required this.code,
    required this.text,
    this.large = false,
  });

  final String code;
  final String text;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = switch (code.toUpperCase()) {
      'C' || 'CHILLED' => 'C',
      'F' || 'FROZEN' => 'F',
      _ => 'A',
    };
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 12 : 8,
        vertical: large ? 5 : 2,
      ),
      decoration: BoxDecoration(
        color: tempChipColor(c),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style:
            (large ? theme.textTheme.titleMedium : theme.textTheme.labelLarge)
                ?.copyWith(fontWeight: FontWeight.w700, color: PdaColors.ink),
      ),
    );
  }
}

/// 숫자 칸 — 작은 이름 + 큰 숫자(예 "이 봉투 3개"). [strong] 이면 보라.
class StatBox extends StatelessWidget {
  const StatBox({
    super.key,
    required this.label,
    required this.value,
    this.strong = false,
    this.valueKey,
  });

  final String label;
  final String value;
  final bool strong;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: strong ? PdaColors.softer : PdaColors.soft,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: strong ? PdaColors.lilac : PdaColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: PdaColors.body),
          ),
          const SizedBox(width: 8),
          SwapValue(
            value: value,
            child: Text(
              value,
              key: valueKey,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: strong ? PdaColors.primary : PdaColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 됐다는 한 줄(초록 체크 + 굵은 글씨) — "모든 상품 포장 끝" 처럼 확인된 상태.
class DoneLine extends StatelessWidget {
  const DoneLine({super.key, required this.text, this.textKey});

  final String text;
  final Key? textKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 4),
    child: Row(
      children: [
        const PopIn(
          child: Icon(Icons.check_circle, size: 20, color: PdaColors.ok),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            key: textKey,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700, color: PdaColors.okInk),
          ),
        ),
      ],
    ),
  );
}

/// 이름표 + 값 한 쌍(예 "LOT  L261107000497", "유통기한  2026-11-05") — 값은 진하게.
class MetaPair extends StatelessWidget {
  const MetaPair({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: theme.textTheme.bodyMedium?.copyWith(color: PdaColors.muted),
          ),
          TextSpan(
            text: value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: PdaColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// 수량 숫자 — 늘면 아래에서, 줄면 위에서 새 숫자가 들어온다.
class _Counter extends StatefulWidget {
  const _Counter({required this.value, required this.child});

  final int value;
  final Widget child;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  bool _up = true;

  @override
  void didUpdateWidget(_Counter old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _up = widget.value > old.value;
  }

  @override
  Widget build(BuildContext context) =>
      SwapValue(value: widget.value, up: _up, child: widget.child);
}
