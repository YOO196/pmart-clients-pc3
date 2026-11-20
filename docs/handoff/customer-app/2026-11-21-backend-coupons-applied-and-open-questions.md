# 알림·요청 — 쿠폰·할인가·AI 상담 상품 답 고객 앱 반영(목 모드) + 회신 기다리는 것 4가지

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform (쿠폰·할인·주문), rag (AI 상담 — 1-3 만)
- 답하는 것:
  - `../pmart-backend/docs/handoff/clients/customer-app/2026-11-21-request-coupons-discounts.md`(ADR-0082, 1~7번)
  - `../pmart-backend/docs/handoff/clients/all/2026-11-20-notice-rag-product-info.md`(customer-assistant 0.3.0)
- 상태: 앱은 **목 모드로 확인**했다(flutter analyze No issues, flutter test 674 통과). **LAN 실기기 확인은 아직** — 확인 뒤 다시 알린다.
- 앱 커밋: `a03ce469`(쿠폰·AI 상담), `30f40b2b`(할인가).
- 계약: promotion 0.2.0(새로 생성 — 고객 경로 3개), order 0.18.0, customer-assistant 0.3.0, cart 0.4.0, pricing 0.3.0, search 0.6.0, storefront 0.8.0.

## 1. 반영한 것

### 1-1. 쿠폰(요청 1~6번)
- **쿠폰함**(마이 → 쿠폰함, 회원만): 쿠폰 받기 `GET /coupon-campaigns`·`POST …/downloads`(Idempotency-Key, 결과 불명이면 같은 키로 한 번 더) / 사용 가능 `GET /me/coupons?status=AVAILABLE` / 지난 쿠폰(`status` 없이 받아 AVAILABLE 을 뺌).
  - 422 `COUPON_LIMIT_REACHED`·`COUPON_SOLD_OUT`·`NOT_ACTIVE`(·`UNSUPPORTED_ACTION`)는 code 로만 나눠 안내. 받은 뒤 행사 목록·쿠폰함을 다시 읽는다(받은 수·남은 수량은 서버 값만). `remaining` null 은 무제한(0·마감 아님).
- **주문서 쿠폰 고르기**: 결제수단 아래 "할인쿠폰 / N개 보유". 고르거나 빼면 **새 purchaseIntentId 로** `POST /order-drafts`(`couponId`)를 다시 보낸다(주문서는 그대로 두고 새 초안으로 바뀜). 새 "주문하기"는 지난 쿠폰을 비운다.
  - 할인은 견적 `couponDiscount`·`coupon.name` 그대로("N원 할인 적용됨"). 앱이 계산하지 않는다.
  - `coupon.applicable=false` → `reason` 문구(빨강) + [쿠폰 빼기]. 차단 사유 `COUPON_NOT_APPLICABLE` → 결제 버튼 문구 "쿠폰을 쓸 수 없어요" + 배너 [쿠폰 빼기].
  - 결제 진입 422 `COUPON_NOT_APPLICABLE` → 안내 + [쿠폰 빼기]. `RE_QUOTE_REQUIRED` 는 원래대로 전후 금액 재동의.
- **금액 줄**(주문서·주문상세): 상품금액 = `baseItemAmount`(없으면 `itemAmount`), "상품할인 −`promotionDiscount`", 쿠폰 이름(주문상세는 이름이 없어 "쿠폰 할인") −`couponDiscount`. 0 이면 줄 없음.
- 하지 않은 것: 주문상세 품목별 `discountShare` 표시(금액 줄만), 환불 화면은 서버 값 그대로라 변경 없음.

### 1-2. 할인가(요청 7번)
- 카드(검색 0.6.0·진열 0.8.0): "33% 3,990원"(빨간 할인율 + 할인가 — 레퍼런스 카드처럼 정가 취소선 없음). `salePrice` null 이면 정가만.
- 상세(pricing 0.3.0): 할인이 product-content 에 없어서 **옵션 SKU 모두** `GET /prices?skus=` 로 묻는다(전에는 가격이 빈 옵션만). `discount` 가 있으면 "33% 3,990원 ~~5,980원~~", `discountAvailable=false`·조회 실패면 정가만(오류 아님).
- 장바구니(cart 0.4.0): 줄 "33% 할인가×수량 ~~정가×수량~~", 상품금액은 서버 `selectedItemAmount`(할인 뒤), 회원 결제금액에 "상품할인(반영됨) −`selectedDiscountAmount`".
- 할인가가 정가 이상으로 오면 할인 없음으로 본다. 100g당 가격은 서버 값(정가 기준) 그대로.

### 1-3. AI 상담 상품 답(rag 알림)
- `state=PRODUCT_INFO`·`answerMode=PRODUCT_TEMPLATE` 를 받는다(전에는 모르는 state 를 계약 위반으로 막아 상담이 실패로 보였을 것). 답 문장 그대로(줄바꿈 그대로), 근거는 원래 고객에게 보이지 않는다.

## 2. 회신 부탁(4가지)
- **R1. BR-71 주문 줄의 상품 사진**(요청서 `docs/handoff/customer-app/2026-11-20-backend-order-line-images.md`) — 아직 회신·계약 변경이 없다. `GET /orders` `lines[]`·`GET /orders/{id}` `OrderLine` 에 `imageUrl`(BR-67 과 같은 규칙) 넣을 수 있는지, 언제쯤인지.
- **Q1. 찜 한도 `details` 읽는 법**(`2026-11-20-backend-wishlist-applied.md` Q1) — 422 `WISHLIST_LIMIT_EXCEEDED` 의 `details` 를 `field = "limit"`, `reason = "200"` 으로 읽었다. 맞는지.
- **Q2. BR-64 기존 계정 안내 `details` 읽는 법**(`2026-11-20-backend-handoff-replies-applied.md` Q1) — `field` = 이름(`provider`·`joinedAt`·`emailMasked`·`rejoinAvailableAt`), `reason` = 값으로 읽었다. 맞는지.
- **Q3. 탈퇴 대기 중 주문 거절 문구**(`2026-11-20-backend-br67-68-70-withdrawal-applied.md` Q1) — 대기 중 새 주문은 422 `ACCOUNT_NOT_PURCHASABLE` 로 오고, 앱은 이 code 의 일반 문구("지금은 이 계정으로 주문할 수 없어요. 고객센터로 문의해 주세요")를 쓴다. 탈퇴 대기라는 걸 따로 알릴 code·detail 이 있으면 알려 달라(없으면 지금대로).

## 3. 알려 주면 좋은 것(급하지 않음)
- LAN 의 `require-identity`(BR-64 가입 휴대폰 확인 강제)·`unlink-after-exchange`(BR-74 네이버 로그인마다 연결 끊기) 스위치가 지금 켜져 있는지. 앱은 둘 다 서버 단계 그대로 따라가서 고칠 것은 없다 — 실기기 확인 순서를 정하려는 것.
