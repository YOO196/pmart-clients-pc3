# 요청: 품질 사고(MB-2) — 사용자 결정과 필요한 API

보낸 앱: mfc-backoffice (PC 3)
받는 백엔드 영역: mfc (mfc-quality-service, 고객 영향은 case-service)

- 작성: pmart-clients PC 3, 2026-11-19
- 답하는 것: 회신 `clients/mfc-backoffice/2026-11-18-reply-lists-and-roles.md` §3 의 질문 1~4(사용자 2026-11-19 답). 질문 5(본사 MD 가 센터 권한 없이 상품 취급 변경)는 아직 답이 없어 **지금대로(센터 권한 필요)** 둔다.
- 지금 계약: `GET /quality-incidents`·`/{incidentId}` 조회만, 501. 화면은 이 문서의 API 가 계약에 들어온 뒤 만든다(계약에 없는 것은 부르지 않는다).

## 1. 사용자 결정(2026-11-19)

| # | 질문 | 결정 |
|---|---|---|
| 1 | 누가 여나 | **자동 + 센터 관리자 직접 등록 둘 다.** 직접 등록은 현장에서 찾은 파손·변질·오염·유통기한 문제 등 |
| 2 | 결품 보고 중 어떤 것을 | **파손·변질만**(DAMAGED 처럼 품질 문제인 것). 단순 수량 부족(SHORT)·분실은 사고로 열지 않는다 — 재고 정정 쪽 |
| 3 | 종결 | **센터 관리자가 닫는다. 단, 영향 LOT 이 모두 처리(격리 해제·폐기 판정 끝)된 뒤에만.** 닫을 때 사유를 적는다 |
| 4 | 고객 영향 | **자동으로 case 를 같이 연다** — 영향 LOT 이 이미 출고된 고객 주문에 들어갔으면 서버가 case 를 열고 사고에 `caseId` 로 잇는다 |

## 2. 필요한 것(한 번에)

### R1. 조회 구현(501 해제)
- `GET /quality-incidents?mfcId=&state=&kind=&lotId=` — 다른 목록(MB-1)과 같게 `items`·`nextCursor`, `size` ≤ 200, 기본 = 끝나지 않은 것(OPEN·DECIDED) 오래된 순. 권한 = 그 센터 운영자.
- `QualityIncident` 에 더해 주세요: `origin`(AUTO·MANUAL), `description`(직접 등록 설명), `openedBy`(직접 등록한 운영자 ID — 자동이면 null), `closedBy`·`closeReason`, `version`(닫기의 X-Expected-Version), 영향 LOT 별 처리 상태(`affectedLots[].resolved` 또는 그 LOT 의 판정 ID·상태 — 화면이 "남은 LOT n개"를 서버 값으로 보이게), 영향 주문 수(`affectedOrderCount`, 모르면 null).

### R2. 직접 등록 — `POST /quality-incidents`
- 본문: `mfcId`, `kind`(IncidentKind — 직접 등록에 TEMPERATURE_EXCURSION·RECALL 도 받을지는 백엔드 판단), `affectedLots[{ lotId, qty }]`(1개 이상), `description`(필수, 300자 — 개인정보 금지).
- 그 센터 `MFC_SUPERVISOR` 만. `Idempotency-Key`·`X-Source-System`, 같은 키 = 같은 결과. 없는 LOT·다른 센터 LOT 은 400/422 + details.
- 영향 LOT 을 자동으로 격리할지(사고 등록 = 격리 요청까지)도 정해 회신 주세요. 화면은 지금 품질 > 격리·해제 요청 흐름이 있어서, 자동 격리를 안 하면 사고 상세에서 그 흐름으로 보낸다.

### R3. 자동으로 여는 것
- 결품 보고(LineShortageReported) 중 **파손·변질 사유만** 사고 1건(kind = DAMAGE 등, `sourceRef` = 보고 ID). 같은 LOT·같은 원인 중복은 한 건으로 묶을지 백엔드 판단.
- 온도 이탈·리콜은 발행자가 생길 때(지금은 없어도 됨).

### R4. 상태
- OPEN → DECIDED: 영향 LOT 모두에 격리 해제 또는 폐기 판정이 붙었을 때(판정 ID 는 `decisionIds`). 판정과 사고를 잇는 방법(판정 요청 본문에 선택 `incidentId` 를 받거나 서버가 LOT 으로 잇기)을 회신에 적어 주세요 — 화면은 사고 상세에서 판정 요청을 보낼 때 그대로 따른다.
- DECIDED → CLOSED: R5 로만.

### R5. 닫기 — `POST /quality-incidents/{incidentId}/closures`
- 본문 `reason`(필수, 300자). `X-Expected-Version`, 멱등키. 그 센터 `MFC_SUPERVISOR` 만.
- 영향 LOT 이 남아 있으면 409(예: `LOTS_NOT_RESOLVED` + 남은 lotId details). 이미 닫혔으면 409 `INVALID_STATE`.

### R6. 고객 영향 case
- 영향 LOT 이 출고된 고객 주문에 있으면 서버가 case-service 사건을 열고 `caseId` 를 채운다(직접 등록·자동 둘 다). case 종류·처리 주체(고객센터)는 백엔드 판단. 센터 관리자는 사고 상세에서 case 상태를 보기만 한다(지금 배차 실패 사건처럼 — `GET /cases/{caseId}` 를 센터 관리자도 볼 수 있어야 함).

## 3. 게이트웨이
- `/quality-incidents*` 가 이미 quality 라우트에 걸리는지 확인 부탁(POST 둘 포함).
