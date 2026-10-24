SENT 준비(`docs/handoff/2026-10-24-backend-customer-gaps.md`) |SENT 준비(`docs/handoff/2026-10-24-backend-customer-gaps.md`) |SENT 준비(`docs/handoff/2026-10-24-backend-customer-gaps.md`) |SENT 준비(`docs/handoff/2026-10-24-backend-customer-gaps.md`) |SENT 준비(`docs/handoff/2026-10-24-backend-customer-gaps.md`) |SENT 준비(`docs/handoff/2026-10-24-backend-customer-gaps.md`) |# 백엔드 요청 목록 (계약 공백·확인 필요)

클라이언트 구현에 필요한데 `../pmart-backend/contracts` 에 없거나 모호한 것. **이 저장소에서 백엔드를 고치지 않는다.** 항목은 사용자를 통해 백엔드 담당(다른 계정)에 전달한다.
상태: `OPEN`(미전달) / `SENT`(전달) / `AGREED`(합의, 계약 반영 대기) / `DONE`(계약 반영됨, 커밋 SHA) / `WONTFIX`.
목(mock)에서 임시로 쓰는 경우 코드에 `// BR-xx` 를 표시한다.

기준: pmart-backend `75fe667` (2026-10-23).

| ID | 우선 | 앱 | 요약 | 상태 |
|---|---|---|---|---|
| BR-01 | 높음 | 고객 | 토스 결제창 진입 정보·결제 인증 결과 전달 경로가 고객용 API에 없음 | OPEN |
| BR-02 | 높음 | 라이더·MFC·관리자·기사 | 고객 외 주체(라이더·점원·운영자·간선기사) 로그인·전화 본인확인 API 없음 | OPEN |
| BR-03 | 높음 | 전체(특히 웹) | 사용자 토큰 보관 방식(쿠키/CSRF vs Bearer) 미정, 게이트웨이가 `Cookie` 제거 | OPEN |
| BR-04 | 중간 | 관리자 웹 | 게이트웨이 CORS 설정 없음 — 웹 배포 출처 결정 필요 | OPEN |
| BR-05 | 높음 | MFC | PDA 작업 목록·작업 상세(피킹 지시 행) 조회 API 없음 | AGREED (`e817184`, check 통과 `3916354`) |
| BR-06 | 높음 | 라이더 | 배차 제안 수신 채널·대기 목록(일반배차모드) API 없음 | AGREED(부분, `e817184`+`f4dd171`, check 통과 `3916354`) — 푸시·SSE·대기 목록 보류 |
| BR-07 | 높음 | 라이더·고객·관리자 | 파일 업로드 API 없음(`photoRefs` 는 존재하지 않는 "file-service" 참조) | OPEN |
| BR-08 | 낮음 | 전체 | `X-Source-System` 클라이언트 값 목록 확정 | OPEN |
| BR-09 | 중간 | 고객·라이더 | 푸시 토큰(FCM/APNs) 등록·해제 API 없음 | OPEN |
| BR-10 | 중간 | 관리자 웹 | 상세 화면용 조회 경로(bff 미제공 화면)·내보내기/다운로드 API | OPEN |
| BR-11 | 중간 | MFC | 점원 화면의 피킹·패킹·출고대기 현황, 입고 예정 화면의 조회 경로 | OPEN |
| BR-12 | 낮음 | 고객 | 고객 노출 문구용 상태 코드(FUL_*, CXL_* 등) 와 계약 enum 대응 확정 | OPEN |
| BR-13 | 중간 | 고객 | 배송 방식별 현재 가능 여부·불가 사유·예상시간·배달팁 조회 없음 | SENT 준비(`docs/handoff/2026-10-24-backend-customer-gaps.md`) |
| BR-14 | 중간 | 고객 | 견적에 최소주문 부족액·첫 구매 무료 4가지 상태 없음 | SENT 준비(`docs/handoff/2026-10-24-backend-customer-gaps.md`) |
| BR-15 | 중간 | 고객 | 반품·교환 자격(품목별 가능 여부·기한·사유) 조회와 사유별 증빙 요건 없음 | SENT 준비(`docs/handoff/2026-10-24-backend-customer-gaps.md`) |
| BR-16 | 중간 | 고객 | 고객 배송 문의 접수(지연·오배송·파손·누락·미수령) 경로 없음 | SENT 준비(`docs/handoff/2026-10-24-backend-customer-gaps.md`) |
| BR-17 | 낮음 | 고객 | 현금영수증 신청·발급 가능 여부·발급 결과 조회 없음 | SENT 준비(`docs/handoff/2026-10-24-backend-customer-gaps.md`) |
| BR-18 | 낮음 | 고객 | 주문서 이탈 시 초안 처리(명시적 취소 경로 여부) 확인 | SENT 준비(`docs/handoff/2026-10-24-backend-customer-gaps.md`) |

