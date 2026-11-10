# MFC 현장앱 (mfc_app, Flutter · Android PDA 우선)

점원앱·PDA앱·패킹앱을 **역할별 메뉴로 한 앱에** 둔다 `[확정 2026-10-24, ADR-0001]`. 설정·배정·예외 해결은 관리자 웹(backoffice), PDA는 **실행만** (M 784, 1183).
근거: `../pmart-backend/docs/business/MFC-business-logic.md`(M, v2.0), `Delivery-business-logic.md`(D), 계약 `mfc-fulfillment`, `mfc-capacity`, `mfc-inbound`, `mfc-location`, `mfc-quality`, `mfc-inventory`, `delivery-dispatch`, `product-service`(바코드).

## 1. 메뉴와 API

| 메뉴 | API | 비고 |
|---|---|---|
| 로그인(직원 ID) | 없음 | BR-02 |
| 내 작업 | `GET /tasks?mfcId=&assignee=me&type=&state=`, `GET /tasks/{taskId}` | BR-05 AGREED(`e817184`). 기본 state에 BLOCKED 없음 → 막힌 작업은 `state=BLOCKED` 로 따로 조회 |
| 작업 시작 | `POST /tasks/{taskId}/starts`, `GET …/starts/{requestId}` | BR-05. 처리는 §3-1 |
| 피킹 | `POST /tasks/{taskId}/executions`, `GET …/executions/{executionId}`, `GET /barcodes/{barcode}` | 지시 행은 `GET /tasks/{taskId}` 의 `lines[]` |
| 패킹 | `GET /shipments/{id}`, `POST /shipments/{id}/packages`(밀봉 → 포장 QR), `GET /packages/{id}`, `POST /packages/{id}/repackings` | |
| 배차 요청 | `POST /dispatch-requests`, `GET /dispatch-requests/{requestId}`, `GET /deliveries/{id}/dispatch` | 패킹 소요시간 입력 |
| 인계 확인 | `GET /packages?mfcId=&checkRequired=true`, `GET /packages/{id}/handover-resolution`, `POST /packages/{id}/handover-checks`, `GET /deliveries/{id}/eta`(pickupEta) | 라이더 스캔 결과 반영. 허가 만료 뒤 점원 확인(D-1, fulfillment 0.4.4·0.4.9). §6-1 |
| 입고 | `GET /inbound-promises`, `GET /inbound-promises/{trfId}`, `POST …/arrivals`, `POST …/receipts` (+짝 조회) | 2단계(공급 루프)에 본격 사용. 1차는 초기 보유·회수 반입 |
| 회수품 반입 | `POST /return-receipts`, `GET /return-receipts/{id}` | 반입 즉시 격리 |
| 회수품 검수·품질 | `POST /return-inspections`, `POST /quality-decisions`, `POST /disposal-approvals` | 요청자·승인자 분리 |
| 로케이션 | `GET /locations`, `POST /locations/{id}/state-changes`, `GET /putaway-candidates` | 실사 잠금 COUNT_LOCKED |
| 공급 요청 | `POST /supply-requests`, `PATCH`, `…/withdrawals` | WK-14, 2단계 |

## 2. 공통 화면 요소 (M 784)
현재 담당자·배정 버전, 스캔 대상, 지시/확정/잔량 수량, 현재 위치, 다음 행동, **전송 상태**(전송 대기 / 확정 대기 / 반영 / 거절 / 확인 중). 문제 보고는 실행 중에도 가능. 완료 표시는 서버 확정 후.

## 3. 작업 상태 (M 833-841, 1161-1179)
- 유형: RECEIVE, INSPECT, PUTAWAY, REPLENISH, PICK, PACK, DISPATCH.
- `WAITING → READY → ASSIGNED → IN_PROGRESS → COMPLETED | CLOSED_PARTIAL`, 어디서든 `BLOCKED / FAILED / CANCELLED`. 종료 상태에서 재시작 불가.
- 작업 시작은 한 요청만 성공(WK-03). 실적은 잔량 초과 불가. 오상품·오위치·오로트·수량 초과는 실적 0 + 원인 안내.
- **스캔 오류·통신 실패는 작업 FAILED가 아니다** — 요청 오류로 처리.
- 출하 SHP: `PREPARING → READY → PARTIALLY_HANDED_OVER → HANDED_OVER`, `CANCELLED`, `CLOSED_PARTIAL`. 포장 PKG: `OPEN → SEALED → HANDED_OVER`, `INVALIDATED`(재포장), `VOIDED`.
- 재고 반영 상태: `CAPTURED → SUBMITTED → PROCESSING → APPLIED | REJECTED | UNKNOWN_RESULT`. 확정 전엔 "확정 대기". `UNKNOWN_RESULT` 일 때 **물리 작업을 다시 하지 말라**고 안내.

### 3-1. 작업 시작 처리 (`POST /tasks/{taskId}/starts`, 계약 `c609a4d`)
근거: `../pmart-backend/docs/handoff/2026-10-24-clients-reply-br05-start-503.md`. 판정 순서는 담당 조회 → 판정 기록 → 응답이다.

