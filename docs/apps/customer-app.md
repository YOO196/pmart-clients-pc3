# 고객앱 (customer_app, Flutter)

근거: `../pmart-backend/docs/business/Commerce-business-logic.md`(C), `OMS-business-logic.md`(O), `flows/order-checkout-saga.md`, `cancel-vs-handover.md`, `return-exchange-refund.md`, 계약 `contracts/openapi/*.yaml`. 숫자는 대략적인 줄 번호. 화면 ID 전체 색인은 C 부록 I.1(≈3510).
Commerce 문서의 PPC = MFC. 1차 제외: 쿠폰·프로모션·할인 배너·찜·재입고 알림·공유·AI 상담. (2026-10-24 레퍼런스 검토 후 유지 확정. 포인트 적립·1+1·증정 배지도 프로모션에 포함해 제외. `customer-app-design-review.md`)

## 1. 화면과 API

| 영역 | 화면 ID | API (gateway `/api/v1`) | 공개 |
|---|---|---|---|
| 로그인 | SCR-AUTH-001 | `POST /auth/social-logins`, `GET /auth/social-logins/{id}`, `POST …/{id}/completions`, `POST /auth/tokens`, `POST /auth/logouts`, `GET /auth/sessions/current` | 로그인 3·갱신 공개 |
| 약관 동의 | SCR-CONSENT-001 | `GET /me/consents`, `POST /me/consent-changes` (+짝 조회) | |
| 주소 | SCR-ADDRESS-001, ADDRESS-EDIT-001 | `GET/POST /me/addresses`, `PATCH/DELETE /me/addresses/{id}`, `POST /me/shopping-address-selections`, `GET /me/shopping-context`, 비회원 `POST/GET /guest-delivery-addresses` | 비회원 배송지 공개 |
| 홈 | SCR-HOME-001 | `GET /storefront/home`, `/storefront/tabs/{tabKey}`, `/storefront/sections/{id}/items`, `/storefront/banners` | 공개 |
| 카테고리·검색 | SCR-CATEGORY/SEARCH/LIST/FILTER-001 | `GET /categories/tree`, `GET /search/products`, `/search/suggestions`, `/search/filters`, `GET/DELETE /me/recent-searches` | 검색 공개 |
| 상품 | SCR-PRODUCT-001, OPTION-001 | `GET /product-contents/{productId}`, `GET /product-contents?…`(카드 일괄), `GET /prices`, `GET /products/{id}/reviews` | 리뷰 공개 |
| 장바구니 | SCR-CART-001, CART-MERGE-001 | `POST /carts`, `GET /carts/{id}`, `POST /carts/{id}/items`, `PATCH/DELETE /carts/{id}/items/{itemId}`, `GET /carts/{id}/change-requests/{requestId}`, `POST/GET /carts/{id}/merges` | 비회원은 비회원 토큰(`POST /auth/guest-sessions`, typ=GUEST, ADR-0022). 병합은 회원 토큰 + `X-Guest-Token` |
| 배송 방식·슬롯 | SCR-DELIVERY-SELECT-001 | `GET /slots`, `GET /delivery-conditions` | |
| 주문서·결제 | SCR-CHECKOUT-001, PAYMENT-001 | `POST /order-drafts`, `GET /order-drafts/{id}`, `POST /order-drafts/{id}/checkouts` + **토스 결제(BR-01)** | |
| 주문내역·상세 | SCR-ORDER-LIST/DETAIL-001 | `GET /orders`, `GET /orders/{id}` | |
| 배송 추적 | SCR-TRACK-001 | `GET /deliveries/{id}/eta`, `GET /deliveries/{id}/stream`(SSE) | |
| 예약시간 변경 | SCR-RESCHEDULE-001 | `POST /orders/{id}/reservation-time-changes` (+짝 조회) | |
| 취소·반품·교환 | SCR-CANCEL-001, CLAIM-FORM/DETAIL-001 | `POST /claims`(CANCEL/RETURN/EXCHANGE), `GET /claims`, `GET /claims/{id}`, `POST /claims/{id}/withdrawals`, `GET /claims/{id}/refunds` | |
| 리뷰 | SCR-REVIEW-LIST/EDIT-001 | `GET /me/review-eligibilities`, `POST /reviews`, `PATCH/DELETE /reviews/{id}` | |
| 알림 | SCR-NOTICE-001 | `GET /me/notifications`, `…/{id}`, `POST …/{id}/reads`, `GET /me/notification-settings`, `POST /me/notification-setting-changes` | |
| 마이·탈퇴 | SCR-ACCOUNT-001, WITHDRAW-001 | `GET /me`, `POST /me/profile-changes`, `POST /me/withdrawals`, `GET /me/withdrawals/{id}`, `POST …/revocations` | |
| 고객센터 | SCR-SUPPORT-001, CHAT-001 | 고객용 경로 없음(case `cs-intakes` 는 운영자 접수). `[결정 필요]` 상담 채널 | |

