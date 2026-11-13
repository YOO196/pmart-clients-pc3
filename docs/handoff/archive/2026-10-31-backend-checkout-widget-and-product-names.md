# [pmart-clients → pmart-backend] 주문서형 결제위젯용 결제창 키, 주문 품목 상품명 사본 요청 (BR-34·BR-35) (2026-10-31)

- 관련: `order-service.yaml`(`OrderDraft.payment`, `DraftLine.productName`, `OrderLine.productName`), 안내 `2026-10-31-clients-notice-checkout.md`, `2026-10-30-clients-notice-customer-payment.md`
- 사용자 결정(2026-10-31): 토스 결제위젯을 **주문서형**으로 붙인다. 결제수단·약관 위젯을 주문서 화면 안에 그리고, "결제하기"를 누르면 바로 결제 인증으로 넘어간다.

## 1. 주문서형 결제위젯 — 결제 진입 전에 결제창 키(clientKey) (BR-34, 필수)
- **현황:** `clientKey` 는 결제 진입(`POST /order-drafts/{id}/checkouts`) 뒤 `nextAction=PAY` 의 `OrderDraft.payment` 에만 있다. 위젯(결제수단·약관)은 clientKey 가 있어야 그릴 수 있다. 그래서 지금 고객앱은 결제하기 → 재고 확보 → **별도 전체 화면**에 위젯을 띄운다.
- **앱 원칙:** 토스 clientKey 는 공개 키지만 서버 응답으로만 받는다(앱 빌드 설정에 넣지 않는다).
- **요청(택1):**
  - (a) 결제 진입 **전**의 초안 조회(`GET /order-drafts/{id}`, DRAFT·REVIEW)에 위젯 렌더링 정보를 둔다. 예: `paymentWidget: { provider: TOSS_PAYMENTS, clientKey, customerKey? }`. 비밀값은 없다.
  - (b) 별도 조회 `GET /payment-widget-config` → `{provider, clientKey}`(고객 토큰).
- **customerKey**(결제 명세 D6 미정): 위젯 생성에 필요하다. 앱은 지금 `ANONYMOUS`(`@@ANONYMOUS`)로 시험한다. 회원별 값을 쓸 계획이면 (a)·(b) 응답에 함께 넣어 달라. 앱이 accountId 등을 직접 만들지는 않는다.
- **앱 흐름(반영 예정):**
  1. 주문서 화면에 위젯을 그린다. 금액은 초안 `quote.totalAmount` 다.
  2. "결제하기"를 누르면 `POST …/checkouts`(새 키) 를 보낸다.
  3. 초안을 1초 간격으로 조회해 `PAY` 를 기다린다.
  4. `payment.amount` 가 위젯 금액과 다르면 `updateAmount` 하지 않는다. 결제를 멈추고 주문서를 다시 확인하게 한다.
  5. `requestPayment(orderId = payment.pgOrderId, orderName = payment.orderName)` 를 부른다.
  6. 이후는 지금과 같다(`/payment-confirmations`, 실패·취소 보고).
- **확인 부탁:** `payment.amount` 는 항상 동의한 견적의 `totalAmount` 와 같은가? 다를 수 있다면 어떤 경우인가?

## 2. 주문 품목 상품명 사본 (BR-35, 필수)
- **현황:** 주문 상세 `OrderLine.productName` 은 계약상 "주문 당시 스냅샷"인데 비어 온다. 계약 `getOrder` 설명에 "productName 은 아직 비운다"고 돼 있다. 초안 `DraftLine.productName` 도 비어 있다. 그래서 고객앱 주문 내역·상세·클레임 화면에 상품명 대신 **SKU(E-00000001)** 가 보인다.
- 결제창 주문명도 "PMart 장보기 N개 상품"이다(안내 §3).
- **앱이 지금 상품명을 조회해 채우지 않는 이유:** 업무 문서(Commerce F, OMS 확정 스냅샷)는 주문 내역을 "주문 당시 고정 사본"으로 보여 주라고 한다. 현재 이름으로 다시 쓰면 나중에 바뀐 이름이 과거 주문에 나온다.
- **요청:**
  - 초안 생성 때 품목별 고객용 상품명·옵션 라벨 사본을 `DraftLine.productName` 에 저장한다(product-content). 주문 확정 때 `OrderLine.productName` 으로 넘긴다.
  - 가능하면 결제창 주문명도 상품명 기반으로 만든다(예: "국산콩 두부 300g 외 2건").
  - 사본을 만들 때 product-content 조회에 실패하면 이름을 지어내지 말고 비워 둔다. 앱은 그때만 SKU 로 대신한다.
