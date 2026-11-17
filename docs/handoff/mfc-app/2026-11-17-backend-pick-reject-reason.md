# [pmart-clients → pmart-backend] 요청: 실적 거절 사유를 응답·실행 조회에 (2026-11-17)

- 보낸 앱: mfc-app (PC 3)
- 받는 백엔드 영역: mfc (fulfillment)
- 계기: 실서버 PDA 피킹에서 실적이 `REJECTED` 로 끝났는데, 작업자도 관리자도 이유를 볼 수 없었다.

## 지금
- `POST /tasks/{taskId}/executions` 가 `status: REJECTED` 일 때 응답에는 `nextAction: "QUERY_RESULT"` 만 있다(`TasksController` — APPLIED 가 아니면 늘 QUERY_RESULT).
- 그런데 `GET /tasks/{taskId}/executions/{executionId}`(`TaskExecution`)에도 거절 사유 필드가 없다. 0.8.0(브랜치 `mfc/pick-to-cart`)에도 없다.
- 서버는 사유를 이미 저장한다(`finishExecution(…, "REJECTED", …, c.code() + ": " + c.detail())`). 밖으로 내보내지 않을 뿐이다.
- PDA 는 그동안 `nextAction` 을 사유로 잘못 보여 "사유 QUERY_RESULT" 가 떴다. 이번에 고쳐서 지금은 "서버(재고)가 거절했어요 — 사유는 서버가 아직 알려 주지 않아요"만 보인다.

## 요청
| # | 요청 |
|---|---|
| E1 | `TaskExecution` 에 **`rejectCode`**(예 `LOCATION_ZONE_MISMATCH`·`LOT_MISMATCH`·`INSUFFICIENT_STOCK`)와 **`rejectReason`**(짧은 설명, 화면에 그대로 보일 문장)을 더한다. REJECTED 가 아니면 null. |
| E2 | `POST …/executions` 의 REJECTED 응답에도 같은 코드를 넣는다(예: 공통 `CommandResponse` 의 `code` 또는 `problem`) — 실행 조회 한 번을 아낄 수 있다. 어렵다면 E1 만으로도 된다. |
| E3 | 계약에 쓸 수 있는 거절 코드 목록을 적는다(재고 PICK·PACK·RETURN 거절 사유). PDA 는 아는 코드는 문구로, 모르는 코드는 코드 그대로 보인다. |

## PDA 쪽
- E1 이 오면: 거절된 실적은 실행 조회로 사유를 받아 피킹 화면 "거절된 실적이 있어요" 아래에 보인다.