---

## BR-01 결제 진입·결과 전달 (고객앱)
- 현황: `POST /order-drafts/{draftId}/checkouts` 는 202 `CommandResponse` 만 반환. PG 진입 정보(`clientKey`, `pgOrderId`, `amount`, `orderName`, `checkoutUrl`, `expiresAt`)는 `payment-service` **내부** `POST /internal/payments` 의 `StartPaymentResponse` 에만 있다. `OrderDraft` 스키마에도 없다.
- 토스 결제 인증 후 `successUrl` 로 돌아오는 `paymentKey/orderId/amount` 를 서버에 전달할 고객용 경로가 없다(웹훅만 존재). `successUrl/failUrl` 을 누가 정하는지(앱 딥링크 vs 서버 URL)도 없음.
- 요청: (a) `GET /order-drafts/{draftId}` 의 `nextAction=PAY` 일 때 `checkout` 진입 정보를 포함하거나 별도 조회 경로, (b) 결제 인증 결과 전달 명령 + 짝 조회(또는 서버 `successUrl` 처리 방식 명시), (c) 모바일 딥링크 스킴 합의.
- 클라이언트 원칙(변경 없음): 결제창 복귀만으로 완료 표시 금지, 결과 불명 시 원시도 조회.

## BR-02 고객 외 주체 인증
- 현황: auth-service 외부 경로는 고객 소셜 로그인 3개 + 토큰 갱신·로그아웃·세션 조회뿐. `Session.principalType` 에는 RIDER/OPERATOR 가 있다. `POST /riders/signups` 는 `phoneVerificationRef`(auth 본인확인 결과) 를 요구하지만 본인확인 API가 없다.
- 요청: 라이더 로그인(아이디·비밀번호 또는 전화 OTP), 전화 본인확인, MFC 점원 로그인(직원 ID 바코드 기반 여부), 운영자 로그인(BO-Q01: IAM·추가 인증), 간선기사 로그인(2단계).

## BR-03 토큰 보관 방식
- auth-service.yaml `info.description`: "쿠키/CSRF 방식은 [팀 확인 필요]". 게이트웨이 `default-filters: RemoveRequestHeader=Cookie`.
- 클라이언트 임시안: 모바일은 Bearer + refresh(보안 저장소). 웹은 access token 메모리 보관. 웹 refresh 를 HttpOnly 쿠키로 할지 결정 필요.

## BR-04 CORS
- 게이트웨이에 CORS 설정 없음. 개발은 Vite 프록시로 우회 가능. 운영에서 관리자 웹을 게이트웨이와 같은 출처로 배포할지, 허용 출처를 둘지 결정 필요.

