import 'package:flutter/material.dart';
import 'package:pmart_ui/pmart_ui.dart';

/// 할인율 빨강(레퍼런스 3-2 TOP 30 카드·5-1 장바구니 "33%").
// 할인율 숫자는 레퍼런스 빨강(사용자 2026-11-26 "할인% 글자 색" — 태블릿 나란히 보기에서 잰 색 약 #D94A52).
// 전에는 팔레트 분홍 #D9457A(사용자 2026-11-23 "분홍")였다.
const discountRateColor = Color(0xFFD94A52);

/// 기간 할인 가격 줄(ADR-0082 4단계 — 서버 값만, 앱이 할인가·할인율을 계산하지 않는다):
/// `[33%] 5,990원 [8,990원(취소선)]`. 레퍼런스 카드는 취소선 정가 없이([showBase] false), 장바구니·상세는 함께.
/// [price]·[base] 는 표시할 금액 그대로(장바구니는 수량만큼 곱한 값을 넘긴다).
class DiscountPriceText extends StatelessWidget {
  const DiscountPriceText({
    super.key,
    required this.price,
    required this.style,
    this.ratePercent,
    this.base,
    this.showBase = true,
    this.prefix,
    this.rateColor = discountRateColor,
  });

  /// 할인율 색(기본 [discountRateColor]). 장바구니 추천 시트는 실측 #FF3E3E.
  final Color rateColor;

  final int price;
  final int? ratePercent;

  /// 정가(취소선). null 이면 그리지 않는다.
  final int? base;
  final bool showBase;
  final TextStyle? style;

  /// 금액 앞 글(예: 장바구니 "합계 "). 없으면 없음.
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = style?.fontSize ?? 14;
    return Text.rich(
      TextSpan(
        children: [
          if (ratePercent case final r? when r > 0)
            TextSpan(
              text: '$r% ',
              style: TextStyle(color: rateColor),
            ),
          if (prefix case final p?) TextSpan(text: p),
          TextSpan(text: formatKrw(price)),
          if (showBase)
            if (base case final b? when b > price)
              TextSpan(
                text: ' ${formatKrw(b)}',
                style: TextStyle(
                  fontSize: size * 0.82,
                  fontWeight: FontWeight.w400,
                  color: scheme.outline,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: scheme.outline,
                ),
              ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}
