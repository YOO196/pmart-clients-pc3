# [pmart-clients → pmart-backend] 고객앱 우선 범위와 필요한 서버 기능 (2026-10-30)

- 기준: pmart-backend `main` `2f507dc`, LAN 게이트웨이 `http://192.168.0.40:8080`(PC4 `D603-16`, health `UP`)
- 클라이언트 상태: 고객앱(Android)은 아래 화면을 목(mock)으로 끝까지 만들어 두었다. 사용자 지시로 이제 **실제 게이트웨이로 확인**하려 한다. 지금 실서버로 끝까지 되는 것은 Google 로그인뿐이다.
- **우선 범위(사용자 지정)**: ① 고객(소셜 로그인 → 계정·주소·동의) ② 장바구니 ③ 검색 ④ 상품 상세·가격 ⑤ 주문서·결제
- 근거 확인 방법: 게이트웨이에 직접 요청(토큰 없이), 각 서비스의 `src/main/java/**/application` 구현 여부. 토큰이 필요한 경로는 401 만 확인됐고 구현 여부는 코드로 봤다.

## 1. 한눈에

| # | 영역 | 고객앱이 부르는 경로 | LAN 응답(토큰 없이) | 서버 구현 | 막히는 것 |
|---|---|---|---|---|---|
| ① | 로그인 | `POST /auth/social-logins`(GOOGLE), `GET …/{id}`, `POST /auth/tokens`, `GET /auth/sessions/current`, `POST /auth/logouts` | 401 PROVIDER_REJECTED(가짜 토큰) — 정상 | **됨**(ADR-0019) | BR-27 |
| ① | 주소·쇼핑 주소 | `GET /me/addresses`, `POST /me/addresses`, `POST /me/shopping-address-selections`, `GET /me/shopping-context` | 401 | **없음**(customer-service application 0) | 아래 2-1 |
| ① | 동의 | `POST /me/consent-changes`, `POST /auth/social-logins/{id}/completions` | 401 | 없음 / completions 는 INVALID_STATE(동의 생략) | BR-20 |
| ② | 장바구니 | `POST /carts`, `GET /carts/{cartId}`, `POST /carts/{cartId}/items`, `PATCH …/items/{itemId}`, `DELETE …/items/{itemId}`, `GET …/change-requests/{requestId}` | 401 | **없음**(cart-service application 0) | 아래 2-2 |
| ③ | 검색 | `GET /search/products`, `GET /search/suggestions`, `GET /search/filters` | **501** | **없음** | 검색 색인 원천 |
| ③ | 홈·진열 | `GET /storefront/home`, `GET /storefront/sections/{id}/items` | **501** | **없음** | 진열 데이터 |
| ④ | 카테고리 | `GET /categories/tree` | 401 | 됨(product) — **비회원 불가** | 2-3 |
| ④ | 상품 상세·카드 | `GET /product-contents/{productId}`, `GET /product-contents?productIds=` | 401 | 됨(content) — **비회원 불가** | 2-3, 데이터 없음 |
| ④ | 가격 | (상세 응답의 `options[].price` 사본) / `GET /prices/{sku}` | 401 | 됨(pricing) | 2-3 |
| ⑤ | 배송 조건·슬롯 | `GET /delivery-conditions`, `GET /slots` | 401 | **없음** | BR-13 |
| ⑤ | 주문서 | `POST /order-drafts`, `GET /order-drafts/{draftId}`, `POST /order-drafts/{draftId}/checkouts` | 401 | **없음**(order-service application 0) | BR-14, BR-21 |
| ⑤ | 결제 | 결제 진입 정보·인증 결과 전달 | — | **없음**(payment application 0) | **BR-01**(고객용 경로가 계약에 없음) |

## 2. 요청·질문

### 2-1. 고객(customer-service) — 로그인 다음 단계
- 로그인은 되지만 로그인 뒤 고객앱 첫 동작이 `GET /me/shopping-context`·`/me/addresses` 다. customer-service 가 없으면 회원도 주소를 저장하지 못해 장바구니·주문서로 못 간다.
- 요청: `/me/addresses`(목록·추가), `/me/shopping-address-selections`, `/me/shopping-context`(배송 가능 판정 포함) 구현. ADR-0019 결과의 "CustomerAuthenticated 구독 → 고객 프로필 생성"이 먼저 필요해 보인다.
- 비회원 주소(`POST/GET /guest-delivery-addresses`)는 공개 경로로 열려 있으나 구현 없음. 고객앱은 비회원이 홈에서 주소를 정하는 흐름이 있다.

