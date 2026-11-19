# 요청(급함) — 배송 현황 화면에 필요한 서버 값: 배송 ID(BR-61)·주문한 센터 이름(BR-62)

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform (order-service — R1·R2), 참고 delivery (tracking — 라이더 위치), mfc (center-master — 센터 이름 출처)
- 계기: 사용자 2026-11-19 실기기 "라이더는 왜 지도에 안 뜨냐", "배달 주소·요청사항·주문 넣은 MFC·주문내역·총 결제금액 다 떠야지"(레퍼런스 = 배민 배송 현황 캡처)
- 고객 앱 반영: pmart-clients `42b9a5d` — 배송 현황 화면은 레퍼런스대로 다 만들었고(지도·시트·단계·배달정보·주문 상품·총 결제금액), 아래 두 값만 서버에 없어 비어 있다.

## R1(BR-61, 급함) — 고객 주문 조회에 배송 ID 를 채워 달라 → 라이더가 지도에 뜬다
- 지금: `GET /orders/{orderId}` 가 `shipments` 를 **늘 빈 배열**로 준다(`services/order-service/.../api/OrdersController.java:145` `.shipments(List.of())`).
- 그래서 고객 앱은 그 주문의 `deliveryId` 를 모르고, `GET /deliveries/{deliveryId}/eta`·`/stream` 을 부를 수 없다 → **라이더 마커·"N분 남음"이 안 뜬다**.
  - 실기기 확인: 주문 `ORD-ed68685a-6596-3856-a18f-6783c49a7a04`(배송 중) — 고객 앱이 `/eta`·`/stream` 을 한 번도 부르지 못함(2026-11-19 16:05·16:17·16:46 로그).
  - 고객이 주문으로 배송 ID 를 알 다른 경로가 없다(`GET /deliveries?orderId=` 는 OPERATOR 전용).
- 요청: `Order.shipments[]` 에 `{shipmentId, deliveryId, state, lines[]}` — 배차로 배송이 생긴 뒤부터. 분할이면 배송마다 한 줄. 배송 전에는 빈 배열이어도 된다.
- 앱: 코드 변경 없이 바로 동작(값이 오면 실시간 화면으로 바뀌고, 픽업 뒤 라이더 마커가 SSE 로 움직인다 — PC 5 실시간 위치 작업과 이어짐).
- 원 요청서: `docs/handoff/customer-app/2026-11-19-backend-order-shipments-empty.md`.

## R2(BR-62) — 주문한 센터 이름(고객에게 보일 이름)
- 레퍼런스 시트에 "B마트 부산동래"처럼 주문한 지점 이름이 있다. 지금 고객 앱은 `Order.mfcId` 만 받아 **브랜드("PMart")만** 보인다(ID 를 그대로 보이지 않는다).
- 고객용 센터 이름 경로가 없다 — center-master 센터 조회는 직원 전용, 이름은 배차·실행 직원 응답(`mfcName`)에만 있다.
- 요청: `GET /orders/{orderId}`(고객) 응답에 `mfcName`(고객에게 보여도 되는 지점 이름, 예 "PMart 부산진구점") — 또는 고객용 센터 이름 조회. 주소·좌표는 필요 없다(매장 위치 공개는 별도 정책).

## 확인(이미 서버에 있어 앱이 보이는 것 — 바뀌는 것 없음)
- 배달주소·요청사항: 주문 `shippingAddress`(사본)·`deliveryNote`
- 주문 상품: 주문 `lines[]`(상품명 사본·수량)
- 총 결제금액: 주문 `quote.totalAmount`
- 할인·포인트·배너(레퍼런스에 있음)는 1차 제외 기능이라 넣지 않았다.

## 회신 부탁
- R1 언제 반영·배포되는지(급함 — 라이더 지도 시연이 막혀 있다), `shipments` 가 채워지는 시점(배정·픽업).
- R2 넣을지와 필드 이름.
