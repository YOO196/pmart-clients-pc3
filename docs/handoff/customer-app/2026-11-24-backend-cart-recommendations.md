# 요청 — BR-98 "회원님을 위한 추천 상품"(장바구니 막대 펼친 시트)

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform (storefront 또는 추천 담당 — 서버 판단)
- 계기: 사용자 2026-11-24 새 UI — 홈·검색·카테고리 아래 장바구니 막대의 ^ 를 누르면 시트: 위 막대(⌄) · "회원님을 위한 추천 상품" 3칸 × 2줄 · [다른 추천 상품 보기 ⟳].

## 지금
- 개인 추천 API 가 계약에 없다(storefront 는 운영자 편성 영역만, replenishment `/recommendations` 는 발주 추천).
- 앱은 지금 홈 구성(`GET /storefront/home`)의 첫 상품 진열 영역을 쓴다: 6개씩, [다른 추천 상품 보기]는 다음 6개 → 받은 것을 다 보면 `GET /storefront/sections/{id}/items?cursor=` 다음 묶음 → 끝이면 처음으로. 코드 `apps/customer_app/lib/shared/cart_recommendations.dart`(`// BR-98`).

## 요청
- R1 회원(비회원은 서버 판단) 추천 목록 — 예 `GET /storefront/recommendations?context=CART&mfcId=&cursor=&size=6`. 항목은 홈 진열과 같은 `ProductTile`(이름·사진·대표 SKU·가격·기간 할인·단위가격·평점).
- R2 장바구니에 담긴 상품은 빼거나 표시(서버 판단). [다른 추천 상품 보기]는 다음 묶음(`nextCursor`), 끝이면 처음부터.
- Q1 사용자 UI 의 카드에는 "N개 남음"(재고 적음)·"배민클럽 가격"·꼬리표(단독·신선보장·최저가 도전)가 있다 — 지금 `ProductTile` 에 없는 값이라 앱은 그리지 않는다. 필요하면 함께 정해 주세요(재고 적음 수량은 상품 상세 `availableQty` 와 같은 기준?).
