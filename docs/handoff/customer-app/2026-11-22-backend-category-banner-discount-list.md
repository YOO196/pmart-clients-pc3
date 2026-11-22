# 요청 — BR-82 카테고리 화면 배너 자리(CATEGORY)·할인 상품 목록

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform (storefront-service · search-service)
- 계기: 사용자 2026-11-22 — 카테고리 화면을 레퍼런스(3-3)처럼: 맨 위 배너, 아래 "추천" 타일(할인·기획전·인기·신상)·고객센터 상자. "7, 8 다 추가하고싶어", 할인 타일은 "백엔드 요청 + 지금은 쿠폰함".

## R1. 카테고리 화면 배너 — `Banner.placement` 에 CATEGORY
- 지금: `GET /storefront/banners?placement=` 의 query enum 에는 `CATEGORY` 가 있는데(HOME_TOP·HOME_MIDDLE·CATEGORY·POPUP·SPLASH),
  배너 본문 `Banner.placement`(편성 초안·발행) enum 은 `HOME_TOP·HOME_MIDDLE·POPUP·SPLASH·HOME_INLINE` 뿐이라 백오피스가 CATEGORY 배너를 만들 수 없다.
- 부탁: 편성 `Banner.placement` 에 `CATEGORY` 를 넣어 `GET /storefront/banners?placement=CATEGORY` 로 나오게. 홈 `banners` 에는 섞지 않기(POPUP·SPLASH 처럼).
  LAN 에 시험용 CATEGORY 배너 1~2장도 부탁.
- 앱(2026-11-22 반영): 카테고리 화면 맨 위에서 `placement=CATEGORY` 로 읽어, 있으면 홈과 같은 넘기는 배너(링크 SECTION·PRODUCT·CATEGORY), 비거나 실패하면 자리를 비운다.

## R2. 할인 상품 목록
- 지금: 검색 결과에 기간 할인(`salePrice`·`discountRatePercent`, search 0.6.0)은 실리지만, 할인 중인 상품만 모으는 조건·정렬이 없다(`SortKey` DISCOUNT 는 1차 제외).
- 부탁: 할인 중인 상품만 보는 방법 하나 — 예 `GET /search/products?onSale=true`(대표 SKU 기간 할인 있음만, 정렬은 기존 SortKey) 또는 할인율순 정렬. 형식은 백엔드가 정해 계약에.
- 앱: 카테고리 "추천"의 [할인] 타일이 지금은 쿠폰함(`/me/coupons`)으로 간다. 생기면 할인 상품 목록으로 바꾼다.

## 참고(요청 아님)
- [기획전] = 홈의 지금 기간 안 첫 MD 탭(없으면 홈), [인기] = 홈 RANKING 탭, [신상] = 홈 NEW 탭 — 기존 계약으로 됨.
- 고객센터 상자: 전화번호·운영시간이 업무 문서·계약에 없어 넣지 않고 앱 고객센터(`/support`)로 보낸다. 번호·시간을 보일 거면 값의 출처를 정해야 한다(지금은 요청 안 함).

## 백엔드 회신·앱 반영 (2026-11-22)
- 회신: `../pmart-backend/docs/handoff/clients/customer-app/2026-11-22-reply-br82-category-banner-discount-list.md` (main 41497f1e). storefront 0.11.0(CATEGORY 자리), search 0.8.0(`onSale`).
- 앱: storefront·search 다시 생성(contracts.lock 41497f1e). `ProductQuery.onSale` 을 더해 `searchProducts(onSale: true)` 로 보낸다. 카테고리 [할인] 타일 → `/products?onSale=true&title=할인 상품`(모든 카테고리, 정렬만 — `/search/filters` 가 onSale 을 받지 않아 필터는 두지 않음). 비면 "지금 할인 중인 상품이 없어요", 503 은 오류·다시 시도.
- LAN 확인: `onSale=true` total 7(모두 salePrice 있음), `placement=CATEGORY` 배너 B-CAT-VEG·B-CAT-MEAT(linkType CATEGORY → 카테고리 상품 목록).
- 남은 것: 폰에서 화면 확인 뒤 archive.