| 상황 | 의미 | 앱 동작 |
|---|---|---|
| 201 | 시작 성공 | IN_PROGRESS로 바꾸고 피킹 화면으로 이동 |
| 409 `ALREADY_STARTED` / `NOT_ASSIGNEE` / `PREDECESSOR_NOT_COMPLETED` / `INVALID_STATE` / `VERSION_CONFLICT` | 거절 확정 | 원인 안내 후 작업 상세를 다시 조회 |
| 503 `DEPENDENCY_UNAVAILABLE` | **시작 안 됨 확정**(판정 기록 없음) | "다시 시도" 버튼. 재시도는 **같은 키**로 하고, 같은 키로 보내면 서버가 다시 판정 |
| 응답 없음(타임아웃·연결 끊김) | 결과 불명 | "확인 중" 표시. **같은 키 재전송**으로 확정한다. 짝 조회와 `activeStart` 는 보조 수단 |
| 409 `IDEMPOTENCY_CONFLICT` `retryable=true` | 같은 키의 앞선 요청이 처리 중 | "확인 중" 유지, 잠시 뒤 같은 키로 재전송 |
| 409 `IDEMPOTENCY_CONFLICT` `retryable=false` | 같은 키에 다른 본문(클라이언트 버그) | 오류 안내, 자동 재시도 금지 |
| 짝 조회 404 | 미도달·처리 중·503 중 하나 | **시작 안 됨으로 확정하지 않는다.** 같은 키로 재전송 |
| 키 분실(앱 재설치 등) | — | `GET /tasks/{taskId}` 의 `activeStart.workerId` 로 본인 시작 여부 확인. 새 키로 재시작하면 `ALREADY_STARTED` |

- 확정 전에는 피킹 화면으로 넘어가지 않는다.
- `UNKNOWN_RESULT` 는 이 명령에서 오지 않지만, 오면 "확인 중"으로 처리한다(방어).

## 4. 피킹 (M 639-676, IV-07)
- 화면: 영수증번호, 진행(3/5), 층, 현재·다음 로케이션, 보관방법, SKU·바코드, 제조일·유통기한, 지시·기피킹·피킹 수량.
- 바코드 용도 구분: 작업자, 상품, 장바구니, 선반·슬롯, 완료. 순서 예: 냉장 → 냉동 → 상온.
- 피킹으로 재고가 줄지 않는다(인계 시 차감).
- 결품(WK-06): 다른 위치 확인 후 예외 기록. 대체는 고객 동의 필요, 무응답이면 출하 보류·지원팀 이관. 임의 대체·자동 부분취소 금지. 알림 닫기·ACK로 보류가 풀리지 않음.

## 5. 패킹 (M 562-637, WK-07)
13단계: 장바구니 도착 → 직원 ID 스캔 → 장바구니 스캔 → 상품·수량 대조 → 유통기한 확인 스캔 → 포장 방법 확인 → 포장재 스캔(보냉팩·아이스팩·드라이아이스) → 온도별 포장 → 주의 스티커 → 밀봉 → 패킹 완료 스캔 → 영수증·라벨 출력·부착 → 외부 출하대기 랙 이동.
- 보냉백 XS/S/M/L/XL, 상온 봉투 소/중/대.
- 유효 포장 구성 합계 = 확정 피킹량. 누락·혼입·초과는 준비 완료 차단.
- 라벨 재출력은 같은 PKG ID, 실제 재포장만 새 PKG. 인계된 포장은 재포장 불가.
- 패킹 시작·패킹 완료·배차 요청은 각각 기록.

## 6. 인계 (M 1885-1987)
- 라이더가 포장 QR을 스캔 → fence `HANDOVER_IN_PROGRESS` → 커밋 → 재고 H/E/R 차감 → `HANDED_OVER`.
- fence 동안 그 포장의 취소·재포장·다른 기사 인계 보류. 불명·만료 시 시간 경과로 원상복구하지 않고 대사.
- `[결정 필요]` 점원 쪽 QR 표시 화면이 필요한지(현재는 포장 라벨 QR 스캔 방식으로 해석).

### 6-1. 점원 인계 확인 (백엔드 공지 `2026-11-08-clients-notice-handover-check.md`)
라이더가 QR을 찍은 뒤 확정 없이 허가가 만료되면 실물이 라이더에게 갔을 수 있다. 점원이 포장대에서 실물을 보고 확인한다.

| 버튼 | 본문 `result` | 서버 결과 | 앱 |
|---|---|---|---|
| 포장대에 있음 | `AT_STATION` | 허가 해제 → 다른 라이더가 다시 찍을 수 있음 | 확인 대화상자 후 전송 |
| 포장대에 없음 | `TAKEN_BY_RIDER` | 허가 라이더에게 인계 확정, 재고 인계 전기 | **되돌릴 수 없어** 경고 대화상자 후 전송 |
| — | 409 `FENCE_ACTIVE` | 허가가 아직 살아 있음 | "라이더가 픽업을 마치는지 기다려 주세요", 다시 조회 |
| — | 409 `INVALID_STATE` | 확인할 허가 없음(이미 처리됐을 수 있음) | 안내 후 다시 조회 |
| — | 응답 없음·`IDEMPOTENCY_CONFLICT`(retryable) | 결과 불명 | 같은 키로 자동 재전송 2회, 그래도 모르면 "다시 확인"(보냈던 값으로만) |

