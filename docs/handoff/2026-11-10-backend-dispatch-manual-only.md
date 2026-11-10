# [pmart-clients → pmart-backend] 요청: 배차 자동 요청 제거 — 점원 요청만 (2026-11-10)

- 관련: BR-51, 계약 `mfc-fulfillment-service.yaml` 0.4.5 `requestDispatch`(D-5), `Delivery-business-logic.md` §3.1
- 사용자 결정(2026-11-10): **배차는 무조건 점원(직원) 요청.** 출하 준비(READY) 시 자동 요청(`AUTO_ON_READY`)은 쓰지 않는다.

| # | 요청 |
|---|---|
| R1 | READY 전이 시 자동 `DispatchRequested`(trigger `AUTO_ON_READY`) 발행을 없애 주세요 |
| R2 | `DispatchRequest.trigger` enum 정리(MANUAL 만) 또는 유지 사유 회신 |
| R3 | 업무 문서 D-5 문구("요청이 없으면 READY 때 자동 요청") 갱신 |
| R4 | 점원이 요청을 잊은 READY 출고를 운영자가 볼 수 있는 경로가 있으면 알려 주세요(없으면 PDA 경고만으로 둠) |

- PDA(mfc_app) 현재: 예상 포장 시간(1~180분) 입력 → `POST /shipments/{id}/dispatch-requests`. 요청 없이 READY 면 경고. 서버가 `AUTO_ON_READY` 를 보내면 숨기지 않고 "관리자에게 알려 주세요" 로 표시.
