# [pmart-clients → pmart-backend] 고객 Google 로그인 확인 요청 (BR-27)

- 회신 대상: `pmart-backend/docs/handoff/2026-10-30-clients-notice-customer-google-login.md`, ADR-0019
- 기준 커밋: pmart-backend `2f507dc`, `contracts/openapi/auth-service.yaml`
- 클라이언트 상태: 고객앱(Android)에 Google Sign-In 을 붙였다(`google_sign_in` 7.2.0, serverClientId = 안내의 웹 클라이언트 ID). 실서버 모드에서는 Google 버튼만 보인다. 디버그 APK 빌드·서명 지문 확인까지 했고, 실제 기기 로그인은 아직 하지 않았다.

## 1. 이용 불가 계정 오류 코드가 계약과 안내에서 다르다 (BR-27)
- 계약 `POST /auth/social-logins` · `completions`: `422` `REQUIRED_CONSENT_MISSING / ACCOUNT_NOT_PURCHASABLE (WITHDRAW_PENDING 등)`
- 안내 §4 표: `403` `ACCOUNT_NOT_AVAILABLE` — "이용할 수 없는 계정"
- 질문: 실제 응답은 어느 쪽인가? 둘 다 쓴다면 차이는 무엇인가(로그인 자체 불가 vs 구매 불가)? 계약에 403 `ACCOUNT_NOT_AVAILABLE` 을 추가할 계획인가?
- 클라이언트 처리(회신 전): 두 코드 모두 "지금은 이 계정으로 이용할 수 없어요"로 보인다.

## 2. 참고: 클라이언트가 이렇게 처리한다 (확인만 부탁)
- 카카오·네이버 `501 UNSUPPORTED_ACTION`: 변경 요청의 5xx 라도 결과 불명이 아니라 "지원 안 함"으로 확정 처리한다. 실서버 모드에서는 버튼 자체를 숨긴다. 501 을 결과 불명으로 봐야 하는 경우가 있으면 알려 달라.
- 앱 시작 때 보안 저장소에 refresh token 이 있으면 `GET /auth/sessions/current` 를 부른다(access 가 없어 401 → `/auth/tokens` 회전 → 재시도). `principalType=CUSTOMER` 일 때만 회원으로 본다. 앱을 켤 때마다 refresh 회전이 한 번 일어나는 것이 괜찮은지 확인 부탁.
- Google 창 취소·중단은 서버를 부르지 않는다. Google 설정 오류(DEVELOPER_ERROR)도 서버를 부르지 않고 앱에서 안내한다.

## 3. iOS 는 진행하지 않는다
- 클라이언트 ADR-0002(2026-10-30): Flutter 앱은 Android 만 개발한다. 안내 §2 의 iOS OAuth 클라이언트·허용 목록 추가는 지금 필요 없다.
