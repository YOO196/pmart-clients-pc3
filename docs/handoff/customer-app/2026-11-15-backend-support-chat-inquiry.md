# 알림: 고객앱 고객센터 — 문의 남기기·내 문의·AI 채팅 상담 반영

- 보낸 앱: customer-app
- 받는 백엔드 영역: platform (case-service 문의) · rag (customer-assistant-service — 영역이 나뉘었으면)
- 작성: pmart-clients, 2026-11-15
- 답하는 것: `../pmart-backend/docs/handoff/clients/all/2026-11-09-clients-request-customer-inquiry-page.md` §1, `…/customer-app/2026-11-09-clients-request-customer-chat-assistant.md`
- 계약: `case-service.yaml` 0.2.0, `customer-assistant-service.yaml` 0.1.0 (`dart tools/gen_api.dart --only=case,customer-assistant`)
- 상태: 코드·시험 끝, **미커밋**. **실서버 확인은 하지 않았다**(목 저장소·단위·위젯 시험만).

## 1. 반영한 것
- 들어오는 곳: 마이페이지 "고객센터", 주문 상세 "문의하기"(주문을 고른 상태), AI 상담의 "고객센터에 문의 남기기".
- 문의 남기기 `POST /inquiries` — `category`(7종)·`body`·`title`(선택)·`orderId`(선택)·`origin`(`INQUIRY_PAGE` / `ASSISTANT_HANDOFF`). 결과 불명은 같은 키·같은 본문으로 다시.
- 내 문의 `GET /inquiries`(커서 "더 보기")·`GET /inquiries/{inquiryId}`. 알림이 없어 당겨서 새로 고침.
- AI 상담 `POST /customer-assistant/questions` — 상태 5가지 화면, 근거 접기, 최근 주문 고르기(같은 질문 + `orderId`, 새 키), `handoff` → 문의 페이지(질문을 본문 초안으로), 429 는 서버 `detail` 그대로 + 문의 버튼.
- 202 `PROCESSING`: 2초 간격으로 3번까지 **같은 키로 POST** 를 다시 보내고, 그래도 처리 중이면 "다시 확인" 버튼. `GET ?requestId=` 는 쓰지 않는다.

## 2. 쓰지 않은 것
- `GET /customer-assistant/recent-orders`, `GET /customer-assistant/questions/{answerId}`, `GET …?requestId=`.
- 문의 주문 고르기 목록(주문 상세·AI 상담에서 넘어올 때만 주문이 붙는다 — 문의 페이지에서 직접 고르는 화면은 없다).

## 3. 물어볼 것
1. 202 처리 중에 같은 키로 POST 를 다시 보내는 것이 괜찮은가(요청 제한에 안 세는 것으로 읽었다). `GET ?requestId=` 를 써야 하면 바꾼다.
2. 429 의 `Retry-After` 가 짧으면(1분 제한) 공통 HTTP 층이 기다렸다가 같은 키로 한 번 더 보낸다. 그 재전송도 세지 않는가.
3. 요청서가 말한 참고 화면 `docs/customer-app-design/. 고객센터/` 는 이 PC 의 캡처 폴더에 없다(9-1·9-2 "문의하기" 캡처만 있다). 고객센터 메인은 그 캡처의 "무엇을 도와드릴까요?" 모양으로 만들었다.

## 4. 같이 확인할 것(LAN)
- Google 로그인한 고객 토큰으로: 문의 남기기 → 백오피스(`CS_AGENT`) 답변 → 앱 "내 문의"에서 답변 보임.
- AI 상담 실제 질문(취소·배송·근거 없는 질문·"내 주문 어디쯤") — 답·근거·주문 고르기·문의 연결.
