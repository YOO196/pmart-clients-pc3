# 요청 BR-108 — 주소에 "라이더 요청사항"(문 앞에 두고 노크해주세요 등) 저장

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform (customer-service), order(주문 기본값)
- 계기: 사용자 2026-11-26 "노크해주세요 이건 왜 안 떠" — 레퍼런스(주소 편집·주소 상세)는 주소마다 라이더 요청사항을 고르고(펼침 목록), 주소 목록에 회색 줄로 보인다.

## 지금
- customer `Address` 에는 `entranceMethod`(FREE·PASSWORD·CALL·OTHER)·`entranceNote` 만 있다. 라이더 요청사항 칸이 없어 앱이 저장·표시할 수 없다.
- order 는 주문마다 `deliveryNote`(200자)만 있다.

## 요청
- R1 `Address`·`AddressInput` 에 `riderRequest`(string|null, 100자 안, 줄바꿈 불가) — 고객이 고른 문구(예: "문 앞에 두고 노크해주세요.", "문 앞에 두고 초인종 눌러주세요.", "직접 받을게요.", "전화주시면 마중 나갈게요.") 또는 직접 입력.
- R2 고를 수 있는 기본 문구 목록을 서버가 준다(예 `GET /address-rider-request-options` 또는 계약 enum + 표시 문구) — 앱이 문구를 정하지 않게.
- R3 주문서 초안이 쇼핑 주소의 `riderRequest` 를 `deliveryNote` 기본값으로 채우는지(또는 별 칸으로 넘기는지) 정해 주세요 — 라이더 앱에 보이는 곳도.

## 앱 처리(계약 전)
- 주소 목록 회색 줄·주소 상세 "라이더 요청사항" 펼침 목록은 넣지 않는다(지어내지 않음). 계약이 나오면 레퍼런스대로 넣는다.