- 화면: 작업 목록 상단 "인계 확인" → 확인 필요 목록(만료 오래된 순, 놓인 위치·라이더·만료 시각). 포장별 "인계 상태" 화면은 판정·허가·재고 반영·마지막 확인·라이더 픽업 ETA. 패킹 화면의 포장을 눌러도 들어간다.
- 재고 반영 `APPLIED` 만 "재고 차감 완료"로 보인다. `PROCESSING` = 확정 대기, `UNKNOWN_RESULT`·값 없음 = "다시 건네지 마세요", `REJECTED` = 관리자 대사 필요(재인계·재포장 금지).
- 키는 화면 상태에만 둔다. 앱을 다시 켜서 키를 잃어도 판정 조회의 `checkRequired`·`lastCheck` 로 반영 여부를 알 수 있다(새 키 재전송은 409 `INVALID_STATE`).

## 7. 입고·적치·실사
- 입고(IV-02): 차량 확인 → 냉동·냉장 우선 하차 → 바코드·수량·소비기한 검수 → 판정(정상/초과/부족/손상/미발주/온도이탈) → 위치 등록. 입력: 인수·정상·격리·보류 수량, 로트, 증빙 사진(BR-07).
- 적치는 실제 목적지 도착 시만 완료, 중단 시 현재 위치·잔량 보존. 선반 보충은 자동 생성만(수동 생성 없음).
- 실사(IV-11): 위치 잠금 후 시작, 첫 계수는 장부 수량 숨김(blind), 차이 시 다른 작업자 재계수, 조정 요청자 ≠ 승인자.

## 8. 중지·교대·권한
- 장비 고장·위치 불가 → BLOCKED/FAILED, 완료 실적 보존. 교대·재배정 시 후임은 잔량만, 전임의 늦은 스캔은 `VERSION_CONFLICT`.
- 권한 회수 시 신규 시작 거절, 진행 실물·실적 보존. PDA의 "취소" 버튼은 화면 문구만 바꿈(서버 취소 아님).

## 9. 단말
- 업무 문서 기준: PDA 하드웨어 스캐너(키보드 웨지 또는 브로드캐스트 인텐트), 라벨·영수증 프린터, 직원 ID 바코드. 카메라 스캔은 보조.
- **지금 단계 `[결정 2026-11-10]`**: 전용 PDA 대신 **일반 안드로이드 기기**를 한시적으로 쓴다. **카메라 바코드 스캔 필수.** 프린터는 **포장대 고정형** 가정.
  - 스캔: `lib/shared/scanner/` — `CameraScanner` 어댑터(기본 `mobile_scanner` 7.5.0, CameraX + ML Kit 번들) + `ScanInput`(입력칸 = 키보드 웨지·직접 입력, 카메라 버튼). 피킹·패킹 상품 스캔은 연속, 포장 QR 스캔은 1회. 같은 코드를 비추고 있는 동안은 다시 받지 않는다(`ScanDedup`, 1.5초 안 보였다가 다시 보이면 받음). 인식 시 진동·소리, 거절은 진동 + 원인 문구. 전용 PDA 스캐너는 같은 어댑터 자리에 끼운다.
  - 포장 QR: `PKG:<packageId>:<packageVersion>`(fulfillment authorizePackageHandover 설명 0.4.0). 찍은 버전 ≠ 지금 포장 버전이면 "무효 라벨" 경고.
  - 출력: `lib/shared/printer/` — 화면 미리보기(기본) / 네트워크 라벨 프린터(ZPL, RAW 9100). 설정은 기기에 저장(작업 목록 앱바 → 프린터 설정, 시험 라벨). RAW 출력은 결과를 돌려주지 않아 "나왔는지 확인" 안내. 재출력은 같은 포장 ID·같은 서버 QR. 라벨 항목은 BR-22 전이라 QR·포장·버전·주문·배송·온도대·봉투 수(영문·숫자만 — 기본 글꼴에 한글 없음).
- 오프라인: 실적은 `execution_id`(=Idempotency-Key)와 함께 내구 저장 후 재전송. 임시 저장분을 완료로 표시하지 않음.

## 10. `[결정 필요]`
전용 PDA 기종·스캐너 SDK(지금은 안드로이드 기기 + 카메라), 프린터 기종·명령어(지금은 고정형 ZPL 가정), 바코드 체계·로케이션 코드 문법(Q-02/Q-03), 유통기한·FEFO(Q-05), 교대·강제 인계(Q-09), 실사 승인자(Q-11), 결품 연락 횟수(Q-12), 단말 임시 저장 보존(Q-16), 인계 토큰 유효시간(Q-01), 분할 기준 자동화 여부(Q-10 vs DM 10,000g).
