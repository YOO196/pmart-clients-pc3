import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../orders/presentation/tracking_map.dart' show RiderArt;

/// 주문 완료 축하 움직임(사용자 지시 2026-11-25 "체크 아이콘이라도 애니메이션 넣어서 신나게").
///
/// 한 번만 돈다(약 2.4초) — 끝없이 도는 움직임은 두지 않는다. 기기에서 움직임 줄이기가 켜져 있으면 바로 끝 모습.
/// 화면은 서버가 결제·주문을 확정한 뒤에만 열리므로 축하는 확정된 결과에만 붙는다.
class OrderDoneMotion extends StatefulWidget {
  const OrderDoneMotion({super.key, required this.builder});

  /// [t] 는 0→1 전체 진행. 각 조각은 [Interval] 로 자기 구간만 쓴다.
  final Widget Function(BuildContext context, double t) builder;

  @override
  State<OrderDoneMotion> createState() => _OrderDoneMotionState();
}

class _OrderDoneMotionState extends State<OrderDoneMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else if (!_c.isAnimating && _c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => widget.builder(context, _c.value),
  );
}

double _seg(double t, double a, double b, [Curve curve = Curves.linear]) =>
    curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

/// 체크 배지: 보라 원이 통통 튀며 커지고 → 흰 체크가 그려지고 → 둘레로 색종이가 터진다 + 퍼지는 고리.
class DoneCheckBadge extends StatelessWidget {
  const DoneCheckBadge({super.key, required this.t, this.size = 88});

  final double t;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size * 2.2,
      child: CustomPaint(
        painter: _BadgePainter(
          t: t,
          radius: size / 2,
          color: scheme.primary,
          soft: scheme.primaryContainer,
          confetti: [
            scheme.primary,
            const Color(0xFFB9A7F5),
            const Color(0xFFFF7EA8),
            const Color(0xFFFFC94D),
            const Color(0xFF5ED3B4),
          ],
        ),
      ),
    );
  }
}

class _BadgePainter extends CustomPainter {
  _BadgePainter({
    required this.t,
    required this.radius,
    required this.color,
    required this.soft,
    required this.confetti,
  });

  final double t;
  final double radius;
  final Color color;
  final Color soft;
  final List<Color> confetti;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    // 1) 퍼지는 고리(원이 다 커질 즈음)
    final ring = _seg(t, 0.18, 0.62, Curves.easeOut);
    if (ring > 0 && ring < 1) {
      canvas.drawCircle(
        c,
        radius * (1 + ring * 0.9),
        Paint()
          ..color = soft.withValues(alpha: (1 - ring) * 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10 * (1 - ring) + 1,
      );
    }
    // 2) 색종이(원 둘레에서 밖으로, 돌며 사라짐)
    final burst = _seg(t, 0.22, 0.85, Curves.easeOutCubic);
    if (burst > 0 && burst < 1) {
      const n = 16;
      for (var i = 0; i < n; i++) {
        final angle = (i / n) * math.pi * 2 + (i.isEven ? 0.12 : -0.08);
        final far = radius * (1.05 + (i % 3 == 0 ? 1.15 : 0.85) * burst);
        final p = c + Offset(math.cos(angle), math.sin(angle)) * far;
        final fade = (1 - _seg(t, 0.6, 0.85)).clamp(0.0, 1.0);
        final paint = Paint()
          ..color = confetti[i % confetti.length].withValues(alpha: fade);
        canvas
          ..save()
          ..translate(p.dx, p.dy)
          ..rotate(angle + burst * math.pi * (i.isEven ? 2 : -2));
        if (i % 3 == 1) {
          canvas.drawCircle(Offset.zero, 3.2, paint);
        } else {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(-5, -2, 10, 4),
              const Radius.circular(2),
            ),
            paint,
          );
        }
        canvas.restore();
      }
    }
    // 3) 원(통통 튀며 커짐)
    final grow = _seg(t, 0.0, 0.32, Curves.elasticOut);
    if (grow > 0) {
      canvas.drawCircle(c, radius * grow, Paint()..color = color);
    }
    // 4) 흰 체크(그려짐)
    final draw = _seg(t, 0.2, 0.42, Curves.easeOut);
    if (draw > 0) {
      final s = radius * grow.clamp(0.0, 1.2);
      final path = Path()
        ..moveTo(c.dx - s * 0.42, c.dy + s * 0.02)
        ..lineTo(c.dx - s * 0.1, c.dy + s * 0.32)
        ..lineTo(c.dx + s * 0.44, c.dy - s * 0.28);
      final metric = path.computeMetrics().first;
      canvas.drawPath(
        metric.extractPath(0, metric.length * draw),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * 0.16
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_BadgePainter old) => old.t != t || old.color != color;
}

/// 글이 아래에서 살짝 올라오며 나타난다([a]~[b] 구간).
class DoneRise extends StatelessWidget {
  const DoneRise({
    super.key,
    required this.t,
    required this.a,
    required this.b,
    required this.child,
  });

  final double t;
  final double a;
  final double b;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final v = _seg(t, a, b, Curves.easeOutCubic);
    return Opacity(
      opacity: v,
      child: Transform.translate(offset: Offset(0, (1 - v) * 16), child: child),
    );
  }
}

/// 라이더가 왼쪽에서 달려 들어와 살짝 튕기며 서고, 몸을 두 번 들썩인다(출발 준비).
class DoneRiderDriveIn extends StatelessWidget {
  const DoneRiderDriveIn({super.key, required this.t, required this.width});

  final double t;
  final double width;

  @override
  Widget build(BuildContext context) {
    final run = _seg(t, 0.25, 0.7, Curves.easeOutBack);
    final screen = MediaQuery.sizeOf(context).width;
    final dx = (1 - run) * -(screen / 2 + width);
    // 멈춘 뒤 두 번 들썩(위로 3dp)
    final hop = _seg(t, 0.7, 1.0);
    final dy = -3 * math.sin(hop * math.pi * 2).abs() * (1 - hop);
    // 달려올 때 앞으로 살짝 기울었다가 서면서 바로
    final tilt = (1 - _seg(t, 0.55, 0.75, Curves.easeOut)) * -0.06;
    return Transform.translate(
      offset: Offset(dx, dy),
      child: Transform.rotate(
        angle: tilt,
        alignment: Alignment.bottomCenter,
        child: RiderArt(key: const ValueKey('pay-done-art'), width: width),
      ),
    );
  }
}