비회원: 둘러보기·장바구니까지. 주문서부터 로그인.

## 2. 화면별 핵심 규칙

**로그인·동의** (C 672-845)
- 사용자 취소 → 원래 화면 복귀·장바구니 유지. 제공자 장애 → 재시도. `AUTH_UNKNOWN` → 원인증 조회.
- 423 `AUTH_RESTRICTED`(15분 5회 → 10분): `retryAfterSeconds` 표시. 사용자 취소·제공자 장애는 횟수 제외(서버 판정).
- 같은 이메일로 계정 병합 안 함. 필수/선택 동의 분리, 선택 거부해도 구매 가능. 동의·앱 알림 설정·OS 권한은 서로 다른 값.
- 일반 로그인 후 회원 장바구니로 전환(자동 병합 없음). 주문서에서 로그인(`purpose=CHECKOUT`)하면 병합 확인 화면.
- 실서버 제공자는 Google 만(백엔드 ADR-0019, 2026-10-30). `google_sign_in` 으로 ID 토큰 → `providerToken`. serverClientId = 백엔드 안내의 웹 클라이언트 ID(`--dart-define=PMART_GOOGLE_SERVER_CLIENT_ID` 로 바꿀 수 있음). Android OAuth 클라이언트(패키지 `com.pmart.customer_app` + 서명 SHA-1) 등록 필요. 카카오·네이버 버튼은 실서버 모드에서 숨김(501). 애플은 Android 만 개발이라 없음(ADR-0002).
- 마이 탭에 로그인 제공자·계정(제공자 SDK 의 이메일, 기기 화면에만, 저장 안 함)을 보인다. 목 계정은 `mock-…@pmart.invalid`. 앱 재시작으로 복원한 세션은 계정 표시가 없다.
- 목 모드는 앱 모서리 "목 데이터" 띠와 로그인 화면 안내로 표시한다(목 로그인은 제공자 창 없이 항상 성공).
- 앱 시작 때 저장된 refresh token 이 있으면 `GET /auth/sessions/current` 로 세션 복원(서버가 확인한 CUSTOMER 만 회원). 로그아웃은 토큰 삭제 + Google 계정 선택 해제(서버 `POST /auth/logouts` 는 아직 부르지 않음).

**주소** (C 847-957)
- 검색 → 지도 확인 → 상세주소·출입 안내·라이더 요청 → 구분 → 기본 지정 → 저장. 위치 권한 거부 시 직접 검색 유지.
- "주소 저장 성공"과 "배송 가능 판정"을 따로 표시: 가능 / 지역 외 / 운영시간 외 / 센터 제한 / 확인 중 / 확인 실패.
- 쇼핑 주소 변경 시 장바구니를 비우지 않고 재검증, 구매 불가 품목은 사유 표시·선택만 막음.
- 결제 후 주소·연락처·요청사항 변경 불가. 입력 길이 상한은 하드코딩 금지(`[결정 필요]` C 881).

