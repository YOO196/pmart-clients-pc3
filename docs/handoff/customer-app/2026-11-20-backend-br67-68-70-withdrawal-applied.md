# 알림 — BR-67·68·70 회신, 회원 탈퇴 요청 고객 앱 반영(목 모드)

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform
- 답하는 것(pmart-backend `docs/handoff/clients/customer-app/`):
  `2026-11-20-reply-br67-br68-br70.md`, `2026-11-20-reply-br69-naver-token-exchange.md`, `2026-11-20-request-customer-withdrawal.md`
- 상태: 앱은 **목 모드로 확인**했다(flutter analyze No issues, flutter test 622 통과). **LAN 실기기 확인은 아직** — 확인 뒤 다시 알린다.
- 계약: `dart tools/gen_api.dart --only=auth,review,order,customer`(auth 0.10.1·review 0.5.0·order 0.17.0·customer 0.12.0).

## 1. BR-70 네이버 프로필 사진 (auth 0.10.1)
- `POST /auth/naver-token-exchanges` 200 의 `profileImageUrl`(null·빈 값은 없음으로)을 메모리에 두고, 로그인 본문 세 곳
  (`social-logins`·`completions`·`…/confirmations`)의 `profileImageUrl` 에 그대로 실어 보낸다. 네이버가 아니면 보내지 않는다(값이 없다).
- 결과 불명 재전송(같은 Idempotency-Key)도 같은 주소를 쓴다.
- 탈퇴 재인증의 교환에서는 사진을 쓰지 않는다.

## 2. BR-67 리뷰관리 (review 0.5.0)
- 탭 머리 "리뷰 쓰기 N개 | 내가 쓴 리뷰 N개" — `counts.writable`·`counts.written`. 처음 열리는 "리뷰 쓰기" 목록 첫 쪽에 딸려 온 값을 쓴다(숫자만 보려고 따로 부르지 않음). 못 받으면 숫자 없이.
- 주문 묶음 머리: `mfcName`(굵게) + `orderedAt` "2026. 10. 24 주문". 둘 다 없으면 머리 없이.
- 품목 카드: `imageUrl`(없으면 자리 그림)·`optionLabel`(있으면 한 줄).
- `total` 은 받기만 하고 아직 화면에 쓰지 않는다.

## 3. BR-68 주문내역 카드 (order 0.17.0)
- `lines`(앞 5개): 이름 · 옵션 / **금액**(`lineAmount`) 수량. 사진은 계약에 없어 그리지 않는다.
- 나머지는 "외 N개" — N = `itemCount` − 보인 행의 수량 합(수량 기준).
- `mfcName` 은 카드 머리 아래 한 줄. 줄이 있으면 아래는 "결제금액 / 총액", 줄이 없으면(예전 응답) 지금처럼 "대표 상품 외 N개".
- 목록의 "같은 상품 담기"·지금 살 수 있는지 표시는 넣지 않았다(R3 미포함 그대로).

## 4. 회원 탈퇴 (customer 0.12.0, ADR-0077)
- 들어가는 곳: 마이 → 내 정보 → 아래 "회원 탈퇴"(`/me/withdrawal`). 계정 상태 `WITHDRAW_PENDING` 이면 마이 맨 위 띠 "탈퇴 처리 대기 중이에요" → 같은 화면.
- 접수: 안내(지워지는 것·남는 것·대기·재가입 30일) → 사유(선택) → "위 내용을 모두 확인했어요" → **같은 소셜 재인증** → `POST /me/withdrawals`.
  - 재인증할 소셜은 `GET /me` 의 `socialProvider` 가 먼저, 없으면 이번에 로그인한 제공자.
  - `reasonCode` 는 앱이 정한 값: `RARELY_USE`·`DELIVERY`·`PRODUCTS`·`PRICE`·`PRIVACY`·`OTHER`. `reasonText` 는 최대 500자.
  - `COMPLETED` → 이 기기의 로그인 정보만 지우고(서버에 더 묻지 않음 — 푸시 토큰 지우기·조용한 재로그인 없음) 홈 + "탈퇴가 완료됐어요".
  - `BLOCKED_BY_OBLIGATIONS` → "탈퇴 처리 대기 중이에요" + `openObligations`(주문 → 주문 상세, 클레임·환불 → 처리 내역) + `lastCheckedAt`.
  - 그 밖의 끝나지 않은 상태(`UNKNOWN`·`PENDING`·`CHECKING_OBLIGATIONS`·`COMPLETING`) → "탈퇴를 확인하고 있어요"(완료로 보이지 않음).
  - 401 `PROVIDER_REJECTED`·403 `REAUTHENTICATION_MISMATCH`·409 `INVALID_STATE`(상태 다시 읽기) 문구. 결과 불명은 완료로 보이지 않고, 다시 누르면 같은 키·같은 토큰으로 보낸다.
- 철회: 대기 화면의 [탈퇴 철회] → 재인증 → `…/revocations` → `REVOKED` 면 "탈퇴를 철회했어요". 마케팅 수신 동의가 되돌아오지 않는다는 안내는 대기 화면에 있다.
- 화면을 열 때 `GET /me/withdrawals` 의 끝나지 않은 접수가 있으면 접수 화면이 아니라 상태부터 보인다.
- **아직 안 한 것**: 완료 뒤 다른 기기에서 401 을 받았을 때의 "탈퇴가 완료됐어요" 안내(지금은 일반 "다시 로그인해 주세요"가 뜬다). `GET /me/withdrawals/{id}` 단건 조회는 쓰지 않는다(목록으로 충분).

## 물음
- Q1. 대기 중 새 주문은 "기존처럼 422 `ACCOUNT_NOT_PURCHASABLE`" — 앱은 이 코드의 문구를 따로 두지 않았다(일반 거절 문구). 탈퇴 대기용 문구가 필요하면 알려 달라.
