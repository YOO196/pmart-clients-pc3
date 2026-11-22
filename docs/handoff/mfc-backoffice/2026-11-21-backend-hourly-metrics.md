# MFC 백오피스 대시보드 추이 — 시간대별(1시간 칸) 지표를 읽을 API 가 없음

보낸 앱: mfc-backoffice (PC 3)
받는 백엔드 영역: mfc (mfc-fulfillment) · delivery (delivery-dispatch)
날짜: 2026-11-21
상태(2026-11-21 저녁): 피킹 지표는 회신·반영 끝(mfc-fulfillment 0.34.0 `bucket`, 회신 `../pmart-backend/docs/handoff/clients/mfc-backoffice/2026-11-21-reply-hourly-and-order-metrics.md` §1) — 정시 배송 시간 칸만 남음(delivery-dispatch DD-6, PC 5).

## 상황
- 사용자 요청(2026-11-21): 센터 대시보드 추이 그래프를 "시간대별 기록 1일·7일·한 달·년 단위" 로 자세히 보고 싶다.
- 지금 계약은 날짜(일) 단위뿐이다.
  - mfc-fulfillment `GET /metrics/picking-lines` — from·to 날짜, 최대 92일, 날짜별 pickedLines·shortLines.
  - delivery-dispatch `GET /metrics/on-time-deliveries` — from·to 날짜, 최대 31일, 날짜별 due·onTime·late.
- 화면이 한 일
  - 일·주·월 칸: 서버 날짜 합계를 더해 그린다(1년 = 피킹 92일씩·정시 배송 31일씩 나눠 읽기). 실서버에서도 된다.
  - 시간 칸: **목 모드에서만** 그날 서버 합계를 하루 수요 곡선으로 나눠 그린다(시뮬레이션). 실서버에서는 "시간" 단추를 끄고 "시간대별 지표 API 없음"을 보인다.

## 요청
1. 두 지표에 시간 칸 선택을 더하기 — 예: `bucket=HOUR|DAY`(기본 DAY).
   - HOUR 일 때 줄 키는 `hour`(Asia/Seoul 기준 시작 시각, 예 `2026-11-21T14:00:00+09:00`). 0건 시간은 줄 없음(날짜와 같은 규칙).
   - 기간 상한은 HOUR 7일이면 충분(7 × 24 = 168칸).
   - 피킹은 "피킹 시작 시각", 정시 배송은 "약속 시간대 끝" 기준처럼 시간에 넣는 기준 시각을 알려 주세요.
2. (있으면 좋음) 1년 보기에서 여러 번 나눠 읽지 않도록 `bucket=WEEK|MONTH` 또는 상한 366일.

## 화면 쪽 약속
- 서버가 준 칸 값만 그린다. 시간 칸 API 가 생기면 목 시뮬레이션을 지우고 실서버에서도 "시간" 단추를 켠다.
- 조회 실패는 "조회 실패"(0·빈 그래프로 바꾸지 않음), 칸 값이 없는 비율은 "—".