**홈·목록·검색** (C 971-1218)
- 영역별 부분 실패는 그 영역만 재시도. 진행 주문 조회 실패를 "주문 없음"으로 표시하지 않음.
- 일시품절은 목록 뒤·담기 막음, 판매중지는 제외. 정렬: 기본·인기·신규·가격↑↓·별점(할인율순 없음).
- 필터는 임시 선택(적용/초기화/닫기 = 기존 유지), 결과 0개면 적용 막음. 연속 검색은 마지막 요청만 반영. 상세에서 복귀 시 검색어·필터·스크롤 복원.

**상품** (C 1068-1250)
- 카드: 이미지·이름·규격·기본가·100g/100mL당 가격·별점·리뷰 수·남은 수량·`+`. "1개 남음"은 안내일 뿐 확보 아님.
- E(낱개)/B(밀봉 묶음) 별도 SKU. 같은 기초상품 낱개 환산 합계 10개 상한(장바구니 포함, 서버 검증).
- 리뷰 집계 실패를 0점·0건으로 표시하지 않음.

**장바구니** (C 1265-1393)
- 수량은 절대값 설정(합산 아님), 서버 확정값만 반영(`cartVersion`). 상태 `CART_STABLE / CHANGE_PENDING / CHANGE_UNKNOWN`.
- 선택 해제 ≠ 삭제. 1에서 `-` 는 삭제 확인. 합계는 선택된 구매 가능 품목만.
- 배지 숫자의 의미 `[결정 필요]`(C 1301).
- "주문하기"(장바구니) ≠ "결제하기"(PG 진입).

**배송 방식·슬롯** (C 1514-1597)
- 한집 / 알뜰 / 예약. 주문서 진입 전 선택, 주문서의 "변경"은 이 화면으로.
- 예약은 서버가 준 오늘·내일 1시간 구간만, 마감 구간 비활성. 00~08시 도착 슬롯 없음(심야에도 이후 시간 예약 가능).
- 슬롯 조회 실패는 자동 재시도 없이 "다시 조회". 슬롯 선택 ≠ 확보.

**주문서·결제** (C 1599-1849, O 245, saga)
- 표시: 품목, 방식·시간, 주소, 라이더 요청, 연락처·안심번호, 품절 시 처리(품절만 취소/전체 취소 + 다음에도 적용), 상품액·배달팁(무료 사유)·봉투값·총액, **견적 만료와 재고 예약 만료 각각**.
- 결제 버튼은 서버가 전 품목 예약·슬롯·여력·무료배달 자격 확보를 회신했을 때만(`OrderDraft.nextAction=PAY`, `resources.*`).
- 금액이 바뀌면 전후 비교 + 재동의(`RE_QUOTE_REQUIRED` 422).
- 결제 진행 문구: 결제 준비 중 → 결제 인증 중 → 결제 결과 확인 중 → 주문 완료 / 결제 실패 확인 / 결제 승인·주문 복구 중 / 취소·환불 확인 중.
- **결제창 복귀·인증 성공·PG 승인 어느 것도 "주문 완료"가 아니다.** `GET /order-drafts/{id}` 가 `orderId` 와 확정 상태를 줄 때만 완료 화면.
- 뒤로가기·새로고침·연타·재실행은 같은 결제 시도를 조회. 결과 불명(`PAYMENT_UNKNOWN`) 동안 "다시 결제" 금지. 앱 시작 시 진행 중 초안·주문을 서버에서 확인.

**주문·배송** (C 1851-1976)
- 상세는 주문 당시 스냅샷 + 원천별 `asOf`. 10,000g 초과는 분할배송: 배송별 품목·ETA·상태.
- 위치 조회 실패 ≠ 배송 실패. 다른 고객 주소·전체 동선 비노출.
- "같은 상품 담기"는 현재 조건 새 담기(과거 무료배달 승계 없음).

**예약시간 변경**: `상품준비`(PREPARING) 전만. `PENDING/CONFIRMED/REJECTED/UNKNOWN`, 불명이면 "변경 확인 중", 옛 시간·새 시간을 동시에 확정 표시하지 않음.

