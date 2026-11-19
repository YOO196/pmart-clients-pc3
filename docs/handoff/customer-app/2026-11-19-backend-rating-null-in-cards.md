# 요청 — BR-63 홈 진열·상품 상세 응답의 평점이 비어 옴(평점 집계는 480개)

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform (storefront·product-content)
- 계기: 사용자 2026-11-19 "홈화면에 무농약 햇양파가 리뷰가 480개인데 안 보여"

## 확인(LAN, 2026-11-19 17:40 무렵, 상품 `PRD-20dfc645-58c1-4ee8-a50b-371669e6272a` 무농약 햇양파 1kg)
| 응답 | 평점·리뷰 수 |
|---|---|
| `GET /product-contents/{id}/rating-summary` | 4.1 · **480** |
| `GET /products/{id}/reviews` 의 `summary` | 4.1 · **480** |
| `GET /product-contents/{id}?mfcId=` 의 `rating` | **null** |
| `GET /storefront/home?mfcId=MFC-SEED-01` 항목의 `rating`·`reviewCount` | **null·null** |

- 고객 앱 홈·목록 카드는 진열 항목의 `rating`·`reviewCount` 를, 상세는 상세 응답 `rating` 을 보인다 → 리뷰 480개가 "평점 정보 없음"으로 보였다.
- 집계(rating-summary)는 채워지는데 진열·상세 응답의 사본에는 전달되지 않는 것으로 보인다(리뷰 시드를 사건 없이 넣었거나, storefront·상세 투영이 집계를 구독하지 않음).

## 요청
- R1. 상세 응답 `ProductContent.rating` 과 진열 항목 `rating`·`reviewCount` 를 평점 집계와 같은 값으로 채워 달라(기존 리뷰도 — 다시 채우기).
- R2. 원인이 시드 방식이면 LAN 데이터도 맞춰 달라.

## 앱이 한 것
- 상세: 평점 집계 API(`rating-summary`)를 먼저 쓴다(백엔드 안내대로) — 상세는 이제 4.1·480 이 보인다.
- 홈·목록 카드: 카드마다 API 를 부르지 않는다(수십 번 호출) — R1 반영 뒤 그대로 보인다.