## BR-05 MFC 작업 목록
- 현황: `mfc-fulfillment` 외부 경로는 `POST /tasks/{taskId}/executions`, shipments/packages 뿐. 작업 생성은 `/internal/work-orders`. 점원이 "내 작업"을 받을 경로는 `mfc-capacity GET /assignments`(배정)뿐이고, 피킹 지시 행(로케이션·SKU·LOT·지시수량·기피킹량)을 담은 작업 상세가 없다.
- 요청: `GET /tasks?assignee=me&type=&status=`, `GET /tasks/{taskId}`(지시 행·잔량·버전), 작업 시작(claim) 명령(WK-03 "한 요청만 성공").
- 회신(2026-10-24, `../pmart-backend/docs/handoff/2026-10-24-clients-reply-high.md`): 수용. `d3ce55c` + 검토 수정 `e817184`.
  - `GET /tasks?mfcId=&assignee=me&type=&state=`: 파라미터는 `status` 가 아니라 `state`. 기본값은 ASSIGNED, IN_PROGRESS이고 BLOCKED는 빠짐.
  - `GET /tasks/{taskId}`: `lines[].pendingQty`, `pendingExecutions`, `activeStart`.
  - `POST /tasks/{taskId}/starts` 와 짝 조회 `GET …/starts/{requestId}`.
  - 서비스 빌드는 미검증이고 서버 구현 전까지 501이므로 목으로만 쓴다. `assignee=me` 는 BR-02, 실제 배정은 mfc-capacity 수동 배정 계약에 의존한다.
- 추가 질문: 시작 503의 의미, 짝 조회 여부, 같은 키 재전송 → `docs/handoff/2026-10-24-backend-br05-start-503.md`
- 추가 회신(`../pmart-backend/docs/handoff/2026-10-24-clients-reply-br05-start-503.md`, 계약 `c609a4d`):
  - 503은 항상 `DEPENDENCY_UNAVAILABLE` 이고, 시작 안 됨이 확정이다. 판정이 기록되지 않으므로 같은 키로 보내면 다시 판정한다.
  - 짝 조회 404는 확정이 아니다.
  - 응답이 없으면 같은 키로 재전송하는 것이 기본 확정 방법이다.
  - 처리표는 `docs/apps/mfc-app.md` §3-1. 상태는 AGREED 유지(빌드 미검증).

## BR-06 라이더 배차 제안
- 현황: `GET /offers/{offerId}`, `POST /offers/{offerId}/responses` 만 있음. 제안이 라이더에게 도착하는 채널(푸시·SSE·폴링)과 일반배차모드의 대기 목록 조회가 없다.
- 요청: `GET /riders/me/offers`(활성 제안, 남은 시간) 또는 SSE 스트림, 일반배차모드 대기 목록.
- 회신(`../pmart-backend/docs/handoff/2026-10-24-clients-reply-high.md`, `d3ce55c` + `e817184`): 부분 수용.
  - 수용: `GET /offers?state=` 는 본인 제안만 준다. state를 생략하면 SENT이면서 만료 전인 것만 나온다. 응답에 `serverTime` 이 있고, 각 제안에 `remainingSec` 이 있다. 경로는 게이트웨이 라우팅 때문에 `/riders/me/offers` 가 아니라 `/offers` 로 정해졌다.
  - 보류: 푸시·SSE 전달 채널(notification 결정 대기)과 일반배차모드 대기 목록(업무 문서 공백). 푸시 토큰은 BR-09에서 따로 회신한다.
  - 클라이언트 반영: `docs/apps/rider-app.md` "제안 수신과 남은 시간".
- 추가 질문: 폴링 간격 → `docs/handoff/2026-10-24-backend-br06-offer-polling.md`
  - 회신(`../pmart-backend/docs/handoff/2026-10-24-clients-reply-br06-offer-polling.md`, `f4dd171`, lint만 통과, 빌드 미검증): 수용. 응답에 `pollAfterSec` 이 추가됐다(잠정 5초). 받을 수 없는 상태면 null이다. 처리율 제한은 JWT subject 단위 단일 버킷이다. 백그라운드에서 놓쳐도 되는지는 업무 결정 대기다(푸시·BR-09와 함께). 클라이언트 반영: `rider-app.md`.

## BR-07 파일 업로드
- 현황: `delivery-execution` 전달 완료가 `photoRefs`(설명: "file-service 업로드 완료 참조")를 요구하지만 file-service 는 서비스 목록·계약에 없다. 리뷰 사진·CS 첨부·회수/파손 증빙·간선 인계 증빙도 같은 문제.
- 요청: 업로드 경로(사전 서명 URL 등), 용량·형식·개수 제한, 업로드 성공과 명령 성공을 분리하는 참조 ID 규칙.