**취소·반품·교환** (C 1978-2158)
- 취소 버튼 = 요청 접수. 인계된 수량은 반품·회수로 연결(`NOT_CANCELLABLE`, `PARTIALLY_CANCELLED`).
- 기한(서버 판정, Asia/Seoul): 일반 7일, 신선 24시간, 하자·오배송·광고 상이 교환 3개월 또는 인지 30일. 교환 왕복 9,000원(단순 변심), 상품·배달 문제 0원. 회수·재배달 주소는 원주문 주소 고정.
- 품목별 승인/거절, 수거 수량과 반납 수량을 각각 표시. 철회는 심사 전까지, 그 사이는 "철회 확인 중". 첨부 성공 ≠ 접수 성공.
- 환불은 서버가 준 승인액·성공액·진행/불명액·잔액을 그대로 표시(앱 계산 금지). PG 성공 전 "완료" 표시 없음.

**리뷰**: 품목별 배송완료 후 14일, 1건, 최초 등록 3일 미만 수정, 삭제 후 재작성 불가. "리뷰 쓰기"/"내가 쓴 리뷰" 분리. 사진은 BR-07.

**알림**: 탭 → 최신 상태 화면(준비·출발·곧 도착→배송현황, 완료→주문상세, 리뷰→작성 목록, 취소·환불→처리내역). 읽음 ≠ 수령. 거래 안내는 끌 수 없음.

**탈퇴**: 재인증 → 접수 → 미결 의무 있으면 "탈퇴 처리 대기"+사유, 신규 구매 차단(조회·고객센터 유지). 대기 중 철회 가능, 마케팅 동의는 자동 복원 안 함.

## 3. 금액 표시 규칙 (서버 값 표시, 클라이언트 검증은 안내용)
| 규칙 | 값 |
|---|---|
| 최소 주문 | 순수 상품액 15,000원. 부족 시 "얼마 더 담기" + PG 진입 막음 |
| 배달팁 | 한집 4,000 / 알뜰·예약 3,000. 상품액 30,000원 이상 또는 첫 구매 0원(중복 차감 없음). 분할배송 추가 없음 |
| 봉투값 | 주문당 100원 1회 |
| 첫 구매 무료 | "적용 예상 / 다른 주문에서 적용 확인 중 / 적용 확정 / 적용 불가" 4가지(C 1490-1512) |
| 부분 품절 | 15,000원 미만이 돼도 재결제·배달팁 추가 없음 |
| 타이머 | 가격 동결 10분과 재고 예약 10분은 별개. 더 이른 만료를 안내. 재진입 시 타이머 재시작 금지. 앱 타이머로 확보 해제 금지 |

## 4. 상태 → 고객 문구 (잠정, BR-12)
| `OrderStatus` | 문구 |
|---|---|
| DRAFT / RESOURCE_PENDING | 주문 확인 중 |
| PAYMENT_PENDING | 결제 진행 중 |
| PAYMENT_UNKNOWN | 결제 결과 확인 중 |
| CONFIRMED | 주문 확인 |
| PREPARING | 상품 준비 중 |
| PARTIALLY_HANDED_OVER | 배송 준비 |
| IN_DELIVERY | 배송 중 |
| PARTIALLY_DELIVERED | 일부 전달 |
| COMPLETED | 배송 완료 |
| CANCELLED | 주문 취소 |
| EXPIRED | 주문 시간 만료 |

## 5. `[결정 필요]` (UI 영향)
입력 길이·주소록 상한, 장바구니 배지 의미, 남은 수량 노출 임계값, "마지막으로 둘러보기" 단계 여부, 안심번호, 08/09시 개시·슬롯 정원, 일반 취소 마감, 반품비·환불 시점, 리뷰 사진 제한, 첨부 제한, 상담 채널, 알림 문구·잠금화면 노출, 주문 조회 기간, 약관 구성, 주류 판매(PG 인증).
