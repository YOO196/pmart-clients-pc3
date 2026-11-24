# 요청 — BR-92 취소·반품 품목에 상품 이름·사진 사본(`ClaimLine`)

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform (claim-service, `contracts/openapi/claim-service.yaml` `ClaimLine`)
- 계기: 사용자 2026-11-24 "취소, 반품 처리 내역에 상품이 SKU로 보여"

## 지금
- `ClaimLine` 에는 `orderLineId`·`sku` 만 있고 상품 이름·옵션·사진이 없다.
- 앱은 처리 내역(`GET /claims/{claimId}`)을 그릴 때 **주문 상세(`GET /orders/{orderId}`)를 따로 읽어** 같은 `orderLineId` 의 `productName`·`optionLabel`·`imageUrl` 을 붙인다.
- 주문 상세를 못 읽으면(네트워크, 고객이 지운 주문, 이름 사본이 없는 2026-11-02 이전 주문) 이름을 붙일 수 없다. 앱은 지금까지 SKU 를 보였고, 2026-11-24 부터는 SKU 대신 "상품 정보를 불러오지 못했어요"(+ 주문 조회 실패면 "다시 시도")를 보인다.

## 요청 R1
- `ClaimLine` 에 접수 때의 주문 품목 사본을 넣어 주세요(주문 줄 `OrderLine` 과 같은 이름·뜻):
  - `productName: string`
  - `optionLabel: string`(단일 옵션 상품이면 비워도 됨 — 주문 줄과 같은 규칙)
  - `imageUrl: string`(BR-71 주문 줄 사진과 같은 값)
- 이름 사본이 없는 옛 주문의 클레임은 비워 보내 주세요 — 앱은 그때 안내 문구를 보인다(SKU 를 보이지 않는다).
- 질문 Q1: 고객이 지운(숨긴) 주문도 `GET /orders/{orderId}` 가 열리나요? 안 열리면 R1 이 그 경우의 유일한 길이다.

## 앱
- R1 이 오면 클레임 품목의 이름·사진을 `ClaimLine` 에서 먼저 쓰고, 없을 때만 주문 상세에서 붙인다(지금 방식은 대체로 남긴다).
