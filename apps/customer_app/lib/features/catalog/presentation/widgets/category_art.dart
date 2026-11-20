import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 카테고리·배너 그림. 카테고리는 사용자가 준 그림 파일(2026-11-20)을 쓰고, 맞는 파일이 없거나 배너면 코드로 그린다(2026-11-11).
/// 카테고리 그림은 계약에 없어서 **이름에 든 낱말**로 고른다 — 맞는 낱말이 없으면 장바구니 그림.
enum CategoryArtKind {
  fruit,
  dairy,
  snack,
  seafood,
  drink,
  noodle,
  bread,
  frozen,
  grain,
  sauce,
  meal,
  living,
  beauty,
  liquor,
  basket,
}

/// 이름 → 그림 종류. 앞에 있는 규칙이 먼저다.
CategoryArtKind categoryArtFor(String name) {
  const rules = <(List<String>, CategoryArtKind)>[
    (['아이스', '냉동', '빙과'], CategoryArtKind.frozen),
    (['우유', '유제품', '치즈', '요거트', '요구르트'], CategoryArtKind.dairy),
    (['과일', '채소', '샐러드', '야채', '청과'], CategoryArtKind.fruit),
    (['라면', '면'], CategoryArtKind.noodle),
    (['과자', '간식', '초콜릿', '시리얼', '스낵', '젤리', '사탕'], CategoryArtKind.snack),
    (['정육', '수산', '계란', '고기', '생선', '해산', '축산'], CategoryArtKind.seafood),
    (['주류', '맥주', '와인', '전통주', '소주'], CategoryArtKind.liquor),
    (['음료', '커피', '생수', '주스', '차', '탄산'], CategoryArtKind.drink),
    (['빵', '떡', '잼', '베이커리'], CategoryArtKind.bread),
    (['쌀', '잡곡', '견과', '곡물'], CategoryArtKind.grain),
    (['양념', '장류', '오일', '소스', '조미'], CategoryArtKind.sauce),
    (
      [
        '밥',
        '도시락',
        '국',
        '탕',
        '찌개',
        '요리',
        '반찬',
        '분식',
        '야식',
        '밀키트',
        '통조림',
        '햄',
        '어묵',
      ],
      CategoryArtKind.meal,
    ),
    (['뷰티', '화장', '클렌징', '선케어', '헤어', '바디'], CategoryArtKind.beauty),
    (
      ['세제', '방향', '탈취', '화장지', '생리대', '생활', '리빙', '주방', '청소', '휴지'],
      CategoryArtKind.living,
    ),
  ];
  for (final (words, kind) in rules) {
    if (words.any(name.contains)) return kind;
  }
  return CategoryArtKind.basket;
}

/// 이름 → 카테고리 그림 파일(사용자 제공 그림, 2026-11-20 — 레퍼런스 카테고리 화면과 같게).
/// 앞에 있는 규칙이 먼저다. 맞는 파일이 없으면 null(코드 그림으로).
String? categoryImageFor(String name) {
  const rules = <(List<String>, String)>[
    (['아이스', '빙과'], 'icecream'),
    (['우유', '유제품', '요거트', '치즈'], 'milk'),
    (['과일', '채소', '샐러드', '야채'], 'fruitveg'),
    (['라면', '면'], 'noodle'),
    (['과자', '초콜릿', '시리얼', '스낵', '간식'], 'snack'),
    (['정육', '수산', '계란'], 'meatfish'),
    (['음료', '커피', '생수'], 'drink'),
    (['빵', '떡', '잼'], 'bread'),
    (['쌀', '잡곡', '견과'], 'grain'),
    (['양념', '장류', '오일'], 'sauce'),
    (['밥', '도시락'], 'rice'),
    (['국', '탕', '찌개'], 'soup'),
    (['요리', '반찬'], 'sidedish'),
    (['분식', '야식'], 'snackfood'),
    (['햄', '어묵', '통조림'], 'ham'),
    (['식단'], 'diet'),
    (['유기농', '친환경'], 'organic'),
    (['헤어', '바디', '쉐이빙'], 'hair'),
    (['세제', '방향', '탈취'], 'detergent'),
    (['화장지', '생리대', '휴지'], 'tissue'),
    (['뷰티', '클렌징', '선케어', '화장품'], 'beauty'),
    (['청소', '욕실'], 'cleaning'),
    (['주방', '일회용'], 'kitchen'),
    (['문구', '사무'], 'stationery'),
    (['가전', '게임', '전기'], 'digital'),
    (['반려'], 'pet'),
    (['유아', '아동'], 'baby'),
    (['의료'], 'medical'),
    (['인테리어'], 'interior'),
    (['생활', '잡화', '패션', '리빙'], 'living'),
  ];
  for (final (words, file) in rules) {
    if (words.any(name.contains)) return 'assets/images/categories/$file.png';
  }
  return null;
}

