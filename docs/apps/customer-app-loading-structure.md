# 고객앱 로딩 구조 — 홈·상품 상세·주문내역·리뷰 (2026-11-25 기준)

- 목적: 사용자 2026-11-24 "상품 페이지·홈·주문내역·리뷰 로딩이 너무 길다" — 다른 쪽(백엔드·다른 세션)에서도 원인을 찾을 수 있게 **지금 구현된 요청 순서**를 적는다.
- 범위: `apps/customer_app` 실서버 모드(`PMART_ENV=local`). 목 모드는 저장소가 메모리라 해당 없음.
- 아직 재지 않았다: 기기에서 profile 빌드로 화면별 시간을 재는 것은 다음 할 일(폰 연결 필요). 아래 "의심 지점"은 코드로 본 후보이지 측정 결과가 아니다.
- 서버 쪽 이미 확인한 것(2026-11-24): API 응답 자체는 빠름(홈 0.07~0.09초 등). 홈 배너 그림이 장당 약 2.2MB PNG → BR-99(`docs/handoff/customer-app/2026-11-25-backend-banner-image-size.md`).

## 0. 공통 — HTTP·상태·이미지

| 항목 | 지금 구현 | 위치 |
|---|---|---|
| HTTP | dio 하나(회원 토큰) `dioProvider` + 장바구니 전용 `guestDioProvider`. 연결 제한 5초·응답 제한 15초 | `lib/shared/providers.dart`, `packages/pmart_core/lib/src/http_client.dart` |
| 인터셉터 순서 | 헤더 → (debug 만) 로그 → 401 토큰 갱신(한 번에 하나) → 429/재시도(최대 3번, 0.5초부터 늘림) | `packages/pmart_core/lib/src/interceptors.dart` |
| 요청마다 하는 일 | `X-Device-Id` — 처음 한 번 보안 저장소에서 읽고 이후 메모리(`_pending`). 액세스 토큰은 메모리 값 | 같은 파일 `PmartHeadersInterceptor` |
| 비회원 장바구니 요청 | 요청마다 `tokens.readRefreshToken()`(**보안 저장소 읽기**) 후 없으면 비회원 세션 시작 | `lib/features/cart/data/guest_session.dart` `GuestSessionInterceptor.onRequest` |
| 상태 | Riverpod 3. 화면이 `ref.watch(...)` 하는 provider 가 처음 그려질 때 요청을 시작한다. 대부분 `autoDispose` — **화면을 나가면 버리고 다시 들어오면 다시 읽는다**(예외는 아래 표에 적음) | 각 `*_providers.dart`·`*_controller.dart` |
| 이미지 | `Image.network`(Flutter 기본). **디스크 캐시 없음**(`cached_network_image` 등 안 씀) — 메모리 이미지 캐시만. 대부분 `cacheWidth` 로 화면 크기만큼만 디코드. 주소는 게이트웨이 `/api/v1/content-images/{imageId}` | `lib/features/catalog/presentation/widgets/content_image.dart`, `product_tile_card.dart`, `home_screen.dart:1033` 등 |
| 로그 | debug 빌드는 요청마다 로그 줄(`PmartLogInterceptor`). release/profile 은 없음 | `providers.dart` `log: kDebugMode ? debugPrint : null` |

> 지금 사용자가 쓰는 LAN APK 는 **debug 빌드**(사설 CA 를 debug 에서만 믿음 — CLAUDE.md). debug 는 JIT·로그·검사 때문에 화면 그리기가 release 보다 몇 배 느리다. 측정은 profile 빌드로 해야 한다.

## 1. 앱 시작 → 홈

### 1-1 시작 게이트 (`lib/features/start/presentation/start_controller.dart` `startStepProvider`)
아래를 **차례로** 기다린 뒤에야 홈을 그린다(하나가 끝나야 다음을 본다).

1. `splashPromoProvider` — 로딩 화면 프로모션 이미지 조회. 있으면 **최소 1.5초**(`splashPromoMinDuration`) 보여 준다(`splashHoldProvider`).
2. `startFlagsProvider` — 처음 실행 여부(기기 저장소).
3. `sessionRestoreProvider` — 저장된 refresh token 을 보안 저장소에서 읽고, 있으면 `currentAccountId()` 로 서버 확인(토큰 갱신 포함 가능).
4. `addressBookProvider` — 회원: `GET` 주소록 1번. 비회원: 기기에 둔 배송지 ID 마다 `GET` 을 **하나씩 차례로**(`_guestBook`의 for-await).
5. → `currentMfcIdProvider`(주소록의 쇼핑 센터) 확정 → 홈.

