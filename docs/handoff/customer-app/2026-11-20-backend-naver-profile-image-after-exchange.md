# 질문 — BR-70 네이버 프로필 사진: 서버 교환(auth 0.10.0) 뒤에는 앱이 access token 을 못 받는다

- 보낸 앱: customer-app (PC 1) — rider-app 도 네이버 로그인이라 같은 질문
- 받는 백엔드 영역: platform (auth-service)
- 답하는 것: `../pmart-backend/docs/handoff/clients/customer-app/2026-11-20-request-naver-profile-image.md`(auth 0.8.0 — 앱이 네이버 프로필 API 로 사진 주소를 읽어 `profileImageUrl` 로 넘기기)
- 이어지는 것: `docs/handoff/customer-app/2026-11-20-backend-naver-token-exchange.md`(BR-69 — auth 0.10.0 `POST /auth/naver-token-exchanges`, ADR-0078)
- 계기: 사용자 2026-11-20 "네이버 프로필 기능까지 넣은거지?" → "응 질문 문서 써줘"

## 두 요청이 서로 맞지 않는다
- **프로필 사진 요청(0.8.0)**: 앱이 flutter_appauth `authorizeAndExchangeCode` 결과의 **access token** 으로 `GET https://openapi.naver.com/v1/nid/me` 를 불러 `profile_image` 를 얻고, 그 주소를 로그인 본문 세 곳에 `profileImageUrl` 로 보낸다.
- **서버 교환(0.10.0)**: 네이버가 client secret 없는 교환을 거절해, 이제 앱은 인가 코드까지만 받는다. 서버가 교환한 뒤 **id_token 만** 돌려주고 access/refresh token 은 버린다(계약 설명 그대로).
- 그래서 앱에는 access token 이 없다 — 프로필 API 를 부를 수 없고, `profileImageUrl` 을 채울 방법이 없다. 고객 앱은 0.10.0 방식으로 이미 바꿨다(main `6fbf970a`, 목 모드).

## 물음 — 어느 쪽으로 할지 정해 달라
- **(가) 서버가 직접 읽는다.** 교환 때 받은 access token 으로 서버가 `…/v1/nid/me` 를 불러 사진을 얻고, 그 로그인 흐름(`authRequestId`)에 묶어 customer 로 넘긴다. 앱은 할 일이 없다(`profileImageUrl` 을 보내지 않음). access token 이 앱으로 나오지 않는다.
- **(나) 교환 응답에 사진 주소를 같이 준다.** `POST /auth/naver-token-exchanges` 200 에 선택 `profileImageUrl` 을 더한다(서버가 프로필 API 를 부른 결과). 앱은 받은 주소를 메모리에만 두고 지금 계약(0.8.0)의 세 곳에 그대로 실어 보낸다. 서버 규칙(https·`*.pstatic.net` 만)은 그대로.
- **(다) access token 을 앱에 돌려준다.** 원래 요청서대로 앱이 프로필 API 를 부른다. 앱에 제공자 access token 이 생기는 것이라 권하지 않는다.

앱 쪽 생각: (가)가 가장 단순하다(앱 변경 없음, 토큰이 서버 밖으로 안 나감). (나)도 바로 맞출 수 있다 — 계약만 알려 주면 된다.

## 같이 확인해 줄 것
- (가)·(나) 어느 쪽이든 회원 탈퇴 재인증(`POST /me/withdrawals` 의 `providerToken`)처럼 로그인이 아닌 교환에서는 사진을 읽지 않아도 되는지.
- 네이버 콘솔 "제공 정보 — 프로필 사진" 체크는 그대로 필요한지(사용자 몫).
- 라이더 앱(rider-auth 0.3.0)도 같은 방식인지.

## 상태
- 2026-11-20: 질문. 회신 대기. 그때까지 네이버 회원의 프로필 사진은 오지 않는다(로그인에는 영향 없음).
