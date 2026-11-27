보낸 앱: mfc-app (PDA — MFC 모드·DC 모드)
받는 백엔드 영역: mfc (mfc-capacity), DC(cdc-outbound)

# 요청 — 작업자가 대기 작업 목록에서 골라 받기

## 사용자 결정 (2026-11-27)
> "pda앱 오래된 작업부터 뜨게 하지 말고 해야 하는 작업 대기 목록에서 선택할 수 있게 만들어"

지금 계약은 2026-11-08 결정("현장 크루는 시스템이 작업을 하나씩 배정")대로 작업자가 **다음 작업 받기**만 할 수 있다.
- MFC: `POST /mfcs/{mfcId}/workers/{workerId}/next-tasks` — 서버가 급한 순서로 하나를 정해 준다. 특정 작업 지정은 `POST /assignments`(MFC_SUPERVISOR 만).
- DC: `POST /cdcs/{cdcId}/workers/{workerId}/next-tasks` — 같은 방식. 특정 작업 지정은 `POST /cdcs/{cdcId}/tasks/{taskId}/reassignments`(운영자).

사용자가 이번에 작업자가 **대기 목록을 보고 직접 골라** 받게 바꾸기로 했다. 클라이언트만으로는 할 수 없어(작업자 토큰으로 특정 작업을 맡는 API 없음) 아래를 요청한다.

## 필요한 것

### 1. 내가 받을 수 있는 대기 작업 목록 (작업자 본인 토큰)
- MFC: `GET /mfcs/{mfcId}/workers/{workerId}/available-tasks?workArea=` (이름은 백엔드가 정함)
  - next-tasks 가 줄 수 있는 후보와 **같은 기준**(업무·자격·담당 없음·READY, 격리 이동·자기 PACK 우선 규칙 포함)
  - 줄마다: taskId·taskType·화면 번호(주문/TRF/작업 번호)·출하 약속 시각(또는 기한)·상품 수·첫 상품명·위치(구역)·대기 시간·권장 순서(next-tasks 순번)
- DC: `GET /cdcs/{cdcId}/workers/{workerId}/available-tasks?kind=` — next-tasks 후보 기준(시작한 Wave 의 담당 없는 CREATED 등)과 같게, 줄마다 taskNumber·waveNumber·trfNumbers·kind·줄 수

### 2. 고른 작업 맡기 (작업자 본인 토큰)
- MFC: `POST /mfcs/{mfcId}/workers/{workerId}/task-claims` 본문 `{ taskId, workArea }` — Idempotency-Key 필수
  - 성공: next-tasks 와 같은 `Assignment`(detail 포함)
  - 거절: 409 `TASK_TAKEN`(그새 다른 사람이 맡음)·`ALREADY_HOLDING`(들고 있는 작업이 있음 — 한 번에 하나 규칙 유지)·`NOT_AVAILABLE`, 422 `WORK_AREA_NOT_ALLOWED` 등 next-tasks 와 같은 코드
- DC: `POST /cdcs/{cdcId}/workers/{workerId}/task-claims` 본문 `{ taskId }` — 같은 규칙

## 정해 주실 것
- 줄 수 있는 후보를 전부 보여 줄지, 급한 순 위 N개만 보여 줄지(출하 약속을 지키려면 위 N개 제한이 나을 수 있음)
- 다른 사람이 피킹한 PACK·미리 정한 격리 이동처럼 "그 사람만" 받는 작업은 목록에서 빼는지(지금 next-tasks 규칙)
- 기존 [다음 작업 받기]는 그대로 두는지(클라이언트는 둘 다 두고 목록 위에 "권장" 표시할 예정)

## 클라이언트 계획
- PDA 업무 안내 화면에 대기 작업 목록(급한 순) + 줄마다 [이 작업 받기], 맨 위 [권장 작업 받기](= next-tasks).
- 계약이 나오기 전에는 목(mock)으로만 만들고, 실서버에는 지금처럼 다음 작업 받기만 쓴다.
