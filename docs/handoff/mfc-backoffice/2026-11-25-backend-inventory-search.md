# 요청 — 재고·LOT 운영자 검색(Elasticsearch) — mfc-inventory-service

보낸 앱: mfc-backoffice (PC 3)
받는 백엔드 영역: mfc (mfc-inventory-service, 색인은 search-service 와 같은 Elasticsearch·Logstash 쪽이면 함께)
날짜: 2026-11-25
상태: 요청

## 왜
- 사용자 2026-11-25 "웹에 쓰이는 검색도 고객앱 참조해서 엘라스틱서치로 처리해줘" · "지난 LOT 도 넣어".
- 고객앱 검색(`search-service GET /search/products`, ES — 형태소·동의어·오타 교정·초성)은 판매용 상품 색인이라 결과가 상품 ID·이름뿐이고(SKU·LOT·칸·수량 없음),
  판매 중지·미취급 상품은 빠진다. 창고에 남은(또는 남았던) LOT 을 상품명으로 찾는 데는 쓸 수 없다.
- 지금 MFC 백오피스 "재고 > LOT 추적"(clients #540 계열) 첫 화면은 `GET /mfcs/{mfcId}/stock-units` 를 200줄씩 최대 20쪽 읽어 화면이 LOT 별로 묶고,
  상품명·상품 코드·LOT 번호는 **받은 목록 안에서 글자 그대로** 거른다 — 4,000줄을 넘는 센터는 다 못 보고, 오타·초성·동의어("우유"↔"밀크")를 못 찾는다.
  `stock-units` 는 수량 > 0 만이라 다 나간 LOT 은 목록에 없다.
- "재고 이력"(`stock-ledger?sku=` 필수)·"상품별 재고"(`stock?sku=`)도 상품 코드를 정확히 알아야 한다.

## 바라는 것

### R1. LOT 목록 — `GET /mfcs/{mfcId}/lots` (새 경로)
한 줄 = 그 센터에 **한 번이라도 들어온** LOT(지금 수량 0 인 지난 LOT 포함).
```json
{ "items": [ {
    "lotId": "…", "lotNo": "L261107000497", "sku": "SKU-…", "productName": "서울우유 1L",
    "expiryDate": "2026-11-28", "tracking": "TRACKED",
    "onHandQty": 14, "quarantinedQty": 2, "sellableQty": 12,
    "locationCount": 2, "firstLocationCode": "A-P1-01-1-01",
    "firstReceivedAt": "…", "lastMovedAt": "…", "temperatureZones": ["CHILLED"]
  } ],
  "nextCursor": null, "total": 1496, "asOf": "…" }
```
- 거르기(모두 선택): `q`(아래 R3), `state` = `IN_STOCK`(onHand > 0, 기본) · `DEPLETED`(지금 0 — 지난 LOT) · `ALL`, `qualityState`(그 상태 수량이 있는 LOT), `temperatureZone`, `expiryBefore`(날짜, 임박 보기).
- 정렬 `sort` = `EXPIRY`(소비기한 이른 순, 기본 — 없음은 뒤) · `RECENT`(마지막 움직임 최근 순) · `RELEVANCE`(q 가 있을 때 기본).
- 쪽 나눔 `size`(≤ 200)·`cursor`, `total`(쪽 표시용 — 어려우면 null 허용). 권한은 `stock-units` 와 같다(그 센터 운영자, 다른 센터 403).
- 지난 LOT 의 `onHandQty` 등은 0, `lastMovedAt` = 마지막 확정 시각(원장). 화면은 지난 LOT 을 누르면 지금처럼 `lot-resolutions` → `stock-ledger?lotId=` 로 지나온 길을 본다.

### R2. `stock-units` 에 `q`
- `GET /mfcs/{mfcId}/stock-units?q=` — 같은 검색(R3)으로 단위 행을 거른다(센터 재고 목록·도면 랙 칸 찾기에).

### R3. 검색어 `q` 의 뜻(고객앱 검색과 같은 분석기면 좋다)
- 한 칸으로: **상품명**(형태소·동의어·오타 교정·초성 — search-service 0.4.0·0.12.0 과 같은 규칙), **상품 코드(SKU)**, **상품 바코드**(880… 앞부분 일치), **LOT 번호**(앞부분 일치), 제조사 LOT 원문.
- 판매 중지·미취급 상품도 찾는다(운영자 화면 — 창고에 있는 것은 다 보여야 한다).
- 결과가 0건이고 교정된 검색어로 찾았으면 `correctedQuery`(고객앱과 같은 모양)로 알려 주면 화면이 "○○ 로 찾았어요"를 보인다.

### R4. (있으면 좋음) 재고 이력·상품별 재고를 상품명으로
- `stock-ledger`·`stock` 은 지금처럼 sku 필수로 두되, 화면이 R1/R2 결과에서 sku 를 골라 넘긴다 — 따로 바꿀 필요는 없다. 다만 상품 고르기용 가벼운 자동완성
  `GET /mfcs/{mfcId}/sku-suggestions?q=`(상품명·코드·바코드 → sku·productName 최대 10개, 그 센터에 들어온 적 있는 상품)가 있으면 재고 이력 찾기 칸에 쓴다.

## 화면이 할 것(받으면)
- LOT 추적 첫 화면을 R1 로 바꾼다(서버 쪽 나눔·정렬, 찾기 칸 = q, 필터에 "지난 LOT 포함"·소비기한 임박). 받은 목록 안 거르기·4,000줄 상한을 뺀다.
- 재고 이력·상품별 재고 찾기 칸에 R4 자동완성(없으면 R1 결과로 sku 고르기).
- 그동안은 지금 화면(받은 목록 안 거르기, 지금 수량 > 0 LOT 만)을 그대로 둔다.

## 답이 필요한 것
- 색인을 search-service(같은 ES 클러스터, Logstash 로 inventory 사건 색인)에 둘지, mfc-inventory 가 직접 둘지 — 화면은 경로만 맞으면 된다(경로를 search-service 쪽 `/search/mfc-lots` 등으로 바꿔도 좋다).
- 지난 LOT 을 얼마나 오래 둘지(예: 마지막 움직임 뒤 1년) — 화면 필터 문구에 쓴다.
