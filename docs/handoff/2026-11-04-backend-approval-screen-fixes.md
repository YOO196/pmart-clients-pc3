# [pmart-clients → pmart-backend] 백오피스 승인 화면 수정 안내 + `requestedAmount: null` 계약 확인 (2026-11-04)

- 관련: `contracts/openapi/backoffice-bff.yaml`(`servers.url`), `contracts/openapi/approval-service.yaml`(`ApprovalLine.requestedAmount`, `GET /approvals/{approvalId}`), LAN 게이트웨이 `api-gateway.yml` 라우트 `backoffice-bff`.
- 요약: 오늘 LAN 에서 막힌 승인 화면 3건은 **백오피스 버그**였고 클라이언트에서 고쳤다(백엔드 수정 불필요). 다만 2번은 서버 응답이 계약과 달라 확인을 부탁한다.

## 1. 통합 승인함(bff) 404 — 클라이언트 버그, 백엔드 조치 없음
- 현상: `GET http://d603-16:8080/api/v1/views/approval-inbox` → 404.
- 원인: bff 계약 `servers.url` = `/api/v1/backoffice`, 게이트웨이 라우트 `Path=/api/v1/backoffice/views/**,…/commands/**`. 백오피스가 bff 만 다른 서비스와 같은 `/api/v1` 기준으로 불렀다. BR-40 서버 구현은 정상.
- 조치(클라이언트): bff 기준 경로를 `/api/v1/backoffice` 로. 목·테스트도 같이 고침.

## 2. 승인 상세 화면 깨짐 — `requestedAmount: null` (확인 요청)
- 현상: 상품(PRODUCT) 승인 상세에서 `lines[].requestedAmount` 가 **`null`** 로 와서 화면이 금액 변환 중 멈췄다.
- 계약: `ApprovalLine.requestedAmount: { $ref: Money }` — 선택 필드지만 nullable 아님(생략은 되고 null 은 아님). `approvedAmount` 도 같은 모양.
- 조치(클라이언트): null·생략 모두 빈칸으로 표시하게 고침(앞으로 어느 쪽이 와도 깨지지 않음).
- 요청(택1): (a) 금액 없는 행은 필드를 생략해 달라(계약 그대로). (b) null 이 의도라면 계약을 `type: [integer, 'null']`(또는 nullable Money)로 바꿔 달라. `requestedQty`·`approvedQty`·`approvedAmount` 도 같은 처리인지 함께.

## 3. 승인 뒤 "정본 반영을 확인하고 있어요" 무한 표시 — 클라이언트 버그 + 반영 지연
- 화면: 결정 기록 뒤 1초 × 30회 `GET /approvals/{approvalId}` 로 `executionState` 가 APPLIED/PARTIAL/REJECTED 가 되길 기다린다(handoff 2026-10-30 §1). 응답이 같으면 화면이 다시 그려지지 않아 30회 뒤에도 스피너가 돌았다 → 고침. 이제 30초 뒤 "아직 정본 반영이 확인되지 않았어요 + 다시 확인".
- 백엔드 참고: 이 표시가 났다는 것은 해당 승인의 `executionState` 가 30초 안에 최종 상태가 되지 않았다는 뜻이다(사용자: 백엔드 쪽에서 늦게 받았다고 들음). 원인·조치는 백엔드 판단. 30초가 LAN 기준으로 짧다면 권장 대기 시간을 알려 주면 맞춘다.

## 검증 (클라이언트)
- typecheck·lint 통과, Vitest 87개 통과(2·3번 재현 테스트 추가, 3번은 수정 전 코드로 실패 확인). LAN dist 빌드, 배포는 사용자.