## BR-08 X-Source-System 값
- `_common.yaml` 예시는 `customer-app`. 클라이언트 제안값: `customer-app`, `rider-app`, `mfc-app`, `backoffice-web`, `driver-app`. 게이트웨이 `/gateway/routes` 의 앱 구분(`CUSTOMER, RIDER, STORE, DRIVER, ADMIN`)과의 대응 확인.

## BR-09 푸시 토큰
- notification-service 채널에 `APP_PUSH` 가 있으나 기기 푸시 토큰 등록·해제 경로가 없다.

## BR-10 관리자 웹 조회·내보내기
- bff `views` 8개 외 화면(승인 상세·결정 이력, 사건 상세, 센터·캘린더, 감사, 대량 변경, 정책 참조, 권한·대행 목록 등)은 원서비스 경로를 직접 호출해야 하는지 확인. 게이트웨이 라우트 존재 여부 포함.
- 내보내기/다운로드 생성 API 없음(BO-25: 다운로드 시 현재 권한 재검사).
- 운영자 권한·대행 조회는 auth 내부 API만 존재.

## BR-11 MFC 관리자·입고 현황
- bff `/views/packing-handover`(mfcId) 는 관리자 웹용. PDA/점원 화면에서 같은 정보를 쓸 수 있는지, `mfc-inbound GET /inbound-promises` 의 ETA 포함 여부 확인.

## BR-12 고객 노출 상태
- Commerce 문서는 FUL_*/CXL_*/RET_* 코드와 문구를 쓰지만 계약은 `OrderStatus`, `Shipment.state`, 클레임 상태를 쓴다. 고객 문구 매핑표(Commerce C 621, 1845 "인터페이스 승인 때 확정")를 합의 필요.

## BR-13 배송 방식별 가능 여부·예상시간·배달팁 (고객앱 배송 방식 선택·홈 요약)
- 근거: Commerce :1552 "표시: 한집/알뜰/예약 가능성·예상시간·배달팁·오늘/내일 1시간 슬롯·정원/마감·미설정 사유", :1524·:1530 "권역 밖·휴무·정원 소진·설정 확인 중·조회 실패를 구분해 안내", :1520 00~08시 실제 배송 없음.
- 현황(`f4dd171`): `GET /delivery-conditions` 는 제공 방식 목록(`deliveryModes`)과 `timeRestriction` 만 준다. 지금 한집·알뜰이 가능한지, 불가 사유(심야·휴무·정원·미설정), 예상 소요시간 범위, 방식별 배달팁(적용 전·후)이 없다. `GET /slots` 는 예약 슬롯만 다룬다.
- 요청: 주소(또는 mfcId)와 장바구니 기준으로 방식별 `{mode, availability, unavailableReason, etaMinRange, deliveryTip, deliveryTipReason}` 를 주는 조회. 심야에는 "예약만 가능"과 가장 빠른 도착 슬롯을 서버가 판정한다.
- 클라이언트는 기기 시계로 심야 여부를 판단하지 않는다. 회신 전에는 목으로만 쓴다.

## BR-14 견적의 최소주문 부족액·첫 구매 상태
- 근거: Commerce :1706 "미달은 부족액·불가품목/슬롯 사유 표시", :2821 "최소 주문 15,000원은 오퍼·프로모션 후, 쿠폰 전 상품액", :1490-1512 첫 구매 무료 4가지 상태(적용 예상/다른 주문에서 확인 중/적용 확정/적용 불가).
- 현황: `Quote` 에 `minOrderSatisfied`(boolean)와 `deliveryTipReason`(`FIRST_PURCHASE` 등)만 있다. 부족액과 첫 구매 상태가 없다. 장바구니(`Cart.selectedItemAmount`)는 "견적 아님"이라 장바구니 단계에서는 최소주문·배달팁을 보여줄 서버 값이 없다.
- 요청:
  1. `Quote` 에 최소주문 기준액과 부족액(`minOrderShortfall`)을 넣는다.
  2. 첫 구매 상태 enum을 넣는다.
  3. 장바구니 화면에서 최소주문 미달 여부와 배달팁 예상을 서버 값으로 받을 경로가 있는지(아니면 주문서 진입 후에만 표시하는지) 정해 준다.
