# [pmart-clients → pmart-backend] 회신: 리뷰 0.2.0(사진)·고객 알림함 0.2.0 반영 (2026-11-16)

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform
- 원 문서: `../pmart-backend/docs/handoff/clients/customer-app/2026-11-16-notice-review-service.md`, `…/2026-11-16-notice-notification-inbox.md`
- 계약 다시 생성: review·notification(백엔드 `4852052e`), `contracts.lock`(dart)

## 1. 리뷰 (review 0.2.0)
- 자격의 `productName` 을 작성 화면·목록 이름에 쓴다(비면 상품 조회).
- 사진: 작성 화면 "사진 n/5" 칸 → 사진첩·카메라 → 고르면 바로 한 장씩 `POST /review-photos`(multipart `file`, 칸마다 `Idempotency-Key`). 결과 불명은 같은 키로 "다시 올리기"(같은 photoId 기대), 422 는 그 칸만 거절(빼기). 앱은 긴 변 2,048px·품질 85 로 줄여 보내고, 10MB 넘는 파일은 보내지 않는다(판정은 서버).
- 못 올린 사진이 있으면 등록 버튼을 막고 "다시 올리거나 빼 주세요" — 올라간 사진만 몰래 보내지 않는다(§3). 사진 실패와 리뷰 등록 실패는 따로 보인다. `PHOTO_NOT_FOUND` 는 "확인할 수 없는 사진 — 오래된 사진은 빼고 다시".
- 공개 리뷰 사진은 `photos[].url`(상대 경로)에 게이트웨이 출처를 붙여 토큰 없이 연다. 작성 중 미리보기는 기기 원본.
- 공통 HTTP: 토큰 갱신 뒤·429 재전송 때 multipart 본문을 복사해 다시 보낸다(같은 키) — `pmart_core`.
- 수정(PATCH)·삭제(DELETE) 화면은 아직 없다(이번 범위 밖).

## 2. 고객 알림함 (notification 0.2.0)
- 목적지 `INQUIRY` → 내 문의 상세(`/support/inquiries/{inquiryId}`).
- 푸시가 없으니 알림함을 열 때와 앱이 다시 앞으로 올 때 목록을 다시 읽는다. 설정 화면은 서버 `locked` 그대로 스위치를 잠근다(끄기 시도 없음).

## 3. LAN APK (HTTPS)
- 고객앱 APK 를 `https://192.168.0.40:8443/api/v1` 로 빌드했다(커밋 기준 리뷰 사진·알림함·고객센터·AI 상담 포함).
- Dart HTTP 는 안드로이드 `network_security_config`·폰에 설치한 CA 를 쓰지 않아서, debug 빌드가 LAN 루트 CA(공개 인증서)를 앱 안에서 믿게 했다(`pmart_core` `trustPmartLanRootCa`, release 는 부르지 않음 — ADR-0057 T6). 그래서 **고객앱 API 는 폰에 루트 CA 를 설치하지 않아도 된다**(기기 설치는 브라우저용).
- 이 PC 에서 같은 CA 로 확인: 공개 상품 리뷰 목록 200, `/me/notifications`·`/customer-assistant/recent-orders` 401(경로 있음).
- mfc_app·rider_app 은 아직 `http://…:8080` — HTTPS 로 옮길 때 같은 한 줄이 필요하다.

## 4. 백엔드 문서 바로잡기 부탁
- `pmart-backend/docs/rag/HANDOVER.md` 에 "고객 앱 채팅 상담 화면은 아직 없다"가 남아 있다. 화면은 2026-11-15 에 들어갔다(`/support/chat` — `POST /customer-assistant/questions`·`GET /customer-assistant/recent-orders`, 클라이언트 `2482f24`·`df930dc`, 앞 회신 `customer-app/2026-11-15-backend-support-chat-inquiry.md`). 오늘 HTTPS APK(§3)에 들어 있으니, 실제 앱 토큰 확인은 사용자가 폰으로 로그인한 뒤부터 할 수 있다고 바꿔 주세요.

## 5. 확인
- 목 모드: customer_app `flutter analyze` 문제 없음·`flutter test` 358개 통과, pmart_core 41·pmart_ui 11 통과. 360dp 캡처(리뷰 쓰기·사진 고르기·사진 다시 올리기·다 올라감).
- **실서버 확인은 아직** — LAN 에 전달 완료된 배송이 없어 리뷰 자격이 비어 있고, 알림함은 고객 토큰으로 주문을 넣어 봐야 한다.
