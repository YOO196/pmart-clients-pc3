# [pmart-clients → pmart-backend] 장바구니 담기·수량 변경이 느림 — 변경 응답에 장바구니 포함(BR-43)·표시용 조회 timeout/병렬화(BR-42) (2026-11-03)

- 관련: `contracts/openapi/cart-service.yaml` `CartChangeResult`, `GET /carts/{cartId}`; `services/cart-service` `CartService.addItem/change`, `CartView.view`, `CatalogClient`, `deploy/lan/.config-repo/cart-service-lan.yml`.
- 우선: 높음(고객이 가장 자주 하는 동작. 사용자 체감 "너무 느려", PC3 를 켠 뒤에도).

## 1. 지금 흐름 (탭 한 번)
1. 앱 → `POST /carts/{id}/items`(또는 `PATCH …/items/{itemId}`) — cart-service 는 product-service `/internal/skus/{sku}`(판매 가능)·구매 상한 조회 → 저장 → `APPLIED`.
2. 앱 → `GET /carts/{id}` — `CartView.view` 가 product-service(`/internal/skus`)·product-content-service(카드)·pricing-service(가격)·mfc-inventory-service(가용, pc3) 를 **순차** 호출해 표시용 사본과 `selectedItemAmount` 를 만든다.
- 앱이 두 번째 호출을 하는 이유: 변경 응답에 갱신된 품목 사본·합계가 없기 때문. 금액은 서버 값만 보이는 규칙이라 앱이 합계를 계산해 확정하지 않는다.
- 서비스 간 호출이 탭당 5~6번. pc2(cart·product·content·pricing) ↔ pc3(mfc-inventory) 를 건넌다.

## 2. 앱이 한 것 (2026-11-03)
- 연속 수량 ± 를 350ms 모아 최종 수량 한 번만 보낸다.
- 수량·선택·삭제는 응답 `cartVersion` 으로 장바구니를 바로 갱신한다(서버가 APPLIED 로 확정한 내용만 반영). 합계는 "확인 중"으로 두고 뒤에서 `GET /carts/{id}` 로 채운다. 담기(새 행)는 이름·단가 사본이 필요해 그대로 다시 읽는다.
- 가용 UNKNOWN 은 `mfcId` 없음(배송지 미정)·`sources[]` 의 mfc-inventory UNAVAILABLE(재고 원천 장애)·그 밖으로 나눠 안내한다.

## 3. 요청
### BR-43 변경 응답에 갱신된 장바구니
- `CartChangeResult` 에 갱신된 `Cart` 전체(권장) 또는 최소한 `selectedItemAmount` + 바뀐 `CartItem`(display 포함) 을 넣어 달라. 앱은 그 값으로 화면을 끝내고 두 번째 `GET` 을 하지 않는다.
- 서버 쪽 비용: 변경 뒤 `CartView.view` 를 한 번 더 도는 것이라 지금 앱이 따로 부르는 것과 같다. 대신 왕복 하나와 게이트웨이 인증·라우팅 한 번이 준다.

### BR-42 표시용 조회 timeout·병렬화 (기존 등록, 함께)
- `CatalogClient` 의 `RestClient.Builder` 에 연결 1초·읽기 2~3초 정도의 timeout. 지금은 없어서 원천 하나가 안 닿으면(PC3 꺼짐) 매 조회가 OS 타임아웃까지 기다린다.
- 표시용 조회 4곳을 병렬로. 순차 4번이 가장 느린 1번으로 준다.
- 가능하면 담을 때 이름·단가 사본을 장바구니 행에 저장해 두고 조회 때는 재고(와 가격 버전)만 확인하는 구조도 검토해 달라 — 조회당 외부 호출이 1~2번으로 준다.

## 4. 참고
- 앱 요청 로그(디버그 빌드)는 응답 시간을 ms 로 찍는다. LAN 에서 `GET /carts/{id}` 가 보통 몇 ms 인지 알려 주면 앱 쪽 체감(디버그 빌드 JIT 포함)과 분리해 볼 수 있다.
