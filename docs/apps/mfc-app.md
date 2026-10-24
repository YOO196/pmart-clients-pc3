# MFC 현장앱 (mfc_app, Flutter · Android PDA 우선)

점원앱·PDA앱·패킹앱을 **역할별 메뉴로 한 앱에** 둔다 `[확정 2026-10-24, ADR-0001]`. 설정·배정·예외 해결은 관리자 웹(backoffice), PDA는 **실행만** (M 784, 1183).
근거: `../pmart-backend/docs/business/MFC-business-logic.md`(M, v2.0), `Delivery-business-logic.md`(D), 계약 `mfc-fulfillment`, `mfc-capacity`, `mfc-inbound`, `mfc-location`, `mfc-quality`, `mfc-inventory`, `delivery-dispatch`, `product-service`(바코드).

## 1. 메뉴와 API

| 메뉴 | API | 비고 |
|---|---|---|
| 로그인(직원 ID) | 없음 | BR-02 |
| 내 작업 | `GET /assignments`(mfc-capacity) | 작업 목록·상세 없음(BR-05) |
| 피킹 | `POST /tasks/{taskId}/executions`, `GET …/executions/{executionId}`, `GET /barcodes/{barcode}` | 지시 행 조회 BR-05 |
| 패킹 | `GET /shipments/{id}`, `POST /shipments/{id}/packages`(밀봉 → 포장 QR), `GET /packages/{id}`, `POST /packages/{id}/repackings` | |
| 배차 요청 | `POST /dispatch-requests`, `GET /dispatch-requests/{requestId}`, `GET /deliveries/{id}/dispatch` | 패킹 소요시간 입력 |
| 인계 확인 | `GET /packages/{id}/handover-resolution`, `GET /deliveries/{id}/eta` | 라이더 스캔 결과 반영 |
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

## 7. 입고·적치·실사
- 입고(IV-02): 차량 확인 → 냉동·냉장 우선 하차 → 바코드·수량·소비기한 검수 → 판정(정상/초과/부족/손상/미발주/온도이탈) → 위치 등록. 입력: 인수·정상·격리·보류 수량, 로트, 증빙 사진(BR-07).
- 적치는 실제 목적지 도착 시만 완료, 중단 시 현재 위치·잔량 보존. 선반 보충은 자동 생성만(수동 생성 없음).
- 실사(IV-11): 위치 잠금 후 시작, 첫 계수는 장부 수량 숨김(blind), 차이 시 다른 작업자 재계수, 조정 요청자 ≠ 승인자.

## 8. 중지·교대·권한
- 장비 고장·위치 불가 → BLOCKED/FAILED, 완료 실적 보존. 교대·재배정 시 후임은 잔량만, 전임의 늦은 스캔은 `VERSION_CONFLICT`.
- 권한 회수 시 신규 시작 거절, 진행 실물·실적 보존. PDA의 "취소" 버튼은 화면 문구만 바꿈(서버 취소 아님).

## 9. 단말
- PDA 하드웨어 스캐너(키보드 웨지 또는 브로드캐스트 인텐트), 라벨·영수증 프린터, 직원 ID 바코드. 카메라 스캔은 보조.
- 오프라인: 실적은 `execution_id`(=Idempotency-Key)와 함께 내구 저장 후 재전송. 임시 저장분을 완료로 표시하지 않음.

## 10. `[결정 필요]`
PDA 기종·스캐너 SDK, 프린터 종류, 바코드 체계·로케이션 코드 문법(Q-02/Q-03), 유통기한·FEFO(Q-05), 교대·강제 인계(Q-09), 실사 승인자(Q-11), 결품 연락 횟수(Q-12), 단말 임시 저장 보존(Q-16), 인계 토큰 유효시간(Q-01), 분할 기준 자동화 여부(Q-10 vs DM 10,000g).
