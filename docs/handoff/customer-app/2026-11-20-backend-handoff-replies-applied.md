# 알림 — 2026-11-20 백엔드 요청·회신 4건 고객 앱 반영(목 모드)

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform
- 받은 문서(pmart-backend `docs/handoff/clients/customer-app/`):
  `2026-11-20-request-search-correction-text.md`, `2026-11-20-request-review-photo-thumbnails.md`,
  `2026-11-20-request-home-banners-themes.md`, `2026-11-20-reply-br64-phone-identity.md`
  (`2026-11-20-reply-review-edit-empty-text.md` 는 확인만 — 앱이 막는 것 없음)
- 상태: 앱은 **목 모드로 확인**했다(flutter test 579 통과). **LAN 실서버 확인은 아직** — 확인 뒤 다시 알린다.

## 1. 검색어 교정 문구(search 0.4.0~0.5.1)
- 고친 검색어로 찾았으면 "**'순두부'** 검색 결과예요" + 작은 링크 "'순두뷰'로 검색하기"(`noCorrection=true` 로 다시 — 띠 없음).
- 결과가 적으면 "혹시 **'순두부'**를 찾으셨나요?" — 누르면 그 검색어로 새로 찾는다.
- 다음 쪽은 같은 원래 `q` + `cursor`. 최근 검색어는 고객이 친 검색어 그대로.

## 2. 리뷰 사진 축소본(review 0.4.0)
- 목록·미리보기 썸네일 `?w=240`(화소가 크면 480), 크게 보기 `?w=720`. 세 곳 모두 `cacheWidth`(그리는 폭 × 기기 화소비).

## 3. 홈 배너·테마·탭(storefront 0.7.0)
- HOME_TOP 배너: 화면 폭 가로 넘기기(sortOrder 순). HOME_MIDDLE: 첫 영역 아래. 배너가 없으면 자리 없음.
- 누르기: SECTION → 그 영역 전체 보기, PRODUCT → 상품 상세, CATEGORY → 카테고리 목록, NONE·NOTICE → 누를 수 없음.
- 테마 영역은 기존 영역 카드(제목·부제·가로 목록·전체 보기), 다음 묶음 409 `LAYOUT_VERSION_CHANGED` 이면 홈을 다시 부른다(이미 있던 동작). 탭(HOME·RANKING·NEW)·순위 숫자·NEW 표시는 이미 있다.
- 배너 그림은 토큰 없이 `Image.network`(게이트웨이 출처 + `imageUrl`).

## 4. BR-64 로그인 휴대폰 확인(auth 0.6.0)
- `AUTH_IDENTITY` → 휴대폰 확인 화면(내 정보 화면과 같은 모양): 번호 입력 → `identity-verifications`(본문 `providerToken`·`phone`) → "{sendTo}로 {text}를 문자로 보내 주세요"(문자 앱 열기·숫자 복사) → "보냈어요" 때만 `confirmations`.
  - PENDING: 남은 횟수 안내, 그 단계에 남음. FAILED·EXPIRED: 번호 입력부터.
  - 409 `IDENTITY_ALREADY_REGISTERED`: "이 번호로 {카카오}로 가입한 계정이 있어요" + 가입일·가린 이메일 + [{카카오}로 로그인].
  - 409 `IDENTITY_REJOIN_BLOCKED`: "탈퇴한 번호는 {날짜}부터 다시 가입할 수 있어요".
  - `/completions` 가 `AUTH_IDENTITY` 를 줘도 이 화면으로 이어진다(동의 → 확인 → 회원).
  - 결과 불명은 같은 키로 한 번 더, 만료된 ID 토큰(401)은 새 토큰으로 한 번 더.
- **질문 Q1:** `details` 의 `field`·`reason` 을 `provider`→`KAKAO`, `joinedAt`→ISO 시각, `emailMasked`→문자열, `rejoinAvailableAt`→ISO 시각으로 읽었다(field = 이름, reason = 값). 맞는지 확인 부탁.
- **스위치 `require-identity`**: 앱 쪽은 반영됐다. 켜는 것은 사용자 허락 뒤(백엔드 문서대로). LAN 에서 켠 뒤 실기기로 확인하겠다.
- 처리방침 새 판(R7)은 사용자 결정 대기 — 앱이 할 것 없음(서버 목록대로 동의 화면이 나온다).
