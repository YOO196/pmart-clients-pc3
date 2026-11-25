# 요청 — 재고 이력에 주문·처리한 사람 잇기(LOT 추적) — mfc-inventory-service

보낸 앱: mfc-backoffice (PC 3)
받는 백엔드 영역: mfc (mfc-inventory-service)
날짜: 2026-11-25
상태: **회신 받음** — 백엔드 `clients/mfc-backoffice/2026-11-25-reply-stock-ledger-order-actor.md`: mfc-inventory 0.49.0(#472) orderId·actorOperatorId·거르기 orderId, 주문번호는 mfc-fulfillment 0.36.0(#473) `OrderFulfillmentView.orderNumber`. 화면 반영 브랜치 `mfc/lot-trace`(백엔드 #472 → #473 병합 뒤).

## 왜
- 사용자 2026-11-25 "재고추적탭 만들어줘" → LOT 추적: LOT 하나가 **입고 → 칸 이동 → 어느 주문으로 나갔나**를 따라간다.
- 지금 `GET /mfcs/{mfcId}/stock-ledger?sku=&lotId=`(0.48.0, 백엔드 #470)로 그 LOT 의 확정 단위는 다 나온다. 비어 있는 두 곳:
  1. **어느 주문인지** — `sourceRef` 가 원인마다 다른 번호다. HANDOVER 는 packageId 라 화면이 `GET /packages/{packageId}`(fulfillment `orderNumber`)로 이을 수 있지만,
     RESERVE·RELEASE·EXPIRE·SHORTAGE·CANCEL_RETURN 은 reservationId 라 운영자 API 로 주문을 찾을 수 없다(`/internal/reservations` 만 있음).
     줄마다 포장 조회를 부르는 것도 줄 수만큼 요청이 나간다.
  2. **누가 했는지** — 원장에 작업자가 없다(계약 설명 그대로). TASK_EXECUTION 은 taskId 로 작업 서비스 기록을 따로 봐야 하고, 정정·품질 판정은 요청자를 화면이 알 수 없다.

## 바라는 것 (`StockLedgerCommit` 에 선택 필드 셋 — 추가만, 없으면 null)
```json
{ "commitId": "…", "cause": "HANDOVER", "sourceRef": "PKG-…",
  "orderId": "ORD-…", "orderNumber": "20000001",
  "actorOperatorId": "OP-…" }
```
- `orderId`·`orderNumber`: 그 확정 단위가 한 주문에 딸렸으면(예약·풀림·만료·확정·인계·결품·취소 복귀) 그 주문. 아니면 null. `orderNumber` 는 화면용 8자리(fulfillment `Package.orderNumber` 와 같은 값), 번호 전 주문은 null.
- `actorOperatorId`: 그 확정을 일으킨 사람(작업 실행이면 작업자, 정정·품질 판정이면 요청한 관리자). 시스템(만료·자동 보충 등)이면 null. 화면은 운영자 ID 를 그대로 보이지 않고 이름·사번으로 바꿔 보인다(ADR-0070).
- 있으면 좋음(같은 이유): 거르기 `orderId=`(그 주문의 확정 단위만) — 주문 하나의 재고 흐름을 바로 볼 수 있다.

## 답이 필요한 것
- 위 셋을 원장 사본으로 둘 수 있나요, 아니면 예약 → 주문을 운영자 조회로 열어 주는 편이 맞나요(예: `GET /mfcs/{mfcId}/reservations/{reservationId}` → orderId·orderNumber)?
- 다른 센터·간선(TMS)으로 간 LOT 은 이 센터 원장 밖이라 화면은 "이 센터 안"만 보인다고 적었습니다 — 맞나요?
