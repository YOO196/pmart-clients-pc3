# [pmart-clients → pmart-backend] 요청: 피킹 실적의 도착지를 장바구니로 — 실서버 PDA 피킹이 전부 거절됨 (2026-11-17)

- 보낸 앱: mfc-app (PC 3)
- 받는 백엔드 영역: mfc (fulfillment · inventory)
- 급함: **높음** — 실서버에서 피킹 실적이 한 건도 반영되지 않는다(아래 1).
- 사용자 결정(2026-11-17): **"장바구니, 집품위치, 상품바코드 모두 찍혀야 해"**. 피킹은 PDA 에서 ① 장바구니 → ② 집품 칸 → ③ 상품 바코드를 모두 찍는 흐름이고, 서버가 이 흐름 그대로 받도록 고쳐 달라는 요청이다.

## 1. 지금 일어나는 일
- 실서버 PDA(2026-11-17 11:19 화면): 피킹 작업에서 장바구니 `CRT-A-01` → 칸 `C-B7-06-3-01` → 상품(당근 500g)을 찍고 실적을 보낸다. 실적은 **거절**되고 화면은 "확정 0 / 지시 4"인 채 칸 단계로 돌아간다. 화면에는 "거절된 실적이 있어요 — 관리자에게 알려 주세요"가 뜬다.
- 원인: `POST /tasks/{taskId}/executions`(PICK)는 `toLocation` 이 없으면 400 VALIDATION_FAILED 로 거절한다.
  - mfc-fulfillment `TaskService`: "집품은 fromLocation(선반)·toLocation(포장 위치)이 필요합니다."
  - mfc-inventory `TaskExecutionService`: "PICK 은 toLocation(포장 위치)이 필요합니다." + `locations.requirePacking(toLocation)`(PACKING 구역 위치만 받음).
- PDA 는 칸마다 상품을 다 찍는 즉시 실적을 보낸다(한 실행 = 한 선반). 이 시점에 작업자는 아직 포장대에 가지 않았고, 상품은 **장바구니**에 들어 있다. 그래서 PDA 가 보낼 수 있는 "포장 위치"가 없다(작업 상세·시작 응답에도 없음).
- 계약(mfc-fulfillment `TaskExecutionRequest`)에서 `toLocation` 은 필수가 아니다(`required: [executionType, workerId, lines]`). 계약과 서버 판정이 어긋나 있다.

## 2. 요청 — 피킹 도착지 = 찍은 장바구니

| # | 요청 | 지금 | 바라는 것 |
|---|---|---|---|
| P1 | **PICK 의 `toLocation` 으로 장바구니(구역 CART·ACTIVE 위치, 예 `CRT-A-01`)를 받는다** | inventory 가 PACKING 구역만 받음(`requirePacking`) | PICK 은 `requireCart`(이미 있는 `Locations` 카트 검사, IV-03)로. 반영: 선반 `NORMAL·STORED −q` → 장바구니 `NORMAL·PICKED +q`(예약 그대로) |
| P2 | **포장(밀봉)이 장바구니 → 패킹대로 옮기며 PACKED** | PACK 은 `fromLocation = 포장 위치` 한 곳에서 PICKED → PACKED(위치 그대로) | `POST /shipments/{id}/packages` 의 `packingLocation`(PDA 가 찍은 패킹대 `PAK-…`)을 도착지로. 출발지는 그 출고의 PICK 실적 도착지(장바구니). inventory PACK 은 `fromLocation = 장바구니`, `toLocation = 패킹대` 로 `PICKED −q` / `PACKED +q` |
| P3 | 계약에 판정을 적는다 | `toLocation` 설명만("내려놓은 포장 위치(구역 PACKING)") | PICK 이면 `toLocation` 필수(구역 CART), 아니면 400 — 설명과 거절 코드(예 `TO_LOCATION_REQUIRED`·`NOT_CART`)를 계약에. `TaskDetail.packingLocations` 설명("PICK 실적의 도착지")도 장바구니에 맞게 |
| P4 | 한 출고는 한 장바구니 | 없음 | 같은 출고의 PICK 실적이 다른 장바구니로 오면 409 `CART_MISMATCH`(이동의 규칙과 같게). 필요 없다고 보면 이유를 회신 |

### PDA 가 보낼 값(P1 이 되면 바로 바꿈)
```
POST /api/v1/tasks/{taskId}/executions
{ "executionType": "PICK", "workerId": "...", "assignmentVersion": 3,
  "fromLocation": "C-B7-06-3-01",   // ② 찍은 집품 칸
  "toLocation":   "CRT-A-01",       // ① 찍은 장바구니
  "lines": [{ "orderLineId": "...", "sku": "...", "lotId": "LOT-...", "pickedQty": 2 }] }   // ③ 상품 바코드로 센 수량
```
포장은 지금처럼 `POST /shipments/{shipmentId}/packages` 에 `packingLocation: "PAK-A-01"`(찍은 패킹대)을 보낸다.

## 3. 같이 봐 달라는 곳(장바구니가 중간에 끼면 달라지는 것)
- **복귀(RETURN) 작업**: 취소된 주문의 `picks[].locations` 가 지금은 "포장 위치"다. 피킹 뒤·포장 전에 취소되면 상품은 장바구니에 있으니 장바구니 코드가 와야 한다. PDA 는 받은 위치를 그대로 출발지로 보낸다.
- **집품 뒤 중지·인계**: 포장 위치를 쓰는 다른 곳(`Package.packingLocation`, 인계 화면 위치)은 P2 뒤에는 패킹대 그대로다.
- **결품 보고(shortage)만 있는 실적**: 집은 양이 0 이면 `toLocation` 은 필요 없다(지금 `anyPick` 조건과 같게).

## 4. 회신 받을 것
- P1~P4 각각 받아들이는지, 다르게 하면 PDA 가 보낼 값.
- 반영 버전(mfc-fulfillment·mfc-inventory)과 LAN 배포 시각. PDA 는 그 뒤 실서버에서 피킹 → 포장 → 출하대기까지 한 번 돌려 확인한다.

## 5. PDA 쪽에서 할 일(PC 3)
- P1 이 되면: 피킹 실적에 `toLocation` = 찍은 장바구니를 넣는다(지금은 빠져 있음 — PDA 의 빠뜨림도 원인이다).
- 회신과 무관하게: 거절된 실적의 거절 코드·사유를 피킹 화면에 보인다. 목 서버도 `toLocation` 이 없으면 실서버처럼 거절하게 한다.
