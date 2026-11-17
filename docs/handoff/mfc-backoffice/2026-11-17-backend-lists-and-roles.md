# [pmart-clients → pmart-backend] 요청: MFC 센터 관리자 웹 — 목록 API 전부·품질 사고·권한 결정 (MB-1·MB-2·MB-3) (2026-11-17)

- 보낸 앱: mfc-backoffice (PC 3 — 2026-11-17 PC 2 에서 넘겨받음)
- 받는 백엔드 영역: mfc (capacity · inventory · inbound · quality · fulfillment)
- 근거: 백엔드 요청서 `docs/architecture/service-requests/mfc-backoffice-staff-apis.md`(MB-1~3), 공지 `clients/mfc-backoffice/2026-11-17-notice-mfc-approval-ref-and-new-fields.md` §4("어느 목록부터 만들지 알려 달라").
- **한 번에 모두 요청한다.** 아래 순서는 구현 순서 제안일 뿐 — 나눠 PR 해도 되고, 한 PR 이어도 된다.
- 지금 화면: 아래 목록이 없어 모두 "ID 를 넣어 열기"로만 쓴다(`web/mfc-backoffice` `MB-1` 주석). 목록이 오면 그 자리를 목록으로 바꾼다.

## 1. 목록 API (MB-1) — 전부

| 순서 | 서비스 | 제안 경로 | 화면 | 왜 이 순서 |
|---|---|---|---|---|
| 1 | quality | `GET /api/v1/quality-decisions?mfcId=&state=`(해제 승인 대기 = `PENDING_APPROVAL`) | 품질 > 해제 승인 대기 | 관리자가 처리할 일인데 지금은 있는지조차 모른다 |
| 1 | quality | `GET /api/v1/disposal-approvals?mfcId=&state=`(요청됨·승인됨·실행 중) | 품질 > 폐기 | 같은 이유 |
| 1 | quality | `GET /api/v1/return-inspections?mfcId=&state=` | 품질 > 회수품 검수 | 같은 이유 |
| 2 | inventory | `GET /api/v1/mfcs/{mfcId}/count-sessions?state=`(승인 대기 = `PENDING_APPROVAL`) | 재고 > 순환 실사 | 승인 대기 실사를 찾을 길이 없다 |
| 3 | inbound | `GET /api/v1/return-receipts?mfcId=&from=&to=` | 입고 > 회수품 반입 | 일상 확인 |
| 3 | inbound | `GET /api/v1/supply-requests?mfcId=&state=` | 입고 > 공급 요청 | 일상 확인 |
| 3 | inbound | `GET /api/v1/initial-stock-loads?mfcId=&state=`(지금은 `approvalId` 필수) | 입고 > 초기 보유 수령 대기 | 일상 확인 |
| 4 | inventory | `GET /api/v1/mfcs/{mfcId}/stock` 를 `sku` 없이도(센터 전체 — `sku`·`locationCode`·`lotId`·`qualityState` 거르기, 페이지) | 재고 > 센터 재고 | 지금은 상품 코드를 알아야만 본다 |
| 4 | capacity | `GET /api/v1/assignment-plans?mfcId=&date=&state=` | 배정 > 지난 추천 | 있으면 편함 |

공통:
- 페이지 `size`·`cursor`(`_common.yaml` Page). 대기 큐(1·2 순서)는 **오래된 것부터**, 나머지는 최근 것부터.
- 항목은 단건 응답의 요약(ID·상태·수량·SKU·위치·요청자·시각·버전). 상세는 지금 단건 조회를 쓴다.
- 권한: 조회 = 그 센터 권한(`canAccessCenter`), 지금 단건 조회와 같게.
- 상태를 비우면 "끝나지 않은 것"(대기 큐) — 끝난 것은 `state` 로 고를 때만.

## 2. 계약만 있는 것 (MB-2)

| 경로 | 요청 |
|---|---|
| quality `/api/v1/quality-incidents*` (지금 501) | **구현해 달라** — 목록(`mfcId`·`state`)·상세·등록·종결. 품질 화면이 "품질 사고"를 안내만 하고 있다. 업무 규칙이 문서에 없으면 회신에 질문으로 적어 주세요(사용자에게 묻겠다) |
| inbound `/api/v1/inbound-promises*` 입고 예정(TRF, 지금 501) | **지금은 하지 않아도 된다** — 간선(TMS·CDC) 입고 예정이 생길 때 같이. 그 전까지 화면은 안내만 |

## 3. 권한 결정 (MB-3) — PC 3 가 정함(사용자 2026-11-15 "pc3한테 맡기고")

| # | 결정 | 이유 |
|---|---|---|
| 1 | **확인 필요 포장 목록·확인**(`GET /packages?mfcId=&checkRequired=true`, `POST /packages/{id}/handover-checks`)을 **`MFC_SUPERVISOR` 도 허용**한다(MFC_WORKER 는 그대로 — PDA 가 쓴다) | 인계 허가가 만료됐는데 확정 요청이 없는 포장은 예외 처리다. 현장 작업자가 없거나 놓친 경우 관리자가 화면(작업 현황)에서 확인·처리할 수 있어야 한다. 메뉴 정본(`backoffice-role-menus.md` §3)도 센터 관리자 메뉴에 두었다. 허용되면 작업 현황의 "현장 작업자(PDA)만" 안내를 목록·확인 단추로 바꾼다 |
| 2 | **위치·LOT 정정**(`POST /mfcs/{mfcId}/stock-corrections`)과 **위치(칸) 등록·수정·닫기·열기·폐지**(`/locations*` 변경)를 **`MFC_SUPERVISOR` 만**으로 좁힌다(조회는 그대로 센터 권한) | 재고 수치·칸 구조를 바꾸는 관리 동작이다. PDA(작업자 앱)는 이 API 를 부르지 않는다(`apps/mfc_app` 확인 — 정정·칸 변경 호출 없음). 좁혀도 현장은 영향 없다 |
| 3 | **상품 취급**(`sku-handlings*` 변경)은 **`MFC_SUPERVISOR` + MD** 로 좁힌다 | MD 도 같은 API 를 쓴다(요청서 그대로). 작업자는 부르지 않는다 |

- 좁힐 때 403 은 지금 형식(`FORBIDDEN`) 그대로면 된다 — 화면은 이미 403 을 권한 없음으로 보인다.

## 4. 회신에 적어 줄 것

- 경로·필드가 위 제안과 다르면 실제 계약(버전)으로.
- 각 목록의 기본 정렬과 "상태를 비우면" 의미.
- 품질 사고 업무 규칙에서 정해야 할 것(있으면).
- 병합·LAN 배포 순서(PC 1).
