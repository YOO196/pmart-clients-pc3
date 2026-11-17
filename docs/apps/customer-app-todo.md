# 고객앱 해야 할 일 (PC 1)

- 만든 날: 2026-11-17 (사용자 "해야 할 일 md 파일을 작성해줘")
- 고친 날: 2026-11-18
- 끝난 항목은 지우지 말고 `~~취소선~~` + 커밋을 적는다. 새 항목은 맨 아래 절에 더한다.
- 계약·회신 경로: 백엔드 회신은 `../pmart-backend/docs/handoff/clients/<customer-app|all>/`, 우리 요청은 `docs/handoff/customer-app/`.

## 1. 백엔드 준비됨 — 고객앱이 만들 것

| # | 할 일 | 근거(계약·백엔드 문서) | 메모 |
|---|---|---|---|
| 1 | **고객센터 문의에 사진 붙이기** — 한 장씩 `POST /inquiry-photos`(multipart) → 문의 `photoIds`(5장, 장당 10MB), 남긴 뒤 보완 `POST /inquiries/{id}/photos`, 상세 사진 보기 | case 0.14.0, `clients/all/2026-11-17-request-inquiry-photos.md` | 사용자 2026-11-17 "해야 할 일에 기억". 사진 실패해도 문의는 남게(첨부 성공 ≠ 접수 성공). 리뷰 사진 코드(`features/reviews`) 방식 그대로. 백오피스 보기는 #59 로 끝남 |
| 2 | 문의 만족도 — 답변 받은 문의에 1~5점 + 한 줄(200자), 한 번만 | case 0.15.0, `clients/all/2026-11-17-request-inquiry-satisfaction.md` | 409 `INQUIRY_NOT_ANSWERED`·`ALREADY_RATED` 문구 |
| 3 | 리뷰 수정·삭제 화면 — "내가 쓴 리뷰"에서 수정(`PATCH`, `X-Expected-Version`, 3일 안 — `editableUntil` 그대로)·삭제(삭제 뒤 재작성 불가 안내) | review 0.2.0, `clients/customer-app/2026-11-16-request-review-edit-delete.md` | 앱에 API 호출 코드는 있음(`updateReview`·`deleteReview`), 화면 없음 |
| 4 | 실시간 도착 예정·배송 현황 실서버 확인 + 라이더 위치 점(픽업 뒤만) | tracking 0.5.0(`/eta`·`/stream` 구현), 0.6.0 `riderLocation`, `clients/customer-app/2026-11-17-reply-delivery-eta.md`·`…-reply-reference-gap-delivery.md` | 앱 구현은 있음(501 이던 것). 라이더 위치 지도는 새로 — 위치는 픽업 뒤(TO_CUSTOMER·AT_CUSTOMER)만 오고 그 전·끝난 뒤 null(사용자 결정 2026-11-17, `clients/customer-app/2026-11-18-notice-reference-gap-update.md` §1). 매장 위치는 보이지 않음(결정) |
| 5 | 전달 완료 사진·놓은 곳 보기(오배송 확인) | execution 0.9.0~ `GET /deliveries/{id}/delivery-proof`·`evidence-photos/{ref}` — **백엔드 main 반영 확인함(2026-11-18, 지금 0.22.2)** | 고객은 전달 완료(COMPLETED) 뒤 **전달 완료 증빙 사진만**(실패·회수 사진 안 됨). 사진은 앱에 저장하지 않음(`no-store`) |
| 6 | 배송 신고(지연·미수령·오배송)를 문의로 — `POST /inquiries` 에 `deliveryIssue`(DELAYED·NOT_RECEIVED·MISDELIVERED)·`deliveryId`(선택) | case 0.16.0, 지연 신고는 0.23.0(2026-11-18) — **백엔드 main 반영 확인함(2026-11-18)** | 11-18 갱신 알림 §2 의 "배달 지연 제보 — 고객용 API 없음"은 계약 0.23.0 보다 먼저 쓰인 것으로 보임(계약이 정본) |
| 7 | 최근 검색어·인기 키워드 | search 0.2.0 `/me/recent-searches`·`suggestions.popular` | `search_screen.dart` 주석에 "로그인 단계에서 붙인다"만 있음 |
| 8 | 비회원 장바구니 병합(주문서 로그인 뒤) | cart `POST /carts/{id}/merges`, BR-50(OPEN) | BR-50 질문 회신부터 확인 |
| 9 | 주소 수정·삭제 | customer `PATCH`·`DELETE /me/addresses/{id}` | 레퍼런스 대비 A 목록에도 있음 |
| 10 | 회원 탈퇴·탈퇴 철회, 내 동의 목록, AI 상담 답 다시 찾기·다시 보기 | customer `/me/withdrawals`·`GET /me/consents`, customer-assistant `GET /customer-assistant/questions(/{id})` | 화면 위치는 레퍼런스 캡처 먼저 |
| 25 | **약관 동의(CU-1) — 급함** (1단계 로그인 흐름 끝 2026-11-17, 남은 것 = 주문 전 재동의·설정 마케팅): 로그인 동의 완료 본문 `providerToken`+`consents`(필수 + 선택 MARKETING, 끈 것도 false), `/me/consent-changes` 먼저 부르기 지움, 재동의 안내(`newAccount=false`), 완료 오류 표, 로그인해 있는 고객의 주문 전 재동의(`GET /me/consents` `requiredConsentOutdated`), 설정의 마케팅 켜고 끄기 | auth 0.2.0·customer 0.3.0, `clients/customer-app/2026-11-17-notice-consents.md`(BR-20 회신 포함) | **최신 계약으로 다시 만들면 고객앱이 컴파일되지 않음**(2026-11-17, `consentChangeRequestId` 없어짐). LAN 스위치 2개는 앱 반영 때까지 꺼짐 — 준비되면 백엔드(PC 1 백엔드)와 함께 켬. `contracts.lock`(dart)은 이것과 함께 올림 |
| 26 | 주소 검색(카카오 우편번호) 스크립트 도메인 `t1.daumcdn.net` → `t1.kakaocdn.net`, 이름 `daum.Postcode` → `kakao.Postcode` — **2026-11-30 종료**, 옛 주소면 검색 창 위에 개발자 공지가 고객에게 보임 | PC 5 알림 `docs/handoff/rider-app/2026-11-17-pc1-postcode-domain.md`(라이더앱은 #63 에서 바꿈) | 고객앱 `postcode_screen.dart` |
| 29 | ~~**"받았어요"(고객 수령 확인)** — 주문 상세 배송 카드에 픽업 뒤·전달 전일 때 버튼, 확인 대화 뒤 `POST /deliveries/{id}/receipt-confirmations`~~ 2026-11-18 끝(커밋은 worklog) | execution 0.20.0, `clients/customer-app/2026-11-17-request-receipt-confirmation.md` | 사용자 2026-11-18 "이 요청 문서에 추가하고 바로 만들어". 실서버 확인은 30. 못 받음 신고는 6 |
| 31 | ~~**반품 회수비 결제** — 처리 내역(클레임 상세)에 결제 카드, 토스 결제위젯·승인 결과 확인·실패 뒤 새 시도~~ 2026-11-18 끝(커밋은 worklog) | claim 0.2.0·0.3.0, `clients/all/2026-11-17-request-return-recovery.md` §3 | 사용자 2026-11-17 미뤄 둔 요청 → 2026-11-18 "진행해". 실서버 확인은 32 |
| 33 | **문의 "상담 종료"** — 고객이 답변 받은 문의를 스스로 끝내기 | `clients/all/2026-11-17-request-inquiry-close.md` | 2026-11-17 미뤄 둔 요청. 2026-11-18 할 일 문서에 올림 |
| 35 | 리뷰 요청 알림 `REVIEW_REQUESTED`(알림함만, 대상 ORDER) — 누르면 그 주문의 리뷰 쓰기 화면 | notification 0.4.2, `clients/customer-app/2026-11-18-notice-gap-a-built.md` §1 | 알림함 목적지 매핑(`noticeFromContract`)에 종류 하나 |
| 36 | 주문 내역 카드 — 대표 상품 "<상품명> 외 N개"(`representativeItem`·`itemCount`), 배송 방식(`deliveryMode`), 썸네일은 productId 로 | order 0.12.0, 같은 문서 §2 | 2026-11-02 전 주문은 `productName` null → "상품 N개" |
| 37 | 주문 내역 기간·상품명 검색(`from`·`to`·`q`) — **조건 없으면 최근 3개월만 옴**(배포 뒤 지금 앱도 3개월 전 주문이 안 보임) | order 0.12.0, 같은 문서 §3 | 다음 쪽은 같은 조건 + cursor. 레퍼런스 캡처의 주문 내역 필터 먼저 |
| 38 | 주문 내역 삭제(숨기기) `POST /orders/{id}/hides` — 끝난 주문만(409 `ORDER_NOT_FINISHED`), 되돌리기 없음 → 확인 창 | order 0.12.0, 같은 문서 §4 | 멱등 키·출처 헤더 |
| 39 | 장바구니 최소 주문 금액 진행 바 — `Cart.minOrderAmount`·`minOrderShortfall`(null 이면 바 숨김, 0 으로 바꾸지 않음) | cart 0.2.0, 같은 문서 §5 | 안내용 — 최종은 주문서 견적 |
| 40 | 품절 처리 "다음에도 적용" — 주문서 체크 때 `PUT /me/order-preferences`, 다음 주문서 기본값은 `GET` | customer 0.4.0, 같은 문서 §6 | **customer 계약 다시 만들기 = 25(CU-1)와 함께**(지금 다시 만들면 컴파일 안 됨) |
| 41 | 배달 지연 신고 — 배송 현황·진행 중 주문에 "늦어요" → 문의 `deliveryIssue: DELAYED`(진행 중 주문만, 그 밖 422 `ORDER_NOT_IN_PROGRESS`) | case 0.23.0, 같은 문서 §7 | 6(배송 신고)과 같이 |
| 42 | FAQ 목록·검색 `GET /customer-assistant/faqs(/{id})` — 회원만(비회원 403), `answer` 는 마크다운 | customer-assistant 0.2.0, 같은 문서 §8 | LAN 은 배포·색인 전 422 `CONFIG_REQUIRED`. 마크다운 그리기 라이브러리 추가는 사용자 확인 먼저 |
| 34 | 고객센터가 대신 취소한 주문의 클레임이 처리 내역에 보이는지(채널 `CS`) — 앱은 보이기만 | claim 0.4.0(2026-11-18), `clients/customer-app/2026-11-18-notice-reference-gap-update.md` §1 | 지금 앱 표시(목 데이터)부터 확인. 계약 다시 만들기는 25(CU-1)와 함께 |

## 2. 백엔드에 회신할 것

| # | 할 일 | 근거 |
|---|---|---|
| 11 | **레퍼런스 대비 빠진 기능 A 목록의 착수 순서 회신**(오늘 순서 5번) (11-18 갱신 §2 "백엔드 없는 것"은 백엔드 쪽 사용자 결정 "A해줘"로 8가지를 만들어 35~42 로 옮김. 교환·현금영수증·단위 가격·라이더 통화·실시간 상담·매장 위치는 "나중에" — 백엔드 `pending-user-decisions.md` L-8~L-13) | `clients/customer-app/2026-11-17-notice-reference-gap.md`·`…/2026-11-18-notice-reference-gap-update.md` — 회신은 `docs/handoff/customer-app/` 또는 PR 본문. 고르는 건 사용자 |
| 12 | 재고 표시 요청 등록 — 목록 카드의 센터 재고 상태(일시품절), 상세·목록의 "N개 남음" 기준·개수 | 2026-11-17 조사(storefront·search 에 재고 필드 없음, product-content·cart 의 LOW 는 "아직 쓰지 않음"). 레퍼런스 대비 C(정책 결정 대기)에 "카드의 남은 수량" — **사용자 결정 뒤** `backend-requests.md` 에 BR 등록 |

## 3. 사용자 결정 기다림

| # | 물음 | 맥락 |
|---|---|---|
| 13 | 지금 주소로 배달하지 않아 숨긴 상품이 다시 보일 때 자동으로 다시 선택할지 | `e7d937f` — 지금은 선택이 꺼진 채 보임 |
| 14 | 장바구니에 "지금 주소로 배달하지 않는 상품 N개는 숨겼어요" 한 줄을 넣을지 | 같음 — 지금은 안내 없음 |
| 15 | "10개 미만이면 N개 남음" 표시를 할지(정책) | 위 12 와 같이 |
| 16 | lock 커밋 메시지의 백엔드 SHA 바로잡기 기록(`8fb3058`, `0a57b9f`)을 남길지 | 기능 영향 없음 |

## 4. 실서버·실기기에서 확인할 것 (목 모드로만 확인함)

| # | 기능 | 커밋 |
|---|---|---|
| 17 | 주문서 진입 전 재고 부족 422 → 장바구니 표시, 배달 안 하는 상품 숨김 | `e7d937f` |
| 18 | 화면용 주문번호 8자리(주문 상세·결제 완료) | `53fb6c9` |
| 19 | 오배송 다시 배송비 9,000원 결제·환불 고르기 — LAN 에 고객 잘못 오배송 건이 있어야 함(백오피스 접수부터) | `e9115ca` |
| 20 | 예약 시간 변경 거절 사유·오늘·내일 슬롯 | `aba8b12` |
| 21 | 알림함(쌓이는지) — 휴대폰 푸시는 27 | 2026-11-16 |
| 27 | **휴대폰 푸시(폰 연결 필요)**: Firebase 콘솔 테스트 메시지 수신 → 로그인 뒤 `GET /me/push-tokens` 에 단말 → 주문 취소·배송 출발 때 푸시가 오고 누르면 그 화면, 주문 확정은 알림함에만 → **Google 로그인 그대로**(빌드 값 `googleServerClientId` 꼭 넣어 빌드). 결과는 `docs/handoff/customer-app/2026-11-18-backend-customer-push-fcm-reply.md` §2 에 덧붙임 | `7cbe1f2`, 2026-11-18 푸시 누르면 목적지 |
| 28 | Firebase 프로젝트 합치기(백엔드는 2026-11-18 `pmart-123` 으로 합침 — 회신 `clients/customer-app/2026-11-18-reply-customer-push-q6-q8.md`. 옛 `pmart-42b37` 단말 토큰은 새 키로 못 보내니 로그인하면 앱이 다시 등록): 사용자가 `pmart-123` 에 `com.pmart.customer_app` 을 등록해 받은 `google-services.json` 으로 `apps/customer_app/android/app/google-services.json`(git 제외)만 바꾼 뒤 27 다시 | 코드 변경 없음 |
| 30 | "받았어요" 실서버: 배송 중(픽업 뒤) 주문에서 버튼 → 완료로 바뀌고 라이더 앱에도 완료, 도착 예정 + 20분에 알림함 "상품을 받으셨나요?" → 누르면 주문 상세. **백엔드 LAN 배포 먼저 확인**(요청서 작성 때 배포 전) | 2026-11-18 받았어요 |
| 32 | 반품 회수비 실서버: 백오피스(고객센터)에서 고객 사유 반품 접수 → 고객앱 처리 내역에 9,000원 결제 카드 → 토스 결제 → 반품 진행으로. 결제창 닫기 → 다시 결제(새 시도). 회사 잘못 반품은 카드 없음 | 2026-11-18 반품 회수비 |

## 5. 다른 PC 일 중 PC 1 이 챙길 것

| # | 할 일 | 맥락 |
|---|---|---|
| 22 | PC 3 의 실서버 PDA 피킹(장바구니) → 포장(패킹대) → 출하대기 확인 결과 받기 | #57(`c6f4930`), 백엔드 #91 배포. handoff README·PR #57 댓글 |
| 23 | mfc-fulfillment 0.9.0(백오피스 처리 대기 F-4) — 백오피스 처리 대기의 MFC 목록이 켜지면 PC 2 PR 검토 | 백엔드 #95(PC 3). mfc_app 은 영향 없음 |

## 6. 사용자가 백엔드에 전달할 것

| # | 문서 | 상태 |
|---|---|---|
| 24 | `docs/handoff/mfc-app/2026-11-17-backend-pick-reject-reason.md`(실적 거절 사유를 응답·조회에) | #57 로 main 에 들어옴 — 전달 여부 확인 필요 |
