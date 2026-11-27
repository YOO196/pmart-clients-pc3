# 요청 BR-111 — 카카오 가입 때 실명(name) 받기

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform (auth-service · customer-service)
- 계기: 사용자 2026-11-26 "처음 소셜로그인으로 가입할 때 name 을 받긴 하는데 이름 입력창에 안 들어간다 — 카카오톡, 구글도 확인해줘(카카오톡은 실명이 아닌 닉네임을 주는 것 같아)"

## 확인한 것 (2026-11-26, 백엔드 main 읽기만)
| 제공자 | 서버가 넣는 `Profile.name` | 출처 | 앱 |
|---|---|---|---|
| 네이버 | 네이버 이름 | 교환 때 네이버 프로필 API(`NaverProfileEmailStore` → 로그인 사건, 가입 완료 약 1초 뒤) | **앱 결함이었음** — "내 정보 등록"이 처음 열릴 때 빈 이름으로 한 번만 채우고, 늦게 온 이름을 넣지 않았다. 고침(2026-11-26): 고객이 손대지 않은 빈 이름 칸은 나중에 온 서버 이름으로 채운다 |
| 구글 | 구글 프로필 이름 | ID 토큰 `name` 클레임 → 로그인 사건 | 같은 앱 고침으로 채워진다 |
| 카카오 | **늘 비어 있음** | `CustomerSocialLoginService.withProviderProfile` 이 일부러 넣지 않음(주석 "카카오는 실명을 주지 않는다"). `KakaoUnlinkClient.profile` 은 `kakao_account.profile.nickname` 만 읽고 `kakao_account.name` 은 읽지 않음 | 이름 칸이 비어 고객이 직접 입력 |

카카오 닉네임은 계약대로 `providerNickname`(닉네임 칸)으로만 간다. 앱이 닉네임을 이름 칸에 넣는 것은 하지 않는다(실명이 아님).

## 요청
- R1 카카오 사용자 정보(`GET /v2/user/me`)의 `kakao_account.name`(동의항목 "이름")이 있으면 로그인 사건의 `name` 으로 싣는다 — 네이버·구글과 같게 `Profile.name`(nameSource PROVIDER). 동의 안 했거나 항목이 없으면 지금처럼 비운다(닉네임으로 채우지 않는다).
- R2 고객이 이미 이름을 넣었으면(nameSource CUSTOMER) 덮지 않는다 — 지금 규칙 그대로(BR-107).
- R3 계약(customer `Profile.name` 설명 "카카오는 비어 있다")을 R1 에 맞게 고친다.

## 백엔드 밖 할 일 (사용자)
- 카카오 디벨로퍼스 콘솔에서 동의항목 **"이름(name)"** 을 켜야 값이 온다. 이 항목은 **비즈 앱 전환 + 권한 신청(검수)** 이 필요한 항목이다 — 사용자 작업. 켜기 전에는 R1 을 넣어도 계속 비어 있다(앱은 그대로 입력받는다).
- 같은 콘솔의 "닉네임(profile_nickname)" 동의는 이미 사용자 작업으로 남아 있다(백엔드 진단 2026-11-25-naver-profile-photo-diagnosis.md).

## 질문
- Q1 카카오 "이름" 동의가 검수 전이라 당장 못 켜면, R1 만 먼저 넣어 두고 콘솔이 켜지면 바로 들어오게 할지(추천), 아니면 보류할지.
