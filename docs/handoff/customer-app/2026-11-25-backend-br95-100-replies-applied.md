# 회신 — BR-95·96·97·99·100(1단계) 회신 앱 반영

- 보낸 앱: customer-app (PC 1)
- 받는 백엔드 영역: platform
- 원 문서(백엔드 회신): `../pmart-backend/docs/handoff/clients/customer-app/2026-11-25-reply-br95-br100-decisions.md`, `2026-11-25-reply-br100-r1-r9.md`, `2026-11-25-reply-br96-br97-delivery-guide-cart-list-amount.md`, `2026-11-25-reply-br99-banner-image-width.md`
- 생성: cart·order·product-content·storefront 클라이언트 재생성(백엔드 `5ee78be7` — 그 시각 백엔드 작업 폴더에 R7 `lowStockQty` 미커밋 변경이 있어 contracts.lock `backendContractsDirty: true`. 앱은 `lowStockQty` 를 아직 쓰지 않는다)
- 상태: 반영(목·시험). LAN 실기기 확인 대기.

## 반영
- **BR-99** 배너 그림에 `?w=` — 360·720·1080·1440 단계(그릴 폭 × 화소 비율 이상 가장 작은 값). 홈 배너·홈 팝업은 화면 폭, 로딩 화면 그림은 1440. 바뀜 비교(로딩 화면)는 원래 주소로.
- **BR-97** 장바구니 막대 줄 긋기 금액 = `Cart.selectedListAmount`(할인이 있을 때만). 앱이 더하지 않는다 — 옛 응답(값 없음)이면 그리지 않는다.
- **BR-96** `GET /delivery-options`: `minOrderAmount` VALUE 만 숫자(NOT_SET → 없음, 0 아님), `deliveryTip.tiers`, 응답의 `serviceHours` → 홈 "최소주문 15,000원"·"30,000원부터 배달팁 0원"·배달 안내 시트(구간·운영 시간).
- **BR-100 R1** 상세 `origin`·`expiryGuide`·`legalInfo[]` 사용(빈 글은 없음). 0.9.0 이 LAN 에 오기 전 응답이면 지금처럼 notices 줄로.
- **BR-100 R9** 상품페이지 배너 `GET /storefront/banners?placement=PRODUCT_DETAIL` — 비면 칸을 뺀다.
- **BR-100 Q1·Q2** "모든 리뷰는 검토 후 보여드려요"·공유 버튼 넣지 않음(원래 넣지 않았다).
- **BR-95** 반품·교환 진입: "반품 신청하기"는 늘 흐리게 + "반품(환불)은 고객센터에서 도와드려요" + [고객센터 문의하기]. 교환 이유에서 "일부 안 왔어요"·"배달완료인데 안 왔어요"를 뺌. 교환 접수는 계약(ADR-0087 구현) 전이라 목 그대로.

## 질문
- Q1 상품페이지 배너 비율: 회신은 "홈·카테고리와 같은 2.8:1". 사용자 레퍼런스의 상품페이지 배너 칸은 약 411×91dp(약 4.5:1)이다. 같은 그림을 쓰면 위아래가 잘린다 — (가) 상품페이지 전용 규격 4.5:1 을 `banner-image-specs` 에 둔다, (나) 2.8:1 로 그리고 앱 칸 높이를 바꾼다 — 어느 쪽인지(앱 칸 높이는 사용자에게 함께 묻는다).
- Q2 교환 접수 계약(ADR-0087) 나오면 알려 주세요 — 앱 신청서·이유·교환비(정책값 CONFIG_REQUIRED) 연결.

## 로딩 계획(`clients/customer-app/2026-11-25-customer-app-loading-plan.md`) §5 답
- 이미지 불변·1년 캐시 확인 감사합니다 — 앱은 디스크 캐시만 붙이면 된다는 것으로 이해(패키지 추가는 사용자 확인 뒤).
- **S5 상세 2번 요청의 두 번째**: `GET /prices?skus=<그 상품 옵션 SKU 전부>`(pricing). product-content 옵션 `price`·`priceVersion` 은 정가뿐이고 **기간 할인(salePrice·ratePercent·name·endsAt)과 PRICE_NOT_SET(notSet)이 없어서** 부른다(pricing 0.3.0 — 상세 할인가 표시, ADR-0082). 코드 `apps/customer_app/lib/features/catalog/data/catalog_repository.dart` `_pricesFor`.
- 요청 R-S5: product-content 상세 옵션에 지금 기간 할인(`discount {salePrice, ratePercent, name, endsAt}`)과 가격 미설정 표시를 함께 실어 주면 앱은 `/prices` 를 부르지 않고 한 번에 그린다. 어렵다면 앱은 가격 없이 본문을 먼저 그리고 가격 줄만 나중에 채우는 쪽으로 바꾼다.

## BR-100 2단계·R7 반영(회신 `2026-11-25-reply-br100-r3-r5.md`·`2026-11-25-reply-br100-r1-r9.md` R7 갱신)
- 재생성: customer·storefront·product-content·search(백엔드 `cc5adcec`, contracts 깨끗).
- R3 찜 수 — `GET /product-wish-counts?productIds=` 로 상세·리뷰 전체 보기 아래 막대 하트 밑 숫자. 0·읽는 중·실패면 숫자 없음(0 으로 보이지 않음). 찜·빼기 서버 반영 뒤 다시 읽음(앱이 ±1 하지 않음).
- R5 함께 산 상품 — `GET /storefront/products/{id}/related?kind=BOUGHT_TOGETHER&mfcId=` → "다른 사람들이 함께 구매한 상품" 구획, 빈 목록이면 구획 없음. "함께 본 상품"은 실서버에서 그리지 않음(목만).
- R7 "N개 남음" — 상세 옵션 줄(LOW + `lowStockQty` → "N개 남음", 수가 없으면 "남은 수량이 적어요"), 진열·검색 카드 `lowStockQty` → 사진 왼쪽 아래 작은 꼬리표. 레퍼런스에 모양이 없어 자리는 사용자 확인 대기.
