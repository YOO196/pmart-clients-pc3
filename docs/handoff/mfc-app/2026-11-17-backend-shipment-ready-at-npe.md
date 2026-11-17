# [pmart-clients → pmart-backend] 버그: 출고 조회 `GET /shipments/{shipmentId}` 가 READY 전이면 500 (2026-11-17)

- 보낸 앱: mfc-app (PC 3)
- 받는 백엔드 영역: mfc (fulfillment)
- 급함: 실서버 PDA 패킹 테스트가 이 오류로 멈춰 있다.

## 증상
- PDA 패킹 화면은 출고를 `GET /api/v1/shipments/{shipmentId}` 로 그린다(3초마다 다시 조회).
- 2026-11-17 14:09~14:11(KST) LAN 서버 fulfillment 로그에 같은 출고 `ORD-ac047fd4-7ff2-309e-9c59-5a38fe4f920e-S1` 조회가 **매번 500** 으로 남았다. 다른 출고(`ORD-7a21bdc3-…-S1`)도 같다.

```
Unhandled exception GET /api/v1/shipments/ORD-ac047fd4-7ff2-309e-9c59-5a38fe4f920e-S1
java.lang.NullPointerException
  at java.util.Objects.requireNonNull
  at java.util.Optional.of
  at java.util.stream.FindOps$FindSink$OfRef.get
  at java.util.stream.ReferencePipeline.findFirst
  at com.pmart.mfc.fulfillment.infrastructure.TaskStore.shipmentReadyAt(TaskStore.java:709)
  at com.pmart.mfc.fulfillment.application.PackageService.shipment(PackageService.java:312)
  at com.pmart.mfc.fulfillment.api.ShipmentsController.getShipment(ShipmentsController.java:143)
```

## 원인(코드 읽기)
`TaskStore.shipmentReadyAt` (origin/main):

```java
return jdbc.query("SELECT ready_at FROM shipment WHERE shipment_id = ?",
        (rs, i) -> instant(rs, "ready_at"), shipmentId)
    .stream().findFirst().orElse(null);
```

출고가 아직 READY 가 아니면 `ready_at` 이 NULL → 목록 원소가 `null` → `findFirst()` 가 `Optional.of(null)` 로 NPE. 행이 없을 때만 `orElse(null)` 이 동작한다.

## 요청
| # | 요청 |
|---|---|
| S1 | `ready_at` 이 NULL 이어도 `null` 을 돌려주게 고친다(예: 목록이 비면 null, 아니면 `list.get(0)`). 같은 `.stream().findFirst()` + nullable 값 패턴이 다른 조회에도 있으면 함께 |
| S2 | READY 전 출고 조회(`readyAt` null) 통합 테스트 추가 — 피킹 중·패킹 중 출고 |

## PDA 쪽
- 고칠 것 없음. 배포 뒤 실서버에서 피킹 → 패킹 → 출하대기를 다시 확인한다.
- 같은 테스트에서 피킹 실적 두 건은 재고에 정상 반영됐다(inventory 로그 `EXE-52b85098…` 2개, `EXE-e2516513…` 1개). PDA 의 "거절된 실적" 표시는 별도로 PDA 쪽에서 확인 중이다.
