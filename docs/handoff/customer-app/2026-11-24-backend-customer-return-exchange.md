# 요청 — BR-95 고객 앱 반품·교환 직접 접수(레퍼런스 12)

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform (claim-service 고객 접수·자격 조회, 사진 올리기) — 회수·재배달 배차는 delivery 영향 있음
- 계기: 사용자 2026-11-24 "A로 해줘 일단 목업과 백엔드요청서만" — 고객이 앱에서 반품·교환을 **접수**하고, 처리(승인·회수·환불·재배달)는 서버와 상담원이 한다.
- 지금 계약(claim-service 0.15.0): 고객 토큰의 RETURN 은 422 `UNSUPPORTED_ACTION`(고객센터로 문의), EXCHANGE 는 직원도 422. ADR-0060 결정 2(인계 뒤 반품은 고객센터만)를 바꾸는 요청이다 — **ADR 변경이 필요하면 사용자 승인 뒤** 진행해 주세요.

## 앱이 지금 한 것(목만)
- 주문 상세(배송 완료) [반품·교환] → `/orders/{orderId}/return-exchange`
  - ① "어떤 처리를 원하세요?": 반품 신청하기 / 교환 신청하기. 신청할 수 없으면 그 칸을 흐리게 + "고객센터로 문의" → 환불 문의(case).
  - ② 신청서: 상품 선택(체크·수량, "교환 제한"·"신선보장" 꼬리표, 신청 불가 상품 펼치기) → 이유(변심·실수 / 상품문제 / 배달문제 13개) → 상세 이유(200자)·사진(3장, 문제 사유면 필수) → 방법(라이더 회수·재배달, 라이더 요청사항 회수할 때·재배달할 때) → 결제 금액 정보 → [신청 완료]. 뒤로 가면 "신청을 취소할까요?".
  - 접수하면 처리 내역(클레임 상세)으로 간다. 접수 ≠ 승인 — 진행은 서버 상태 그대로.
- **실서버(local)는 아직 신청 불가로 보이고 고객센터 문의로 잇는다**(계약이 생기면 연결). 코드: `apps/customer_app/lib/features/claims/{domain/return_request.dart, data/return_request_repository.dart, presentation/return_request_*.dart}` (`// BR-95`).

## 요청
- **R1 고객 RETURN·EXCHANGE 접수** — `POST /claims` 고객 토큰(channel `CUSTOMER_APP`)에서 RETURN·EXCHANGE 허용.
  - 본문(지금 ClaimCreate 에 더해): 품목 `{orderLineId, qty}[]`, `reason`, `reasonDetail`(최대 200자), `photoIds[]`(최대 3), 라이더 요청사항 `pickupNote`·`redeliveryNote`(EXCHANGE 만, 최대 50자).
  - 심사는 직원 RETURN 과 같게: 품목별 ≤ 전달 완료 수량 − 진행·완료 반품·교환 수량(넘으면 `QUANTITY_EXCEEDS_AVAILABLE`), 전달 완료 없음 `NOT_DELIVERED_YET`, 같은 키·같은 본문은 재생.
  - 회수비: 고객 사유(변심·실수)는 지금처럼 9,000원 FEE_PENDING → 앱 처리 내역에서 결제(이미 있는 회수비 결제 흐름을 그대로 씀). 상품·배달 문제는 회사 잘못으로 보고 면제 → 바로 진행.
  - 상품·배달 문제 사유는 사진·상세 이유 필수(없으면 400 `EVIDENCE_REQUIRED` 등 — code 를 알려 주세요).
  - 신선·냉동 등 변심 반품 불가 품목을 변심 사유로 보내면 422 — code 를 알려 주세요.
