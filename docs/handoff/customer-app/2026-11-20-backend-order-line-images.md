# 요청 — BR-71 주문 줄의 상품 사진(주문내역 카드·주문상세)

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform (order-service)
- 이어지는 것: `../pmart-backend/docs/handoff/clients/customer-app/2026-11-20-reply-br67-br68-br70.md` §BR-68(order 0.17.0 — `lines` 에 사진 없음)
- 계기: 사용자 2026-11-20 "주문상세에 담은 상품 이미지 … 레퍼런스랑 다름 (상품 이미지가 안보임)", "주문 내역에서도 상품 담을 수 있어야 함"

## 레퍼런스가 그리는 것
- 주문내역 카드(9-2 `1. 주문내역 - 배송완료 후`)·주문상세(9-1 `3-3. 주문상세 - 같은 상품 담기`): 줄마다 **상품 사진** + 이름 + 금액·수량 + 오른쪽 ⊕.

## 지금 계약
- `GET /orders` 의 `OrderSummary.lines[]`(0.17.0): `orderLineId·productId·sku·productName·optionLabel·quantity·lineAmount` — 사진 없음.
- `GET /orders/{id}` 의 `OrderLine`: `productId` 는 있고 사진 없음.

## 앱이 지금 한 것(2026-11-20, 목 모드)
- **주문상세**: 줄마다 `productId` 로 `GET /product-contents/{id}` 를 불러 **지금 상품의 대표 사진**을 쓴다(리뷰관리 BR-67 과 같은 기준). 줄 수만큼 조회가 더 나간다(상세 조회는 몇 분 붙잡아 둔다). 못 읽으면 자리 그림.
- **주문내역 카드**: 사진 없이 이름 / 금액·수량 + ⊕. 주문 여러 건 × 줄 5개를 상품 조회로 채우면 조회가 너무 많아 하지 않았다.
- ⊕(다시 담기)는 두 화면 모두 `lines[].sku`·수량으로 장바구니에 새로 담는다(서버 판정).

## 부탁
- **R1.** `OrderSummary.lines[]` 에 `imageUrl`(지금 상품의 대표 사진 `/api/v1/content-images/{id}` — review 0.5.0 `Eligibility.imageUrl` 과 같은 값·같은 규칙, 게시 안 된 상품은 null).
- **R2.** `GET /orders/{id}` 의 `OrderLine` 에도 같은 `imageUrl` — 오면 앱은 줄마다 부르는 상품 조회를 걷는다.
- 주문 당시 사본이 아니라 지금 사진이어도 된다(BR-67 결정과 같게).

## 상태
- 2026-11-20: 요청. 회신 대기. 그때까지 주문내역 카드는 사진 없이, 주문상세는 상품 조회로 그린다.
