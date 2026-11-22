# MFC 백오피스 대시보드 — 센터 관리자가 볼 주문 수·매출 추이(시간·날짜, 카테고리·상품별) API 가 없음

보낸 앱: mfc-backoffice (PC 3)
받는 백엔드 영역: platform (order-service) — 카테고리는 상품 원천(product/catalog) 확인 필요
날짜: 2026-11-21
상태(2026-11-23): 회신·반영 끝 — order-service 0.20.0 O-11(회신 `../pmart-backend/docs/handoff/clients/mfc-backoffice/2026-11-23-reply-order-metrics-supervisor.md`), 화면 `features/dashboard/orderQueries.ts`. 남은 것: LAN 확인 뒤 archive.

## 상황
- 사용자 요청(2026-11-21): 대시보드 추이 그래프를 **주문량**으로(매출이 좋은 시기·시간대를 알려고), **카테고리별**·**상품별 매출 추이**를 따로 보고 싶다.
- 지금 계약(order-service 0.13.0)
  - `GET /orders/metrics/summary` — 기간 **합계 하나**(상태별 주문 수·승인 금액). **OPERATOR_ADMIN 만**(센터 관리자 MFC_SUPERVISOR 403).
  - `GET /orders/metrics/top-products` — 기간 SKU별 수량·금액 상위 N. 같은 권한. 카테고리 없음.
  - 날짜·시간별로 나눈 값이 없어 그래프를 그릴 수 없다.
- 화면이 한 일: **목 모드에서만** 시뮬레이션(주문 수·매출, 카테고리·상품 거르기, 요일 × 시간대 열지도, 많이 팔린 상품). 실서버는 "센터 주문·매출 지표 API 없음"을 보이고 피킹 줄을 기본으로 연다.

## 요청
1. **시간·날짜별 주문 지표** — 예: `GET /orders/metrics/series?mfcId=&from=&to=&bucket=HOUR|DAY&categoryId=&sku=`
   - 줄: `{ bucket(시작 시각, Asia/Seoul), orderCount, approvedAmount, qty? }`. 0건 칸은 줄 없음.
   - 기준 시각은 summary 와 같은 주문 확정 시각(confirmedAt). HOUR 는 7일, DAY 는 93일(또는 366일)까지.
   - categoryId 를 주면 그 카테고리 상품이 든 주문 수·그 카테고리 줄 금액, sku 를 주면 그 상품 판매 수량·금액.
2. **권한**: 센터 관리자(MFC_SUPERVISOR)는 **토큰 센터만**(mfcId 필수·검사). 지금 summary·top-products 에도 같은 범위를 열어 주면 "많이 팔린 상품"을 실서버로 바꿀 수 있다.
3. **카테고리**: top-products 줄에 `categoryId`·`categoryName`(주문 때 스냅샷)을 더하고, 카테고리 목록을 읽을 곳을 알려 주세요.
4. (있으면 좋음) 요일 × 시간대 평균을 서버가 주면(`bucket=WEEKDAY_HOUR`) 1년 열지도도 한 번에 읽는다.

## 확인할 정의
- 매출 = 승인 금액(환불 빼지 않음, Q-19 확정 전) — 화면은 "주문 확정 기준 승인 금액"으로 적는다. 순매출이 정해지면 알려 주세요.

## 화면 쪽 약속
- 서버 값만 그린다. API 가 생기면 시뮬레이션을 지우고 실서버에서도 주문·매출을 기본으로 연다.
- 조회 실패는 "조회 실패"(0·빈 그래프로 바꾸지 않음). 개인정보 없음.
