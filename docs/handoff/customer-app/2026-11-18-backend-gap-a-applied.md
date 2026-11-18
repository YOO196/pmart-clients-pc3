# [pmart-clients → pmart-backend] 회신: 고객앱 갭 A 8가지 + CU-1 앱 반영(목 모드), 요청 1건 (2026-11-18)

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform (notification·customer·order·cart·case·customer-assistant)
- 원 문서: `../pmart-backend/docs/handoff/clients/customer-app/2026-11-18-notice-gap-a-built.md`, `…/2026-11-17-notice-consents.md`(CU-1 §3)
- 계약: 백엔드 main `6c06cf36` 으로 다시 생성(auth·customer·cart·order·claim·review·case·customer-assistant·notification).
- 확인: 목 모드만(`flutter analyze`·`flutter test`). **LAN 실서버는 아직** — 백엔드 LAN 배포(Docker Hub 잠김 풀린 뒤) 다음에 본다.

## 1. 앱에 넣은 것

| 알림 § | 앱 |
|---|---|
| 1 리뷰 요청 알림 | **아래 3의 요청 때문에 리뷰 쓰기로 바로 가지 못함** — 지금은 목적지 ORDER 그대로 주문 상세(리뷰 쓰기 구역 있음)로 간다 |
| 2 주문 내역 카드 | 배송 방식 · 상태, "<대표 상품> 외 N개"(N = `itemCount` − 대표 수량), 상품명 사본 없으면 "상품 N개". 썸네일은 넣지 않음(카드마다 상품 조회가 생겨서 — 필요하면 목록에 이미지 URL 을 주세요) |
| 3 기간·검색 | 위 줄 "검색 · 조회 기간(최근 3개월·6개월·1년·전체) · 상태". 3개월은 `from` 을 보내지 않음(서버 기본), 전체는 `from=2020-01-01` |
| 4 숨기기 | 끝난 주문 카드에 "삭제" → 확인 창(되돌릴 수 없음) → `POST /orders/{id}/hides`. 결과 불명이면 같은 키로 한 번 더. 409 `ORDER_NOT_FINISHED` 문구 |
| 5 장바구니 진행 바 | "15,000원부터 배달 가능해요 / N원 더 담으면 주문할 수 있어요" + 바. `minOrderShortfall` null 이면 숨김, 0 이면 숨김. 안내용이라 주문 버튼은 막지 않음 |
| 6 품절 처리 기본값 | 배송 방식 화면에 "다음에도 적용". 들어올 때 `GET` 값이 있으면 그 값 + 체크, 다음 단계로 넘어갈 때 체크돼 있으면 `PUT`(실패해도 주문은 진행, 알림) |
| 7 배달 지연 신고 | 주문 상세 "문의하기" → "무엇을 도와드릴까요?"(레퍼런스): 진행 중 = 늦어요, 완료 = 못 받았어요·다른 곳에 왔어요, 그 외 문의. 문의 `category DELIVERY` + `deliveryIssue` + (배송이 하나면) `deliveryId`. 422 `ORDER_NOT_IN_PROGRESS` 문구 |
| 8 FAQ | 고객센터 메인에 검색칸 · "자주 묻는 질문 >" · 분류 칩(회원만), 목록·검색, 답은 마크다운(`flutter_markdown_plus`). 422 `CONFIG_REQUIRED` 는 "준비 중"으로 |
| CU-1 §3 | 배송 방식 화면에서 다음으로 넘어갈 때 `GET /me/consents` 가 `requiredConsentOutdated=true` 면 재동의 화면 → `POST /me/consent-changes`(필수 = latestVersion·true, 마케팅 = 고른 값, 끈 것도 false). 설정 "마케팅 정보 수신 동의"는 스위치(같은 API) |

- CU-1 LAN 스위치 두 개(`require-consent`·`purchase-gate`)는 **앱이 LAN 에서 확인될 때까지 켜지 말아 주세요** — 실서버 확인 뒤 이 폴더에 알리겠습니다.

## 2. 확인

- 목 모드: `flutter analyze` 문제 없음, `flutter test` 전체 통과(새 시험 — 주문 내역 8·장바구니 3·배송 신고 5·FAQ 5·품절 기본값 6·동의 6). 라이더앱·MFC앱 `flutter analyze` 문제 없음(같은 생성 패키지).
- 실서버·실기기 확인 없음.

## 3. 요청 — 알림함 응답에 `templateKey` (리뷰 요청 알림 구분)

| # | 요청 | 왜 |
|---|---|---|
| R1 | `GET /me/notifications` 의 `Notification` 에 `templateKey`(예 `REVIEW_REQUESTED`)를 실어 주세요 | 알림 §1 은 "앱은 templateKey 로 리뷰 쓰기 화면을 연다"인데, 고객 알림함 응답에는 templateKey 가 없습니다. `sourceEventType` 도 배송 완료 알림과 같은 `DeliveryCompleted` 라 앱이 리뷰 요청 알림을 가를 방법이 없습니다(제목 글자로 가르는 건 하지 않습니다). 받으면 그 주문의 리뷰 쓰기로 바로 보냅니다 |
