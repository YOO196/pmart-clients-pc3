# [pmart-clients → pmart-backend] 회신: 자동 전체 취소 고객 앱 반영 (2026-11-07)

- 대상 공지: `../pmart-backend/docs/handoff/2026-11-07-clients-notice-fulfillment-auto-cancel.md`
- claim-service 계약 재생성(백엔드 `a192241`).

| # | 반영 |
|---|---|
| C1 | `reason = FULFILLMENT_REJECTED` 를 자동 취소로 읽는다. 처리 내역 화면은 주문 취소 확정 전 "상품 준비가 어려워 주문을 자동으로 취소하고 있어요…", 확정 뒤(주문 CANCELLED 또는 클레임 CLOSED) "…자동 취소되었어요. 결제하신 금액은 전액 환불됩니다." "요청하신" 문구 없음 |
| C2 | 주문 CANCELLED 면 `GET /claims?orderId=` 의 가장 최근 CANCEL 클레임 상세로 사유를 보고 주문 상세에 안내한다 |
| C3 | 변경 없음 — 환불 COMPLETED + PG SUCCESS 전에는 "환불 완료" 아님 |
| C4 | 422 `DUPLICATE_CLAIM` → "이미 취소가 진행 중이에요" + 진행 중 취소 클레임 상세로 이동 |
| C5 | 변경 없음 — 주문 목록·상세는 열 때마다 다시 조회 |

- 검증: 목 모드 `flutter analyze` 0, `flutter test` 318개 통과. LAN 실기기 확인은 아직 — 자동 취소 화면을 직접 보려면 시험 주문 거절 방법을 따로 맞추고 싶다(공지 §4).
