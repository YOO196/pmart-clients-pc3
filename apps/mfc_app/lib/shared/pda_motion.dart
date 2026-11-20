import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// PDA 움직임 기준(사용자 2026-11-20 "Tailwind 등 참조해 PDA UI 개선, 애니메이션도").
///
/// 참고: Tailwind 의 시간 단계(150·200·300ms)와 ease-out, Material 3 의 강조 감속(들어올 때)·강조 가속(나갈 때) 곡선.
/// 현장 단말은 손이 바쁘다 — 움직임은 "무엇이 바뀌었나"를 알려 주는 데만 짧게 쓰고, 기다리게 하지 않는다(모두 320ms 이하).
/// 기기 설정 "애니메이션 줄이기"(MediaQuery.disableAnimations)면 움직이지 않는다.
/// 새 패키지 없이 Flutter 기본 애니메이션만 쓴다.
abstract final class PdaMotion {
  /// 누름·색 바뀜.
  static const fast = Duration(milliseconds: 140);

  /// 칸·글자 바뀜.
  static const base = Duration(milliseconds: 220);

  /// 화면·완료 표시 등장.
  static const slow = Duration(milliseconds: 320);

  /// 들어오는 것 — 빨리 시작해 부드럽게 멈춘다.
  static const enter = Easing.emphasizedDecelerate;

  /// 나가는 것.
  static const exit = Easing.emphasizedAccelerate;

  /// 자리에서 바뀌는 것.
  static const standard = Easing.standard;

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// 줄이기 설정이면 0.
  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;
}

/// 그림자 단계(Tailwind shadow-sm·shadow-md 정도) — 흰 바탕에서 칸이 떠 보이게, 진하지 않게.
abstract final class PdaShadows {
  static const sm = [
    BoxShadow(color: Color(0x0F1F1D24), blurRadius: 3, offset: Offset(0, 1)),
  ];
  static const md = [
    BoxShadow(color: Color(0x141F1D24), blurRadius: 12, offset: Offset(0, 4)),
  ];
}

/// 촉감 — 스캔을 읽었을 때(가볍게)·일이 끝났을 때(조금 세게). 시끄러운 현장에서 소리 대신.
abstract final class PdaHaptics {
  static void scanned() => HapticFeedback.selectionClick();
  static void done() => HapticFeedback.mediumImpact();
}

/// 누르는 동안 살짝 작아진다(0.97) — 장갑을 끼고 눌러도 눌렸는지 보인다.
/// 손가락 이벤트만 엿보므로 안의 InkWell·단추 동작은 그대로다.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: widget.enabled ? (_) => _set(true) : null,
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: AnimatedScale(
      scale: _down ? 0.97 : 1,
      duration: PdaMotion.of(context, PdaMotion.fast),
      curve: PdaMotion.standard,
      child: widget.child,
    ),
  );
}

/// 처음 그려질 때 아래에서 살짝 올라오며 나타난다. [index] 로 차례(목록 칸마다 40ms 늦게, 최대 6칸까지).
/// 타이머 없이 컨트롤러 하나로 늦춘다(시험이 남은 타이머로 깨지지 않게).
class EnterFade extends StatefulWidget {
  const EnterFade({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 10,
  });

  final Widget child;
  final int index;

  /// 올라오는 거리(dp).
  final double offset;

  @override
  State<EnterFade> createState() => _EnterFadeState();
}

class _EnterFadeState extends State<EnterFade>
    with SingleTickerProviderStateMixin {
  static const _step = 40;
  AnimationController? _c;
  Animation<double>? _t;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null) return;
    final delay = _step * widget.index.clamp(0, 6);
    final run = PdaMotion.base.inMilliseconds;
    final total = delay + run;
    _c = AnimationController(
      vsync: this,
      duration: PdaMotion.of(context, Duration(milliseconds: total)),
    );
    _t = CurvedAnimation(
      parent: _c!,
      curve: Interval(delay / total, 1, curve: PdaMotion.enter),
    );
    if (PdaMotion.reduced(context)) {
      _c!.value = 1;
    } else {
      _c!.forward();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t!,
    child: widget.child,
    builder: (_, child) => Opacity(
      opacity: _t!.value,
      child: Transform.translate(
        offset: Offset(0, widget.offset * (1 - _t!.value)),
        child: child,
      ),
    ),
  );
}

/// 완료 표시 등장 — 작게 시작해 살짝 넘쳤다가 자리 잡는다(✓ 원).
class PopIn extends StatefulWidget {
  const PopIn({super.key, required this.child, this.haptic = false});

  final Widget child;

  /// 나타날 때 촉감(완료 화면).
  final bool haptic;

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null) return;
    _c = AnimationController(
      vsync: this,
      duration: PdaMotion.of(context, PdaMotion.slow),
    );
    if (PdaMotion.reduced(context)) {
      _c!.value = 1;
    } else {
      _c!.forward();
    }
    if (widget.haptic) PdaHaptics.done();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: CurvedAnimation(
      parent: _c!,
      curve: const Interval(0, 0.5, curve: Curves.easeOut),
    ),
    child: ScaleTransition(
      scale: Tween<double>(
        begin: 0.6,
        end: 1,
      ).animate(CurvedAnimation(parent: _c!, curve: Curves.easeOutBack)),
      child: widget.child,
    ),
  );
}

/// 값이 바뀌면 새 값이 아래에서(늘면) 또는 위에서(줄면) 들어온다 — 수량·숫자 칸.
/// [child] 는 값마다 다른 키를 가져야 한다(보통 `ValueKey(value)`) — 여기서 감싸 준다.
class SwapValue extends StatelessWidget {
  const SwapValue({
    super.key,
    required this.value,
    required this.child,
    this.up = true,
  });

  final Object value;
  final Widget child;

  /// 값이 늘었나(들어오는 방향).
  final bool up;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: PdaMotion.of(context, PdaMotion.base),
    switchInCurve: PdaMotion.enter,
    switchOutCurve: PdaMotion.exit,
    // 나가는 값은 바로 사라지고(겹쳐 읽히지 않게) 새 값만 움직인다.
    layoutBuilder: (current, previous) =>
        Stack(alignment: Alignment.center, children: [?current]),
    transitionBuilder: (child, a) => FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, up ? 0.35 : -0.35),
          end: Offset.zero,
        ).animate(a),
        child: child,
      ),
    ),
    child: KeyedSubtree(key: ValueKey(value), child: child),
  );
}
