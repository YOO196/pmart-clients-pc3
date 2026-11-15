# [pmart-clients → pmart-backend] 회신·요청: `RIDER_OPS` 역할 반영 + 요청 권한 역할 목록 API (2026-11-15)

- 보낸 앱: hr-backoffice
- 받는 백엔드 영역: platform (employee-auth-service)
- 원 문서: `../pmart-backend/docs/handoff/clients/hr-backoffice/2026-11-15-notice-role-rider-ops.md`
- 클라이언트 등록: `docs/backend-requests.md` BR-57

## 1. 한 것 — `RIDER_OPS` 추가 (목 모드로 확인)
- 직원 등록 화면 "요청 권한 역할" 목록(`web/hr-backoffice/src/api/models.ts` `GRANT_ROLES`)에 `RIDER_OPS` 를 더했다. 이제 13개, 알림 문서와 같은 순서:
  `OPERATOR_ADMIN, HR_ADMIN, CENTER_MASTER_APPROVER, CS_AGENT, DISPLAY_APPROVER, INVENTORY_APPROVER, MD, MFC_SUPERVISOR, MFC_WORKER, PRICE_APPROVER, PRODUCT_APPROVER, RIDER_OPS, SERVICEABILITY_APPROVER`
- 센터 고르기는 다른 역할처럼 선택 사항으로 둔다(화면이 역할별로 센터를 강제하지 않는다 — 판정은 서버).
- 확인: typecheck·lint 통과, 테스트 34개 통과(목 모드). **LAN 빌드·배포는 아직** — 지금 PC 4 의 인사팀 백오피스에서는 `RIDER_OPS` 를 고를 수 없다. 배포 요청은 커밋 뒤 따로 보낸다.

## 2. 요청 — 요청 권한 역할 목록 API (BR-57)
- 지금은 역할 목록 API 가 없어 화면에 고정해 둔다(11-13 요청서 §3). 역할이 늘 때마다 이번처럼 알림 → 화면 수정 → 배포가 필요하고, 그 사이 목록이 어긋난다(서버만 늘면 화면에서 못 고르고, 화면만 늘면 그 행이 `UNKNOWN_ROLE` 로 거절).
- 요청: employee-auth-service 에 `HR_ADMIN` 이 부를 수 있는 **역할 목록 조회**를 계약에 넣어 줄 수 있는지.
  - 항목당 필요한 값: 역할 코드, 화면 표시 이름(한국어), 센터를 골라야 하는 역할인지(예 `MFC_SUPERVISOR`·`MFC_WORKER`), 가능하면 표시 순서.
  - 경로·모양은 백엔드가 정해 주세요(클라이언트는 계약이 나오기 전에는 부르지 않는다).
- 생기면 화면은 고정 목록 대신 그 응답을 쓰고, 못 불러오면 빈 목록이 아니라 오류로 보인다.

## 3. 회신해 줄 것
- §2 를 만들지, 만든다면 대략 언제인지. 안 만들면 지금처럼 역할이 늘 때마다 알림을 계속 주세요.
