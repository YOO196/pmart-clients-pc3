# 요청 — BR-69 네이버 로그인: 토큰 교환이 client secret 없이는 안 된다(`invalid_client`)

- 보낸 앱: customer-app (PC 1) — rider-app 도 같은 방식이라 같이 해당
- 받는 백엔드 영역: platform (auth-service)
- 이어지는 것: `../pmart-backend/docs/handoff/clients/customer-app/2026-11-20-request-naver-login-task-affinity.md`(taskAffinity — 앱 반영 끝, main `dbee5438`)
- 계기: 사용자 2026-11-20 "네이버쪽에서 다시 돌아와서 우리 고객앱으로 돌아왔을 때 '로그인 서비스가 원활하지 않아요'가 떠"

## 지금 증상
- taskAffinity 를 뺀 빌드(main `2f3f83ad` + profile APK, 폰 SM-A536N, 2026-11-20 14:13 세 번)에서 네이버 동의 뒤 **앱으로는 돌아온다**.
  폰 기록: `RedirectUriReceiverActivity` → 떠 있던 `AuthorizationManagementActivity` 로 전달(같은 task, "No stored state" 없음).
- 그 직후 앱이 "로그인 서비스가 원활하지 않아요"를 띄운다 = flutter_appauth `authorizeAndExchangeCode` 가 `PlatformException`. `POST /auth/social-logins`(NAVER)는 보내지 못한다.

## 원인(확인한 것)
네이버 토큰 엔드포인트가 **client secret 없는 요청을 받지 않는다.** ADR-0071 의 전제("토큰 엔드포인트 인증 `none` — 앱이 client secret 없이 ID 토큰을 받는다")가 실제와 다르다.

1. `https://nid.naver.com/.well-known/openid-configuration`(2026-11-20 확인):
   `"token_endpoint_auth_methods_supported": ["client_secret_post"]` — `none` 이 없다. (`code_challenge_methods_supported: ["S256"]` 는 있다 — PKCE 는 받지만 secret 을 대신하지 않는다.)
2. 이 PC 에서 직접 물어봄(가짜 코드, 앱과 같은 본문 — `grant_type=authorization_code`·`client_id`·`code`·`code_verifier`·`redirect_uri`, secret 없음):
   `POST https://nid.naver.com/oauth2/token` → **401 `{"error":"invalid_client"}`**. 코드가 틀렸다는 `invalid_grant` 가 아니라 클라이언트 인증에서 막힌다.
3. 폰 기록: 앱으로 돌아온 직후 앱(uid)의 DNS 조회가 있다(토큰 교환을 보낸 것) — 그 뒤 실패.

앱에 client secret 을 넣을 수는 없다(클라이언트 절대 규칙 — 비밀값을 앱·빌드 설정에 두지 않는다).

## 부탁 — 서버가 인가 코드를 ID 토큰으로 바꿔 달라
앱은 인가 요청(PKCE)까지만 하고, 받은 **인가 코드**를 서버에 넘긴다. 서버가 client secret 으로 토큰 교환을 한 뒤 지금처럼 id_token 을 검증한다.

- **R1.** `POST /auth/social-logins`(NAVER)가 `providerToken`(id_token) 대신 인가 코드를 받을 수 있게 — 예: `authorizationCode`·`codeVerifier`·`redirectUri`(이름은 정해 주는 대로). 앱이 보낸 `redirectUri` 는 인가 요청에 쓴 값 그대로(`…/auth/oauth-callbacks/naver/customer`).
- **R2.** 인가 코드는 한 번만 쓸 수 있다. 그런데 로그인 뒤 단계가 id_token 을 다시 요구한다 — `/completions`(동의)·`/identity-verifications`·`/confirmations`(휴대폰 확인)의 `providerToken`. 서버가 교환해 얻은 id_token 을 **앱에 돌려줄지**(앱이 메모리에만 두고 다음 단계에 다시 보냄), 아니면 **`authRequestId` 에 묶어 서버가 기억할지** 정해 달라. 앱은 어느 쪽이든 맞춘다.
- **R3.** 결과 불명일 때 같은 `Idempotency-Key` 로 다시 보내면 코드를 두 번 교환하지 않게(두 번째는 네이버가 거절한다).
- **R4.** 네이버가 거절(`invalid_grant` 등)·응답 없음일 때의 코드 — 지금의 `PROVIDER_REJECTED`·`PROVIDER_UNAVAILABLE` 그대로면 앱 문구를 그대로 쓴다.
- **R5.** 라이더 앱(`…/naver/rider`)도 같은 방식인지.
- ADR-0055 결정 3·ADR-0071("인가 코드 교환·client secret 을 쓰지 않는다")을 바꾸는 일이라 사용자 결정이 필요하다.

## 앱이 할 일(회신 뒤)
- flutter_appauth `authorizeAndExchangeCode` → `authorize`(코드만 받기)로, 코드·`codeVerifier`·`redirectUri` 를 서버로. 계약을 다시 생성해 반영.
- 그때까지 네이버 로그인은 끝나지 않는다(카카오·구글은 영향 없음).

## 상태
- 2026-11-20: 요청. 회신 대기.
