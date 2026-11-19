# MFC 백오피스 센터 운영판 — 결품 건별 목록·출하 약속 건수 요청

보낸 앱: mfc-backoffice (PC 3)
받는 백엔드 영역: mfc (mfc-fulfillment-service)
날짜: 2026-11-19

센터 관리자 첫 화면에 "센터 운영판·예외 처리함"을 만들었다(`docs/apps/mfc-backoffice-web.md` §4-0). 기존 API 로 출하 약속 초과·임박, 피킹 파손(품질 사고), 인계 확인 필요까지는 됐다.
아래 두 가지가 없어 화면에서 안내만 하거나 클라이언트가 목록을 끝까지 읽는다. 둘 다 조회만이다.

## OE-1. 센터 결품 보고 목록 (필수)
지금은 결품 건수(`GET /metrics/picking-lines`)만 있고 건별 목록이 없다. 작업 BLOCKED·수량 차이를 결품으로 추정하지 않기로 해서 결품(SHORT) 행을 보일 수 없다.
- 제안: `GET /shortages?mfcId=&reason=SHORT|DAMAGED|BLOCKED(반복)&state=OPEN|RESOLVED(반복, 비우면 OPEN)&from=&to=&size=&cursor=` — 센터 관리자·그 센터 직원.
- 항목: `shortageId`, `reason`(SHORT·DAMAGED·BLOCKED), `taskId`, `taskLineId`, `taskType`, `shipmentId`, `orderId`, `orderNumber`, `sku`, `productName`, `lotId`, `locationCode`, `qty`(보고 수량), `reportedBy`(작업자 ID), `reportedAt`, `state`(처리 전·재확보·결품 확정 등 서버 값), `resolvedAt`, 지금 그 작업의 `taskState`·`assignee`.
- 응답: `items`, `page.nextCursor`, `asOf`, 그리고 같은 조건의 **전체 건수 `total`**(첫 쪽만 세지 않게).

## OE-2. 출하 약속 초과·임박 건수 (권장)
지금은 `GET /tasks?state=…`를 200건씩 최대 5쪽 읽어 화면이 출고별로 묶고 센다(넘으면 "N건 이상").
- 제안 A: `GET /tasks` 에 `promisedBefore=<시각>` 거르기와 응답 `total`.
- 제안 B: 출고 단위 요약 `GET /shipments/promise-summary?mfcId=&dueWithinMinutes=` → `{ overdue, dueSoon, noPromise, asOf }`(출하 대기 전 출고만, PICK·PACK 이 끝나지 않은 것).
- 출하 임박 기준(분)이 업무 규칙으로 정해지면 알려 주세요(지금 화면 기준 15분).

회신은 `../pmart-backend/docs/handoff/clients/mfc-backoffice/` 에서 읽는다.
