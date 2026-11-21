# 회신 — 탈퇴 때 구글 연결 끊기 · 로그인 버튼마다 계정 고르기(고객앱 반영)

보낸 앱: customer-app
받는 백엔드 영역: platform
원 문서:
- `../pmart-backend/docs/handoff/clients/customer-app/2026-11-21-request-google-revoke-on-withdrawal.md`
- `../pmart-backend/docs/handoff/clients/customer-app/2026-11-21-request-login-account-chooser.md`

작성: pmart-clients PC 1(고객앱), 2026-11-21. 서버 변경은 요청하지 않는다(ID 토큰·교환 API 그대로 사용).

## 1. 탈퇴 때 구글 연결 끊기 — 반영함
| 요청 | 고객앱 |
|---|---|
| R1 탈퇴가 받아들여진 뒤 `revokeAccess` + `signOut` | 탈퇴 요청이 성공 응답을 받은 뒤 로그인 제공자가 GOOGLE 이면 `GoogleSignIn.disconnect()` → `signOut()` 을 부른다. google_sign_in_android 7.2 의 `disconnect()` 는 Android `AuthorizationClient.revokeAccess` 를 부르고 이어서 Credential Manager `clearCredentialState` 를 한다. 탈퇴 재인증에서 방금 구글로 로그인했으므로 끊을 계정이 잡혀 있다. 실패(오프라인 등)는 흐름을 막지 않고 화면에 오류를 보이지 않는다. 토큰·이메일은 로그에 남기지 않는다. |
| R2 실패·취소면 끊지 않음 | 재인증 화면을 닫거나 탈퇴 요청이 실패·결과 불명이면 끊기 코드까지 가지 않는다. 시험: `withdrawal_test.dart` "탈퇴 연결 끊기" 묶음 4개(성공·실패·취소·결과 불명). |
| R3 로그인 때는 끊지 않음 | 끊기는 탈퇴 성공 뒤에만 부른다. 로그인·로그아웃에서는 부르지 않는다. |

카카오(서버 Admin 키)·네이버(탈퇴 재인증 교환 때 서버)는 앱이 끊지 않는다.

## 2. 로그인 버튼마다 계정 고르기·다시 로그인 — 반영함
| 요청 | 고객앱 |
|---|---|
| R1 구글 | 로그인 버튼은 `GoogleSignIn.authenticate()`이다. Android 에서 늘 버튼 흐름(`GetSignInWithGoogleOption`)으로 계정 선택 창을 띄우고, 자동 선택이 없다. 앱 로그아웃 때 `signOut()`(= `clearCredentialState`)을 부른다(2026-11-21 고침: 전에는 로그아웃 경로에서 구글 정리가 빠져 있었다). `revokeAccess` 는 탈퇴 때만 부른다. |
| R2 카카오 | 카카오톡 앱 자동 로그인을 그만두고 늘 `loginWithKakaoAccount(prompts: [Prompt.login])` 로 한다. 앱 로그아웃·탈퇴 때 카카오 SDK `logout()` 으로 이 기기 토큰을 지운다. 앱 연결 끊기는 서버가 한다. |
| R3 네이버 | 인가 요청에 `auth_type=reauthenticate` 를 붙인다(이미 반영). `reprompt` 는 쓰지 않는다. PKCE·콜백·`POST /auth/naver-token-exchanges` 는 그대로다. |
| R4 동의는 처음 가입 때만 | 어느 제공자도 동의를 다시 묻는 값(`consent`·`reprompt`)을 보내지 않는다. 실패·취소는 지금 로그인 취소 처리 그대로다. |

참고: 세션이 끝났을 때 구글은 계정 선택 없이 조용히 다시 로그인을 먼저 시도한다(`attemptLightweightAuthentication`). 이 시도는 로그인 버튼이 아니어서 그대로 두었다. 로그아웃하면 `clearCredentialState` 로 지워지므로, 로그아웃 뒤 로그인 버튼은 계정 선택 창부터 뜬다.

## 확인
- `flutter analyze` 문제 없음.
- 시험 통과: `kakao_token_source_test.dart` 5개(새로 씀), `naver_token_source_test.dart`, `withdrawal_test.dart`, `login_identity_test.dart`.
- 실기기 확인 전이다. 아래는 사용자가 휴대폰으로 확인할 항목이다.
  - 구글로 가입 → 탈퇴 → 같은 계정으로 다시 가입: 동의 화면이 다시 뜨는지
  - 로그아웃 → 로그인 버튼: 제공자마다 계정 선택·로그인 화면이 다시 뜨는지, 같은 계정이면 동의 없이 들어가는지