### 1-2 홈 화면이 부르는 것 (`lib/features/catalog/presentation/home_screen.dart`)
홈이 그려진 뒤 **동시에** 시작한다(서로 기다리지 않음).

| provider | 요청 | keepAlive |
|---|---|---|
| `homeProvider` | `GET /storefront/home?mfcId=` (홈 구성 — 배너·영역·상품 카드 포함) | **유지**(autoDispose 아님). 1분 지나면 다시 읽음(`homeStaleAfter`) |
| `categoriesProvider` | `GET` 카테고리 트리 | |
| `homeDeliveryOptionsProvider` | 배달 방식·최소주문·배달팁(checkout 쪽, 비회원은 guestDio) | autoDispose |
| `homeInProgressOrderProvider` | 회원만 — 진행 중 주문 찾기(주문 목록 조회 여러 개 `Future.wait`) → 있으면 `homeOrderEtaProvider` 가 `GET /orders/{id}` + 도착 예정 | autoDispose |
| `couponCampaignsProvider` | 쿠폰 캠페인 | |
| `pendingCheckoutsProvider` | 결제 중이던 주문(기기 저장소 + 조회) | |
| `sectionItemsProvider` | 영역 "더 보기" 때만 | |
| 이미지 | 배너(장당 ~2.2MB PNG — BR-99), 카테고리 아이콘, 상품 카드 사진 — 화면에 들어올 때마다 네트워크(디스크 캐시 없음) | |

## 2. 상품 상세 (`product_detail_screen.dart`, `product_detail_sections.dart`)

### 2-1 본문이 나오기 전에 기다리는 것
- `productDetailProvider(productId)` — **두 번 차례로**:
  1. `GET /product-contents/{productId}?mfcId=` (콘텐츠·옵션·재고 가용)
  2. 그 결과의 SKU 들로 `GET /prices?skus=a,b` (가격·기간 할인)
  
  둘 다 끝나야 본문(사진·이름·가격)을 그린다. 그 전에는 로딩 표시.
- 화면을 나가도 **5분 유지**(`productDetailKeep`), 다시 들어오면 바로 보이고 뒤에서 다시 읽음. 센터(`currentMfcIdProvider`)가 바뀌면 새로 읽음.

### 2-2 본문이 그려지며 동시에 시작하는 것
| 구획 | provider | 요청 |
|---|---|---|
| 평점 칸 | `productRatingProvider(productId)` | `GET` 평점 요약(product-content `getRatingSummary`) |
| 함께 본/함께 구매한 상품 | `relatedProductsProvider` | 실서버는 요청 없음(계약 없음 — BR-100 R5) |
| 평점 좋은 상품 | `categoryShelfProvider(sort: RATING)` | `GET /search/products?categoryId=&sort=RATING&mfcId=` |
| 같은 카테고리 인기상품 | `categoryShelfProvider(sort: POPULAR)` | `GET /search/products?...sort=POPULAR` |
| 배너 | `productPageBannersProvider` | 실서버는 요청 없음(BR-100 R9) |
| 리뷰 구획 | `productReviewListProvider(최신순)` | `GET /products/{id}/reviews` |
| 리뷰 사진 격자 | `productReviewListProvider(사진만)` | `GET /products/{id}/reviews?withPhotoOnly=true` |
| 내 리뷰 알아보기 | `myWrittenReviewsProvider`(회원) | `GET /reviews`(리뷰 자격 목록) — **다음 쪽이 있으면 차례로 최대 10번** |
| 찜 하트 | `wishlistIdsProvider`(회원) | 찜 목록 |
| 이미지 | 상품 사진·설명 사진·선반 카드 사진·리뷰 사진 | 디스크 캐시 없음 |

- 본문은 `ListView(children:)`(`product_detail_screen.dart:599`) — 구획 위젯은 화면(+미리 그리는 여유 영역)에 가까워질 때 만들어지므로, **아래 구획(인기상품·리뷰 등)의 요청은 스크롤해 내려갈 때 나간다**. 첫 화면에 보이는 평점·선반 1~2개는 본문과 함께 바로 나간다.

