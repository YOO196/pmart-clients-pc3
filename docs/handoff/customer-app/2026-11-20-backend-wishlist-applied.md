# 알림 — 찜(하트) 고객 앱 반영(목 모드)

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform
- 답하는 것: `../pmart-backend/docs/handoff/clients/customer-app/2026-11-20-request-wishlist.md`(customer 0.13.0, ADR-0081)
- 상태: 앱은 **목 모드로 확인**했다(flutter analyze No issues, flutter test 632 통과). **LAN 실기기 확인은 아직** — 확인 뒤 다시 알린다.
- 계약: `dart tools/gen_api.dart --only=customer`(0.13.0).

## 반영한 것
- **하트 표시**: 회원이 되면(로그인·앱 시작) `GET /me/wishlist-product-ids` 를 한 번 읽어 두고, 찜·빼기는 서버가 반영한 뒤 그 값만 고친다(카드마다 묻지 않음). 비회원은 부르지 않는다.
- **하트 자리**: 상품 상세 아래 막대 왼쪽(레퍼런스 4-1), 목록 카드(홈·검색·카테고리) 사진 오른쪽 위, 찜한 상품 목록의 줄 오른쪽.
- **찜·빼기**: `PUT`·`DELETE /me/wishlist-items/{productId}` + `Idempotency-Key`·`X-Source-System`. 결과 불명은 같은 키로 한 번 더. 서버가 반영해야 하트가 바뀐다.
  - 422 `WISHLIST_LIMIT_EXCEEDED` → "찜은 {limit}개까지 할 수 있어요"(`details` 의 `limit`, 없으면 숫자 없는 문구), 409 `INVALID_STATE` → "지금은 찜할 수 없어요".
  - 비회원이 누르면 "로그인하면 찜할 수 있어요" + [로그인].
  - 찜 ID 를 못 읽은 상태(읽는 중·실패)에서는 하트를 흐리게 두고, 누르면 보내지 않고 다시 읽는다("안 찜함"으로 보이지 않게).
- **마이 → 찜한 상품**(`/me/wishlist`): `GET /me/wishlist-items?page=&size=20`, 아래로 내리면 다음 쪽. "전체 N개"(`total`). 줄 = 사진·이름·가격·하트, 누르면 상품 상세.
  - `SOLD_OUT` "품절"·`ENDED` "판매 종료" — 남기되 흐리게. `UNKNOWN` 또는 이름 null → "상품 정보를 불러오지 못했어요"(지어내지 않음).
  - 조회 실패는 "찜한 상품 없음"이 아니라 실패 + 다시 시도.
- 탈퇴 안내 "지워지는 것"에 찜한 상품을 보탰다.
- 재입고 알림은 넣지 않았다. 목록 줄의 "담기"는 넣지 않았다(상세에서 담는다).

## 물음
- Q1. 422 의 `details` 를 `field = "limit"`, `reason = "200"` 으로 읽었다(BR-64 때 물은 것과 같은 읽는 법). 다르면 알려 달라.
