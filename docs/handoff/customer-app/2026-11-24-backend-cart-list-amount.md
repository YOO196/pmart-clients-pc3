# 요청 — BR-97 장바구니 할인 전 합계(`selectedListAmount`)

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform (cart-service `Cart`)
- 계기: 사용자 2026-11-24 "할인가 표시해" — 홈·검색·카테고리 아래 장바구니 막대에 "31,400원 ~~45,580원~~"(할인 뒤 합계 + 줄 그은 할인 전 합계).

## 지금
- cart 0.4.0 `Cart.selectedItemAmount`(기간 할인 뒤 합계)와 `selectedDiscountAmount`(기간 할인 합계)만 있다. 할인 전 합계 필드는 없다.
- 앱은 지금 두 서버 값을 **더해 보이기만** 한다(`cartListPrice`, 할인 합계 > 0 일 때만, 둘 중 하나라도 null 이면 안 그림). 결제 금액은 주문서 견적 그대로.

## 요청
- R1 `Cart.selectedListAmount`(Money, 선택 품목의 기간 할인 전 단가 합계 — `selectedItemAmount` 가 null 이면 null). 주문 초안 `Quote.baseItemAmount` 와 같은 기준.
- 생기면 앱은 더하기를 지우고 이 값을 그대로 쓴다.
