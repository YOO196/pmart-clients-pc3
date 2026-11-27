# 요청 — 센터 관리자 "배정 풀기"(입고·검사·적치·이동 작업)

보낸 앱: mfc-backoffice (PC 3) · mfc-app(PDA)
받는 백엔드 영역: mfc (mfc-capacity · mfc-inbound)
날짜: 2026-11-27
상태: 요청

## 무엇이 막혔나
- 실서버 PDA(2026-11-27): 작업자가 입고를 고르면 "받아 둔 다른 작업부터 끝내 주세요" — 전에 받은 **적치(PUTAWAY)** 배정이 남아 있다.
  mfc-capacity 다음 작업 받기는 들고 있는 작업을 먼저 돌려주므로, 그 적치를 끝내기 전에는 다른 업무를 못 받는다(규칙대로).
- 센터 관리자가 그 배정을 풀어 주려 해도 공개 경로가 없다:
  - 피킹·포장은 mfc-fulfillment `POST /tasks/{taskId}/releases`(작업 내놓기, 0.4.8 — 관리자 가능)로 풀 수 있어 백오피스 배정 화면에 "배정 풀기"를 넣었다.
  - 입고(RECEIVE)·품질검사(INSPECT)·적치(PUTAWAY)·이동(MOVE·REPLENISH)·회수품(RETURN_RECEIPT·RETURN_INSPECT)·실사(CYCLE_COUNT)는
    capacity `POST /internal/assignments/{taskId}/releases`(서비스 전용) 말고는 풀 길이 없다. 지금 화면은 "다른 작업자에게 재배정"만 권한다
    (`POST /assignments` — 다른 사람에게 넘길 뿐 아무에게도 안 맡기는 상태로는 못 돌린다).

## 바라는 것
- 그 센터 `MFC_SUPERVISOR`(·`OPERATOR_ADMIN`)가 부르는 공개 배정 해제 — 예: mfc-capacity `POST /assignments/{taskId}/releases` 또는 `POST /assignments/{assignmentId}/releases`.
  - 본문: `workerId`(지금 담당 — 다르면 409 NOT_ASSIGNEE), `reason`(필수, 배정 이력 endReason), 해제자는 토큰(endedBy).
  - Idempotency-Key·X-Source-System, 같은 키 같은 결과. 활성 배정이 없으면 변화 없는 성공(내부 경로와 같게).
  - 작업 원장 쪽 상태 되돌리기가 필요한 유형(mfc-inbound 작업 IN_PROGRESS 등)은 원장 서비스 규칙대로 — 진행 중 실적이 있으면 409(fulfillment 의 EXECUTION_IN_FLIGHT 처럼).
    어느 유형이 원장 쪽 처리가 필요한지(예: PUTAWAY 를 잡고 있던 카트·수량)는 백엔드가 정해 주세요.
- 정해지면 화면은 배정 화면의 "배정 풀기"를 유형 상관없이 그 경로로 보낸다(`web/mfc-backoffice/src/features/assignments/AssignmentPages.tsx` `ReleaseAssignment`).

## 지금 쓰는 우회
- 관리자가 그 적치를 다른 작업자에게 재배정하거나, 작업자가 PDA 에서 [작업 시작]으로 적치를 끝낸다.
