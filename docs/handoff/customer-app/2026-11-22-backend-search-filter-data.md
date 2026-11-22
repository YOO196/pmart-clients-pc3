# 요청 — BR-81 검색·카테고리 필터 데이터가 LAN 에 없음(승인 속성·필터 패널)

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform (search-service · product-service)
- 계기: 사용자 2026-11-22 "상품검색쪽에 필터가 안들어간것같은데 아니면 그냥 카테고리쪽 필터도" → "응 요청해줘"

## 지금
- 고객앱은 검색 결과·카테고리 상품 목록에 필터를 이미 그린다(레퍼런스 3-4 "중량 200g 이하 …" 줄 + [필터] 창).
  - 속성은 `GET /search/filters?q=&categoryId=&mfcId=` 의 `attributes`(FilterAttribute key·label·multiSelect·values)로 받고,
    고르면 `GET /search/products … filters=attributeKey.value` 로 다시 찾는다.
  - 받은 속성이 없으면 줄을 숨긴다(계약대로). 그래서 폰에서는 "필터가 없다"로 보인다.
- LAN(`https://192.168.0.40:8443/api/v1`) 2026-11-22 11:12 KST 조회 결과 — **전부 비어 있음**:
  - `GET /search/filters`(조건 없음)·`?q=우유`·`?categoryId=p02-c01-l01|p02-c01|p02` → `"attributes": []`
  - `GET /categories/p02-c01-l01|p02-c01|p02/filters` → `"groups": []`(version 11)

## 부탁
- **R1. 검색 필터 속성 데이터**: LAN 상품에 승인 속성(용량·중량·개당 수량 등)을 넣고 검색 색인에 실어, `GET /search/filters` 가 검색어·카테고리별로 속성을 돌려주게 해 달라. 적어도 우유(용량)·라면(중량/개수) 같은 몇 카테고리면 된다.
- **R2. 카테고리 필터 패널**: `GET /categories/{id}/filters` 의 `groups` 도 LAN 에 게시해 달라(백오피스 정의 패널).
- **Q1. 어느 쪽이 정본?** 고객앱 카테고리 상품 목록은 지금 `GET /search/filters?categoryId=` 를 쓴다. 카테고리 화면은 `/categories/{id}/filters`(그룹·선택 방식·화면 순서)를 써야 하는지, 두 응답이 같은 속성을 가리키는지 알려 달라. 그쪽을 써야 하면 앱을 바꾼다.
- **Q2.** 가격대(`minPrice`·`maxPrice`)는 계약에 있다. 필터 창에 가격대를 넣을 때 구간(예 1만원 이하)을 서버가 주는지, 앱이 정해도 되는지.

## 앱이 할 일
- R1·R2 는 데이터만 들어오면 앱 변경 없이 보인다. Q1 답에 따라 카테고리 목록의 필터 출처를 바꿀 수 있다.

## 회신(PC1 백엔드, 2026-11-22 세션 메시지)
- Q1: 앱은 지금처럼 `GET /search/filters?categoryId=` 를 쓴다(바꿀 것 없음). 이 응답은 product-service 필터 패널(그룹 이름·선택 방식·옵션 순서)을 그 카테고리 + 조상까지 합쳐(5분 사본) 색인 집계 건수를 붙인 것이고, 상품 없는 옵션은 빠진다. `/categories/{id}/filters` 는 패널 정의 원본(건수 없음·조상 안 합침) — 백오피스·참고용. 두 응답의 그룹·옵션 이름은 같다(색인 filters = "그룹.옵션").
- Q2: 계약에 가격 구간은 없다 — 앱이 정한 구간으로 `minPrice`·`maxPrice` 를 보내면 된다.
- R1·R2: LAN 카테고리 트리(v11)에 필터 패널이 하나도 없고 상품 `filterOptions` 도 비어 둘 다 []. 넣으려면 카테고리 트리 새 버전(패널 포함)·상품 속성 수정 → PRODUCT 승인 → 색인 자동 반영. LAN 데이터 변경이라 백엔드가 사용자에게 범위(몇 카테고리)를 먼저 묻는다. 끝나면 다시 알림.

## LAN 반영(PC1 백엔드 회신 `clients/customer-app/2026-11-22-reply-br81-search-filter-data.md`, 2026-11-22 12:19)
- 카테고리 트리 v12(필터 그룹 282)·상품 463개 속성(내용량·입수·보관·상품명 낱말 근거). search 0.7.0: `/search/filters` 이름을 모든 패널에서 찾고 같은 이름 그룹은 한 줄(key `n:<그룹 이름>`), 새 원산지 줄(key `origin`, 국내산·수입산).
- 영양 정보(열량·당류)는 검색·필터에 넣지 않음(사용자 결정) — 패널의 "열량"·"저칼로리" 줄은 안 나온다.
- 앱 확인(PC 1, 12:23): `GET /search/filters?q=라면` → 중량·개당 중량 등 속성, `GET /search/products?q=라면&filters=n:중량.500g ~ 1kg` → 10건. 앱 토큰 형식(`<key>.<value>`) 그대로 맞음. search 다시 생성(contracts.lock 74ae1158). 남은 것: 폰에서 화면 확인 → archive.
