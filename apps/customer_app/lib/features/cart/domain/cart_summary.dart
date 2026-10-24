import 'package:flutter/foundation.dart';

/// 홈 화면의 장바구니 요약. 생성 DTO(`Cart`)를 화면에 직접 쓰지 않는다.
@immutable
class CartSummary {
  const CartSummary({
    required this.cartId,
    required this.cartVersion,
    required this.lineCount,
    required this.selectedItemAmount,
  });

  final String cartId;
  final int cartVersion;

  /// 담은 품목 줄 수. 배지 숫자의 의미(줄 수/수량 합)는 `[결정 필요]` 라 여기서 정하지 않는다.
  final int lineCount;

  /// 서버가 준 선택 품목 표시 합계. 견적이 아니다(계약 설명). 없으면 null(0으로 바꾸지 않음).
  final int? selectedItemAmount;
}