- **R2 신청 자격 조회** — 예: `GET /orders/{orderId}/return-eligibility`(경로·이름은 서버 판단). 앱은 표시·막기에만 쓰고 최종 판정은 R1.
  - 주문 단위: `returnAllowed`·`exchangeAllowed`(false 면 이유 code — 기한 지남·미전달·이미 전부 신청 등).
  - 품목별: `orderLineId`, 이름·옵션·사진 사본, 단가·줄 금액, 전달 수량, **지금 신청할 수 있는 수량**, `changeOfMindAllowed`(신선·냉동 등 false), `freshGuarantee`(신선보장 꼬리표), **품목별 기한**(일반 7일·신선 24시간 — `deadlineAt`).
  - 신청할 수 없는 품목 목록(품절 취소·이미 신청·판매 중지 등)과 이유.
  - 고객 사유 회수비(배달팁) 금액(서버 정책 값 — 앱은 표시만), 회수·재배달 주소(원주문 주소 고정).
  - 사용자 질문: "배송 완료 4일 지났는데 반품·교환 버튼이 뜬다" — 앱은 기한을 계산하지 않으므로 버튼을 보일지도 이 조회(또는 주문 상세의 값)로 정하고 싶다.
- **R3 사진 올리기** — 반품·교환 증빙 사진. case 문의 사진(`POST /inquiries/photos` 류)처럼 먼저 올려 `photoId` 를 받고 R1 에 싣는 방식이면 좋겠다(장당 한도·형식도 알려 주세요).
- **R4 이유 대응** — 앱 이유 13개 → ClaimReason / ReturnFaultCode:

| 묶음 | 앱 이유 | ClaimReason | faultCode(회수비 면제) |
|---|---|---|---|
| 변심·실수 | 상품이 마음에 들지 않아요 | CHANGE_OF_MIND | — |
| | 상품을 잘못 주문했어요 | CHANGE_OF_MIND | — |
| | 주소를 잘못 설정했어요 | ADDRESS_ERROR | — |
| 상품문제 | 상품이 설명과 달라요 | NOT_AS_ADVERTISED | DEFECTIVE? |
| | 상품의 기능에 문제가 있어요 | DEFECT | DEFECTIVE |
| | 식품이 변질됐어요 | DEFECT | DEFECTIVE |
| | 상품에 이물질이 발견됐어요 | DEFECT | DEFECTIVE |
| | 상품의 유통/소비기한이 지났어요 | DEFECT | DEFECTIVE |
| 배달문제 | 상품이 파손되어 배달됐어요 | DAMAGED_IN_DELIVERY | DAMAGED_IN_DELIVERY |
| | 일부 다른 상품이 배달됐어요 | WRONG_ITEM | MISDELIVERY 또는 WRONG_SUBSTITUTE |
| | 모두 다른 상품이 배달됐어요 | WRONG_ITEM | MISDELIVERY |
| | 주문한 상품 중 일부는 배달이 안 왔어요 | MISSING_ITEM | ? |
| | 배달완료인데 아직 배달이 안 왔어요 | MISSING_ITEM | ? (오배송 흐름 R-16 과 겹침 — Q3) |

  - 앱 세부 이유(13개)를 서버에 남길 값(예: `reasonCode`)이 필요한지, 아니면 `reasonDetail` 에 문구로 충분한지 정해 주세요.
- **R5 교환** — EXCHANGE 접수 뒤 같은 상품 재배달(라이더 회수·재배달 한 번에). 재고가 없으면 교환 취소(앱 안내 문구 "교환 상품의 재고가 없으면 교환이 취소될 수 있어요") — 그때 상태·환불이 어떻게 되는지 알려 주세요.

## 질문
- Q1 ADR-0060 결정 2 를 바꾸는 범위 — 반품·교환 모두 고객 접수 허용인지, 반품만인지.
- Q2 클레임 상세(`ClaimView`)에 교환의 재배달 진행(회수 → 재배달 배송 ID)이 어떻게 보이는지.
- Q3 "배달완료인데 아직 안 왔어요"는 오배송 선택 흐름(case 0.39.0 R-16, 문의 NOT_RECEIVED)과 겹친다 — 반품·교환 이유에서 빼고 그 흐름으로 보내야 하는지.
- Q4 회수 요청사항(회수할 때·재배달할 때)이 라이더 앱에 전달되는 곳(delivery 배송 메모?).

## 앱이 하지 않는 것
- 기한·금액·자격 계산(서버 값만 표시), 사진 올리기(R3 전까지 목은 개수만), 결제(회수비는 이미 있는 처리 내역 결제로).
