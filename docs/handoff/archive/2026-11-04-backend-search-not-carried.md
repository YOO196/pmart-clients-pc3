# [pmart-clients → pmart-backend] 상품 검색: 센터 지정 시 전 상품 미취급·total 불일치·빈 페이지 (BR-47) (2026-11-04)

- 관련: `contracts/openapi/search-service.yaml` `GET /search/products`(`mfcId`·`includeNotCarried` 기본 false·`SearchResult.total`·`page`), `services/search-service/.../ProductSearch.java`(`enrich`), 재고 서비스 취급 여부 조회(`AvailabilityClient.carried`). 읽은 백엔드 HEAD `b409385`.
- 증상(고객앱, LAN): 검색하면 "1개"라고 나오는데 목록은 "검색 결과가 없어요".
- 확인 방법: LAN 게이트웨이 `http://192.168.0.40:8080/api/v1` 에 직접 GET(인증 없음, 2026-11-04 16:45 KST 무렵).

## 1. 확인 결과

| 요청 | total | items | page |
|---|---|---|---|
| `q=탄산수` | 1 | 1 (초정탄산수 250ml, `carried: null`) | `nextCursor: null` |
| `q=탄산수&mfcId=MFC-BSN-01` | 1 | **0** | `size: 0` |
| `q=제주누보&mfcId=MFC-BSN-01` | 2 | **0** | `nextCursor: null` |
| `q=제주누보&mfcId=MFC-BSN-01&includeNotCarried=true` | 2 | 2 (둘 다 `carried: false`) | — |
| `mfcId=MFC-BSN-01` (검색어 없음) | 162 | **0** | `size: 0`, **`nextCursor: "bzo1MA"`** |
| (센터 지정 없음, 검색어 없음) | 162 | 50 | `nextCursor: "bzo1MA"` |

`MFC-SEED-01` 도 같은 결과. 고객앱이 실제로 보내는 `mfcId` 는 주소의 담당 센터 값(`addressBook.context.mfcId`)이며, 위 두 값으로 재현했다.

## 2. 요청

| # | 문제 | 요청 |
|---|---|---|
| 1 | **센터의 전 상품이 미취급(`carried: false`)** — 검색어 없이 162건 중 첫 페이지 50건이 전부 false. 홈 카드(`storefront/home?mfcId=`)는 `carried` 가 비어 있음(null) | LAN 데이터에서 이 센터들(`MFC-BSN-01`·`MFC-SEED-01`)의 취급 등록이 실제로 없는 것인지, 재고 서비스 판정이 잘못된 것인지 확인. 시드 상품을 고객앱에서 볼 수 있는 센터 기준 데이터가 필요 |
| 2 | **`total` 이 뺀 상품을 포함** — 미취급을 페이지에서 빼지만 `total` 은 빼기 전 색인 건수(`ProductSearch` 주석대로). 화면은 "1개"와 빈 목록을 함께 보이게 된다 | `includeNotCarried=false` 로 뺀다면 `total` 도 뺀 뒤 기준으로 맞추거나, 맞출 수 없으면 계약에 "total 은 미취급 포함 색인 건수"라고 적고 표시용 건수를 따로 달라(또는 total 을 생략) |
| 3 | **빈 페이지 + 다음 커서** — 페이지 안의 미취급을 사후에 빼서 `items: []` 인데 `nextCursor` 가 있다. 클라이언트는 "0건"과 "이 페이지는 비었지만 더 있음"을 구분할 수 없다 | 서버가 뺀 만큼 다음 문서로 채워 페이지를 구성하거나(색인 질의 단계에서 거르기), 계약에 "items 가 비어도 nextCursor 가 있으면 계속 조회"를 명시해 달라 |
| 4 | **정책 확인** — 업무 문서 Commerce §3627 "검색 0건, 검색 서버 오류, 판매중지, 품절, 미취급 PPC를 각각 다르게 표시한다" | 기본 검색에서 미취급을 **숨기는 것**(현 `includeNotCarried=false`)이 정책인지, 보이되 "취급하지 않음"으로 구분하는 것인지 확정해 달라. 숨기는 쪽이면 고객앱은 지금 동작(서버 결과 그대로) 유지 |

참고: `SearchController` 의 `includeNotCarried == null || includeNotCarried` 는 생성 인터페이스가 `defaultValue = "false"` 를 넣어 null 이 오지 않으므로 실제 기본값은 계약대로 false 다(동작 문제 아님, 읽는 사람이 헷갈릴 수 있음).

## 3. 고객앱 현황
- 검색은 `mfcId` 만 붙이고 `includeNotCarried` 는 보내지 않는다(계약 기본 false = 숨김).
- 건수 칸은 서버 `total` 을 그대로 "N개"로, 목록이 비면 "검색 결과가 없어요"를 보인다. 회신(#2·#3·#4) 전에는 바꾸지 않는다.
- 회신 뒤: #3 이 "계속 조회"로 정해지면 빈 페이지에서 다음 묶음을 이어 받도록, #4 가 "구분 표시"면 `includeNotCarried=true` + 카드에 미취급 표시(문구는 이미 있음)로 바꾼다.
