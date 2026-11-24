# 요청 — 출하 약속 준수율 지표(날짜·시간 칸) — mfc-fulfillment-service

보낸 앱: mfc-backoffice (PC 3)
받는 백엔드 영역: mfc (mfc-fulfillment-service)
날짜: 2026-11-24
상태: 요청 — 화면은 목 시뮬레이션으로 먼저(`web/mfc-backoffice/src/features/dashboard/shipSim.ts`), 실서버는 "API 없음"

## 왜
- 사용자 2026-11-24: 대시보드 추이의 "정시 배송률"은 배차·라이더 이동이 섞인 배송 결과라 센터 관리자가 움직일 수 없다 → 추이 탭에서 빼고(위 카드에만 "배송 결과"로 남김), **센터가 책임지는 몫 = 출하 약속 시각 안에 포장·인계를 끝냈나**를 추이로 보고 싶다.
- 지금 계약에는 지금 이 순간 수만 있다: `GET /shipments/promise-summary`(0.21.0 — 초과·임박·여유·없음, PICK·PACK 이 아직 끝나지 않은 것만). 지난 날짜의 비율·추이는 없다.

## 바라는 것 (picking-lines 와 같은 모양이면 좋다)
`GET /metrics/ship-promises?from=&to=&mfcId=&bucket=` — bucket `HOUR·DAY·WEEK·MONTH`(기본 DAY), 기간 상한은 picking-lines 와 같게(HOUR 7일·DAY 92일·WEEK·MONTH 366일).

```json
{ "items": [ { "date": "2026-11-24", "hour": null, "mfcId": "MFC-BJG-01",
               "due": 82, "onTime": 79, "late": 3, "pending": 0 } ],
  "asOf": "…" }
```
- 칸 = **출하 약속 시각**(Asia/Seoul)을 그 단위로 내린 값.
- `due` = 출하 약속 시각이 지난 출고(취소 제외), `onTime` = 약속 시각까지 **인계 확정**(포장 끝 + 라이더 인계)까지 끝낸 것, `late` = 약속을 넘긴 것(아직 인계 전 포함), `pending` = 아직 약속 전(분모에서 뺌). `due = onTime + late`.
- 0건 칸은 줄 없음(picking-lines 와 같은 규칙) — 화면은 "출하 없음"으로 보이고 0% 로 바꾸지 않는다.
- 기준이 "포장 끝"인지 "인계 확정"인지는 백엔드가 정해 주면 화면 문구를 맞춘다(화면 지금 문구: "출하 약속 시각 안에 포장·인계를 끝낸 작업 ÷ 약속이 지난 작업").
- 권한: picking-lines 와 같게 — 그 센터 MFC_SUPERVISOR(토큰 센터만), OPERATOR_ADMIN 모든 센터.

## 화면에서 쓰는 곳
- MFC 백오피스 센터 대시보드 › 추이 › "출하 준수" 탭: 비율 선(세로축 값 근처~100%), 기간 평균 점선, 출하 없는 칸 옅게, 아래 "늦은 출하 많은 때 상위 5"(late·due).
- API 가 생기면 `shipSim.ts` 를 `mocks/` 로 옮기고 서버 값만 쓴다.
