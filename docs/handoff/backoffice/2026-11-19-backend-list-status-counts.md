# 목록 상태별 개수 요청 (백오피스 목록 맨 위 숫자 띠)

보낸 앱: backoffice (PC 2)
받는 백엔드 영역: platform (product-service·order-service·claim-service·case-service), delivery (delivery-execution-service) — 담당이 다르면 알려 달라

- 근거: 사용자 2026-11-19 "전체 UI·UX 를 관제 화면 형식으로" → 목록마다 맨 위에 상태별 개수 띠(#183). 접수 건·승인함·처리 대기는 이미 서버 개수가 있어 넣었다.
- 아래 목록은 응답에 개수가 없어 띠를 만들지 못했다. 첫 쪽(50건)을 세면 틀린 숫자가 되어 하지 않는다(조회 실패·잘림을 0·정상으로 보이지 않는 규칙).

## 요청

목록과 **같은 거르기**(상태 거르기 제외)로 상태별 개수를 돌려주는 조회. 모양은 하나로 맞추면 좋겠다.

```
GET <목록 경로>/counts?<목록과 같은 거르기>
200 { "counts": [ { "key": "<상태 값>", "count": 12, "capped": false } ], "asOf": "2026-11-19T03:00:00Z" }
```

- `capped`: 셀 수 있는 상한을 넘었으면 true(화면은 "N+"). 원천을 못 읽으면 503(화면은 "?" — 0 으로 보이지 않는다).
- 모든 상태 값을 빠짐없이(0 도) 준다 — 빠진 것을 0 으로 짐작하지 않게.

| 목록 | 서비스·경로 | 나눌 값(이미 있는 거르기) |
|---|---|---|
| 상품 조회 | product-service `GET /products` | `saleState`(SaleState) — `categoryId` 는 같이 거른다 |
| 주문 조회 | order-service `GET /orders/lookups` | `status`(OrderStatus) — 기간·센터 거르기 같이 |
| 배송 확인 | delivery-execution-service `GET /deliveries` | `state`(ExecutionState) |
| 클레임 | claim-service `GET /claims` | `state`(ClaimState), 가능하면 `type`(ClaimType)도 |
| 라이더 컴플레인 | case-service `GET /rider-complaints` | `complaintType`(RiderComplaintType) — 기간 거르기 같이 |

- 가격은 SKU 일괄 조회(`GET /prices?skus=`)라 상태 목록이 아니어서 요청하지 않는다.

## 열리면 클라이언트가 할 것

- 각 목록 맨 위에 숫자 띠(공통 `StatStrip`·`StatCard`)를 넣고, 카드를 누르면 그 상태로 거른다. 개수는 서버 값만 쓴다.

## 질문

1. 화면 하나에서 여러 서비스를 부르지 않게 bff 에 `views/list-counts?list=` 로 묶는 쪽이 낫다면 그쪽으로 해도 된다 — 어느 쪽인지 알려 달라.
2. 주문 개수에 셀 수 있는 상한이 필요하면 그 값을 알려 달라(화면 "N+").
