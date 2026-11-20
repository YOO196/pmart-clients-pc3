import 'dart:math' as math;

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

  /// 현재 위치로 찾기(고객앱 주소 검색, 레퍼런스 2-4 — 원 + 네 방향 눈금).
  locate,

  /// 배달 오토바이(고객앱 배송 현황 — 라이더 마커·지금 단계).
  scooter,

  /// 상담(고객앱 배송 현황 "문의하기").
  headset,

  /// 닫기 X.
  close,

  /// 체크 ✓.
  check,

  /// 원 안 체크(완료).
  checkCircle,

  /// 위치 핀(주소).
  pin,

  /// 설정 톱니.
  settings,

  /// 원 안 i(안내).
  info,

  /// 원 안 !(오류·주의).
  alert,

  /// 휴지통(삭제).
  trash,

  /// 다시(↻).
  refresh,

  /// 정렬(⇅).
  sort,

  /// 필터(가로 막대 + 손잡이).
  filter,

  /// 영수증(주문).
  receipt,

  /// 연필(편집).
  pencil,

  /// 원 안 X(지우기).
  clearCircle,
  clock,

  /// 찜(하트 — 선). 찜한 상태는 [heartFilled].
  heart,

  /// 찜한 하트(채움).
  heartFilled,
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
      case PmartLineIcons.heart:
      case PmartLineIcons.heartFilled:
        final heart = Path()
          ..moveTo(12, 20)
          ..cubicTo(5.2, 15.4, 3, 12.2, 3, 8.9)
          ..cubicTo(3, 6.2, 5.1, 4.2, 7.6, 4.2)
          ..cubicTo(9.4, 4.2, 11, 5.1, 12, 6.6)
          ..cubicTo(13, 5.1, 14.6, 4.2, 16.4, 4.2)
          ..cubicTo(18.9, 4.2, 21, 6.2, 21, 8.9)
          ..cubicTo(21, 12.2, 18.8, 15.4, 12, 20)
          ..close();
        if (icon == PmartLineIcons.heartFilled) canvas.drawPath(heart, fill);
        canvas.drawPath(heart, line);
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
      case PmartLineIcons.locate:
        canvas.drawCircle(const Offset(12, 12), 8, line);
        canvas.drawLine(const Offset(12, 2.6), const Offset(12, 7), line);
        canvas.drawLine(const Offset(12, 17), const Offset(12, 21.4), line);
        canvas.drawLine(const Offset(2.6, 12), const Offset(7, 12), line);
        canvas.drawLine(const Offset(17, 12), const Offset(21.4, 12), line);
      case PmartLineIcons.scooter:
        // 바퀴 둘
        canvas.drawCircle(const Offset(5.8, 17.6), 2.4, line);
        canvas.drawCircle(const Offset(18.4, 17.6), 2.4, line);
        // 발판·앞 기둥·손잡이
        canvas.drawPath(
          Path()
            ..moveTo(8.2, 17.6)
            ..lineTo(13.6, 17.6)
            ..quadraticBezierTo(15.4, 17.6, 15.8, 15.2)
            ..lineTo(17.2, 7.6)
            ..moveTo(15.6, 7.2)
            ..lineTo(19.2, 7.2)
            ..moveTo(17.2, 7.6)
            ..lineTo(18.4, 15.2),
          line,
        );
        // 안장과 뒷몸통
        canvas.drawPath(
          Path()
            ..moveTo(4.2, 12.6)
            ..lineTo(10.6, 12.6)
            ..lineTo(12.4, 17.6),
          line,
        );
        // 짐 상자(안장 위 작게)
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(4.6, 7.4, 4.8, 3.8),
            const Radius.circular(0.8),
          ),
          line,
        );
      case PmartLineIcons.headset:
        canvas.drawPath(
          Path()
            ..moveTo(4.4, 14)
            ..lineTo(4.4, 12)
            ..arcToPoint(
              const Offset(19.6, 12),
              radius: const Radius.circular(7.6),
            )
            ..lineTo(19.6, 14),
          line,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3.4, 13, 3.6, 5.6),
            const Radius.circular(1.4),
          ),
          line,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(17, 13, 3.6, 5.6),
            const Radius.circular(1.4),
          ),
          line,
        );
        canvas.drawPath(
          Path()
            ..moveTo(18.8, 18.6)
            ..quadraticBezierTo(18.8, 20.8, 14, 20.8),
          line,
        );
      case PmartLineIcons.close:
        canvas.drawLine(const Offset(6, 6), const Offset(18, 18), line);
        canvas.drawLine(const Offset(18, 6), const Offset(6, 18), line);
      case PmartLineIcons.check:
        canvas.drawPath(
          Path()
            ..moveTo(5, 12.5)
            ..lineTo(10, 17.5)
            ..lineTo(19, 7),
          line,
        );
      case PmartLineIcons.checkCircle:
        canvas.drawCircle(const Offset(12, 12), 9, line);
        canvas.drawPath(
          Path()
            ..moveTo(7.8, 12.3)
            ..lineTo(10.8, 15.2)
            ..lineTo(16.4, 9.2),
          line,
        );
      case PmartLineIcons.pin:
        canvas.drawPath(
          Path()
            ..moveTo(12, 21)
            ..cubicTo(12, 21, 5, 14.6, 5, 9.8)
            ..arcToPoint(
              const Offset(19, 9.8),
              radius: const Radius.circular(7),
            )
            ..cubicTo(19, 14.6, 12, 21, 12, 21)
            ..close(),
          line,
        );
        canvas.drawCircle(const Offset(12, 9.8), 2.4, line);
      case PmartLineIcons.settings:
        canvas.drawCircle(const Offset(12, 12), 3, line);
        for (var i = 0; i < 8; i++) {
          final a = i * 3.14159265 / 4;
          final c = Offset(12 + 7.2 * _cos(a), 12 + 7.2 * _sin(a));
          final d = Offset(12 + 9.2 * _cos(a), 12 + 9.2 * _sin(a));
          canvas.drawLine(c, d, line);
        }
        canvas.drawCircle(const Offset(12, 12), 6.8, line);
      case PmartLineIcons.info:
        canvas.drawCircle(const Offset(12, 12), 9, line);
        canvas.drawLine(const Offset(12, 11), const Offset(12, 16.6), line);
        canvas.drawCircle(const Offset(12, 7.8), 1.1, fill);
      case PmartLineIcons.alert:
        canvas.drawCircle(const Offset(12, 12), 9, line);
        canvas.drawLine(const Offset(12, 7.2), const Offset(12, 13), line);
        canvas.drawCircle(const Offset(12, 16.4), 1.1, fill);
      case PmartLineIcons.trash:
        canvas.drawLine(const Offset(4.5, 6.6), const Offset(19.5, 6.6), line);
        canvas.drawPath(
          Path()
            ..moveTo(9.4, 6.6)
            ..lineTo(9.4, 4.4)
            ..lineTo(14.6, 4.4)
            ..lineTo(14.6, 6.6),
          line,
        );
        canvas.drawPath(
          Path()
            ..moveTo(6.4, 6.6)
            ..lineTo(7.4, 19.6)
            ..lineTo(16.6, 19.6)
            ..lineTo(17.6, 6.6),
          line,
        );
      case PmartLineIcons.refresh:
        canvas.drawArc(
          Rect.fromCircle(center: const Offset(12, 12), radius: 7.4),
          -1.2,
          5.2,
          false,
          line,
        );
        canvas.drawPath(
          Path()
            ..moveTo(15.4, 3.6)
            ..lineTo(15.6, 6.2)
            ..lineTo(13, 6.6),
          line,
        );
      case PmartLineIcons.sort:
        canvas.drawPath(
          Path()
            ..moveTo(8, 19)
            ..lineTo(8, 5)
            ..moveTo(4.6, 8.4)
            ..lineTo(8, 5)
            ..lineTo(11.4, 8.4),
          line,
        );
        canvas.drawPath(
          Path()
            ..moveTo(16, 5)
            ..lineTo(16, 19)
            ..moveTo(12.6, 15.6)
            ..lineTo(16, 19)
            ..lineTo(19.4, 15.6),
          line,
        );
      case PmartLineIcons.filter:
        canvas.drawLine(const Offset(4, 7), const Offset(20, 7), line);
        canvas.drawLine(const Offset(4, 17), const Offset(20, 17), line);
        canvas.drawCircle(const Offset(9, 7), 2.2, line);
        canvas.drawCircle(const Offset(15, 17), 2.2, line);
      case PmartLineIcons.receipt:
        canvas.drawPath(
          Path()
            ..moveTo(6, 3.6)
            ..lineTo(18, 3.6)
            ..lineTo(18, 20.4)
            ..lineTo(15.6, 18.8)
            ..lineTo(13.2, 20.4)
            ..lineTo(10.8, 18.8)
            ..lineTo(8.4, 20.4)
            ..lineTo(6, 18.8)
            ..close(),
          line,
        );
        canvas.drawLine(const Offset(9, 8.6), const Offset(15, 8.6), line);
        canvas.drawLine(const Offset(9, 12.4), const Offset(15, 12.4), line);
      case PmartLineIcons.pencil:
        canvas.drawPath(
          Path()
            ..moveTo(4.6, 19.4)
            ..lineTo(5.4, 15.4)
            ..lineTo(15.8, 5)
            ..lineTo(19, 8.2)
            ..lineTo(8.6, 18.6)
            ..close(),
          line,
        );
        canvas.drawLine(
          const Offset(13.6, 7.2),
          const Offset(16.8, 10.4),
          line,
        );
      case PmartLineIcons.clearCircle:
        canvas.drawCircle(const Offset(12, 12), 9, fill);
        final white = Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          const Offset(8.8, 8.8),
          const Offset(15.2, 15.2),
          white,
        );
        canvas.drawLine(
          const Offset(15.2, 8.8),
          const Offset(8.8, 15.2),
          white,
        );
      case PmartLineIcons.clock:
        canvas.drawCircle(const Offset(12, 12), 8.6, line);
        canvas.drawLine(const Offset(12, 7.4), const Offset(12, 12), line);
        canvas.drawLine(const Offset(12, 12), const Offset(15.2, 13.8), line);
    }
  }

  static double _cos(double a) => math.cos(a);
  static double _sin(double a) => math.sin(a);

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.icon != icon || old.color != color || old.strokeWidth != strokeWidth;
}
