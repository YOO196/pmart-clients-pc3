# 사용자 결정 — 센터 관리자(MFC_SUPERVISOR)에게 주문 수·매출 지표를 연다 (O-11 권한)

보낸 앱: mfc-backoffice (PC 3)
받는 백엔드 영역: platform (order-service — PC 1)
날짜: 2026-11-23

## 결정
- 사용자 2026-11-23: **연다.** 센터 관리자(MFC_SUPERVISOR)가 MFC 백오피스 센터 대시보드에서 **자기 센터의** 주문 수·매출 추이를 본다.
- 백엔드 회신 `../pmart-backend/docs/handoff/clients/mfc-backoffice/2026-11-21-reply-hourly-and-order-metrics.md` §3 의 "사용자 결정이 필요한 것"에 대한 답이다. O-8(2026-11-18, OPERATOR_ADMIN 만)을 이 범위만큼 바꾼다.

## 요청 (order-service O-11 — 앞 요청서 `2026-11-21-backend-center-order-metrics.md` 그대로, 권한만 확정)
1. 시간·날짜별 계열(O-11 1번) — 센터 관리자 허용.
2. 권한 범위: MFC_SUPERVISOR 는 **토큰 센터만**(mfcId 필수·토큰 센터 검사, 다른 센터 403). OPERATOR_ADMIN 은 지금처럼 모든 센터.
3. 같은 범위로 `GET /orders/metrics/summary`·`GET /orders/metrics/top-products` 도 센터 관리자에게(그래야 "많이 팔린 상품"도 실서버 값).
4. 카테고리(O-11 3번)·요일 × 시간대(4번)는 앞 요청 그대로.

## 그대로 둘 것
- 매출 정의 = 승인 금액(환불 빼지 않음, Q-19 전) — O-8 과 같다.
- 개인정보 없음(합계·SKU 만). 고객 정보는 열지 않는다.

## 화면 쪽
- API 가 생기면 목 시뮬레이션(`features/dashboard/orderSim.ts`)을 지우고 실서버에서도 주문·매출을 기본으로 연다. 그 전에는 지금처럼 실서버 "주문 지표 API 없음".
- 조회 실패는 "조회 실패"(0·빈 그래프로 바꾸지 않음), 403 은 권한 안내.
