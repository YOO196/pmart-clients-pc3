import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'pda_motion.dart';
import 'pda_theme.dart';

/// 화면 꾸밈 요소(사용자 2026-11-27 "PPT 처럼 글자만 — 다양한 디자인 요소·애니메이션, 부드럽고 세련되게, 보라 유지").
/// 그라데이션·아이콘 배지·성공 표시·은은한 빛. 새 패키지 없이 Flutter 기본만.
abstract final class PdaGradients {
  /// 주 보라 — 왼쪽 위 밝게 → 오른쪽 아래 깊게.
  static const primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8E6BE8), Color(0xFF5E3BB2)],
  );

  /// 홈 머리 카드 — 보라에서 남보라로.
  static const hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C5CE0), Color(0xFF5B3CB0), Color(0xFF4A3496)],
    stops: [0, 0.6, 1],
  );

  /// 업무마다 다른 결의 보라 계열(구분은 되고 튀지 않게).
  static const violet = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF9A7BF0), Color(0xFF6B45C9)],
  );
  static const indigo = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7D8BF5), Color(0xFF5059D6)],
  );
  static const orchid = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFC07CE8), Color(0xFF8E48C4)],
  );
  static const lavenderBlue = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8FA6FF), Color(0xFF6274E6)],
  );
  static const plum = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFB58CF5), Color(0xFF7A4FD0)],
  );

  static const all = [violet, indigo, orchid, lavenderBlue, plum];

  /// 그라데이션 끝색(그림자 색으로).
  static Color tail(LinearGradient g) => g.colors.last;
}

/// 계속 도는 은은한 움직임(빛 숨쉬기 등)을 켤지 — 시험(`pumpAndSettle` 이 끝나지 않는다)·애니메이션 줄이기면 끈다.
abstract final class PdaAmbient {
  static final bool _test =
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  static bool on(BuildContext context) => !_test && !PdaMotion.reduced(context);
}

/// 둥근 네모 그라데이션 배지 + 흰 그림 + 같은 색의 옅은 그림자.
class GradientBadge extends StatelessWidget {
  const GradientBadge({
    super.key,
    required this.icon,
    this.size = 44,
    this.iconSize,
    this.gradient = PdaGradients.primary,
    this.radius,
    this.circle = false,
    this.enabled = true,
  });

  final IconData icon;
  final double size;
  final double? iconSize;
  final LinearGradient gradient;
  final double? radius;
  final bool circle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final g = enabled
        ? gradient
        : const LinearGradient(colors: [Color(0xFFD9D7E0), Color(0xFFBFBCC9)]);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: g,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle
            ? null
            : BorderRadius.circular(radius ?? size * 0.32),
        boxShadow: [
          BoxShadow(
            color: PdaGradients.tail(g).withValues(alpha: 0.30),
            blurRadius: size * 0.32,
            offset: Offset(0, size * 0.12),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 위쪽 반짝임 — 평평한 색면이 아니게.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: size * 0.5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: circle
                    ? BorderRadius.vertical(top: Radius.circular(size / 2))
                    : BorderRadius.vertical(
                        top: Radius.circular(radius ?? size * 0.32),
                      ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.22),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Icon(icon, size: iconSize ?? size * 0.52, color: Colors.white),
        ],
      ),
    );
  }
}

/// 성공 표시 — 그라데이션 원이 튀어나오고 ✓ 가 그려지며 물결 두 겹이 퍼진다(한 번).
class SuccessBurst extends StatefulWidget {
  const SuccessBurst({super.key, this.size = 76, this.icon = Icons.check});

  final double size;
  final IconData icon;

  @override
  State<SuccessBurst> createState() => _SuccessBurstState();
}

class _SuccessBurstState extends State<SuccessBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    // 완료 화면의 자동 다음 작업 초 세기(1초)를 잡아먹지 않게 1초 안에
    duration: const Duration(milliseconds: 650),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (PdaMotion.reduced(context)) {
      _c.value = 1;
    } else if (!_c.isAnimating && _c.value == 0) {
      PdaHaptics.done();
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 1.9,
      height: s * 1.9,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final pop = Curves.elasticOut.transform(
            (_c.value / 0.7).clamp(0.0, 1.0),
          );
          final check = Curves.easeOutCubic.transform(
            ((_c.value - 0.25) / 0.45).clamp(0.0, 1.0),
          );
          return Stack(
            alignment: Alignment.center,
            children: [
              for (final (i, delay) in const [(0, 0.05), (1, 0.25)].indexed)
                Builder(
                  builder: (_) {
                    final t = ((_c.value - delay.$2) / 0.75).clamp(0.0, 1.0);
                    return Opacity(
                      opacity: (1 - t) * (i == 0 ? 0.35 : 0.22),
                      child: Container(
                        width: s * (1 + 0.9 * t),
                        height: s * (1 + 0.9 * t),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: PdaColors.primary,
                        ),
                      ),
                    );
                  },
                ),
              Transform.scale(
                scale: pop,
                child: Container(
                  width: s,
                  height: s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: PdaGradients.primary,
                    boxShadow: [
                      BoxShadow(
                        color: PdaColors.primary.withValues(alpha: 0.35),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: CustomPaint(
                    painter: _CheckPainter(check, widget.icon == Icons.check),
                    child: widget.icon == Icons.check
                        ? null
                        : Icon(widget.icon, color: Colors.white, size: s * 0.5),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t, this.draw);

  final double t;
  final bool draw;

  @override
  void paint(Canvas canvas, Size size) {
    if (!draw || t <= 0) return;
    final w = size.width;
    final p = Path()
      ..moveTo(w * 0.29, w * 0.52)
      ..lineTo(w * 0.44, w * 0.66)
      ..lineTo(w * 0.72, w * 0.37);
    final metric = p.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * t),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.085
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t;
}

/// 은은하게 숨 쉬는 빛 — 지금 눌러야 할 단추를 알린다(시험·줄이기 설정에선 멈춘 빛).
class BreathingGlow extends StatefulWidget {
  const BreathingGlow({
    super.key,
    required this.child,
    required this.radius,
    this.color = PdaColors.primary,
    this.active = true,
  });

  final Widget child;
  final double radius;
  final Color color;
  final bool active;

  @override
  State<BreathingGlow> createState() => _BreathingGlowState();
}

class _BreathingGlowState extends State<BreathingGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(BreathingGlow old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.active && PdaAmbient.on(context)) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = 0.5;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = Curves.easeInOut.transform(_c.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.18 + 0.17 * v),
                blurRadius: 10 + 12 * v,
                spreadRadius: 1 + 2 * v,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// 홈 머리 카드 뒤 장식 — 옅은 원 몇 개(평평한 색면이 아니게).
class BubblesPainter extends CustomPainter {
  const BubblesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.08);
    canvas
      ..drawCircle(Offset(size.width * 0.92, size.height * 0.08), 70, p)
      ..drawCircle(Offset(size.width * 0.78, size.height * 1.05), 52, p)
      ..drawCircle(
        Offset(size.width * 0.55, -10),
        28,
        p..color = Colors.white.withValues(alpha: 0.06),
      );
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.12);
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * 0.95, size.height * 0.85),
        radius: 46,
      ),
      math.pi,
      math.pi,
      false,
      ring,
    );
  }

  @override
  bool shouldRepaint(BubblesPainter old) => false;
}
