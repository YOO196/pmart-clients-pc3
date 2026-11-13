# [pmart-clients → pmart-backend] 홈·섹션 진열: 센터 지정 시 미취급 상품 빼기 (BR-49) (2026-11-05)

- 관련 계약: `contracts/openapi/storefront-service.yaml`
  - `GET /storefront/home?mfcId=`
  - `GET /storefront/tabs/{tabKey}?mfcId=`
  - `GET /storefront/sections/{sectionId}/items?mfcId=`
  - `DisplayItem.carried`("mfcId 지정 시 취급 여부. 불명이면 null")
- 참고: 검색은 해결됨. `2026-11-05-clients-notice-search-changes.md` §2 에 따라 색인에서 거르고, `total` 이 정확하다.
- 확인 방법: LAN 게이트웨이 `http://192.168.0.40:8080/api/v1` 에 직접 GET(인증 없음), 2026-11-05 10:00 KST 무렵.

## 1. 확인 결과

| 요청 | 결과 |
|---|---|
| `storefront/home?mfcId=MFC-SEED-01` | 섹션 `S-ALL` 10건, 모두 `carried: null` |
| `storefront/sections/S-ALL/items?mfcId=MFC-SEED-01&layoutVersion=0` | 50건, 모두 `carried: null` |
| `storefront/home?mfcId=MFC-BSN-01` (LAN 에 없는 센터) | 10건, 모두 `carried: null` — 거르지 않음 |
| 비교: `search/products?mfcId=MFC-BSN-01` | `total: 0`, `items: []` |

센터를 지정해도 진열은 취급 여부를 판정하지 않는다. 그래서 검색에서는 빠지는 상품이 홈·섹션에서는 보인다.

## 2. 요청

| # | 요청 |
|---|---|
| 1 | **`mfcId` 를 주면 홈·탭·섹션 항목에서 그 센터의 미취급 상품을 빼 달라.** 검색 기본(`includeNotCarried=false`)과 같은 결과가 되게 해 달라. 판정 기준도 검색과 같게: 대표 SKU, 취급 변경 사본 |
| 2 | 빼고 나서 섹션이 비면 섹션을 생략할지, 빈 섹션으로 줄지 계약에 적어 달라. 섹션 항목 목록의 페이지 채우기·`nextCursor` 규칙도 검색과 같게 해 달라(빈 페이지 + 다음 커서 없음) |
| 3 | 거른 뒤에는 `carried` 를 `true` 로 채워 달라. 어렵다면 "mfcId 를 주면 미취급은 오지 않는다"고 계약에 적어 달라. 지금 설명("불명이면 null")만으로는, 화면이 null 을 "취급"으로 볼 수 없다 |
| 4 | 정책 확인: 사용자(클라이언트 쪽) 결정은 **"연결된 MFC 가 취급하지 않으면 안 보인다"**. 검색·진열 모두 숨김이다. 업무 문서 Commerce 1006·3627행("구분 표시")과 다르다. 그러니 백엔드 쪽 문서·정책에 반영할지 판단해 달라 |

## 3. 고객앱 현황
- 홈·섹션 전체보기는 서버 항목을 그대로 그린다. `carried` 가 null 이면 미취급 표시를 하지 않는다. 모르는 값을 클라이언트가 판정하지 않는다.
- 검색은 `includeNotCarried` 를 보내지 않는다(기본 false = 숨김). 지금 동작을 유지한다.
- 회신·LAN 반영 뒤 고객앱은 바꿀 것이 없을 것으로 본다. 서버가 빼서 주면 그대로 그린다. #2 에서 빈 섹션 규칙이 정해지면 그에 맞춘다.