- 참고: 30,000원 판정 상품액은 문서 안에서 :1621("기본단가×수량")과 :2857·:2760("오퍼·프로모션 후, 쿠폰 전")이 다르게 적혀 있다. 계약 `itemAmount` 설명은 후자다. 확인을 부탁한다.

## BR-15 반품·교환 자격과 증빙 요건
- 근거: Commerce :1990 / OMS :336 [확정 정책] 일반 7일, 신선 24시간, 하자·오배송·광고 상이 교환은 3개월 또는 인지 후 30일. Commerce :1986 사유·사진 접수.
- 현황: `ClaimReason` enum(10종)과 `POST /claims` 는 있다. 접수 전에 품목별 가능 여부·불가 사유·기한을 조회할 경로가 없다. 리뷰에는 `GET /me/review-eligibilities` 가 있다. 사유별 사진·상세 필수 여부와 개수·용량 상한도 없다(첨부 업로드 자체는 BR-07).
- 요청: 주문(또는 주문 품목)별 `{orderLineId, claimTypes[RETURN|EXCHANGE], eligible, ineligibleReason, deadline}` 조회, 사유별 증빙 요건(사진 필수·최소/최대 개수·상세 필수·글자 수).
- 클라이언트는 수령 시각으로 기한을 계산하지 않는다.

## BR-16 고객 배송 문의 접수
- 근거: Commerce :1986 "배송 중/완료 주문에서 지연·오배송·파손·품질·누락·미수령·기타 문의를 접수… 오배송은 원주소와 전달 사진 확인, 라이더 연락·채팅/상담 경로", :2238 [팀 확인 필요] 상담 채널·운영 시간·첨부·전달 사진 공개 여부, :2174 고객센터 화면 구성(AI 상담은 필수 범위 아님).
- 현황: `case-service` 의 `/cs-intakes` 는 운영자 접수, `/help-requests` 는 라이더 도움요청이다. 고객이 직접 문의를 접수하고 결과를 조회할 경로가 없다. 고객이 전달 사진을 조회할 경로도 없다.
- 요청: 고객 문의 접수와 조회(주문·배송 건·품목·사유·사진 참조, 멱등), 전달 사진 공개 여부와 조회 경로, 상담 채널 결정(채팅/전화)과 운영 시간 제공 방식.

## BR-17 현금영수증
- 근거: Commerce :1771 "현금영수증은 신청 정보, 실제 발급 가능 여부, 발급 결과 조회를 구분한다. 개인/사업자 입력 화면이 있다는 이유만으로 모든 결제수단이 발급 가능하다고 안내하지 않는다."
- 현황: 계약에 현금영수증 관련 필드·경로가 없다.
- 요청: 1차 범위인지 확인. 1차라면 결제수단별 발급 가능 여부, 신청(개인 휴대폰/사업자 10자리), 발급 결과 조회.

## BR-18 주문서 이탈 시 초안 처리
- 근거: Commerce :109 "화면 이탈이나 제한시간 경과만으로 … 확보를 해제하지 않는다", :1563 "앱에서 타이머만으로 점유 해제하지 않는다". 견적은 초안 생성 후 10분에 만료된다(`Quote.quoteExpiresAt`).
- 현황: `order-drafts` 에는 POST, GET, `/checkouts` 만 있고 취소 경로는 없다.
- 질문: 고객이 주문서에서 뒤로 나갈 때 클라이언트는 아무 호출도 하지 않고 초안 만료를 기다리면 되는가? 아니면 명시적인 초안 취소(확보 해제) 경로를 둘 계획인가? 회신 전 클라이언트 처리안은 "호출 없이 이탈, 재진입 시 GET으로 재검증"이다.
