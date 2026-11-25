# 요청 — BR-105 탈퇴 때 구글 연결(동의)을 서버가 끊기

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform (customer-service 탈퇴 · auth-service)
- 계기: 사용자 2026-11-25 "구글도 소셜(서버)이 끊게 못 만들어?" → 방법 1 선택("1번으로 해줘").
- 관련: 카카오는 서버가 Admin 키로(289a989a), 네이버는 서버가 교환 토큰으로(purpose=WITHDRAWAL) 끊는다. 구글만 앱이 기기에서 `disconnect()`(Android revokeAccess) — 실패해도 앱이 조용히 넘겨 끊겼는지 알 수 없다.

## 요청
- R1 `POST /me/withdrawals`(그리고 철회 재인증 등 같은 본문을 쓰는 곳)에 **선택 필드 `providerAccessToken`**(문자열, GOOGLE 일 때만) — 앱이 탈퇴 재인증 직후 구글에서 받은 **OAuth 접근 토큰**. 로그·응답·사건에 남기지 않는다(providerToken 과 같은 취급).
- R2 탈퇴가 받아들여지면(대기·완료 모두) 서버가 `POST https://oauth2.googleapis.com/revoke`(form `token=<접근 토큰>`)로 이 앱과의 구글 연결을 끊는다. **클라이언트 비밀값·API 키 필요 없음**(토큰만). 토큰을 보관하지 않고 한 번 쓰고 버린다.
  - 결과는 로그에 성공/실패·HTTP 코드만(토큰 값 없이). 실패해도 탈퇴는 그대로.
  - 토큰이 없으면(옛 앱) 지금처럼 앱의 기기 끊기에 맡긴다.
- R3 철회(REVOKED)로 끝나면 끊지 않는다(지금 앱 규칙과 같음).

## 앱 처리
- 계약이 나오면 탈퇴 재인증(구글) 때 `google_sign_in` authorizationClient 로 접근 토큰을 받아 `providerAccessToken` 에 싣는다(지금 구글 로그인 설정 그대로 — 새 콘솔 설정 없음).
- 서버 반영 전·후 모두 기기 `disconnect()` 는 그대로 둔다(두 겹).