/// 둥근 네모 바탕 위의 카테고리 그림.
class CategoryArt extends StatelessWidget {
  const CategoryArt({
    super.key,
    required this.name,
    required this.size,
    this.radius,
  });

  final String name;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = BorderRadius.circular(radius ?? size / 3);
    // 그림 파일이 있으면 그것(바탕까지 그림에 들어 있다), 없으면 코드 그림.
    if (categoryImageFor(name) case final asset?) {
      return ClipRRect(
        borderRadius: r,
        child: Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          filterQuality: FilterQuality.medium,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(radius ?? size / 3),
      ),
      child: CustomPaint(painter: _CategoryPainter(categoryArtFor(name))),
    );
  }
}

Paint _f(int color) => Paint()..color = Color(color);

Paint _s(int color, double w) => Paint()
  ..color = Color(color)
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

RRect _rr(double x, double y, double w, double h, double r) =>
    RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r));

class _CategoryPainter extends CustomPainter {
  const _CategoryPainter(this.kind);

  final CategoryArtKind kind;

  @override
  void paint(Canvas c, Size size) {
    // 48x48 좌표로 그린다.
    c.scale(size.width / 48, size.height / 48);
    // 바닥 그림자
    c.drawOval(
      Rect.fromCenter(center: const Offset(24, 41.5), width: 26, height: 4),
      Paint()..color = const Color(0x14000000),
    );
    switch (kind) {
      case CategoryArtKind.fruit:
        // 잎채소(뒤) + 사과(앞)
        for (final o in const [
          Offset(31, 20),
          Offset(36, 24),
          Offset(33, 28),
        ]) {
          c.drawCircle(o, 6.5, _f(0xFF4CB56A));
        }
        c.drawCircle(const Offset(33, 22), 2.2, _f(0xFF7BD08F));
        c.drawRRect(_rr(31, 28, 5, 9, 2), _f(0xFF8FD6A0));
        c.drawCircle(const Offset(17.5, 28), 9, _f(0xFFEF4B45));
        c.drawCircle(const Offset(25, 28), 9, _f(0xFFEF4B45));
        c.drawCircle(const Offset(16, 25), 2.6, _f(0x55FFFFFF));
        c.drawLine(
          const Offset(21, 20),
          const Offset(22, 14.5),
          _s(0xFF7A4B2A, 1.6),
        );
        c.save();
        c.translate(26, 15);
        c.rotate(-0.5);
        c.drawOval(
          Rect.fromCenter(center: Offset.zero, width: 8, height: 4),
          _f(0xFF3FA85C),
        );
        c.restore();
      case CategoryArtKind.dairy:
        // 우유 팩 + 컵
        c.drawPath(
          Path()
            ..moveTo(12, 17)
            ..lineTo(20, 9)
            ..lineTo(28, 17)
            ..close(),
          _f(0xFFBBD8FF),
        );
        c.drawRRect(_rr(17, 6.5, 6, 3.5, 1), _f(0xFF8FBDF9));
        c.drawRRect(_rr(12, 17, 16, 24, 2), _f(0xFFFFFFFF));
        c.drawRRect(_rr(12, 27, 16, 14, 2), _f(0xFF4C8DF6));
        c.drawRect(const Rect.fromLTWH(12, 27, 16, 3), _f(0xFF4C8DF6));
        c.drawCircle(const Offset(20, 33.5), 3.4, _f(0xFFFFFFFF));
        c.drawRRect(_rr(12, 17, 16, 24, 2), _s(0xFFD5DEEA, 0.8));
        c.drawRRect(_rr(30, 25, 9, 16, 2.5), _f(0xDDEAF4FF));
        c.drawRRect(_rr(30, 30, 9, 11, 2.5), _f(0xFFFFFFFF));
        c.drawRRect(_rr(30, 25, 9, 16, 2.5), _s(0xFFC6D4E6, 0.8));
      case CategoryArtKind.snack:
        // 과자 봉지
        c.drawRRect(_rr(12, 9, 24, 32, 3), _f(0xFFFFC533));
        c.drawRect(const Rect.fromLTWH(12, 9, 24, 4.5), _f(0xFFF39C1F));
        c.drawRect(const Rect.fromLTWH(12, 36.5, 24, 4.5), _f(0xFFF39C1F));
        for (var x = 14.0; x < 35; x += 3) {
          c.drawLine(Offset(x, 9.6), Offset(x, 12.6), _s(0x66FFFFFF, 0.7));
          c.drawLine(Offset(x, 37.4), Offset(x, 40.4), _s(0x66FFFFFF, 0.7));
        }
        c.drawCircle(const Offset(24, 24.5), 7.5, _f(0xFFE5483B));
        c.drawOval(
          Rect.fromCenter(center: const Offset(24, 24.5), width: 9, height: 6),
          _f(0xFFFFE08A),
        );
        c.drawCircle(const Offset(17, 17), 1.6, _f(0x55FFFFFF));
      case CategoryArtKind.seafood:
        // 생선 + 달걀
        c.drawPath(
          Path()
            ..moveTo(30, 23)
            ..lineTo(40, 15)
            ..lineTo(40, 31)
            ..close(),
          _f(0xFF2F7DE1),
        );
        c.drawOval(
          Rect.fromCenter(center: const Offset(21, 23), width: 26, height: 16),
          _f(0xFF4AA3F0),
        );
        c.drawPath(
          Path()..addOval(
            Rect.fromCenter(center: const Offset(21, 26), width: 22, height: 9),
          ),
          _f(0xFFBFE2FF),
        );
        c.drawPath(
          Path()
            ..moveTo(18, 15.5)
            ..lineTo(24, 10.5)
            ..lineTo(26, 16)
            ..close(),
          _f(0xFF2F7DE1),
        );
        c.drawCircle(const Offset(14, 21), 2.2, _f(0xFFFFFFFF));
        c.drawCircle(const Offset(13.6, 21), 1.1, _f(0xFF1F1F23));
        c.drawOval(
          Rect.fromCenter(center: const Offset(33, 36), width: 9, height: 11),
          _f(0xFFFFF3DD),
        );
        c.drawOval(
          Rect.fromCenter(center: const Offset(33, 36), width: 9, height: 11),
          _s(0xFFE8D2A8, 0.7),
        );
      case CategoryArtKind.drink:
        // 생수병 + 캔
        c.drawRRect(_rr(14, 6, 8, 4, 1), _f(0xFF2F7DE1));
        c.drawRRect(_rr(15, 10, 6, 5, 1), _f(0xFFCDEBFF));
        c.drawRRect(_rr(11, 14, 14, 27, 4.5), _f(0xFFCDEBFF));
        c.drawRect(const Rect.fromLTWH(11, 23, 14, 9), _f(0xFF3C8BE8));
        c.drawRRect(_rr(13, 16, 2, 6, 1), _f(0x88FFFFFF));
        c.drawRRect(_rr(28, 21, 11, 20, 2.5), _f(0xFFE5483B));
        c.drawRRect(_rr(28, 21, 11, 3, 1.5), _f(0xFFD9DCE2));
        c.drawRRect(_rr(28, 38, 11, 3, 1.5), _f(0xFFD9DCE2));
        c.drawPath(
          Path()
            ..moveTo(28, 33)
            ..quadraticBezierTo(33.5, 27, 39, 31)
            ..lineTo(39, 33.5)
            ..quadraticBezierTo(33.5, 29.5, 28, 35.5)
            ..close(),
          _f(0xFFFFFFFF),
        );
      case CategoryArtKind.noodle:
        // 라면 그릇 + 젓가락
        c.drawLine(
          const Offset(28, 6),
          const Offset(22, 22),
          _s(0xFF9B6B3D, 1.5),
        );
        c.drawLine(
          const Offset(33, 7),
          const Offset(26, 22),
          _s(0xFF9B6B3D, 1.5),
        );
        for (var i = 0; i < 4; i++) {
          final x = 14.0 + i * 5.5;
          c.drawPath(
            Path()
              ..moveTo(x, 24)
              ..quadraticBezierTo(x + 3, 15, x + 5.5, 24),
            _s(0xFFFFC533, 2.4),
          );
        }
        c.drawCircle(const Offset(31, 21.5), 3, _f(0xFFFFFFFF));
        c.drawCircle(const Offset(31, 21.5), 1.4, _f(0xFFFFB300));
        c.drawPath(
          Path()
            ..moveTo(8, 23.5)
            ..lineTo(40, 23.5)
            ..arcToPoint(
              const Offset(8, 23.5),
              radius: const Radius.circular(16),
            )
            ..close(),
          _f(0xFFE5483B),
        );
        c.drawRRect(_rr(7, 22, 34, 3.4, 1.7), _f(0xFFC63A30));
        c.drawRRect(_rr(18, 37.5, 12, 3, 1.5), _f(0xFFC63A30));
      case CategoryArtKind.bread:
        // 식빵
        for (final o in const [
          Offset(16, 20),
          Offset(24, 18),
          Offset(32, 20),
        ]) {
          c.drawCircle(o, 7.5, _f(0xFFD98F45));
        }
        c.drawRRect(_rr(9, 20, 30, 20, 4), _f(0xFFD98F45));
        c.drawRRect(_rr(12.5, 22, 23, 15.5, 3), _f(0xFFF8DDAA));
        for (final o in const [
          Offset(17.5, 22),
          Offset(24, 21),
          Offset(30.5, 22),
        ]) {
          c.drawCircle(o, 4.6, _f(0xFFF8DDAA));
        }
        c.drawCircle(const Offset(19, 29), 1, _f(0xFFE9C48A));
        c.drawCircle(const Offset(27, 32), 1.2, _f(0xFFE9C48A));
        c.drawCircle(const Offset(30, 26), 0.9, _f(0xFFE9C48A));
      case CategoryArtKind.frozen:
        // 아이스크림
        c.drawPath(
          Path()
            ..moveTo(15.5, 25)
            ..lineTo(32.5, 25)
            ..lineTo(24, 43)
            ..close(),
          _f(0xFFE3A55A),
        );
        c.drawLine(
          const Offset(19, 28),
          const Offset(27, 36),
          _s(0xFFC98A42, 0.9),
        );
        c.drawLine(
          const Offset(29, 28),
          const Offset(21, 36),
          _s(0xFFC98A42, 0.9),
        );
        c.drawCircle(const Offset(24, 18), 10.5, _f(0xFFFF8FB1));
        c.drawRRect(_rr(13.5, 22, 21, 5, 2.5), _f(0xFFFF7AA2));
        c.drawCircle(const Offset(20, 14.5), 2.6, _f(0x66FFFFFF));
        c.drawCircle(const Offset(27, 7.5), 2.8, _f(0xFFE5483B));
        c.drawLine(
          const Offset(27, 5),
          const Offset(29.5, 2.5),
          _s(0xFF3FA85C, 1.1),
        );
      case CategoryArtKind.grain:
        // 밥그릇
        c.drawPath(
          Path()
            ..moveTo(11, 24)
            ..quadraticBezierTo(24, 6, 37, 24)
            ..close(),
          _f(0xFFFFFFFF),
        );
        c.drawPath(
          Path()
            ..moveTo(11, 24)
            ..quadraticBezierTo(24, 6, 37, 24),
          _s(0xFFDDE1E8, 0.9),
        );
        for (final o in const [
          Offset(20, 18),
          Offset(26, 15.5),
          Offset(29, 20),
          Offset(23, 21),
        ]) {
          c.drawOval(
            Rect.fromCenter(center: o, width: 2.6, height: 1.5),
            _f(0xFFE6EAF0),
          );
        }
        c.drawPath(
          Path()
            ..moveTo(8, 23.5)
            ..lineTo(40, 23.5)
            ..arcToPoint(
              const Offset(8, 23.5),
              radius: const Radius.circular(16),
            )
            ..close(),
          _f(0xFF6C8FD0),
        );
        c.drawRRect(_rr(7, 22, 34, 3.2, 1.6), _f(0xFF5578BC));
        c.drawRRect(_rr(18, 37.5, 12, 3, 1.5), _f(0xFF5578BC));
      case CategoryArtKind.sauce:
        // 소스 병 + 작은 병
        c.drawRRect(_rr(14, 6, 8, 4, 1), _f(0xFFFFC533));
        c.drawRRect(_rr(15.5, 10, 5, 6, 1), _f(0xFFD8402F));
        c.drawRRect(_rr(11, 15, 14, 26, 4), _f(0xFFD8402F));
        c.drawRRect(_rr(13, 23, 10, 10, 1.5), _f(0xFFFFFFFF));
        c.drawCircle(const Offset(18, 28), 2.4, _f(0xFFD8402F));
        c.drawRRect(_rr(29, 19, 6, 4, 1), _f(0xFF2E7D5B));
        c.drawRRect(_rr(27, 23, 10, 18, 3), _f(0xFFE8C54A));
        c.drawRRect(_rr(28.5, 28, 7, 7, 1), _f(0xFFFFF4C2));
      case CategoryArtKind.meal:
        // 냄비 + 김
        for (final x in const [18.0, 24.0, 30.0]) {
          c.drawPath(
            Path()
              ..moveTo(x, 13)
              ..quadraticBezierTo(x - 2.5, 10, x, 7.5)
              ..quadraticBezierTo(x + 2.5, 5, x, 2.5),
            _s(0xFFC9CED6, 1.3),
          );
        }
        c.drawRRect(_rr(4.5, 24, 7, 4, 2), _f(0xFFD0702A));
        c.drawRRect(_rr(36.5, 24, 7, 4, 2), _f(0xFFD0702A));
        c.drawRRect(_rr(9, 21, 30, 19, 5), _f(0xFFF28A3C));
        c.drawRRect(_rr(8, 18, 32, 5, 2.5), _f(0xFFD0702A));
        c.drawCircle(const Offset(24, 16.5), 2.4, _f(0xFF8B4A1A));
        c.drawRRect(_rr(12, 26, 2.2, 9, 1.1), _f(0x55FFFFFF));
      case CategoryArtKind.living:
        // 세제 통 + 두루마리 휴지
        c.drawRRect(_rr(14, 7, 8, 5, 1.2), _f(0xFFFFFFFF));
        c.drawRRect(_rr(14, 7, 8, 5, 1.2), _s(0xFFCBD3DD, 0.8));
        c.drawRRect(_rr(10, 12, 16, 29, 4), _f(0xFF36BFA5));
        c.drawPath(
          Path()
            ..moveTo(18, 20)
            ..quadraticBezierTo(23, 27, 18, 31)
            ..quadraticBezierTo(13, 27, 18, 20)
            ..close(),
          _f(0xFFFFFFFF),
        );
        c.drawRRect(_rr(28, 24, 12, 17, 2), _f(0xFFFFFFFF));
        c.drawRRect(_rr(28, 24, 12, 17, 2), _s(0xFFD5DAE2, 0.8));
        c.drawOval(
          Rect.fromCenter(center: const Offset(34, 24.5), width: 12, height: 5),
          _f(0xFFFFFFFF),
        );
        c.drawOval(
          Rect.fromCenter(center: const Offset(34, 24.5), width: 12, height: 5),
          _s(0xFFD5DAE2, 0.8),
        );
        c.drawOval(
          Rect.fromCenter(
            center: const Offset(34, 24.5),
            width: 4,
            height: 1.8,
          ),
          _f(0xFFC9B79A),
        );
      case CategoryArtKind.beauty:
        // 립스틱 + 크림 통
        c.drawPath(
          Path()
            ..moveTo(14, 23)
            ..lineTo(14, 13)
            ..lineTo(22, 8)
            ..lineTo(22, 23)
            ..close(),
          _f(0xFFE5487A),
        );
        c.drawRRect(_rr(12.5, 22, 11, 5, 1), _f(0xFFF2C14E));
        c.drawRRect(_rr(12, 26.5, 12, 14.5, 1.5), _f(0xFF2B2B33));
        c.drawRRect(_rr(28, 27, 13, 5, 1.5), _f(0xFFF2C14E));
        c.drawRRect(_rr(28.5, 31, 12, 10, 2), _f(0xFFFFD9E4));
        c.drawRRect(_rr(31, 34, 7, 3.5, 1), _f(0xFFFFFFFF));
      case CategoryArtKind.liquor:
        // 와인병 + 잔
        c.drawRRect(_rr(15.5, 5, 5, 3, 0.8), _f(0xFF8B2C3F));
        c.drawRRect(_rr(16, 8, 4, 10, 1), _f(0xFF2E7D5B));
        c.drawPath(
          Path()
            ..moveTo(16, 17)
            ..quadraticBezierTo(11.5, 20, 11.5, 25)
            ..lineTo(11.5, 39)
            ..quadraticBezierTo(11.5, 41, 13.5, 41)
            ..lineTo(22.5, 41)
            ..quadraticBezierTo(24.5, 41, 24.5, 39)
            ..lineTo(24.5, 25)
            ..quadraticBezierTo(24.5, 20, 20, 17)
            ..close(),
          _f(0xFF2E7D5B),
        );
        c.drawRRect(_rr(13, 27, 10, 9, 1), _f(0xFFFFF4D6));
        c.drawPath(
          Path()
            ..moveTo(29, 22)
            ..lineTo(39, 22)
            ..quadraticBezierTo(39.5, 31, 34, 31)
            ..quadraticBezierTo(28.5, 31, 29, 22)
            ..close(),
          _f(0xFFE9EEF5),
        );
        c.drawPath(
          Path()
            ..moveTo(29.3, 26)
            ..lineTo(38.7, 26)
            ..quadraticBezierTo(38.4, 31, 34, 31)
            ..quadraticBezierTo(29.6, 31, 29.3, 26)
            ..close(),
          _f(0xFF9B2743),
        );
        c.drawLine(
          const Offset(34, 31),
          const Offset(34, 39.5),
          _s(0xFFCBD3DD, 1.2),
        );
        c.drawLine(
          const Offset(30.5, 40.3),
          const Offset(37.5, 40.3),
          _s(0xFFCBD3DD, 1.4),
        );
      case CategoryArtKind.basket:
        // 장바구니
        c.drawCircle(const Offset(19, 20), 5, _f(0xFFEF4B45));
        c.drawCircle(const Offset(28, 19), 5.5, _f(0xFF4CB56A));
        c.drawRRect(_rr(31, 12, 4, 12, 2), _f(0xFFE3A55A));
        c.drawPath(
          Path()
            ..moveTo(15, 22)
            ..quadraticBezierTo(24, 4, 33, 22),
          _s(0xFF5A43C9, 1.8),
        );
        c.drawPath(
          Path()
            ..moveTo(9, 22)
            ..lineTo(39, 22)
            ..lineTo(35.5, 39)
            ..quadraticBezierTo(35, 41, 33, 41)
            ..lineTo(15, 41)
            ..quadraticBezierTo(13, 41, 12.5, 39)
            ..close(),
          _f(0xFF6A4EE0),
        );
        c.drawRRect(_rr(8, 20.5, 32, 4, 2), _f(0xFF5A43C9));
        for (final x in const [18.0, 24.0, 30.0]) {
          c.drawLine(Offset(x, 28), Offset(x, 37), _s(0x55FFFFFF, 1.4));
        }
    }
  }

