# [pmart-clients → pmart-backend] 회신: Google 서버 인가 코드(`authorizeServer`) 실기기 시험 결과 (2026-10-31)

- 요청: `../pmart-backend/docs/handoff/2026-10-31-clients-request-google-server-auth-code-test.md` (ADR-0025 초안)
- 결론: **두 조건 모두 충족.** 추가 동의 화면 없음, 재로그인 때도 코드가 나옴.

## 1. 시험 방법
- `GoogleSocialTokenSource.obtain()` 에서 `authenticate()` 다음에 `account.authorizationClient.authorizeServer(const ['openid', 'email', 'profile'])` 호출.
- `initialize(serverClientId: …)` 는 기존 값(서버용 web 클라이언트 ID) 그대로. 다른 scope·오프라인 접근 요청 없음.
- 시험 플래그(`--dart-define=PMART_GOOGLE_SERVER_AUTH_TEST=true`) + 디버그 빌드에서만 동작. 출시 빌드에는 들어가지 않는다.
- 코드 값은 기록하지 않고 null 여부·길이만 logcat 에 남겼다. 서버에는 보내지 않았고, 로그인은 기존대로 ID 토큰으로 했다.

## 2. 결과

| # | 경우 | 추가 화면 | serverAuthCode | 예외 |
|---|---|---|---|---|
| 1 | 첫 로그인 | 아니오 | 있음(길이 73) | 없음 |
| 2 | 같은 계정 재로그인(앱 로그아웃 → 로그인) | 아니오 | 있음(길이 73) | 없음 |
| 3 | 앱 재설치 뒤 로그인 | — | — | 시험 안 함 |
| 4 | 취소 | — | — | 해당 없음(추가 창이 뜨지 않음) |

- logcat(2026-10-31, 같은 실행): `17:00:50`, `17:03:43`, `17:07:27` 세 번 모두 `serverAuthCode=present(length=73)`. 세 번째도 재로그인으로 보인다(사용자는 첫 로그인·재로그인을 했다고 회신).
- 추가 동의 화면 여부는 사용자가 화면으로 확인했다("추가 동의 화면은 안떴어").

## 3. 기기
- Samsung Galaxy A53 5G (SM-A536N)
- Android 16 (API 36)
- Google Play 서비스 26.42.31 (260400-1005867181)

## 4. 참고
- 경우 1 이 "pmart 연결 해제 뒤"였는지 "처음 쓰는 계정"이었는지는 기록하지 못했다.
- 재설치(경우 3)가 필요하면 다시 요청해 달라.
- ADR-0025 를 승인하고 계약이 나오면 앱은 시험 호출을 실제 흐름으로 바꾸고 시험 플래그는 지운다. 그때까지는 시험 코드를 둔다.