### 2-2. 장바구니(cart-service)
- 요청: 계약 그대로 구현(생성·조회·추가·수량 변경·삭제·변경 결과 조회). `Cart.version`·`X-Expected-Version`·`CartChangeResponse` 4값을 고객앱이 이미 처리한다.
- 질문: **비회원 장바구니**를 어떻게 식별하나? 고객앱은 비회원도 장바구니까지 쓰는 설계인데(`docs/apps/customer-app.md`), `/carts/**` 는 공개 경로가 아니고 비회원 토큰 발급 경로도 없다. (a) 비회원도 토큰(게스트 세션)을 받는다 (b) `X-Device-Id` 로 공개 장바구니 (c) 비회원 장바구니 없음 — 셋 중 무엇인지.

### 2-3. 상품 상세·카테고리·가격 — 비회원 둘러보기 (BR-28)
- 게이트웨이 공개 경로에 storefront·search 는 있는데 **`/categories/tree`, `/product-contents/**`, `/prices/**` 는 없다**(토큰 없이 401). 홈·검색 결과에서 상품을 누르면 비회원은 상세를 볼 수 없다.
- 요청: 고객 둘러보기용 읽기 경로를 공개로 열지(계약 `security: []` + 게이트웨이 public-paths), 아니면 비회원은 상세를 못 보는 것으로 정할지 결정.
- 데이터: LAN 에 카테고리 트리·상품·가격 데이터가 아직 없다(임시 백오피스로 등록 예정). 고객앱 확인을 위해 시험 데이터(트리 1개, 상품 몇 개, 가격, MFC 취급 ON)를 넣을 수 있는지.

### 2-4. 검색·홈(search-service, storefront-service)
- 둘 다 501. 고객앱 첫 화면이 `GET /storefront/home` 이라 실서버로 앱을 켜면 첫 화면부터 오류다.
- 요청: 최소한 홈 1개 섹션(상품 카드 목록)과 `GET /search/products?q=` 를 상품·콘텐츠·가격 사본으로 채워 주는 구현. 색인 원천(ProductContentPublished·PriceVersionEffective 투영)과 순서를 알려 달라.

### 2-5. 주문서·결제(order·delivery·payment)
- 주문서 생성·조회·결제 시작, 배송 조건·슬롯이 모두 없다. 기존 요청 그대로: BR-13(배송 방식별 가능 여부·배달팁), BR-14(최소주문 부족액·장바구니 단계 판정 — 고객앱은 지금 주문서 초안의 `MIN_ORDER_AMOUNT`/`minOrderSatisfied` 로 주문서 진입을 막는다), BR-21(초안 응답 내용).
- **결제는 계약부터 비어 있다(BR-01)**: 토스 결제창 진입 정보(clientKey·orderId·amount)와 인증 결과(paymentKey) 전달 경로가 고객용 계약에 없다. 결제를 하려면 이 계약이 먼저다.

## 3. 고객앱이 지금 하는 처리(참고)
- 실서버 모드: `--dart-define=PMART_ENV=local --dart-define=PMART_API_BASE_URL=http://192.168.0.40:8080/api/v1`. 501·401 은 빈 화면·0원으로 바꾸지 않고 오류 화면으로 보인다.
- 로그인은 마이 탭에서 시작할 수 있다(홈 → 주소 경로는 customer-service 가 없어 막힌다).
- 금액·최소주문·배달팁은 서버 값만 쓴다. 서버 값이 없으면 "확인할 수 없어요"로 보인다.

## 4. 바라는 순서(클라이언트 제안)
1. customer-service 주소·쇼핑 주소(로그인 뒤 첫 화면)
2. 비회원 둘러보기 공개 경로 결정(2-3) + 시험 데이터
3. storefront 홈 1섹션 · search 상품 검색
4. cart-service(비회원 장바구니 방식 포함)
5. delivery-conditions·slots → order-drafts
6. BR-01 결제 계약 → payment
