# 요청 — BR-83 할인 상품 목록의 필터·할인율순 정렬

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform (search-service)
- 계기: 사용자 2026-11-22 "할인 목록 백엔드에 요청해줘" — BR-82 로 카테고리 [할인] 타일이 `GET /search/products?onSale=true` 목록을 열게 됐는데, 이 목록에 필터를 둘 수 없고 할인율순 정렬이 없다.
- 이어지는 문서: BR-82 `docs/handoff/customer-app/2026-11-22-backend-category-banner-discount-list.md`, 회신 `clients/customer-app/2026-11-22-reply-br82-category-banner-discount-list.md`

## R1. `GET /search/filters` 에 `onSale`
- 지금: search 0.8.0 `GET /search/filters` 는 `q`·`categoryId`·`mfcId` 만 받는다. 할인 목록(카테고리·검색어 없음)에서 부르면 전체 상품의 속성·건수가 나와,
  고르면 0건이 되는 값까지 보인다. 그래서 앱은 할인 목록에서 필터 줄·필터 버튼을 숨겼다.
- 부탁: `GET /search/filters?onSale=true` — `searchProducts(onSale=true)` 와 같은 판정(대표 SKU 지금 기간 할인)으로 좁힌 상품의 속성·옵션 건수.
  검색어·카테고리와 같이 쓸 수 있게(검색 목록과 같은 조건).
- 앱(받으면): 할인 목록에도 필터를 둔다(`filters` 조건을 `onSale` 과 함께 보냄 — 이 조합은 0.8.0 이 이미 받는다고 회신에 있음).

## R2. 할인율순 정렬 `SortKey`
- 지금: `SortKey` 설명에 "할인율순(DISCOUNT)은 1차 제외". 할인 목록 정렬은 기본·인기·신상·가격·별점·리뷰만.
- 부탁: 할인율 높은 순 정렬(예 `DISCOUNT_RATE`). 기준은 결과의 `discountRatePercent` 와 같은 값(할인 없는 상품은 뒤로). 1차 제외 범위를 바꾸는 일이라 진행 여부는 사용자 확인 뒤에.
- 앱(받으면): 할인 목록 정렬 시트에 "할인율순" 추가(다른 목록에도 둘지는 그때 사용자에게 묻는다).

## 앱 지금 상태
- 할인 목록 `/products?onSale=true`: 모든 카테고리, 정렬만, 필터 없음. 빈 목록·503 은 빈 문구·오류(다시 시도).

## 백엔드 회신·앱 반영 (2026-11-22)
- 회신: `../pmart-backend/docs/handoff/clients/customer-app/2026-11-22-reply-br83-sale-list-filters-sort.md` (7d6d6b09). search 0.9.0 — `GET /search/filters?onSale=true`, `SortKey.DISCOUNT_RATE`(onSale=true 와 함께만, 아니면 400; 할인율 높은 순 → 할인가 낮은 순 → productId; 할인 상품 최대 1,000개).
- 앱: search 다시 생성(contracts.lock 7d6d6b09 계열). 필터 조회에 `onSale` 을 넘기고 할인 목록에 필터 줄·필터 버튼을 다시 둔다. `SortKey.discountRate`("할인율순")는 할인 목록 정렬 시트에만.
- LAN 확인: filters onSale 건수 합 = 할인 7개 기준, `onSale=true&sort=DISCOUNT_RATE` 7건·nextCursor, `sort=DISCOUNT_RATE` 만 보내면 400.
- 남은 것: 폰 확인 뒤 archive.