## 3. 주문내역 (`lib/features/orders/presentation/orders_screens.dart` `OrderListScreen`)

| 무엇 | provider | 요청 |
|---|---|---|
| 목록 | `orderListProvider(query)`(회원) | `GET /orders?status=&from=&q=` 1번(기본 최근 3개월) — 상태 칩·기간을 바꾸면 조건마다 새로 |
| 카드 상품 사진 | 줄 `imageUrl`(order 0.19.0 BR-71) | 있으면 사진만 받음. **없으면 줄마다 `productDetailProvider`** → 상품 하나당 `product-contents` + `prices` 2번 |
| "더보기"(카드 펼침) | `orderDetailProvider(orderId)` | 누를 때 `GET /orders/{id}` |
| 주문 상세 화면 | `orderDetailProvider` + 줄마다 `productDetailProvider`(사진·"지금 더 할인 중" 표시용) + 결제 수단 `orderPaymentProvider` + 클레임 `claimProvider` + 리뷰 자격 `orderReviewEligibilitiesProvider`(쪽이 있으면 차례로 최대 10번) | |

- 모두 autoDispose — 주문내역을 나갔다 오면 다시 읽는다.

## 4. 리뷰 — 상품리뷰 전체 보기 (`lib/features/reviews/presentation/product_reviews_screen.dart`)

| 무엇 | provider | 요청 |
|---|---|---|
| 목록 | `productReviewListProvider((productId, sort, photoOnly))` | `GET /products/{id}/reviews?sort=&withPhotoOnly=` — 정렬·사진리뷰만을 바꾸면 조건마다 새로 |
| 사진 격자 | `productReviewListProvider(사진만)` | 위와 별도 1번 |
| 내 리뷰 알아보기 | `myWrittenReviewsProvider`(회원) | `GET /reviews` 차례로 최대 10쪽 — **이게 끝나기 전에는 카드 아래 [도움돼요] 칸을 비워 둔다**(높이 흔들림 방지, 2026-11-21) |
| 카드 옵션 줄 | `productDetailProvider(productId)` | 상세에서 왔으면 5분 유지 값 |
| 더 보기 | 스크롤 끝에서 `loadMore` | 커서로 다음 쪽 |
| 이미지 | 카드 사진(160dp)·격자 사진 | 디스크 캐시 없음 |

리뷰관리(마이 → 리뷰관리)는 `writableReviewsProvider`·`myReviewsProvider` 가 `GET /reviews?state=` 를 읽고, 카드마다 리뷰 본문 `reviewProvider(reviewId)` → `GET /reviews/{id}` 를 따로 부른다.

## 4-1. 결제 — 주문서의 토스 결제위젯 (`lib/features/payment/presentation/pg_widget_session.dart`, `checkout/presentation/order_sheet_screen.dart`)
사용자 2026-11-25 "주문서형 토스페이먼츠 컴포넌트가 뜨는 게 느리다".

1. 배송 방식 화면 [다음] → `GET /payment-widget-config`(결제위젯 키)를 **초안 만들기와 동시에** 미리 요청(`delivery_select_screen.dart:741`, provider 는 앱이 켜져 있는 동안 유지).
2. 초안(`prepare` — 견적) 끝 → 주문서 화면.
3. 주문서가 그려지면 그때 `TossPgWidgetSession` 을 만들고 `renderPaymentMethods`·`renderAgreement` 를 동시에 시작 — SDK 가 **WebView(flutter_inappwebview)** 를 띄우고 토스 서버에서 위젯 페이지·스크립트를 받아 결제수단·약관을 그린다. 둘 다 끝나야 "결제수단 불러오는 중"이 사라지고 결제하기가 열린다.
4. 금액은 서버 견적 총액(`quote.totalAmount`) — 견적이 있어야 그리기 시작.

- 의심 지점: (P1) 3번이 주문서가 뜬 **뒤에야** 시작 — WebView 엔진 첫 시동(Android Chromium)·토스 위젯 페이지 내려받기가 그대로 기다림이 된다. (P2) debug 빌드의 플랫폼 뷰(WebView) 합성은 느림. (P3) 토스 서버·인터넷 구간(우리 서버 밖).
- 개선 후보(아직 안 함): ① 배송 방식 화면에서 WebView 엔진을 미리 깨우기(보이지 않는 빈 WebView), ② 결제위젯 세션을 주문서 앞(배송 방식 화면)에서 미리 만들어 그려 두고 견적 금액으로 `updateAmount`(결제 코드 구조 변경 — 금액 불일치 검사는 그대로).

