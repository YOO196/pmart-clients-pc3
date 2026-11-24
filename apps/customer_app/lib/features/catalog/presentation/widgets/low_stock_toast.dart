import 'package:flutter/material.dart';

import '../../../../l10n/gen/app_localizations.dart';
import '../../domain/catalog.dart';

/// 상품페이지 "품절까지 N개 남았어요." — 남은 수(BR-100 R7, 서버 10개 이하)를 옵션들로 모은다.
/// 넉넉한(AVAILABLE) 옵션이 있으면 없음 — 진열 카드 `lowStockQty` 와 같은 기준(storefront 0.18.0).
int? lowStockLeft(ProductDetail p) {
  if (p.options.any((o) => o.availability == Availability.available)) {
    return null;
  }
  final lows = [
    for (final o in p.options)
      if (o.availability == Availability.low) ?o.lowStockQty,
  ];
  if (lows.isEmpty) return null;
  return lows.fold<int>(0, (a, b) => a + b);
}

/// 레퍼런스 7-2(사용자 2026-11-25): 아래 막대 바로 위 가운데 검은 알약(183×38dp, #191A1C) —
/// 상자 그림(12.6×14.5) · 9 · "품절까지 N개 남았어요."(Pretendard 굵게 13.8, 흰색). 좌 19·우 17.
class LowStockToast extends StatelessWidget {
  const LowStockToast({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    height: 38,
    padding: const EdgeInsets.fromLTRB(19, 0, 17, 0),
    decoration: BoxDecoration(
      color: const Color(0xFF191A1C),
      borderRadius: BorderRadius.circular(19),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CustomPaint(size: Size(12.6, 14.5), painter: _BoxPainter()),
        const SizedBox(width: 9.1),
        Text(
          AppLocalizations.of(context).productLowStockToast(count),
          style: const TextStyle(
            fontSize: 13.8,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    ),
  );
}

/// 흰 상자(레퍼런스 아이콘): 왼쪽·오른쪽 면 + 윗면 두 날개, 사이는 바탕색 틈.
class _BoxPainter extends CustomPainter {
  const _BoxPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // 레퍼런스 화소(33×38) 기준 좌표를 크기에 맞춘다.
    final sx = size.width / 33;
    final sy = size.height / 38;
    Offset o(double x, double y) => Offset(x * sx, y * sy);
    final paint = Paint()..color = Colors.white;
    Path poly(List<Offset> pts) => Path()..addPolygon(pts, true);
    // 왼쪽 면·오른쪽 면(가운데 세로 틈 약 2.5).
    canvas.drawPath(
      poly([o(0, 11), o(15.2, 19.5), o(15.2, 38), o(0, 29.5)]),
      paint,
    );
    canvas.drawPath(
      poly([o(17.8, 19.5), o(33, 11), o(33, 29.5), o(17.8, 38)]),
      paint,
    );
    // 윗면 두 날개(왼쪽 위 → 오른쪽 아래로 긴 띠, 사이 틈).
    canvas.drawPath(
      poly([o(1.5, 8.4), o(8.6, 4.4), o(23.4, 12.8), o(16.5, 16.8)]),
      paint,
    );
    canvas.drawPath(
      poly([o(11.2, 3), o(16.5, 0), o(31.5, 8.4), o(26, 11.4)]),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
