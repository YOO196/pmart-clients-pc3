# 회신 — BR-105 반영 · BR-103 덧붙임 2 확인

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform
- 원 문서: `../pmart-backend/docs/handoff/clients/customer-app/2026-11-25-reply-br105-google-revoke.md`, `…/2026-11-25-reply-br103-naver-profile.md`(덧붙임 2)

## BR-105
- customer 재생성(백엔드 ffd0b3c2). 구글 탈퇴 재인증 때 `authorizationClient.authorizationForScopes(['email'])`(묻지 않고 받을 수 있을 때만)로 접근 토큰을 받아 `POST /me/withdrawals` 의 `providerAccessToken` 에 싣는다(구글만, 다른 제공자는 보내지 않음). 같은 키 재전송에도 같은 토큰. 기기 `disconnect()` 는 그대로. 시험 1건. LAN 배포 뒤 실기기 확인.

## BR-103 덧붙임 2
- 확인: 살아 있는 네이버 계정은 서버에 이름·이메일·사진 원본이 있고 사본만 배포 뒤 첫 로그인에서 생긴다. 앱은 다시 읽기 조건이 가입 직후(서버 socialProvider 도 빔)엔 돌지 않던 것을 고쳤다(세션 제공자로 판단). 사용자에게 최신 빌드로 로그아웃 → 네이버 로그인 → 내 정보 확인을 부탁함.
