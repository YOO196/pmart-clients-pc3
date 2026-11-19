# 요청(급함) — BR-61 고객 주문 조회의 `shipments` 가 늘 비어 배송 현황·라이더 지도를 열 수 없음

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform (order-service), 참고 delivery (배송 ID 출처)
- 계기: 사용자 2026-11-19 "배송현황에 지도 안 보인다고. 라이더 위치도 안 보이잖아" — LAN 실기기, 주문 `ORD-ed68685a-6596-3856-a18f-6783c49a7a04`(배달 중)

## 무엇이 문제인가
- 고객 앱은 주문 상세의 `Order.shipments[].deliveryId` 로 배송 현황(`/deliveries/{deliveryId}/eta`·`/stream`)을 연다. 계약(order-service `Shipment`)에 `deliveryId`·`state` 가 있다.
- 그런데 `GET /orders/{orderId}` 는 **`shipments` 를 늘 빈 배열로 준다** — `services/order-service/.../api/OrdersController.java:145` `.shipments(List.of())`.
- 고객이 주문으로 배송 ID 를 알 다른 길이 없다(`GET /deliveries?orderId=` 는 `x-pmart-user-types: [OPERATOR]`).
- 그래서 실기기에서 주문 상세에 "배송 현황" 진입이 보이지 않고, 앱은 `/eta`·`/stream` 을 한 번도 부르지 못했다(16:05·16:17 고객 앱 로그 — 주문 상세만 4번 열림). 라이더 위치 실시간(PC 5 작업, 고객 앱 `3600d8d`)도 여기서 막힌다.
- 목에서는 주문에 `shipments` 를 넣어 두어 시험이 통과했다 — 실서버와 다름을 늦게 발견했다.

## 요청
- **R1. `GET /orders/{orderId}`(고객) 응답에 `shipments[]` 를 채워 달라** — 적어도 배차로 배송이 생긴 뒤 `{shipmentId, deliveryId, state, lines[]}`.
  - 배송이 아직 없으면(배차 전) 빈 배열이어도 된다. 앱은 그때 "배송 현황" 대신 단계만 보인다.
  - 분할 배송이면 배송마다 한 줄.
- **R2. 언제부터 채워지는지**(배정 시점·픽업 시점) 알려 달라 — 앱 문구를 맞춘다.
- (대안) R1 이 오래 걸리면 고객용 "내 주문의 배송" 조회(예: `GET /orders/{orderId}/deliveries` 또는 tracking 쪽)라도.

## 앱이 할 것
- 회신 뒤 실기기에서 주문 상세 → 배송 현황(지도 바로 뜸, 라이더 마커 실시간)을 확인한다. 앱 코드는 `shipments[].deliveryId` 가 오면 그대로 동작한다.
