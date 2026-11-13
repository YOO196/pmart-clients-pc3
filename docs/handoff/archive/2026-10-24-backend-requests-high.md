# [pmart-clients → pmart-backend] 계약 공백 요청 (우선순위 높음 6건)

- 보낸 쪽: pmart-clients 담당 (Flutter 앱 customer/rider/mfc + React backoffice)
- 기준 커밋: pmart-backend `75fe667` (2026-10-23)
- 원본 목록: `pmart-clients/docs/backend-requests.md` (전체 12건 중 높음 6건)
- 클라이언트는 이 항목들을 목(mock)으로 임시 구현하고 실제 연동은 계약 반영 후에 한다. 계약에 없는 경로는 호출하지 않는다.
- 회신 요청: 항목마다 **수용 / 대안 / 보류**와 계약 반영 커밋 SHA. 경로·필드 이름은 백엔드가 정하면 그대로 따른다(아래 경로는 예시).

---

## BR-01 고객 결제: PG 진입 정보와 결제 인증 결과 전달 (customer_app)
**현황**
- `order-orchestration` `POST /order-drafts/{draftId}/checkouts` 는 202 `CommandResponse` 만 반환한다.
- 토스 결제창에 필요한 값(`clientKey`, `pgOrderId`, `amount`, `orderName`, `checkoutUrl`, `expiresAt`)은 `payment-service.yaml` 의 **내부** `POST /internal/payments` → `StartPaymentResponse`(L251)에만 있다. `OrderDraft` 스키마에도 없다.
- 토스 인증 후 `successUrl` 로 돌아오는 `paymentKey / orderId / amount` 를 서버에 넘길 고객용 경로가 없다(웹훅만 있음). `successUrl` 과 `failUrl` 을 누가 정하는지도 없다.

**요청**
1. 고객이 결제 진입 정보를 받을 경로. 예: `GET /order-drafts/{draftId}` 의 응답이 `nextAction=PAY` 일 때 `checkout` 객체를 포함하거나, 별도 조회 경로를 둔다.
2. 결제 인증 결과 전달 명령과 그 짝 조회. 또는 서버가 `successUrl` 을 직접 처리한다면 그 방식을 명시한다.
3. 모바일 복귀 방식 합의: 앱 딥링크 스킴인지, 서버 URL을 거친 뒤 앱으로 돌아오는지.

**클라이언트 원칙**: 결제창에서 돌아온 것만으로 결제 완료를 표시하지 않는다. 결과가 불명이면 원래 시도를 조회해 확정한다.

## BR-02 고객 외 주체 인증 (rider_app, mfc_app, backoffice, driver_app)
**현황**
- `auth-service.yaml` 의 외부 경로는 고객 소셜 로그인 3개와 `/auth/tokens`, `/auth/logouts`, `/auth/sessions/current` 뿐이다.
- `Session.principalType` 에는 RIDER와 OPERATOR가 있는데 이들이 로그인할 경로가 없다.
- `POST /riders/signups` 는 `phoneVerificationRef`(auth 본인확인 결과)를 요구하지만 본인확인 API가 없다.

**요청**
1. 라이더 로그인(아이디·비밀번호 또는 전화 OTP)과 전화 본인확인 발급·검증.
2. MFC 점원 로그인. 직원 ID 바코드 스캔 방식인지, 공용 PDA에서 교대 로그인을 하는지 포함.
3. 운영자 로그인(BO-Q01: IAM 연동 여부, 추가 인증).
4. 간선기사 로그인은 2단계라 일정만 알려 주면 된다.

## BR-03 토큰 보관 방식 (전체, 특히 backoffice 웹)
**현황**
- `auth-service.yaml` 의 `info.description` 에 "쿠키/CSRF 방식은 [팀 확인 필요]"라고 되어 있다.
- 게이트웨이 `application.yml` L29 `default-filters: RemoveRequestHeader=Cookie` 때문에 쿠키 방식이 현재는 불가능하다.

**요청**: 확정 방식.
- 클라이언트 임시안: 모바일은 Bearer 토큰과 refresh 토큰을 보안 저장소에 둔다. 웹은 access token을 메모리에 둔다.
- 웹 refresh 토큰을 HttpOnly 쿠키로 둘지 결정해 주면 된다. 쿠키로 한다면 게이트웨이 필터와 CSRF 처리를 바꿔야 한다.

## BR-05 MFC 작업 목록·작업 상세 (mfc_app)
**현황**
- `mfc-fulfillment` 외부 경로는 `/tasks/{taskId}/executions`(+조회)와 shipments / packages / handover 뿐이다. 작업 생성은 `/internal/work-orders` 이다.
- 점원이 "내 작업"을 받을 수 있는 것은 `mfc-capacity GET /assignments`(배정)뿐이다.
- 피킹 지시 행(로케이션, SKU, LOT, 지시 수량, 이미 피킹한 수량, 잔량, 버전)을 담은 작업 상세가 없다.

**요청**
1. `GET /tasks?assignee=me&type=&status=` 작업 목록
2. `GET /tasks/{taskId}` 작업 상세: 지시 행, 잔량, 배정 버전
3. 작업 시작(claim) 명령. WK-03 "한 요청만 성공" 규칙을 따르고 짝 조회를 둔다.

## BR-06 라이더 배차 제안 수신 (rider_app)
**현황**
- `delivery-dispatch` 에는 `GET /offers/{offerId}` 와 `POST /offers/{offerId}/responses` 만 있다.
- 제안이 라이더에게 도착하는 채널(푸시, SSE, 폴링)이 정해져 있지 않다. 라이더는 `offerId` 를 알 방법이 없다.
- 일반배차모드의 대기 목록 조회도 없다.

**요청**
1. 활성 제안 조회 `GET /riders/me/offers`(남은 응답 시간 포함), 또는 SSE 스트림. 푸시를 쓴다면 푸시 토큰 등록 경로(BR-09)도 필요하다.
2. 일반배차모드 대기 목록 조회.

## BR-07 파일 업로드 (rider_app, customer_app, backoffice)
**현황**
- `delivery-execution-service.yaml` L418-420: 전달 완료가 `photoRefs`(설명: "file-service 업로드 완료 참조")를 필수로 요구한다.
- 그런데 file-service 는 서비스 목록에도 계약에도 없다.
- 리뷰 사진, CS 첨부, 회수·파손 증빙, 입고 증빙, 간선 인계 증빙도 같은 문제다.

**요청**
1. 업로드 경로. 예: 사전 서명 URL 발급 → 업로드 → 완료 확인.
2. 용량·형식·개수 제한.
3. 참조 ID 규칙. 업로드 성공과 업무 명령 성공을 분리하고, 업로드 후 명령이 실패했을 때 참조를 재사용할 수 있는지, 참조가 언제 만료되는지 포함.

---

## 참고: 중간·낮음 6건 (급하지 않음, 원본 문서 참조)
- BR-04: 게이트웨이 CORS. 관리자 웹을 같은 출처로 배포할지, 허용 출처를 둘지.
- BR-08: `X-Source-System` 값 목록. 제안값은 `customer-app`, `rider-app`, `mfc-app`, `backoffice-web`, `driver-app`.
- BR-09: 푸시 토큰 등록·해제.
- BR-10: 관리자 웹 상세 조회 경로와 내보내기.
- BR-11: MFC 점원 화면의 현황·입고 예정 조회.
- BR-12: 고객 노출 상태 코드와 계약 enum의 대응.
