# 회신·요청 — provider-nickname 반영 + BR-107 실명(name)을 고객이 입력·수정

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform (customer-service)
- 원 문서: `../pmart-backend/docs/handoff/clients/customer-app/2026-11-25-backend-provider-nickname.md`
- 계기: 사용자 2026-11-25 "이름이랑 닉네임 내 정보에서 수정할 수 있는 기능 필요해".

## provider-nickname 반영(customer 0.19.0 재생성, 백엔드 80362dbc)
- 표시 이름: `nickname` → `providerNickname` → `name` 순(마이 요약 줄 등).
- 내 정보: **이름** 줄 = `name`(실명, 지금은 보기만) / **닉네임** 줄 = `nickname`(없으면 `providerNickname` 을 보임, 누르면 닉네임 바꾸기 — PATCH `nickname`).
- 배송지 받는 분 기본값은 앱이 프로필에서 채우지 않는다(지금도 직접 입력) — 변경 없음.

## 어긋난 점(확인 부탁)
- 원 문서 "이름은 무조건 입력하게 하는데(고객앱 구현됨)" — **앱의 가입 직후 "이름" 입력(`/me/info?from=signup`)은 `PATCH /me` 의 `nickname` 으로 저장한다**(계약에 실명을 쓰는 칸이 없다). 그래서 서버 `name` 이 빈 계정(카카오 등)에 앱이 실명을 넣을 길이 없다.

## 요청 BR-107
- R1 `PATCH /me` 에 `name`(실명, 1~30자, 줄바꿈·제어 문자 불가) — 고객이 직접 넣은 실명.
- R2 고객이 넣은 실명은 **로그인 때 제공자 이름으로 덮지 않는다**(제공자 이름은 고객이 아직 실명을 넣지 않았을 때만 채움). 구분 칸(예 `nameSource: PROVIDER|CUSTOMER`)이 있으면 앱이 "로그인 계정 이름으로 되돌리기"도 보일 수 있다.
- R3 가입 직후 "이름" 입력은 계약이 나오면 `name` 으로 보내고, 닉네임은 내 정보에서 따로 정한다.

## 앱 처리(계약 전)
- 내 정보 이름 줄은 보기만, 닉네임 줄은 고칠 수 있다.