## 5. 코드로 본 의심 지점 (측정 전 — 확인 필요)

| # | 지점 | 왜 느릴 수 있나 | 확인 방법 |
|---|---|---|---|
| S1 | debug 빌드 APK | 그리기·스크롤이 release 보다 훨씬 느림, 요청 로그 | profile 빌드로 같은 화면 재기 |
| S2 | 홈 배너 그림 ~2.2MB PNG | 장마다 받고 디코드. 디스크 캐시가 없어 앱을 다시 켜면 또 받음 | BR-99 회신, 네트워크 탭에서 크기·시간 |
| S3 | 이미지 디스크 캐시 없음 | 홈·상세·리뷰 사진을 앱 재시작마다 다시 받음 | 두 번째 실행 시간 비교 |
| S4 | 시작 게이트가 차례로 | 프로모션(최소 1.5초) → 세션 확인(서버) → 주소록(서버) → 홈 조회. 홈 요청은 주소록이 끝나야 시작 | 시작~홈 첫 그림 시간을 단계별로 |
| S5 | 상품 상세 2단 요청 | 콘텐츠 → 가격이 차례라 왕복 2번 후 본문 | 두 요청 시간 합 |
| S6 | `myWrittenReviewsProvider` 최대 10쪽 차례 | 회원이고 리뷰 자격이 많으면 상세·리뷰 화면마다 여러 번 왕복. 리뷰 화면의 [도움돼요] 칸이 이것을 기다림 | 회원 계정 자격 수·쪽 수 |
| S7 | 화면을 나가면 버림(autoDispose) | 주문내역·리뷰·상세 선반은 들어갈 때마다 다시 읽음(상세 본문만 5분 유지) | 같은 화면 재진입 시간 |
| S8 | 비회원 장바구니 요청마다 보안 저장소 읽기 | Android 보안 저장소 읽기가 느린 기기 있음(장바구니·홈 배달 안내) | 비회원으로 재기 |
| S9 | 주문 줄 사진이 없을 때 줄마다 상품 조회 | BR-71 이전 응답이면 상품 수×2 요청 | 서버 응답에 `imageUrl` 있는지 |
| S10 | 상품 상세 구획마다 따로 요청 | 스크롤하면 구획마다 새 요청(검색 2번·리뷰 2번·자격) — 내려갈 때 빈 칸이 잠깐 보임 | 스크롤 중 요청 시각 |

## 7. 진행 (2026-11-25)
- S2 배너: 서버 축소본(storefront 0.16.0 BR-99) `?w=` 360·720·1080·1440 — 홈 배너·팝업·로딩 화면 그림에 붙임(장당 약 2.2MB → 약 0.1MB).
- S3 디스크 캐시: `cached_network_image ^4.0.7`(flutter_cache_manager 3.5.0). 모든 서버 사진을 `pmartNetworkImage`(`lib/shared/network_image.dart`)로 — `main.dart` 가 `pmartImageDiskCache = true`, 위젯 시험은 끈 채(플러그인 없음) 기본 NetworkImage. 서버 이미지는 ID 마다 불변·1년 immutable(백엔드 로딩 계획 회신 §5).
- S4 시작 단계: `startPrefetchProvider` — 프로모션(1.5초는 그대로)이 떠 있는 동안 세션 확인 → 주소록 → 홈 조회를 미리 한다(앱이 listen). 화면 차례는 그대로.
- S5: 두 번째 요청은 `/prices`(기간 할인·가격 미설정) — 백엔드에 상세에 함께 실어 달라고 요청(R-S5).
- 아직: S1 profile 측정, S6 리뷰 자격 10쪽, S7 autoDispose 유지 시간, 토스 위젯 미리 띄우기(§4-1).

## 6. 관련 문서
- 할 일 메모: 기기 측정(profile) — 이 PC 세션 메모리 `plan-loading-measure`
- BR-99 배너 그림 크기: `docs/handoff/customer-app/2026-11-25-backend-banner-image-size.md`
- 상세 속도 요청(이전): 백엔드 요청 2026-11-19 상세 속도 R2(상세 5분 유지의 근거)
- 아키텍처 정본: `docs/architecture/client-architecture.md`
