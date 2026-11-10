# [pmart-clients → pmart-backend] 요청: PDA 업무 선택 기반 배정 (2026-11-10)

- 관련: BR-52, 계약 `mfc-capacity-service.yaml` 0.12.0 `pullNextTask`·`getWorker`, `mfc-inbound-service.yaml` `/inbound-tasks`
- 사용자 결정(2026-11-10)
  - 크루(작업자)는 **본인 작업 목록을 볼 수 없다**. 작업 배정 서비스가 최우선 작업을 하나씩 준다.
  - 업무는 **입고 / 품질검사 / 재고 이동 / 재고 실사 / 피패킹** 다섯(아래 R4 표). 작업자가 업무를 고르고 "작업 준비 완료" → 그 업무 설명 한 장 → 확인 → **작업 가능 신호** → 서비스가 작업 단계를 계속 지시.
  - 메인 화면은 모든 작업자 공통. 권한 없는 업무·메뉴를 누르면 "권한이 없어요".

| # | 요청 | 지금 계약 | PDA 지금 |
|---|---|---|---|
| R1 | 다음 작업 받기에 **고른 업무**를 넘길 값(예: 본문 `taskTypes[]` 또는 `workArea`) — 그 업무 안에서만 배정 | 없음. 업무(duty)는 센터 관리자만 정함 | 목만 업무로 거름. 실서버는 업무 무시하고 받음 → 다르면 "고른 업무와 다른 작업이 배정됐어요" 표시 |
| R2 | 다음 작업 받기에 **입고(RECEIVE)·품질검사(INSPECT)·적치(PUTAWAY)** 포함, 그리고 지금 작업 유형이 없는 **회수품 반입·회수품 검사·재고 실사**를 배정 가능한 작업으로(작업 유형 추가) — 상세(`detail`)도 | 순서에 주문 작업·보충·이동·복귀만. 회수품 반입(`return-receipts`)·회수품 검수(`return-inspections`)·실사(`count-sessions`)는 작업 유형 없음 | 목에 피패킹 외 작업 없음 → "지금 할 작업이 없어요". 앱 임시 값 RETURN_RECEIPT·RETURN_INSPECT·CYCLE_COUNT |
| R3 | **작업자 본인 조회** 허용(`GET /mfcs/{mfcId}/workers/{workerId}` 본인 토큰, 또는 `/me`) — `effectiveTaskTypes`·`onBreak`·`displayName` 로 권한·휴게 표시 | 권한 주체 명시 없음(목록은 운영자·서비스 토큰) | 이 조회로 권한 판정(목) |
| R4 | 업무 ↔ 작업 유형 묶음(사용자 결정 2026-11-10): 입고 = RECEIVE / 품질검사 = INSPECT + 회수품 검사 / 재고 이동 = PUTAWAY·REPLENISH·MOVE·RETURN + 회수품 반입 / 재고 실사 = 실사 / 피패킹 = PICK·PACK. 자격(qualification)·업무(duty)·유효 작업 유형도 이 단위로 줄 수 있게 | 없음 | 이 묶음으로 구현 |
| R5 | 업무 외 메뉴 권한: 인계 확인(포장대)·프린터 설정을 볼 수 있는 자격 | 없음 | 가정: 둘 다 PACK 자격. 휴게는 누구나 |
| R6 | "작업 가능" 신호 — 설명 확인 뒤 작업자를 작업 가능(대기) 상태로 남길 API 가 필요한지(배정 추천·감시용). 지금은 다음 작업 받기 호출로 대신 | 없음 | 확인 = 다음 작업 받기 |
| R7 | 검수 단계 API: LOT 등록 + 품질 검사(`/inbound-tasks/{id}/inspections` 와 mfc-quality 의 관계), 단계별 지시 응답 | 일부(inbound inspections) | 미구현 |


## 입고(받기) 화면 — BR-53
| # | 요청 | 지금 계약 | PDA 지금 |
|---|---|---|---|
| R8 | 입고 예정 행(`InboundPromise.lines[]`)과 입고 작업(`InboundTask` — 품질검사·적치)에 **상품명·바코드** — 계수·검사할 때 보이고 스캔으로 대조. 입고 작업은 단건 조회(`GET /inbound-tasks/{taskId}`)도 | `sku`·`lotId`·수량만 | 실서버는 SKU 만 표시, 스캔 대조 안 됨(직접 입력). 목만 상품명·바코드 |
| R9 | RECEIVE 배정(다음 작업 받기)의 `taskId` 로 입고 예정(`trfId`)을 찾는 방법 — taskId = trfId 인지, `detail` 에 trfId 를 줄지 | 없음 | taskId = trfId 로 가정 |
| R10 | 송장(TRF) 바코드 원문 형식 — 도착 등록 때 스캔으로 맞는 송장인지 확인. 채번 지침 G-09(라벨 스캔 값 = `{유형}:{id}:{버전}`)를 따르면 `TRF:{trfId}:{버전}` 인지 | 없음 | 스캔값 = trfId 로 가정(G-09 형식이 정해지면 `PKG` 처럼 해석) |
| R11 | 수령 행의 `discrepancyReason` 은 하나 — 수량 차이(부족·초과·미도착)와 격리 사유(파손·온도)가 같이 있을 때 무엇을 보내나 | 없음 | 수량 차이 우선, 수량이 맞고 격리가 있으면 격리 사유(작업자가 고름) |


