import 'package:flutter/material.dart';

// 홈 배달 요약·배달 안내 시트의 작은 채운 그림(사용자 새 UI 2026-11-24). 그림 파일 없이 직접 그린다.

/// % 한 개(흰 선) — 배지 안에 쓴다. [rect] 안을 채운다.
void _paintPercent(Canvas canvas, Rect rect, Color color) {
  final s = rect.shortestSide;
  final p = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = s * 0.13
    ..strokeCap = StrokeCap.round;
  final c = rect.center;
  final r = s * 0.13;
  canvas
    ..drawLine(
      c + Offset(s * 0.30, -s * 0.30),
      c + Offset(-s * 0.30, s * 0.30),
      p,
    )
    ..drawCircle(c + Offset(-s * 0.24, -s * 0.22), r, p..strokeWidth = s * 0.11)
    ..drawCircle(c + Offset(s * 0.24, s * 0.22), r, p);
}

/// 검은 방패 + 흰 % ("30,000원부터 배달팁 0원" 줄).
class ShieldPercentIcon extends StatelessWidget {
  const ShieldPercentIcon({super.key, this.size = 14, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size, size * 1.08),
    painter: _ShieldPainter(color ?? Theme.of(context).colorScheme.onSurface),
  );
}

class _ShieldPainter extends CustomPainter {
  _ShieldPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, 0)
      ..cubicTo(w * 0.72, h * 0.08, w * 0.88, h * 0.10, w, h * 0.12)
      ..lineTo(w, h * 0.48)
      ..cubicTo(w, h * 0.78, w * 0.74, h * 0.92, w * 0.5, h)
      ..cubicTo(w * 0.26, h * 0.92, 0, h * 0.78, 0, h * 0.48)
      ..lineTo(0, h * 0.12)
      ..cubicTo(w * 0.12, h * 0.10, w * 0.28, h * 0.08, w * 0.5, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    _paintPercent(
      canvas,
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.47),
        width: w * 0.62,
        height: w * 0.62,
      ),
      Colors.white,
    );
  }

  @override
  bool shouldRepaint(_ShieldPainter old) => old.color != color;
}

/// 보라 쿠폰(양옆 파인 홈) + 흰 % (쿠폰 줄).
class CouponFilledIcon extends StatelessWidget {
  const CouponFilledIcon({super.key, this.size = 12.6, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size * 1.15, size * 0.97),
    painter: _CouponPainter(color ?? Theme.of(context).colorScheme.primary),
  );
}

class _CouponPainter extends CustomPainter {
  _CouponPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height * 0.12),
    );
    final notch = size.height * 0.17;
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRRect(r),
      Path()
        ..addOval(
          Rect.fromCircle(center: Offset(0, size.height / 2), radius: notch),
        )
        ..addOval(
          Rect.fromCircle(
            center: Offset(size.width, size.height / 2),
            radius: notch,
          ),
        ),
    );
    canvas.drawPath(path, Paint()..color = color);
    _paintPercent(
      canvas,
      Rect.fromCenter(
        center: size.center(Offset.zero),
        width: size.height * 0.62,
        height: size.height * 0.62,
      ),
      Colors.white,
    );
  }

  @override
  bool shouldRepaint(_CouponPainter old) => old.color != color;
}

/// 알뜰배달 표(파란 동그라미 + 흰 ₩).
class BundledBadge extends StatelessWidget {
  const BundledBadge({super.key, this.size = 13.7});

  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _WonPainter());
}

class _WonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    canvas.drawCircle(
      size.center(Offset.zero),
      s / 2,
      Paint()..color = const Color(0xFF2F6BF0),
    );
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // W 모양 + 가로 두 줄(₩).
    final path = Path()
      ..moveTo(s * 0.24, s * 0.30)
      ..lineTo(s * 0.37, s * 0.72)
      ..lineTo(s * 0.50, s * 0.40)
      ..lineTo(s * 0.63, s * 0.72)
      ..lineTo(s * 0.76, s * 0.30);
    canvas
      ..drawPath(path, p)
      ..drawLine(Offset(s * 0.22, s * 0.47), Offset(s * 0.78, s * 0.47), p)
      ..drawLine(Offset(s * 0.25, s * 0.58), Offset(s * 0.75, s * 0.58), p);
  }

  @override
  bool shouldRepaint(_WonPainter old) => false;
}

/// 한집배달 표(민트 집 + 위 화살표 지붕).
class SingleBadge extends StatelessWidget {
  const SingleBadge({super.key, this.size = 13.7});

  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _HousePainter());
}

class _HousePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()..color = const Color(0xFF16C2B4);
    // 지붕(위 화살표).
    final roof = Path()
      ..moveTo(s * 0.5, 0)
      ..lineTo(s, s * 0.48)
      ..lineTo(s * 0.78, s * 0.48)
      ..lineTo(s * 0.78, s)
      ..lineTo(s * 0.60, s)
      ..lineTo(s * 0.60, s * 0.62)
      ..lineTo(s * 0.40, s * 0.62)
      ..lineTo(s * 0.40, s)
      ..lineTo(s * 0.22, s)
      ..lineTo(s * 0.22, s * 0.48)
      ..lineTo(0, s * 0.48)
      ..close();
    canvas.drawPath(roof, paint);
  }

  @override
  bool shouldRepaint(_HousePainter old) => false;
}
