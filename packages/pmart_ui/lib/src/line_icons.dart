import 'package:flutter/material.dart';

/// 고객 앱의 얇은 선 아이콘. 기본 Material 아이콘은 굵고 채워져 있어 레퍼런스(얇은 선)와 인상이 다르다.
/// 아이콘 패키지를 더하지 않고 24x24 좌표로 직접 그린다.
enum PmartLineIcons {
  home,
  search,
  cart,
  bell,
  grid,
  user,
  chevronDown,
  chevronUp,
  chevronRight,
  back,
  plus,
  minus,

  /// 사진 올리기(고객앱 리뷰 쓰기).
  camera,
}

class PmartLineIcon extends StatelessWidget {
  const PmartLineIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.strokeWidth = 1.8,
  });

  final PmartLineIcons icon;

  /// 없으면 둘러싼 [IconTheme] 을 따른다(하단 탭·앱바에서 그대로 쓸 수 있다).
  final double? size;
  final Color? color;

  /// 24 좌표 기준 선 굵기.
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    return SizedBox.square(
      dimension: s,
      child: CustomPaint(
        painter: _LinePainter(
          icon,
          color ?? theme.color ?? Theme.of(context).colorScheme.onSurface,
          strokeWidth,
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  const _LinePainter(this.icon, this.color, this.strokeWidth);

  final PmartLineIcons icon;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    switch (icon) {
      case PmartLineIcons.home:
        canvas.drawPath(
          Path()
            ..moveTo(4, 10.4)
            ..lineTo(12, 3.8)
            ..lineTo(20, 10.4)
            ..lineTo(20, 20)
            ..lineTo(4, 20)
            ..close(),
          line,
        );
        canvas.drawPath(
          Path()
            ..moveTo(12, 20)
            ..lineTo(12, 15),
          line,
        );
      case PmartLineIcons.search:
        canvas.drawCircle(const Offset(10.8, 10.8), 6.8, line);
        canvas.drawLine(const Offset(15.8, 15.8), const Offset(20, 20), line);
      case PmartLineIcons.cart:
        canvas.drawPath(
          Path()
            ..moveTo(2.8, 4.2)
            ..lineTo(5.4, 4.2)
            ..lineTo(7.4, 15.4)
            ..lineTo(18.4, 15.4)
            ..lineTo(20.4, 7.4)
            ..lineTo(6, 7.4),
          line,
        );
        canvas.drawCircle(const Offset(9, 19.4), 1.3, fill);
        canvas.drawCircle(const Offset(17, 19.4), 1.3, fill);
      case PmartLineIcons.bell:
        canvas.drawPath(
          Path()
            ..moveTo(6, 16.2)
            ..lineTo(6, 10.8)
            ..arcToPoint(
              const Offset(18, 10.8),
              radius: const Radius.circular(6),
            )
            ..lineTo(18, 16.2)
            ..lineTo(19.6, 18)
            ..lineTo(4.4, 18)
            ..close(),
          line,
        );
        canvas.drawPath(
          Path()
            ..moveTo(10.2, 20.6)
            ..arcToPoint(
              const Offset(13.8, 20.6),
              radius: const Radius.circular(1.9),
              clockwise: false,
            ),
          line,
        );
      case PmartLineIcons.grid:
        for (final o in const [
          Offset(4, 4),
          Offset(13.2, 4),
          Offset(4, 13.2),
          Offset(13.2, 13.2),
        ]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              o & const Size(6.8, 6.8),
              const Radius.circular(1.4),
            ),
            line,
          );
        }
      case PmartLineIcons.user:
        canvas.drawCircle(const Offset(12, 12), 8.6, line);
        canvas.drawCircle(const Offset(12, 10), 2.7, line);
        canvas.drawPath(
          Path()
            ..moveTo(6.9, 18.6)
            ..arcToPoint(
              const Offset(17.1, 18.6),
              radius: const Radius.circular(5.6),
            ),
          line,
        );
      case PmartLineIcons.chevronDown:
        canvas.drawPath(
          Path()
            ..moveTo(6.5, 9.5)
            ..lineTo(12, 15)
            ..lineTo(17.5, 9.5),
          line,
        );
      case PmartLineIcons.chevronUp:
        canvas.drawPath(
          Path()
            ..moveTo(6.5, 14.5)
            ..lineTo(12, 9)
            ..lineTo(17.5, 14.5),
          line,
        );
      case PmartLineIcons.chevronRight:
        canvas.drawPath(
          Path()
            ..moveTo(9.5, 6.5)
            ..lineTo(15, 12)
            ..lineTo(9.5, 17.5),
          line,
        );
      case PmartLineIcons.back:
        canvas.drawPath(
          Path()
            ..moveTo(11, 5)
            ..lineTo(4, 12)
            ..lineTo(11, 19)
            ..moveTo(4.4, 12)
            ..lineTo(20, 12),
          line,
        );
      case PmartLineIcons.plus:
        canvas.drawLine(const Offset(12, 5), const Offset(12, 19), line);
        canvas.drawLine(const Offset(5, 12), const Offset(19, 12), line);
      case PmartLineIcons.minus:
        canvas.drawLine(const Offset(5, 12), const Offset(19, 12), line);
      case PmartLineIcons.camera:
        canvas.drawPath(
          Path()
            ..moveTo(3.4, 8.6)
            ..arcToPoint(
              const Offset(5.4, 6.6),
              radius: const Radius.circular(2),
            )
            ..lineTo(8, 6.6)
            ..lineTo(9.6, 4.4)
            ..lineTo(14.4, 4.4)
            ..lineTo(16, 6.6)
            ..lineTo(18.6, 6.6)
            ..arcToPoint(
              const Offset(20.6, 8.6),
              radius: const Radius.circular(2),
            )
            ..lineTo(20.6, 17.6)
            ..arcToPoint(
              const Offset(18.6, 19.6),
              radius: const Radius.circular(2),
            )
            ..lineTo(5.4, 19.6)
            ..arcToPoint(
              const Offset(3.4, 17.6),
              radius: const Radius.circular(2),
            )
            ..close(),
          line,
        );
        canvas.drawCircle(const Offset(12, 12.8), 3.6, line);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.icon != icon || old.color != color || old.strokeWidth != strokeWidth;
}