## 품질검사·재고 이동·재고 실사 연결 중 나온 것 — BR-52 이어서 (R12~R14)
공통 문제: 작업을 **등록**할 API 는 있는데, 현장이 **무엇을** 할지 알아낼 방법이 없다. 사용자 결정(크루는 작업을 고르지 않고 서버가 하나씩 지시)과 맞추려면 서버가 작업을 내줘야 한다.

### R12 회수품 검수 대기 — 무엇을 검사할지
- 흐름: 고객 반품 → 라이더 회수 → 점포 반납 → 점원 반입(`POST /return-receipts`, 격리 증가) → `ReturnItemReceived` → **품질검사 직원 검수**(`POST /return-inspections`, RESALE/DISPOSE).
- 지금 계약: 반입 단건 조회(`GET /return-receipts/{id}` — `inspectionState` PENDING/INSPECTED, `claimId`, 줄별 sku·qty·lotId·conditionNote)와 검수 등록만. **검수 대기 목록·배정이 없다.**
- 현장 문제: 품질검사 직원은 returnReceiptId 를 알 방법이 없어 검수를 시작할 수 없다.
- 요청(권장 순):
  1. 회수품 검수를 **배정 가능한 작업**으로 — 다음 작업 받기(`pullNextTask`)가 품질검사 업무에 `RETURN_INSPECT`(이름은 백엔드가 정함) 작업을 주고, `taskId`(또는 `detail`)로 returnReceiptId 를 알 수 있게.
  2. 최소한 `GET /return-receipts?mfcId=&inspectionState=PENDING`(반입 오래된 순).
  3. 검수 화면에 필요한 값: 줄별 **온도대(temperatureZone)·신선 여부(fresh)** — 검수 요청 필수값인데 반입 조회에 없어 지금은 작업자가 고른다. 상품 마스터 값이면 반입 조회 줄에 같이 주면 좋다.
- PDA 지금: 배정 taskId = returnReceiptId 로 가정하고 반입 조회로 줄을 읽어 검수 화면을 그린다(목). 온도대·신선은 작업자가 고르고, 재판매는 상온·미개봉·신선 아님일 때만 고를 수 있게 막는다(최종 판정은 서버 422).

### R13 회수 라벨 — 반입 때 claimId·returnPickupId 를 어떻게 아나
- 반입 등록 필수값: `claimId`, `returnPickupId`, `toLocationCode`(반품 칸), 줄별 `sku`·`qty`.
- 서버는 이미 안다: 라이더 점포 반납(`POST /deliveries/{id}/returns/store-deliveries`) → `ReturnDelivered`(returnPickupId·claimId·줄별 orderLineId·qty)를 mfc-inbound 가 구독.
- 빠진 것: ① 회수 봉투 라벨 바코드 원문 형식(포장 QR `PKG:<id>:<버전>` 처럼) ② 그 번호로 **반입 예정**(claimId·줄·**SKU**·수량)을 조회하는 API ③ `ReturnDelivered` 줄에 SKU 가 없다(orderLineId 만) — 반입 등록은 SKU 필수.
- 현장 문제: 점원이 반품 번호·회수 번호를 손으로 입력 → 오타면 다른 반품으로 들어가거나 거절.
- 요청(권장): 라벨 형식 확정 — 채번 지침 G-09 `{유형}:{id}:{버전}` 에 맞춰(예 `RTN:<returnPickupId>:1`, 유형 이름은 지침 G-12 접두어와 겹치지 않게) + `GET /return-pickups/{returnPickupId}`(또는 반입 예정 목록 `GET /return-receipts/expected?mfcId=`)로 claimId·줄(sku·qty·orderLineId)·권장 반품 칸. 회수품 반입도 재고 이동 업무의 배정 작업(`RETURN_RECEIPT`)으로 줄지 판단.
- PDA 지금: 반입 등록 연결만. 값은 입력/목.