  @override
  bool shouldRepaint(_CategoryPainter old) => old.kind != kind;
}

/// 홈 배너의 대체 그림: 장 본 물건이 담긴 종이봉투. 서버 배너 그림이 없을 때 오른쪽에 그린다.
class BannerArt extends StatelessWidget {
  const BannerArt({super.key});

  @override
  Widget build(BuildContext context) =>
      const CustomPaint(painter: _BannerPainter());
}

class _BannerPainter extends CustomPainter {
  const _BannerPainter();

  @override
  void paint(Canvas c, Size size) {
    // 120x110 좌표, 높이에 맞춰 오른쪽 아래에 붙인다.
    final k = size.height / 110;
    c.translate(size.width - 120 * k, 0);
    c.scale(k);
    c.drawCircle(const Offset(66, 62), 50, _f(0x40FFFFFF));
    c.drawOval(
      Rect.fromCenter(center: const Offset(64, 101), width: 76, height: 8),
      Paint()..color = const Color(0x1F000000),
    );
    // 바게트
    c.save();
    c.translate(84, 34);
    c.rotate(0.38);
    c.drawRRect(_rr(-7, -30, 14, 54, 7), _f(0xFFE3A55A));
    for (var y = -20.0; y < 14; y += 10) {
      c.drawLine(Offset(-3.5, y), Offset(3.5, y + 4), _s(0xFFC98A42, 1.6));
    }
    c.restore();
    // 잎채소
    for (final o in const [
      Offset(40, 30),
      Offset(50, 22),
      Offset(58, 32),
      Offset(47, 36),
    ]) {
      c.drawCircle(o, 11, _f(0xFF4CB56A));
    }
    c.drawCircle(const Offset(49, 25), 4, _f(0xFF7BD08F));
    // 당근
    c.drawPath(
      Path()
        ..moveTo(66, 20)
        ..lineTo(76, 22)
        ..lineTo(70, 48)
        ..close(),
      _f(0xFFF28A3C),
    );
    c.drawLine(const Offset(70, 20), const Offset(68, 12), _s(0xFF3FA85C, 2.4));
    c.drawLine(const Offset(72, 20), const Offset(76, 13), _s(0xFF3FA85C, 2.4));
    // 사과
    c.drawCircle(const Offset(33, 44), 10, _f(0xFFEF4B45));
    c.drawCircle(const Offset(30, 40), 2.8, _f(0x55FFFFFF));
    // 봉투
    c.drawPath(
      Path()
        ..moveTo(26, 46)
        ..lineTo(100, 46)
        ..lineTo(95, 98)
        ..quadraticBezierTo(94.5, 102, 90, 102)
        ..lineTo(36, 102)
        ..quadraticBezierTo(31.5, 102, 31, 98)
        ..close(),
      _f(0xFF6A4EE0),
    );
    c.drawPath(
      Path()
        ..moveTo(26, 46)
        ..lineTo(100, 46)
        ..lineTo(98.8, 58)
        ..lineTo(27.2, 58)
        ..close(),
      _f(0xFF5A43C9),
    );
    c.drawPath(
      Path()
        ..moveTo(50, 60)
        ..quadraticBezierTo(63, 82, 76, 60),
      _s(0xFFFFFFFF, 3),
    );
    c.drawCircle(const Offset(50, 60), 2.6, _f(0xFFFFFFFF));
    c.drawCircle(const Offset(76, 60), 2.6, _f(0xFFFFFFFF));
    // 반짝임
    _spark(c, const Offset(108, 24), 6, 0xFFFFC533);
    _spark(c, const Offset(18, 22), 4.5, 0xFFFFFFFF);
    _spark(c, const Offset(110, 76), 3.5, 0xFFFFFFFF);
  }

  void _spark(Canvas c, Offset o, double r, int color) {
    final p = Path();
    for (var i = 0; i < 8; i++) {
      final rr = i.isEven ? r : r * 0.36;
      final a = i * math.pi / 4 - math.pi / 2;
      final pt = Offset(o.dx + rr * math.cos(a), o.dy + rr * math.sin(a));
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    c.drawPath(p..close(), _f(color));
  }

  @override
  bool shouldRepaint(_BannerPainter old) => false;
}
