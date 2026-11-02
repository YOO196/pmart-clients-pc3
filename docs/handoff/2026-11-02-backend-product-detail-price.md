# [pmart-clients → pmart-backend] 상품 상세 옵션 가격(`SaleOption.price`)이 비어 옴 (BR-36) (2026-11-02)

- 관련: `contracts/openapi/product-content-service.yaml` `SaleOption.price`, `pricing-service.yaml` `GET /prices`, 안내 `2026-10-31-clients-notice-product-availability.md`, `2026-10-30-clients-notice-public-browse-and-test-data.md`
- 우선: 중간(앱이 우회해 표시 중). 결정만 필요하다.

## 1. 현상 (LAN 192.168.0.40:8080, 2026-11-02)
- `GET /api/v1/product-contents/PRD-22a51eb4-f000-4612-8246-aae14c49a2d2?mfcId=MFC-SEED-01`
  → `options[0] = { sku: E-00000017, label: null, price: null, availability: {carried: true, state: AVAILABLE} }`
- 같은 상품이 `GET /storefront/home` 카드에서는 `basePrice: 5480`, `GET /prices/E-00000017` 도 `{basePrice: 5480, priceVersion: 1}` 200.
- product-content-service `ContentQueries`(281행 근처) 주석: "가격은 pricing 의 것이라 넣지 않는다." 의도된 동작으로 보인다.
- 그러나 계약의 `SaleOption.price` 설명은 "pricing 사본. 견적 확정은 order 초안." 이라 **계약 설명과 구현이 다르다.** 앱은 계약 설명을 믿고 상세 가격을 `price` 에서만 읽어 "가격 확인 중"만 보였다.

## 2. 앱 처리 (반영됨)
- 상세 응답의 옵션 `price` 가 비면 그 SKU 들을 `GET /prices?skus=a,b`(style=form, explode=false)로 읽어 합친다.
- `notSet` 에 있는 SKU 는 "판매 불가"로 보이고 담기를 열지 않는다(0원 아님).
- 가격 조회가 실패하면 상세는 보이되 그 옵션은 "가격 확인 중"으로 남는다.
- 상세에 `price` 가 오면 가격 API 를 부르지 않는다. 백엔드가 채우기 시작해도 앱은 그대로 동작한다.

## 3. 요청 (택1)
- (a) 상세·카드 일괄 조회의 `SaleOption.price` 에 pricing 사본을 채운다(계약 설명대로). 상세 1회 호출로 끝나고 가격·재고의 `asOf` 가 한 응답에 묶인다.
- (b) 계약 설명을 "채우지 않는다. 표시 가격은 `GET /prices?skus=` 로 읽는다"로 고친다. 앱은 지금 방식 유지.
- 어느 쪽이든 `PRICE_NOT_SET` 인 SKU 를 상세에서 어떻게 표현할지(옵션 제외 / `price` 없음 / 별도 표시) 알려 달라. 지금 앱은 `/prices` 의 `notSet` 으로 판단한다.

## 4. 참고
- 홈 카드의 `basePrice` 는 storefront 가 채우고 있어 홈·검색에서는 가격이 보인다. 상세만 비었다.