### R14 실사 배정 — 어느 칸을 누가 셀지, 잠금은 누가
- 지금 계약: 실사 시작(`POST /mfcs/{mfcId}/count-sessions`, 운영자·작업자 모두 가능) → 계수(첫 계수 ≠ 장부면 **다른 작업자** 재계수, 같은 사람 409 SAME_COUNTER) → 차이 승인(관리자). 시작하려면 칸이 mfc-location `COUNT_LOCKED` 여야 한다(아니면 409 LOCATION_NOT_LOCKED).
- 빠진 것: ① 실사 계획(어느 칸을 언제 — 순환 실사 주기) ② 실사를 작업자에게 주는 방법(다음 작업 받기에 실사 없음, 재계수자 ≠ 첫 계수자 배정 규칙) ③ 칸 잠금 주체·순서 — 잠금 요청(`POST /locations/{id}/state-changes`)은 `countSessionId` 를 받는데 세션은 잠금 뒤에야 만들 수 있어 순서가 꼬인다. 잠근 칸은 피킹·보충에 영향, 시간 만료 자동 해제 없음.
- 현장 문제: 재고 실사 업무를 고른 작업자에게 서버가 "이 칸을 세세요"를 줄 수 없다. PDA 가 칸을 고르고 잠그게 하면 크루가 작업을 고르지 않는다는 결정과 어긋난다.
- 요청(권장): 센터 관리자(또는 시스템 주기)가 실사 계획 → 서버가 잠금·세션 시작까지 처리 → 다음 작업 받기가 실사 세션을 `CYCLE_COUNT` 작업으로 줌(taskId = sessionId), 재계수는 첫 계수자 제외 → 작업자는 받은 칸을 세고 제출만. 잠금 해제(MATCHED·ADJUSTED·REJECTED 뒤)도 서버가.
- PDA 지금: 시작·조회·계수 제출 연결만(목).


### R15 품질검사 LOT — 작업자는 소비기한으로 나누기만, LOT 번호는 시스템
- 사용자 결정(2026-11-10): "작업자는 그냥 유통기한 맞춰서 분배만 하고 로트번호 자체는 시스템에서 배정해야 할 듯. 이걸 인간이 어떻게 하니."
- PDA: 품질검사 결과 줄에 `sourceLotRef`(제조 LOT 표기)를 **보내지 않는다**. 줄 = 판정(정상/격리) + 수량 + 소비기한(+ 선택 제조일). 같은 판정·같은 소비기한 줄은 화면에서 한 줄로 합치게 한다.
- **개정(같은 날, 채번 지침 G-06 확인 뒤 사용자 결정 "(가) 다시 받기")**: 동일 배치 판정이 SKU + 제조사 + **제조사 LOT 원문** + 제조일자이고 "식품의 LOT 불명 수량은 판매 가능으로 전환하지 않는다"이므로, PDA 는 포장의 LOT 표기를 **스캔**해 `sourceLotRef` 로 보낸다(손으로 LOT 번호를 만들지 않음). 표기가 없으면 작업자가 "LOT 표기 없음"을 확인하고 `sourceLotRef` 없이 보낸다.
- 확인 요청(개정): ① `sourceLotRef` 없이 온 정상 판정 줄을 서버가 LOT 불명으로 보고 판매 가능 전환을 막는지, 아니면 소비기한·제조일로 배치를 정하는지 ② 제조사·공급사 값은 수령(TRF) 쪽에서 채우는지(PDA 는 안 보냄).
- (이전 문단, 기록용) 확인 요청: `sourceLotRef` 없이 보내면 서버가 **소비기한(+제조일)만으로** LOT 를 나누고 LOT 번호를 배정하는지(계약 설명은 "같은 표기·기한은 같은 LOT"). 아니면 표기 없이도 그렇게 되도록, 그리고 `sourceLotRef` 를 선택값으로 계속 둘지 회신.

### R16 표시 문서 번호 — 채번 지침 G-02 이행
- 지침: 작업·입고·이동·실사 등은 화면에 `document_no`(`TSK-20261110-000123` 형식)를 보이고 내부 UUID 는 보이지 않는다(이행 목록 3).
- 요청: 반영될 때 PDA 가 쓰는 응답(다음 작업 받기 `Assignment`·`detail`, `TaskDetail`, `InboundPromise`(TRF 표시번호), `InboundTask`, `MoveOrder`, `CountSession`, `Package`)에 `documentNo` 필드를 같이 — 그전까지 PDA 는 내부 ID 를 보인다.

- 회신 받기 전 PDA 는 목으로만 동작을 보이고, 실서버에서는 지금 계약 그대로(업무 무시) 부른다.
