// 화면 캡처 도구(디자인 전후 비교용). 에뮬레이터 없이 목 모드 앱을 테스트 러너로 그려 PNG 로 남긴다.
//   flutter test tool/screenshots.dart --update-goldens --dart-define=SHOT_DIR=<절대 경로>
// 글꼴: 테스트 러너에는 한글 글꼴이 없어 이 PC 의 Noto Sans KR(없으면 맑은 고딕)을 읽는다(캡처에만 쓰고 앱에 넣지 않는다).
// 상품 사진은 테스트에서 네트워크를 쓰지 않아 자리표시로 나온다.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';
import 'package:customer_app/features/profile/domain/profile.dart'
    show ProfilePhotoSource;
import 'package:customer_app/features/profile/presentation/profile_photo.dart';
import 'package:customer_app/l10n/gen/app_localizations.dart';

import 'package:customer_app/app.dart';
import 'package:customer_app/features/withdrawal/data/withdrawal_repository.dart';
import 'package:customer_app/features/withdrawal/presentation/withdrawal_screen.dart';
import 'package:customer_app/shared/shopping_context.dart'
    show currentMfcIdProvider;
import 'package:customer_app/features/address/data/current_location.dart';
import 'package:customer_app/features/address/domain/address.dart';
import 'package:customer_app/features/address/data/mock_address_repository.dart';
import 'package:customer_app/features/address/data/guest_address_store.dart';
import 'package:customer_app/features/auth/data/mock_auth_repository.dart';
import 'package:customer_app/features/cart/data/cart_merge_repository.dart';
import 'package:customer_app/features/cart/data/mock_cart_repository.dart';
import 'package:customer_app/features/catalog/data/mock_catalog_repository.dart';
import 'package:customer_app/features/catalog/presentation/catalog_providers.dart'
    show homeClockProvider, recentSearchesRepositoryProvider;
import 'package:customer_app/features/catalog/data/recent_searches_repository.dart'
    show MockRecentSearchesRepository;
import 'package:customer_app/features/cart/presentation/cart_merge_screen.dart';
import 'package:customer_app/features/start/presentation/current_location_flow.dart';
import 'package:customer_app/features/checkout/data/mock_checkout_repository.dart';
import 'package:customer_app/features/checkout/presentation/checkout_controller.dart';
import 'package:customer_app/features/claims/data/mock_claims_repository.dart';
import 'package:customer_app/features/orders/data/mock_orders_repository.dart';
import 'package:customer_app/features/profile/data/mock_profile_repository.dart';
import 'package:customer_app/features/profile/presentation/profile_controller.dart'
    show profileProvider;
import 'package:customer_app/features/redelivery/data/mock_redelivery_payments_repository.dart';
import 'package:customer_app/features/reviews/data/mock_reviews_repository.dart';
import 'package:customer_app/features/wishlist/data/wishlist_repository.dart'
    show MockWishlistRepository;
import 'package:customer_app/features/support/presentation/faq_screens.dart'
    show faqRepositoryProvider;
import 'package:customer_app/features/support/data/mock_faq_repository.dart';
import 'package:customer_app/features/support/domain/faq.dart';
import 'package:customer_app/features/reviews/domain/reviews.dart';
import 'package:customer_app/features/reviews/presentation/reviews_controller.dart';
import 'package:customer_app/features/checkout/domain/checkout.dart'
    show CheckoutProblemCode;
import 'package:pmart_core/pmart_core.dart'
    show
        IdempotencyKey,
        MemoryKeyValueStore,
        ProblemDetail,
        UnknownResultFailure;

import 'package:customer_app/shared/providers.dart' show imageOriginProvider;
import 'package:customer_app/features/start/data/splash_promo.dart';
import 'package:customer_app/features/start/presentation/start_controller.dart'
    show splashPromoStoreProvider;

import '../test/support/app_harness.dart';

const _dir = String.fromEnvironment('SHOT_DIR');
const _scrollShots = bool.fromEnvironment('SHOT_SCROLL');

Future<void> _font(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var any = false;
  for (final p in paths) {
    final f = File(p);
    if (!f.existsSync()) continue;
    final bytes = await f.readAsBytes();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
    any = true;
  }
  if (any) await loader.load();
}

/// 테스트 본문 안(runAsync)에서 불러야 적용된다.
Future<void> _loadFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
  final material = '$flutterRoot/bin/cache/artifacts/material_fonts';
  await _font('MaterialIcons', ['$material/materialicons-regular.otf']);
  const win = 'C:/Windows/Fonts';
  await _font('Roboto', ['$win/malgun.ttf', '$win/malgunbd.ttf']);
  const f = 'assets/fonts';
  await _font('Pretendard', [
    '$f/Pretendard-Regular.otf',
    '$f/Pretendard-SemiBold.otf',
    '$f/Pretendard-Bold.otf',
    '$f/Pretendard-ExtraBold.otf',
  ]);
}

void main() {
  setUpAll(initPmartFormatting);
  reviewFlowShots();

  final now = DateTime.utc(2026, 10, 24, 3); // 서울 12:00

  testWidgets('screens', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    Directory(_dir).createSync(recursive: true);
    await t.runAsync(_loadFonts);
    // 테스트 러너는 그림자를 검은 테두리로 그린다 — 실제처럼 그리게 한다.
    debugDisableShadows = false;
    t.view
      ..physicalSize =
          const Size(1080, 2180) // 360 x 727 @3x (레퍼런스와 같은 폭)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);

    final checkout = MockCheckoutRepository(
      latency: Duration.zero,
      now: () => now,
    );
    final reviews = MockReviewsRepository(latency: Duration.zero);
    // 고른 사진 대신 색 칸 PNG(캡처 전용).
    final samplePhotos = <ReviewPhotoFile>[];
    await t.runAsync(() async {
      for (final (i, c) in const [
        Color(0xFFB9A7E8),
        Color(0xFFF2C77B),
        Color(0xFF9BD3B5),
      ].indexed) {
        final rec = ui.PictureRecorder();
        Canvas(rec)
          ..drawRect(const Rect.fromLTWH(0, 0, 240, 240), Paint()..color = c)
          ..drawCircle(
            const Offset(120, 130),
            60,
            Paint()..color = Colors.white.withValues(alpha: 0.7),
          );
        final img = await rec.endRecording().toImage(240, 240);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        samplePhotos.add(
          ReviewPhotoFile(name: 'p$i.png', bytes: png!.buffer.asUint8List()),
        );
      }
    });
    final orders = MockOrdersRepository(latency: Duration.zero, now: () => now)
      ..rejectNextTimeChange = true
      ..rejectReason = 'LOT_EXPIRY_NOT_MET';
    // 상품 6줄인 끝난 주문 — 카드의 [더보기](2026-11-20)
    orders.overrides['order-six'] = {
      ...orders.orderJson('order-seed-2')!,
      'orderId': 'order-six',
      'lines': [
        for (final (i, name) in const [
          (1, '서울우유 1L'),
          (2, '그릭요거트 플레인 400g'),
          (3, '제주 감귤 1kg'),
          (4, '친환경 대추방울토마토 500g'),
          (5, '감자칩 오리지널 110g'),
          (6, '저지방 우유 900mL'),
        ])
          {
            'orderLineId': 'ol-6$i',
            'productId': 'P-000$i',
            'sku': 'E-0000000$i',
            'productName': name,
            'unitPrice': 2980,
            'originalQty': 1,
            'deliveredQty': 1,
          },
      ],
      'shipments': <Object?>[],
    };
    // 반품 회수비 결제(고객센터가 접수한 고객 사유 반품 — order-seed-1).
    final claims = MockClaimsRepository(
      orders: orders,
      latency: Duration.zero,
      now: () => now,
    );
    final returnClaimId = claims.seedReturnFee(
      'order-seed-1',
      left: const Duration(hours: 23, minutes: 40),
    );
    checkout.externals.add(claims);
    // 주소 입력 캡처용 회원 프로필(처음엔 연락처 없음 → "내 연락처"만 묻는 모습).
    final profile = MockProfileRepository(latency: Duration.zero)
      ..nickname = '김피마';
    await t.pumpWidget(
      testApp(
        profile: profile,
        checkout: checkout,
        reviews: reviews,
        orders: orders,
        claims: claims,
        redelivery: MockRedeliveryPaymentsRepository(
          latency: Duration.zero,
          now: () => now,
        ),
        [
          reviewPhotoPickerProvider.overrideWithValue(
            (_, max) async => samplePhotos.take(max).toList(),
          ),
          clockProvider.overrideWithValue(() => now),
          // 회원 탈퇴 캡처: 진행 중 주문이 있어 "탈퇴 처리 대기"가 되는 경우
          withdrawalRepositoryProvider.overrideWithValue(
            MockWithdrawalRepository(latency: Duration.zero, now: () => now)
              ..obligationsNext = [
                {'kind': 'ORDER_IN_PROGRESS', 'ref': 'order-seed-4'},
              ],
          ),
          draftPollPolicyProvider.overrideWithValue((
            interval: Duration.zero,
            attempts: 3,
          )),
        ],
      ),
    );
    await t.pumpAndSettle();

    var n = 0;
    Future<void> shot(String name) async {
      await t.pumpAndSettle();
      // 그림 파일(Image.asset — 카테고리 그림)은 진짜 비동기로 풀린다. 찍기 전에 잠깐 기다린다.
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await t.pump();
      n += 1;
      final file = File('$_dir/${n.toString().padLeft(2, '0')}-$name.png');
      await expectLater(find.byType(CustomerApp), matchesGoldenFile(file.uri));
      // SHOT_SCROLL=true: 아래로 내릴 수 있는 화면은 끝까지 내려가며 더 찍는다(-down1, -down2 …) — 그 뒤 맨 위로.
      if (!_scrollShots) return;
      ScrollableState? main;
      for (final e in find.byType(Scrollable).evaluate()) {
        final s = (e as StatefulElement).state as ScrollableState;
        final p = s.position;
        if (s.axisDirection != AxisDirection.down || !p.hasContentDimensions) {
          continue;
        }
        if (p.maxScrollExtent <= 1) continue;
        if (main == null ||
            p.viewportDimension > main.position.viewportDimension) {
          main = s;
        }
      }
      if (main == null) return;
      final pos = main.position;
      final start = pos.pixels;
      for (var k = 1; k <= 6 && pos.pixels < pos.maxScrollExtent - 1; k++) {
        pos.jumpTo(
          (pos.pixels + pos.viewportDimension * 0.85).clamp(
            0,
            pos.maxScrollExtent,
          ),
        );
        await t.pump();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)),
        );
        await t.pump();
        final down = File(
          '$_dir/${n.toString().padLeft(2, '0')}-$name-down$k.png',
        );
        await expectLater(
          find.byType(CustomerApp),
          matchesGoldenFile(down.uri),
        );
      }
      pos.jumpTo(start);
      await t.pumpAndSettle();
    }

    GoRouter router() => GoRouter.of(t.element(find.byType(Scaffold).first));
    Future<void> go(String path) async {
      router().go(path);
      await t.pumpAndSettle();
    }

    Future<void> scrollDown(double dy) async {
      await t.drag(find.byType(Scrollable).first, Offset(0, -dy));
      await t.pumpAndSettle();
    }

    await shot('home');
    await scrollDown(700);
    await shot('home-2');
    await scrollDown(900);
    await shot('home-3');

    await go('/categories');
    await shot('categories');
    await go('/search');
    await shot('search');
    await t.enterText(find.byKey(const ValueKey('search-field')), '우유');
    await t.tap(find.byKey(const ValueKey('search-submit')));
    await t.pumpAndSettle();
    await shot('search-results');
    // 필터 시트(사용자 캡처 2026-11-20 — 테두리 알약·고른 값 줄·초기화 + 상품 보기)
    await t.tap(find.byKey(const ValueKey('attr-capacity.1l')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('open-filters')));
    await t.pumpAndSettle();
    await shot('filter-sheet');
    await t.tap(find.byKey(const ValueKey('filter-close')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('attr-capacity.1l')));
    await t.pumpAndSettle();
    // 오타 교정 띠(search 0.4.0) — 목 사전 '우우' → '우유'.
    await t.enterText(find.byKey(const ValueKey('search-field')), '우우');
    await t.tap(find.byKey(const ValueKey('search-submit')));
    await t.pumpAndSettle();
    await shot('search-typo');
    await t.tap(find.byKey(const ValueKey('sort')));
    await t.pumpAndSettle();
    await shot('search-sort-sheet');
    await t.tap(find.byKey(const ValueKey('sort-relevance')));
    await t.pumpAndSettle();
    await go('/products?categoryId=C-10&title=유제품');
    await shot('product-list');

    await go('/');
    await tapTile(t, 'P-0001');
    await shot('product-detail');
    await scrollDown(600);
    await shot('product-detail-2');
    // 상품리뷰 전체 보기(사용자 캡처 2026-11-20): 평점·사진 모음·사진리뷰만·정렬 시트·모아보기
    await go('/products/P-0001/reviews');
    await shot('product-reviews');
    await t.tap(find.byKey(const ValueKey('review-sort-open')));
    await t.pumpAndSettle();
    await shot('product-reviews-sort');
    await t.tap(find.byKey(const ValueKey('review-sort-close')));
    await t.pumpAndSettle();
    // 옵션 필터(BR-76 목만 — 서울우유 1개·2개 묶음)
    await t.tap(find.byKey(const ValueKey('review-option-open')));
    await t.pumpAndSettle();
    await shot('product-reviews-option');
    await t.tap(find.byKey(const ValueKey('review-option-close')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('review-photos-more')));
    await t.pumpAndSettle();
    await shot('review-photos');
    await t.tap(find.byKey(const ValueKey('review-photos-close')));
    await t.pumpAndSettle();

    await go('/cart');
    await shot('cart');
    await t.tap(find.byKey(const ValueKey('cart-order')));
    await t.pumpAndSettle();
    await shot('login');
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    // 로그인 뒤 장바구니로 돌아와 수령방법을 고른다(사용자 결정 2026-11-20).
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('mode-single')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    await shot('cart-receive');
    await t.tap(find.byKey(const ValueKey('mode-single')));
    await t.pump();
    await shot('cart-receive-picked');
    // 예약배달을 누르면 도착 시간 시트(레퍼런스 5-4).
    await t.tap(find.byKey(const ValueKey('mode-scheduled')));
    await t.pumpAndSettle();
    await shot('slot-sheet');
    await t.tap(find.byKey(const ValueKey('slot-sheet-close')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('mode-single')));
    await t.pump();
    // 주문하기가 재고 부족(422 INSUFFICIENT_STOCK, order 0.8.0)으로 막혀 장바구니로 돌아온 모습.
    checkout
      ..rejectNextDraft = CheckoutProblemCode.insufficientStock
      ..rejectNextDraftDetails = const [
        ProblemDetail(
          field: 'E-00000001',
          reason: 'requestedQty=2;availableQty=1',
        ),
        ProblemDetail(field: 'E-00000005', reason: 'NOT_HANDLED'),
      ];
    await t.tap(find.byKey(const ValueKey('cart-order')));
    await t.pumpAndSettle();
    await shot('cart-stock-shortage');
    // 테스트 시계는 저절로 흐르지 않아 알림이 다음 캡처까지 남는다 — 지운다.
    ScaffoldMessenger.of(t.element(find.byType(Scaffold).first))
        .clearSnackBars();
    await t.pumpAndSettle();
    unawaited(router().push('/checkout'));
    await t.pumpAndSettle();
    await shot('order-sheet');
    // 뒤로 → "주문을 취소할까요?"(레퍼런스 6-0)
    await t.tap(find.byType(BackButton).last);
    await t.pumpAndSettle();
    await shot('order-sheet-leave');
    await t.tap(find.text('아니요'));
    await t.pumpAndSettle();
    // 레퍼런스 6-3 "내 연락처"(BR-60) — 주문서 칸과 번호 변경 창.
    await t.ensureVisible(find.byKey(const ValueKey('contact-change')));
    await t.pumpAndSettle();
    await shot('order-sheet-contact');
    await t.tap(find.byKey(const ValueKey('contact-change')));
    await t.pumpAndSettle();
    await shot('contact-sheet');
    await t.tap(find.byKey(const ValueKey('contact-close')));
    await t.pumpAndSettle();
    await scrollDown(700);
    await shot('order-sheet-2');
    // 할인쿠폰(order 0.18.0·promotion 0.2.0, 레퍼런스 6-5) — 고르기 → 주문서 할인 → 다시 빼 둔다.
    Future<void> openCoupons() async {
      await t.ensureVisible(find.byKey(const ValueKey('coupon-open')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('coupon-open')));
      await t.pumpAndSettle();
    }

    await openCoupons();
    await t.tap(find.byKey(const ValueKey('coupon-CPN-MOCK-1')));
    await t.pump();
    await shot('coupon-pick');
    await t.tap(find.byKey(const ValueKey('coupon-pick-use')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('coupon-section')));
    await t.pumpAndSettle();
    await shot('order-sheet-coupon');
    await openCoupons();
    await t.tap(find.byKey(const ValueKey('coupon-CPN-MOCK-1')));
    await t.tap(find.byKey(const ValueKey('coupon-pick-use')));
    await t.pumpAndSettle();

    await go('/my');
    await shot('my');
    await go('/me/coupons');
    await shot('coupon-box');
    await t.tap(find.byKey(const ValueKey('coupon-tab-available')));
    await t.pumpAndSettle();
    await shot('coupon-box-available');
    await t.tap(find.byKey(const ValueKey('coupon-tab-past')));
    await t.pumpAndSettle();
    await shot('coupon-box-past');
    await go('/orders');
    await shot('orders');
    // 사용자 캡처(2026-11-20) 조회 기간·주문 상태·정보 시트
    await t.tap(find.byKey(const ValueKey('orders-period')));
    await t.pumpAndSettle();
    await shot('orders-period-sheet');
    await t.tap(find.byKey(const ValueKey('orders-sheet-close')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('orders-status')));
    await t.pumpAndSettle();
    await shot('orders-status-sheet');
    await t.tap(find.byKey(const ValueKey('orders-sheet-close')));
    await t.pumpAndSettle();
    // 끝난 주문 카드의 [같은 상품 담기](레퍼런스 9-2 1, 2026-11-20)
    final reorderAll = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('order-reorder-all-'),
    );
    for (var i = 0; i < 8 && reorderAll.evaluate().isEmpty; i++) {
      await t.drag(find.byType(Scrollable).last, const Offset(0, -500));
      await t.pumpAndSettle();
    }
    if (reorderAll.evaluate().isNotEmpty) {
      await t.ensureVisible(reorderAll.first);
      await t.pumpAndSettle();
      await shot('orders-reorder-all');
    }
    final moreSix = find.byKey(const ValueKey('order-more-order-six'));
    for (var i = 0; i < 10 && moreSix.evaluate().isEmpty; i++) {
      await t.drag(find.byType(Scrollable).last, const Offset(0, -500));
      await t.pumpAndSettle();
    }
    if (moreSix.evaluate().isNotEmpty) {
      await t.ensureVisible(moreSix);
      await t.pumpAndSettle();
      await shot('orders-more');
      await t.tap(moreSix);
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('order-less-order-six')));
      await t.pumpAndSettle();
      await shot('orders-more-open');
      await go('/orders');
    }
    await t.tap(
      find
          .byWidgetPredicate(
            (w) =>
                w is Material &&
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('order-'),
          )
          .first,
    );
    await t.pumpAndSettle();
    await shot('order-detail');
    await scrollDown(650);
    await shot('order-detail-2');
    // 상품이 여럿인 주문(order-seed-1)의 상품 줄 — 레퍼런스 9-1 3-3 과 간격 비교용
    await go('/orders/order-seed-1');
    await scrollDown(500);
    await shot('order-detail-lines');
    // 배송현황 — 배달 중 라이더 지도(레퍼런스 8-5). 목 모드는 카카오 지도 대신 안내 칸이 그려진다.
    await go('/');
    await shot('home-ordering');
    await go('/deliveries/dlv-s2?orderId=order-seed-1');
    await shot('tracking-map');
    // 받은 지 60초 넘은 라이더 위치 — 마커 흐리게 + "라이더 위치를 확인하고 있어요"(PC 5 요청 2026-11-19).
    orders.riderStaleSeconds = 90;
    await go('/orders/order-seed-1');
    await go('/deliveries/dlv-s2?orderId=order-seed-1');
    await shot('tracking-map-stale');
    orders.riderStaleSeconds = 4;
    // 오배송 다시 배송비 결제(order-seed-1 에 결제 대기 1건).
    await go('/orders/order-seed-1');
    await shot('order-detail-redelivery');
    // "받았어요"(고객 수령 확인, execution 0.20.0) — 배송 중인 배송(dlv-s2)에만. 확인 대화 → 완료 안내.
    Future<void> showShipment() async {
      await t.ensureVisible(find.byKey(const ValueKey('shipment-sh-2')));
      await t.pumpAndSettle();
      final ctx = t.element(find.byKey(const ValueKey('shipment-sh-2')));
      unawaited(Scrollable.ensureVisible(ctx, alignment: 0.15));
      await t.pumpAndSettle();
    }

    await showShipment();
    await shot('order-detail-receipt');
    await t.tap(find.byKey(const ValueKey('receipt-dlv-s2')));
    await t.pumpAndSettle();
    await shot('order-detail-receipt-dialog');
    await t.tap(find.byKey(const ValueKey('receipt-confirm')));
    await t.pumpAndSettle();
    await showShipment();
    await shot('order-detail-receipt-done');
    await go('/orders/order-seed-1');
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('rdp-open-rdp-1')),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.byKey(const ValueKey('rdp-open-rdp-1')));
    await t.pumpAndSettle();
    await shot('redelivery-payment');
    await go('/claims/$returnClaimId');
    await shot('return-fee');
    await t.tap(find.byKey(const ValueKey('ret-fee-pay')));
    await t.pumpAndSettle();
    await shot('return-fee-paid');
    // 예약 시간 변경 — 결과가 거절(LOT_EXPIRY_NOT_MET)이면 원인 + 기존 시간 그대로.
    await go('/orders/order-seed-4/cancel');
    await shot('cancel-dialog');
    await go('/orders/order-seed-4/reschedule');
    await shot('reschedule-sheet');
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('rs-slot-20:00')),
      120,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('reschedule-sheet')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('rs-slot-20:00')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('reschedule-submit')));
    await t.pumpAndSettle();
    await shot('reschedule-rejected');
    await go('/reviews');
    await shot('reviews');
    // 리뷰 쓰기 + 사진(review 0.2.0). 첫 사진은 결과 불명 → 다시 올리기.
    reviews.uploadFailures.add(const UnknownResultFailure(httpStatus: 503));
    await t.tap(find.byKey(const ValueKey('review-quick-star-ol-1-5')));
    await t.pumpAndSettle();
    await shot('review-write');
    await t.tap(find.byKey(const ValueKey('review-photo-add')));
    await t.pumpAndSettle();
    await shot('review-photo-sheet');
    await t.tap(find.byKey(const ValueKey('review-photo-gallery')));
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('review-photo-add')));
    // 사진 미리보기(Image.memory) 디코딩은 실제 시간이 걸린다.
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await t.pumpAndSettle();
    await shot('review-write-photos');
    await t.tap(find.byKey(const ValueKey('review-photo-retry-0')));
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
    await t.pumpAndSettle();
    await shot('review-write-photos-ok');
    await t.tap(find.byKey(const ValueKey('review-close')));
    await t.pumpAndSettle();
    // 내가 쓴 리뷰 → 리뷰 하나(수정·삭제, 백엔드 요청 2026-11-16 review-edit-delete).
    await t.tap(find.byKey(const ValueKey('review-tab-mine')));
    await t.pumpAndSettle();
    await shot('review-mine');
    await t.tap(find.byKey(const ValueKey('review-mine-open-rv-mine-1')));
    await t.pumpAndSettle();
    await shot('review-mine-detail');
    await t.tap(find.byKey(const ValueKey('review-edit')));
    await t.pumpAndSettle();
    await shot('review-edit');
    await t.tap(find.byKey(const ValueKey('review-star-3')));
    await t.pumpAndSettle();
    await shot('review-edit-changed');
    await t.tap(find.byKey(const ValueKey('review-edit-close')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('review-delete')));
    await t.pumpAndSettle();
    await shot('review-delete-confirm');
    await t.tap(find.byKey(const ValueKey('review-delete-cancel')));
    await t.pumpAndSettle();
    // 등록 후 3일이 지난 리뷰(서버 LOCKED).
    reviews.reviewJson.firstWhere(
      (r) => r['reviewId'] == 'rv-mine-1',
    )['state'] = 'LOCKED';
    ProviderScope.containerOf(t.element(find.byType(Scaffold).first))
        .invalidate(reviewProvider('rv-mine-1'));
    await go('/reviews');
    await t.tap(find.byKey(const ValueKey('review-tab-mine')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('review-mine-open-rv-mine-1')));
    await t.pumpAndSettle();
    await shot('review-mine-locked');
    reviews.reviewJson.firstWhere(
      (r) => r['reviewId'] == 'rv-mine-1',
    )['state'] = 'PUBLISHED';
    await go('/addresses/new');
    await shot('address-new-empty');
    // 주소를 고른 뒤(레퍼런스 2-7-1: 지도 미리보기·도로명/지번·상세주소·공동현관).
    await t.tap(find.byKey(const ValueKey('address-search')));
    await t.pumpAndSettle();
    await shot('address-new-no-phone');
    // 프로필에 연락처가 있으면 받는 분·연락처 칸이 없다(BR-60, 레퍼런스 2-7-1).
    profile.phone = '01012345678';
    ProviderScope.containerOf(t.element(find.byType(Scaffold).first))
        .invalidate(profileProvider);
    await go('/addresses');
    await go('/addresses/new');
    await t.tap(find.byKey(const ValueKey('address-search')));
    await t.pumpAndSettle();
    await shot('address-new');
    // 휴대폰 번호 확인(OCTOMO) — 레퍼런스 13 연령확인 모양. 문자 보내기 단계는 남은 시간이 1초마다 바뀌어
    // pumpAndSettle 대신 짧게 그린다.
    Future<void> shotNow(String name) async {
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 60));
      }
      n += 1;
      final file = File('$_dir/${n.toString().padLeft(2, '0')}-$name.png');
      await expectLater(find.byType(CustomerApp), matchesGoldenFile(file.uri));
      // SHOT_SCROLL=true: 아래로 내릴 수 있는 화면은 끝까지 내려가며 더 찍는다(-down1, -down2 …) — 그 뒤 맨 위로.
      if (!_scrollShots) return;
      ScrollableState? main;
      for (final e in find.byType(Scrollable).evaluate()) {
        final s = (e as StatefulElement).state as ScrollableState;
        final p = s.position;
        if (s.axisDirection != AxisDirection.down || !p.hasContentDimensions) {
          continue;
        }
        if (p.maxScrollExtent <= 1) continue;
        if (main == null ||
            p.viewportDimension > main.position.viewportDimension) {
          main = s;
        }
      }
      if (main == null) return;
      final pos = main.position;
      final start = pos.pixels;
      for (var k = 1; k <= 6 && pos.pixels < pos.maxScrollExtent - 1; k++) {
        pos.jumpTo(
          (pos.pixels + pos.viewportDimension * 0.85).clamp(
            0,
            pos.maxScrollExtent,
          ),
        );
        await t.pump();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)),
        );
        await t.pump();
        final down = File(
          '$_dir/${n.toString().padLeft(2, '0')}-$name-down$k.png',
        );
        await expectLater(
          find.byType(CustomerApp),
          matchesGoldenFile(down.uri),
        );
      }
      pos.jumpTo(start);
      await t.pumpAndSettle();
    }

    await go('/me/phone-verification');
    await shot('phone-verify-input');
    await t.tap(find.byKey(const ValueKey('pv-next')));
    await shotNow('phone-verify-send');
    await t.tap(find.byKey(const ValueKey('pv-sent')));
    await shotNow('phone-verify-done');
    await t.tap(find.byKey(const ValueKey('pv-done')));
    await t.pumpAndSettle();
    await go('/notifications/settings');
    await shot('notice-settings');
    await go('/notifications');
    await shot('notifications');
    await go('/addresses');
    await shot('addresses');
    await go('/addresses/edit');
    await shot('address-edit');
    // 주소 편집 [수정] → 주소 상세(별칭 칸, 레퍼런스 3-1 2-4 와 비교)
    await t.tap(
      find
          .byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith(
                  'address-modify-',
                ),
          )
          .first,
    );
    await t.pumpAndSettle();
    await shot('address-modify-form');
    // 마이 "취소·반품 내역"(BR-33) — 환불 완료 줄 하나를 더 보인다.
    claims.claims['claim-demo-done'] = {
      'claimId': 'claim-demo-done',
      'version': 3,
      'orderId': 'order-seed-1',
      'type': 'CANCEL',
      'state': 'CLOSED',
      'openedAt': '2026-11-18T05:10:00Z',
      'reason': 'CHANGE_OF_MIND',
      'lines': <Object?>[],
      'refunds': [
        {
          'state': 'COMPLETED',
          'pgResult': 'SUCCESS',
          'amount': 15960,
          'completedAt': '2026-11-18T05:30:00Z',
        },
      ],
    };
    await go('/claims');
    await shot('my-claims');
    await go('/search');
    await t.enterText(find.byKey(const ValueKey('search-field')), '');
    await t.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await shot('search-recent');
    // 고객센터(레퍼런스 9-2 "3-1. 문의하기" 모양) · 문의 남기기 · 내 문의 · AI 상담
    await go('/support');
    await shot('support');
    await go('/support/inquiries/new');
    await shot('inquiry-new');
    // 사진 첨부(case 0.14.0) — 두 장 고르면 바로 올린다.
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('inq-photo-add')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.byKey(const ValueKey('inq-photo-add')));
    await t.pumpAndSettle();
    // 사진 미리보기(Image.memory) 디코딩은 실제 시간이 걸린다.
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await t.pumpAndSettle();
    await shot('inquiry-new-photos');
    await go('/support/inquiries');
    await shot('inquiries');
    await go('/support/inquiries/inq-seed-1');
    await shot('inquiry-detail');
    // 답변 뒤 만족도(case 0.15.0)
    await t.tap(find.byKey(const ValueKey('inquiry-rate-4')));
    await t.pumpAndSettle();
    await shot('inquiry-rate');
    // 주문 문의하기 → 무엇을 도와드릴까요?(레퍼런스 9-2 3-1) → 배송 신고(case deliveryIssue)
    await go('/orders/order-seed-4/help');
    await shot('order-help');
    await t.tap(find.byKey(const ValueKey('order-help-delayed')));
    await t.pumpAndSettle();
    await shot('help-delayed-guide');
    await t.tap(find.byKey(const ValueKey('help-guide-inquiry')));
    await t.pumpAndSettle();
    await shot('inquiry-delivery-issue');
    await go('/orders/order-seed-4/help');
    await t.tap(find.byKey(const ValueKey('order-help-other')));
    await t.pumpAndSettle();
    await shot('help-other-guide');
    await t.tap(find.byKey(const ValueKey('help-guide-inquiry')));
    await t.pumpAndSettle();
    // 자주 묻는 질문(customer-assistant 0.2.0) — 목록 · 답(마크다운)
    await go('/support/faqs');
    await shot('faq-list');
    // 질문 유형을 고른 뒤 목록까지 한 화면으로 내려간다(2026-11-20 스크롤 고침)
    await t.tap(find.byKey(const ValueKey('faq-cat-CANCEL')));
    await t.pumpAndSettle();
    await t.drag(
      find.byKey(const ValueKey('faq-scroll')),
      const Offset(0, -300),
    );
    await shot('faq-list-category');
    await go('/support/faqs/faq-cancel-1');
    await shot('faq-detail');
    // 로그인해 있는 고객의 재동의(CU-1 §3)
    await go('/me/consents/reconsent');
    await shot('reconsent');
    await t.tap(find.byKey(const ValueKey('reconsent-close')));
    await t.pumpAndSettle();
    // 상담 종류 고르기(레퍼런스 고객센터 2-1) → 주문 건 문의의 최근 주문(2-4)
    await go('/support/chat');
    await shot('chat');
    Future<void> ask(String q) async {
      await t.enterText(find.byKey(const ValueKey('chat-input')), q);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('chat-send')));
      await t.pumpAndSettle();
    }

    await t.tap(find.byKey(const ValueKey('chat-topic-order')));
    await t.pumpAndSettle();
    await shot('chat-pick-order');
    await t.tap(find.byKey(const ValueKey('chat-recent-order-seed-4')));
    await t.pumpAndSettle();
    await shot('chat-order-picked');
    await ask('언제 도착해요?');
    await shot('chat-order-topic');
    await t.tap(find.byKey(const ValueKey('chat-topic-change')));
    await t.pumpAndSettle();
    // 종류 바꾸기 → 앞 대화는 그대로, 새 선택지는 맨 아래(한 줄 시간순)
    await shot('chat-topic-change');
    await t.tap(find.byKey(const ValueKey('chat-topic-general')));
    await t.pumpAndSettle();

    await ask('상품 준비 중인 주문도 취소할 수 있나요?');
    await shot('chat-answer');
    // 취소 같은 실행 요청 → 최근 주문 카드(주문을 고르기 전, 일반 문의에서).
    await ask('주문 취소해 주세요 #취소');
    await t.drag(find.byType(Scrollable).first, const Offset(0, -900));
    await t.pumpAndSettle();
    await shot('chat-cancel-orders');
    await ask('내 주문 어디쯤이에요? #주문');
    await shot('chat-orders');
    await t.tap(find.byKey(const ValueKey('chat-order-order-seed-4')).last);
    await shot('chat-order-status');
    await ask('포인트는 언제 생기나요? #근거없음');
    await shot('chat-handoff');

    // 알림(스낵바)은 아래 떠 있는 장바구니 막대·버튼 위에 뜬다(사용자 2026-11-20 "팝업창이 버튼을 가리는데").
    // 맨 끝에 둔다 — 담기가 앞 장바구니 캡처를 바꾸지 않게.
    await go('/search');
    await t.enterText(find.byKey(const ValueKey('search-field')), '우유');
    await t.tap(find.byKey(const ValueKey('search-submit')));
    await t.pumpAndSettle();
    await t.tap(
      find.byWidgetPredicate((w) {
        final k = w.key;
        return k is ValueKey<String> && k.value.startsWith('quick-add-');
      }).last,
    );
    await shot('notice-over-cart-bar');
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    await tapTile(t, 'P-0001');
    await t.tap(find.byKey(const ValueKey('add-inc')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('add-to-cart')));
    await shot('notice-over-bottom-button');
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    await go('/cart');
    await t.tap(find.byKey(const ValueKey('cart-order')));
    await shot('notice-over-cart-order');
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();

    // 찜한 상품(customer 0.13.0)
    await go('/me/wishlist');
    await shot('wishlist');

    // 회원 탈퇴(customer 0.12.0): 안내·사유 → 재인증 → 탈퇴 처리 대기 → 철회(다른 캡처에 영향 없게 되돌린다).
    await go('/me/withdrawal');
    await shot('withdrawal');
    // 확인 칸은 화면 아래에 있다 — 내려서 만든 뒤 누른다.
    await t.drag(find.byKey(const ValueKey('wd-form')), const Offset(0, -900));
    await t.pumpAndSettle();
    await shot('withdrawal-2');
    await t.tap(find.byKey(const ValueKey('wd-agree')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('wd-submit')));
    await shot('withdrawal-blocked');
    await t.tap(find.byKey(const ValueKey('wd-revoke')));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
    debugDisableShadows = true;
  });

  // 약관 동의(CU-1 — auth 0.2.0): 기존 회원 재동의 + 선택 항목(마케팅).
  testWidgets('consent', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    Directory(_dir).createSync(recursive: true);
    await t.runAsync(_loadFonts);
    debugDisableShadows = false;
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp(
        const [],
        auth: MockAuthRepository(latency: Duration.zero)..reconsentNext = true,
      ),
    );
    await t.pumpAndSettle();
    Future<void> shot(String name) async {
      await t.pumpAndSettle();
      await expectLater(
        find.byType(CustomerApp),
        matchesGoldenFile(File('$_dir/c-$name.png').uri),
      );
    }

    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-naver')));
    await t.pumpAndSettle();
    await shot('reconsent');
    for (final c in MockAuthRepository.requiredConsents.take(2)) {
      await t.tap(find.byKey(ValueKey('consent-$c')));
      await t.pump();
    }
    await shot('reconsent-partial');
    debugDisableShadows = true;
  });

  // 새 가입 약관 동의 E안(사용자 2026-11-21): 처음 / 필수만 / 전체 동의, 이어서 휴대폰 확인(2/3)·내 정보(3/3).
  testWidgets('signup', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    Directory(_dir).createSync(recursive: true);
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp(
        const [],
        auth: MockAuthRepository(latency: Duration.zero)
          ..requireIdentity = true,
      ),
    );
    await t.pumpAndSettle();
    Future<void> shot(String name) async {
      await t.pumpAndSettle();
      await expectLater(
        find.byType(CustomerApp),
        matchesGoldenFile(File('$_dir/s-$name.png').uri),
      );
    }

    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-naver')));
    await t.pumpAndSettle();
    await shot('1-consent');
    for (final c in MockAuthRepository.requiredConsents) {
      await t.tap(find.byKey(ValueKey('consent-$c')));
      await t.pump();
    }
    await shot('2-consent-required');
    await t.tap(find.byKey(const ValueKey('consent-all')));
    await shot('3-consent-all');
    await t.tap(find.byKey(const ValueKey('consent-submit')));
    await shot('4-identity');
    await t.enterText(find.byKey(const ValueKey('id-phone')), '01012345678');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('id-next')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('id-sent')));
    await shot('5-my-info');
  });

  // 검색 — 최근 검색어 10개(서버 max-items 지금 10)가 여러 줄로 감길 때 줄 간격(사용자 2026-11-22).
  testWidgets('search-recent', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    Directory(_dir).createSync(recursive: true);
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp([
        recentSearchesRepositoryProvider.overrideWithValue(
          MockRecentSearchesRepository(
            latency: Duration.zero,
            seeded: const [
              '우유', '감귤', '감자칩', '두부', '계란', //
              '바나나', '닭가슴살', '아이스크림', '생수', '샐러드',
            ],
          ),
        ),
      ]),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    GoRouter.of(t.element(find.byType(Scaffold).first)).go('/search');
    await t.pumpAndSettle();
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/s-recent.png').uri),
    );
  });

  // 카테고리 레퍼런스 3-3 보강(사용자 2026-11-22): 맨 위 CATEGORY 배너, 아래 추천 타일·고객센터.
  // 상품 카드 + 로 담으면 알림 대신 아래 장바구니 막대가 알린다.
  testWidgets('category-picks', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    Directory(_dir).createSync(recursive: true);
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp(
        const [],
        catalog: MockCatalogRepository(latency: Duration.zero)
          ..placementBannersJson['CATEGORY'] = [
            {
              'bannerId': 'CB-1',
              'placement': 'CATEGORY',
              'altText': '라면X김치 국물 조합 특가',
              'linkType': 'NONE',
              'sortOrder': 1,
            },
          ],
      ),
    );
    await t.pumpAndSettle();
    Future<void> shot(String name) async {
      await t.pumpAndSettle();
      await expectLater(
        find.byType(CustomerApp),
        matchesGoldenFile(File('$_dir/k-$name.png').uri),
      );
    }

    await t.tap(find.text('카테고리').last);
    await shot('1-top');
    await t.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await shot('2-bottom');

    await t.tap(find.text('검색').last);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('search-field')), '그릭요거트');
    await t.tap(find.byKey(const ValueKey('search-submit')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('quick-add-P-0002')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    await t.pump(const Duration(milliseconds: 200));
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/k-3-cart-pulse.png').uri),
    );
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
  });

  // 마이 > 내 정보 F안(사용자 2026-11-21): 번호 확인 전 / 이름 바꾸기 시트.
  testWidgets('my-info', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    Directory(_dir).createSync(recursive: true);
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp(
        const [],
        profile: MockProfileRepository(latency: Duration.zero)
          ..nickname = '김피마'
          ..email = 'pmart.user@gmail.com'
          // 사진 시트 4항목이 다 보이게 직접 올린 사진 상태로 둔다.
          ..photoSource = ProfilePhotoSource.custom,
      ),
    );
    await t.pumpAndSettle();
    Future<void> shot(String name) async {
      await t.pumpAndSettle();
      await expectLater(
        find.byType(CustomerApp),
        matchesGoldenFile(File('$_dir/i-$name.png').uri),
      );
    }

    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-info')));
    await shot('1-list');
    await t.tap(find.byKey(const ValueKey('info-name-row')));
    await shot('2-name-sheet');
    await t.tap(find.byKey(const ValueKey('info-name-close')));
    await t.pumpAndSettle();
    // 사진 바꾸기 시트(G-1, BR-80).
    await t.tap(find.byKey(const ValueKey('info-photo-edit')));
    await shot('3-photo-sheet');
  });

  // 사진 맞추기(G-2, BR-80) — 팔레트 색 그라데이션을 사진 대신 쓴다.
  testWidgets('photo-crop', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    Directory(_dir).createSync(recursive: true);
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final bytes = await t.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 600, 800),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero,
            const Offset(600, 800),
            const [PmartBrand.lavender, PmartBrand.violet],
          ),
      );
      final img = await recorder.endRecording().toImage(600, 800);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    await t.pumpWidget(
      MaterialApp(
        theme: PmartCustomerTheme.light(fontFamily: 'Pretendard'),
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ko'),
        home: ProfilePhotoCropScreen(bytes: bytes!),
      ),
    );
    await t.pump(const Duration(milliseconds: 300));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await t.pump();
    await t.pumpAndSettle();
    await expectLater(
      find.byType(ProfilePhotoCropScreen),
      matchesGoldenFile(File('$_dir/i-4-photo-crop.png').uri),
    );
  });

  // 처음 실행(레퍼런스 2): 환영·약관 → 로그인/둘러보기 → 주소 검색.
  testWidgets('start', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    Directory(_dir).createSync(recursive: true);
    await t.runAsync(_loadFonts);
    debugDisableShadows = false;
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp([
        currentLocationSourceProvider.overrideWithValue(
          MockCurrentLocationSource(fix: const LocationDenied(forever: true)),
        ),
      ], startGate: true),
    );
    await t.pumpAndSettle();
    Future<void> shot(String name) async {
      await t.pumpAndSettle();
      await expectLater(
        find.byType(CustomerApp),
        matchesGoldenFile(File('$_dir/s-$name.png').uri),
      );
    }

    await shot('welcome');
    await t.tap(find.byKey(const ValueKey('start-agree-location-open')));
    await shot('terms');
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('start-agree-all')));
    await shot('welcome-agreed');
    await t.tap(find.byKey(const ValueKey('start-begin')));
    await shot('marketing-result');
    await t.tap(find.byKey(const ValueKey('start-marketing-result-ok')));
    await shot('entry');
    await t.tap(find.byKey(const ValueKey('login-browse')));
    await shot('address');
    await t.tap(find.byKey(const ValueKey('start-address-locate')));
    await shot('locate-consent');
    await t.tap(find.byKey(const ValueKey('dialog-confirm')));
    await shot('locate-settings');
    debugDisableShadows = true;
  });

  // 주문서 로그인 뒤 병합 확인(SCR-CART-MERGE-001, BR-50): 고르기 → 결과(일부 거절).
  testWidgets('merge', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    Directory(_dir).createSync(recursive: true);
    await t.runAsync(_loadFonts);
    debugDisableShadows = false;
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final member = MockCartRepository(
      latency: Duration.zero,
      minOrderAmount: 0,
    );
    final guest = MockCartRepository(latency: Duration.zero, seeded: false)
      ..seedLine('E-00000002', 1)
      ..seedLine('E-00000003', 2);
    final merges = MockCartMergeRepository(member: member, guest: guest)
      ..rejectSkus = {'E-00000003': 'QUANTITY_LIMIT_EXCEEDED'};
    await t.pumpWidget(
      testApp(cart: member, [
        cartMergeRepositoryProvider.overrideWithValue(merges),
      ]),
    );
    await t.pumpAndSettle();
    Future<void> shot(String name) async {
      await t.pumpAndSettle();
      await expectLater(
        find.byType(CustomerApp),
        matchesGoldenFile(File('$_dir/m-$name.png').uri),
      );
    }

    // 장바구니는 하단 탭이 아니다(사용자 2026-11-21) — 홈 위 화면으로 연다.
    GoRouter.of(t.element(find.byType(Scaffold).first)).go('/cart');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('cart-order')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await shot('choose');
    await t.tap(find.byKey(const ValueKey('merge-confirm')));
    await shot('result');
    debugDisableShadows = true;
  });

  // 주문상세 배달 정보(사용자 2026-11-21 "박스 안도 띄워놔야지") — 회원 주문 상세에서 [배달 정보]로.
  testWidgets('order-detail-delivery', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    await t.tap(find.text('주문내역').last);
    await t.pumpAndSettle();
    final status = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('order-status-'),
    );
    final id = (t.widget(status.first).key! as ValueKey<String>).value
        .substring('order-status-'.length);
    unawaited(
      GoRouter.of(t.element(find.byType(Scaffold).first)).push('/orders/$id'),
    );
    await t.pumpAndSettle();
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/od-top.png').uri),
    );
    await t.tap(find.byKey(const ValueKey('order-tab-delivery')));
    await t.pumpAndSettle();
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/od-delivery.png').uri),
    );
  });
  // 주문 상태별 버튼(레퍼런스 9-1·9-2, 사용자 2026-11-21) — 예약 확정·배달 중·배송 완료·취소, 예약시간 변경 시트.
  testWidgets('order-detail-actions', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    final router = GoRouter.of(t.element(find.byType(Scaffold).first));
    for (final (id, name) in [
      ('order-seed-4', 'oda-scheduled'),
      ('order-seed-1', 'oda-delivering'),
      ('order-seed-2', 'oda-completed'),
      ('order-seed-3', 'oda-cancelled'),
    ]) {
      unawaited(router.push('/orders/$id'));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(CustomerApp),
        matchesGoldenFile(File('$_dir/$name.png').uri),
      );
      if (id == 'order-seed-4') {
        await t.tap(find.byKey(const ValueKey('reschedule')));
        await t.pumpAndSettle();
        await expectLater(
          find.byType(CustomerApp),
          matchesGoldenFile(File('$_dir/oda-reschedule.png').uri),
        );
        router.pop();
        await t.pumpAndSettle();
      }
      router.pop();
      await t.pumpAndSettle();
    }
  });
  // 취소된 주문 상세 전체(사용자 2026-11-23 "배송 취소 컴포넌트 없애, 처리 내역 디자인 통일").
  testWidgets('order-detail-cancelled-full', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 6600)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    final router = GoRouter.of(t.element(find.byType(Scaffold).first));
    unawaited(router.push('/orders/order-seed-3'));
    await t.pumpAndSettle();
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/odc-full.png').uri),
    );
  });
  // 배송 단계 문구·홈 현황판·끝난 주문 배송현황·전달 완료 사진(사용자 2026-11-21, 레퍼런스 3-1·8·9-2·10).
  testWidgets('delivery-status', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    // 그림자를 실제처럼(시험 기본은 그림자를 검은 선으로 그린다).
    debugDisableShadows = false;
    final orders = MockOrdersRepository(latency: Duration.zero);
    await t.pumpWidget(testApp(const [], orders: orders));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    Future<void> shot(String name) => expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/$name.png').uri),
    );
    final router = GoRouter.of(t.element(find.byType(Scaffold).first));
    Future<void> go(String location) async {
      router.go(location);
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 250));
      }
      // 사진(Image.memory) 풀기는 실제 시간이 든다.
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }

    await go('/');
    await shot('ds-home');
    await go('/orders/order-seed-4/tracking');
    await shot('ds-track-reserved');
    await go('/deliveries/dlv-s2?orderId=order-seed-1');
    await shot('ds-track-delivering');
    await go('/orders/order-seed-2/tracking');
    await shot('ds-track-closed');
    await go('/orders/order-seed-2/help');
    await t.tap(find.byKey(const ValueKey('order-help-misdelivered')));
    await t.pumpAndSettle();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await t.pumpAndSettle();
    await shot('ds-proof');
    await go('/orders/order-seed-1');
    await shot('ds-detail-partial');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 1));
    debugDisableShadows = true;
  });
  // 로딩 모양(사용자 2026-11-21 "로딩 별로"): 리뷰관리 — 가운데 동그라미 대신 회색 자리 표시.
  testWidgets('loading-skeleton', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp(
        const [],
        reviews: MockReviewsRepository(latency: const Duration(seconds: 3)),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();
    unawaited(
      GoRouter.of(t.element(find.byType(Scaffold).first)).push('/reviews'),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 700));
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/loading-reviews.png').uri),
    );
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
  });
  // 홈 머리줄·하단 탭(사용자 2026-11-21): 주소 왼쪽, 알림·장바구니, 하단 탭 주문내역.
  testWidgets('home-topbar', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/home-topbar.png').uri),
    );
    await t.tap(find.text('주문내역').last);
    await t.pumpAndSettle();
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/orders-tab.png').uri),
    );
  });
  // 주소 상세 별칭(새 레퍼런스 3-1/2-5): [우리집][회사][추가], [추가]를 누르면 아래 입력칸.
  testWidgets('address-alias', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final address = MockAddressRepository(latency: Duration.zero);
    await t.pumpWidget(testApp(const [], address: address));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    final id = (await t.runAsync(address.book))!.addresses.first.addressId;
    unawaited(
      GoRouter.of(t.element(find.byType(Scaffold).first))
          .push('/addresses/edit/$id'),
    );
    await t.pumpAndSettle();
    // 레퍼런스처럼 [추가]를 고르고 빈 입력칸(목 주소 별칭 "집"은 지운다).
    await t.tap(find.byKey(const ValueKey('address-alias-home')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('address-alias-custom')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('f-label')), '');
    await t.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/address-alias.png').uri),
    );
  });
  // MD 탭(storefront 0.9.0 customTabs): 고정 탭 뒤, 타이머 탭은 이름 위 남은 시간.
  testWidgets('custom-tabs', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final now = DateTime.utc(2026, 11, 21, 3);
    final catalog = MockCatalogRepository(latency: Duration.zero)
      ..customTabs['X-DEAL'] = (
        title: '오일장',
        endsAt: now.add(const Duration(hours: 5, minutes: 12, seconds: 40)),
        showTimer: true,
        sections: [('S-WEEKLY', 'THEME', '오일장 특가')],
      )
      ..customTabs['X-AUTUMN'] = (
        title: '가을 나들이',
        endsAt: null,
        showTimer: false,
        sections: [('S-NEW', 'THEME', '가을 나들이 필수템')],
      );
    await t.pumpWidget(
      testApp([
        homeClockProvider.overrideWithValue(() => now),
      ], catalog: catalog),
    );
    await t.pumpAndSettle();
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/custom-tabs-home.png').uri),
    );
    await t.tap(find.byKey(const ValueKey('home-tab-X-DEAL')));
    await t.pumpAndSettle();
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/custom-tabs-deal.png').uri),
    );
  });
  // 자동 랭킹 테마(storefront 0.9.0 RANKING_AUTO → 홈 영역 kind RANKING, 항목 rank·badge RANK)와 랭킹 탭.
  testWidgets('ranking-theme', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    Future<void> shot(String name) async {
      await t.pumpAndSettle();
      await expectLater(
        find.byType(CustomerApp),
        matchesGoldenFile(File('$_dir/$name.png').uri),
      );
    }

    await t.drag(find.byType(CustomScrollView).first, const Offset(0, -560));
    await shot('ranking-home');
    await t.drag(find.byType(CustomScrollView).first, const Offset(0, 2000));
    await t.pumpAndSettle();
    await t.tap(find.text('랭킹').first);
    await shot('ranking-tab');
  });
  // 타이머 테마(storefront 0.9.0 showTimer): 제목 옆 남은 시간 알약.
  testWidgets('section-timer', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final now = DateTime.utc(2026, 11, 21, 3);
    final catalog = MockCatalogRepository(latency: Duration.zero)
      ..timedSections['S-NEW'] = now.add(
        const Duration(hours: 2, minutes: 13, seconds: 5),
      );
    await t.pumpWidget(
      testApp([
        homeClockProvider.overrideWithValue(() => now),
      ], catalog: catalog),
    );
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('section-timer-S-NEW')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.drag(find.byType(CustomScrollView).first, const Offset(0, 250));
    await t.pumpAndSettle();
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/section-timer.png').uri),
    );
  });
  // BR-84 띠형(storefront 0.12.0 timerStyle BAND, 초안 06-D).
  testWidgets('section-timer-band', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final now = DateTime.utc(2026, 11, 21, 3);
    final catalog = MockCatalogRepository(latency: Duration.zero)
      ..timedSections['S-NEW'] = now.add(
        const Duration(hours: 5, minutes: 12, seconds: 30),
      )
      ..bandTimerSections.add('S-NEW');
    await t.pumpWidget(
      testApp([
        homeClockProvider.overrideWithValue(() => now),
      ], catalog: catalog),
    );
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('section-timer-band-S-NEW')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.drag(find.byType(CustomScrollView).first, const Offset(0, 250));
    await t.pumpAndSettle();
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/section-timer-band.png').uri),
    );
  });
  // 홈 팝업(storefront POPUP, 사용자 결정 A 가운데 카드): 목은 이미지가 없어 대체 문구로 그려진다.
  testWidgets('home-popup', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final catalog = MockCatalogRepository(latency: Duration.zero)
      ..placementBannersJson['POPUP'] = [
        {
          'bannerId': 'PU-1',
          'placement': 'POPUP',
          'altText': '이번 주 제철 과일 모아 보기',
          'linkType': 'CATEGORY',
          'linkRef': 'C-FV',
          'sortOrder': 1,
        },
        {
          'bannerId': 'PU-2',
          'placement': 'POPUP',
          'altText': '둘째 팝업',
          'linkType': 'NONE',
          'sortOrder': 2,
        },
      ];
    await t.pumpWidget(testApp(const [], catalog: catalog));
    await t.pumpAndSettle();
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/home-popup.png').uri),
    );
  });
  // 처음 로딩 화면 프로모션(storefront SPLASH): 받아 둔 이미지를 화면 가득(캡처는 그림 에셋으로 대신).
  testWidgets('splash-promo', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final bytes = File('assets/images/categories/fruitveg.png')
        .readAsBytesSync();
    final secure = MemoryKeyValueStore();
    await secure.write('pmart.start.welcome', 'at=2026-11-20T00:00:00Z');
    await secure.write('pmart.start.entry', '1');
    await t.pumpWidget(
      testApp(
        [
          splashPromoStoreProvider.overrideWithValue(
            MemorySplashPromoStore(SplashPromo(bannerId: 'BN-1', bytes: bytes)),
          ),
        ],
        startGate: true,
        secure: secure,
      ),
    );
    await t.pump();
    await t.pump();
    await t.runAsync(() async {
      final e = find.byType(Image).evaluate().first;
      await precacheImage((e.widget as Image).image, e);
    });
    await t.pump();
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/splash-promo.png').uri),
    );
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
  });
  // 상품 리뷰 새 레퍼런스(2026-11-21 "4. 상품리뷰 전체 보기 - …"): 위쪽·카드·필터·사진 후기.
  // 사진을 누를 수 있게 출처를 준다(캡처에선 사진이 자리표시로 그려진다).
  testWidgets('reviews-new', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp([
        imageOriginProvider.overrideWithValue('https://img.invalid'),
      ], reviews: MockReviewsRepository(latency: Duration.zero)),
    );
    await t.pumpAndSettle();
    Future<void> shot(String name) async {
      await t.pumpAndSettle();
      await expectLater(
        find.byType(CustomerApp),
        matchesGoldenFile(File('$_dir/r-$name.png').uri),
      );
    }

    unawaited(
      GoRouter.of(t.element(find.byType(Scaffold).first))
          .push('/products/P-0001/reviews'),
    );
    await shot('top');
    await t.tap(find.byKey(const ValueKey('review-filter-open')));
    await shot('filter');
    await t.tap(find.byKey(const ValueKey('review-filter-close')));
    await t.pumpAndSettle();
    await t.drag(
      find.byKey(const ValueKey('product-reviews-list')),
      const Offset(0, -420),
    );
    await shot('card');
    await t.tap(find.byKey(const ValueKey('review-photo-rv-gen-P-0001-0-0')));
    await shot('photo-detail');
  });
  // 자주 묻는 질문 > 질문 유형(사용자 2026-11-21): 4줄 + [더보기], 고른 것 검정 — 분류가 많은 목.
  testWidgets('faq-types', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final faqs = MockFaqRepository(
      latency: Duration.zero,
      extraCategories: [
        for (final (i, title) in const [
          '반품·교환',
          '결제',
          '회원 정보',
          '쿠폰·할인',
          '주문 변경',
          '배송지',
          '상품 문의',
          '품절·결품',
          '오배송',
          '파손',
          '영수증',
          '리뷰',
          '찜',
          '알림',
          '탈퇴',
          '앱 사용',
        ].indexed)
          FaqCategory(category: 'X$i', title: title, count: 0),
      ],
    );
    await t.pumpWidget(
      testApp([faqRepositoryProvider.overrideWithValue(faqs)]),
    );
    await t.pumpAndSettle();
    Future<void> shot(String name) async {
      await t.pumpAndSettle();
      await expectLater(
        find.byType(CustomerApp),
        matchesGoldenFile(File('$_dir/f-$name.png').uri),
      );
    }

    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    unawaited(
      GoRouter.of(t.element(find.byType(Scaffold).first)).push('/support/faqs'),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('faq-cat-CANCEL')));
    await shot('closed');
    await t.tap(find.byKey(const ValueKey('faq-types-more')));
    await shot('open');
  });
  // 상품 할인가(ADR-0082 4단계 — 목 요거트·토마토·저지방 우유): 검색 카드·상세·장바구니.
  testWidgets('discounts', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    debugDisableShadows = false;
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final cart =
        MockCartRepository(
            latency: Duration.zero,
            seeded: false,
            minOrderAmount: 0,
          )
          ..seedLine('E-00000002', 1)
          ..seedLine('E-00000004', 2)
          ..seedLine('E-00000001', 1);
    await t.pumpWidget(testApp(cart: cart, const []));
    await t.pumpAndSettle();
    Future<void> shot(String name) async {
      await t.pumpAndSettle();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await t.pump();
      await expectLater(
        find.byType(CustomerApp),
        matchesGoldenFile(File('$_dir/d-$name.png').uri),
      );
    }

    GoRouter router() => GoRouter.of(t.element(find.byType(Scaffold).first));
    router().go('/search');
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('search-field')), '우유');
    await t.tap(find.byKey(const ValueKey('search-submit')));
    await t.pumpAndSettle();
    await shot('search');
    router().go('/products/P-0002');
    await t.pumpAndSettle();
    await shot('detail');
    router().go('/cart');
    await t.pumpAndSettle();
    await shot('cart');
    // 주문상세 줄: 나눠 넣은 할인·지금 더 할인 중(레퍼런스 9-1)
    router().go('/orders/order-seed-2');
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('line-discount-ol-3')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await t.drag(find.byType(Scrollable).last, const Offset(0, -200));
    await shot('order-detail');
    debugDisableShadows = true;
  });
  // 장바구니 최소주문 막힘·봉투값 줄(사용자 2026-11-21, 레퍼런스 5-1) — 목 장바구니 7,940원(최소 15,000).
  testWidgets('cart-min-order', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    debugDisableShadows = false;
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp(cart: MockCartRepository(latency: Duration.zero), const []),
    );
    await t.pumpAndSettle();
    Future<void> shot(String name) async {
      await t.pumpAndSettle();
      await expectLater(
        find.byType(CustomerApp),
        matchesGoldenFile(File('$_dir/c-$name.png').uri),
      );
    }

    GoRouter.of(t.element(find.byType(Scaffold).first)).go('/cart');
    await t.pumpAndSettle();
    await shot('guest');
    GoRouter.of(t.element(find.byType(Scaffold).first)).go('/my');
    await t.pumpAndSettle();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    // 장바구니는 하단 탭이 아니다(사용자 2026-11-21) — 홈 위 화면으로 연다.
    GoRouter.of(t.element(find.byType(Scaffold).first)).go('/cart');
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('cart-amount-bag')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await shot('member-amounts');
    debugDisableShadows = true;
  });
  // 비회원으로 주소를 넣었던 사람이 로그인 → 회원 주소록이 비면 그 주소를 저장할지 묻는다.
  testWidgets('guest-address', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    Directory(_dir).createSync(recursive: true);
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final secure = MemoryKeyValueStore();
    await secure.write('pmart.start.welcome', 'at=x');
    final repo = _NoMemberAddresses();
    final guest = await t.runAsync(
      () => repo.addGuest(
        const AddressDraft(
          roadAddress: '부산 부산진구 중앙대로 672',
          detailAddress: '12층',
          receiverName: '김피마',
          receiverPhone: '010-1234-5678',
        ),
        key: IdempotencyKey.generate(),
      ),
    );
    await GuestAddressStore(secure).add(guest!.addressId);
    await t.pumpWidget(
      testApp(const [], address: repo, startGate: true, secure: secure),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/g-guest-address.png').uri),
    );
  });
  // 배달 주소(센터)를 모를 때의 상품 상세 — "다 팔렸어요"가 아니라 주소 안내(백엔드 요청 2026-11-20 availability-display).
  testWidgets('no-center-detail', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    Directory(_dir).createSync(recursive: true);
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2180)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp([currentMfcIdProvider.overrideWithValue(null)]));
    await t.pumpAndSettle();
    await tapTile(t, 'P-0001');
    await t.pumpAndSettle();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await t.pump();
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/h-no-center-detail.png').uri),
    );
  });
}

/// 알림 → 리뷰 쓰기 흐름(초안 09 B·C·D·E, 사용자 2026-11-23 "리뷰 쓰기 흐름 다 넣는거라고").
void reviewFlowShots() {
  testWidgets('review-flow', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    Map<String, Object?> el(String line, String name, {String? review}) => {
      'orderId': 'order-x',
      'orderLineId': line,
      'productId': 'P-$line',
      'productName': name,
      'deliveredAt': '2026-11-20T02:30:00Z',
      'eligibleUntil': '2026-11-27T14:59:00Z',
      'state': review == null ? 'REV_ELIGIBLE' : 'PUBLISHED',
      'reviewId': review,
    };
    await t.pumpWidget(
      testApp(
        const [],
        reviews: MockReviewsRepository(
          latency: Duration.zero,
          eligibilities: [
            el('l-1', '국산 햇감자 1kg (특품)'),
            el('l-2', '서울우유 나100% 1L 2개 묶음 기획'),
            el('l-3', '풀무원 국산콩 두부 부침용 300g', review: 'rv-3'),
          ],
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    final router = GoRouter.of(t.element(find.byType(Scaffold).first));
    unawaited(router.push('/orders/order-x/review'));
    await t.pumpAndSettle();
    Future<void> shot(String name) => expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/rf-$name.png').uri),
    );
    await shot('b-pick');
    await t.tap(find.byKey(const ValueKey('review-pick-star-l-1-4')));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('review-text')),
      '알이 굵고 흙도 적어서 손질이 편했어요. 다음에도 살 것 같아요.',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    await shot('c-write');
    await t.tap(find.byKey(const ValueKey('review-submit')));
    await t.pumpAndSettle();
    await shot('d-done');
  });

  // 09-E: 쓸 리뷰가 없는 주문(목의 order-seed-2).
  testWidgets('review-flow-none', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    unawaited(
      GoRouter.of(t.element(find.byType(Scaffold).first))
          .push('/orders/order-seed-2/review'),
    );
    await t.pumpAndSettle();
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/rf-e-none.png').uri),
    );
  });

  // 홈 배달 불가 지역(초안 11-C 회색, 사용자 2026-11-23).
  testWidgets('home-out-of-area', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final secure = MemoryKeyValueStore();
    final store = GuestAddressStore(secure);
    await store.add('gaddr-x');
    await store.select('gaddr-x');
    await t.pumpWidget(
      testApp(const [], address: _OutOfArea(), secure: secure),
    );
    await t.pumpAndSettle();
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/h-out-of-area.png').uri),
    );
  });
  // 찜한 상품(초안 07 C + E, 사용자 2026-11-23 "찜한 상품 목록부터 하자").
  testWidgets('wishlist-c', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    Map<String, Object?> w(String id, String name, int price, String st) => {
      'productId': id,
      'addedAt': '2026-11-20T03:00:00Z',
      'name': name,
      'imageUrl': null,
      'price': price,
      'saleState': st,
    };
    Future<void> openList(List<Map<String, Object?>> seed, String name) async {
      await t.pumpWidget(
        testApp(
          const [],
          wishlist: MockWishlistRepository(latency: Duration.zero, seed: seed),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('마이페이지').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('my-login')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('login-kakao')));
      await t.pumpAndSettle();
      unawaited(
        GoRouter.of(t.element(find.byType(Scaffold).first))
            .push('/me/wishlist'),
      );
      await t.pumpAndSettle();
      await expectLater(
        find.byType(CustomerApp),
        matchesGoldenFile(File('$_dir/$name.png').uri),
      );
    }

    await openList([
      w('P-0001', '국산 햇감자 1kg (특품)', 4980, 'ON_SALE'),
      w('P-0002', '서울우유 나100% 1L 2개 묶음 기획 상품 한정 수량', 5480, 'ON_SALE'),
      w('P-0004', '무항생제 신선 대란 30구', 8990, 'SOLD_OUT'),
      w('P-0003', 'CJ 비비고 왕교자 1.05kg', 9980, 'ON_SALE'),
      w('P-0008', '제주 한라봉 선물세트 3kg', 29000, 'ENDED'),
    ], 'wish-c');
  });

  testWidgets('wishlist-empty', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp(
        const [],
        wishlist: MockWishlistRepository(
          latency: Duration.zero,
          seed: const [],
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    unawaited(
      GoRouter.of(t.element(find.byType(Scaffold).first)).push('/me/wishlist'),
    );
    await t.pumpAndSettle();
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/wish-e-empty.png').uri),
    );
  });

  testWidgets('wishlist-guest', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    unawaited(
      GoRouter.of(t.element(find.byType(Scaffold).first)).push('/me/wishlist'),
    );
    await t.pumpAndSettle();
    await expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/wish-e-guest.png').uri),
    );
  });

  // 취소·반품 내역·처리 내역(초안 08 목록 B·D, 상세 B·C·D — 사용자 2026-11-23).
  testWidgets('claims-08', (t) async {
    if (_dir.isEmpty) fail('--dart-define=SHOT_DIR=<절대 경로> 가 필요하다');
    await t.runAsync(_loadFonts);
    t.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    Map<String, Object?> c(
      String id,
      String type,
      String state,
      String opened, {
      List<Map<String, Object?>> lines = const [],
      List<Map<String, Object?>> refunds = const [],
      Map<String, Object?>? fee,
    }) => {
      'claimId': id,
      'version': 1,
      'orderId': 'order-seed-1',
      'type': type,
      'state': state,
      'openedAt': opened,
      'reason': 'CHANGE_OF_MIND',
      'lines': lines,
      'refunds': refunds,
      'feePayment': ?fee,
    };
    Map<String, Object?> line(
      String id,
      String d, {
      int? amount,
      String? why,
    }) => {
      'orderLineId': id,
      'requestedQty': 1,
      'approvedQty': d == 'APPROVED' ? 1 : 0,
      'decision': d,
      'rejectReason': ?why,
      'refundAmount': ?amount,
    };
    final repo = MockClaimsRepository(latency: Duration.zero);
    repo.claims
      ..['c-fee'] = c(
        'c-fee',
        'RETURN',
        'FEE_PENDING',
        '2026-11-22T09:05:00Z',
        lines: [line('ol-1', 'PENDING')],
        fee: {
          'amount': 9000,
          'state': 'WAITING',
          'paymentAttemptId': 'PA-1',
          'deadlineAt': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 5, minutes: 12))
              .toIso8601String(),
        },
      )
      ..['c-prog'] = c(
        'c-prog',
        'CANCEL',
        'IN_PROGRESS',
        '2026-11-21T00:12:00Z',
        lines: [
          line('ol-1', 'APPROVED', amount: 2980),
          line('ol-2', 'APPROVED', amount: 1980),
        ],
        refunds: [
          {'state': 'PG_PENDING', 'pgResult': 'UNKNOWN', 'amount': 4960},
        ],
      )
      ..['c-done'] = c(
        'c-done',
        'CANCEL',
        'CLOSED',
        '2026-11-20T05:31:00Z',
        lines: [
          line('ol-1', 'APPROVED', amount: 2980),
          line('ol-2', 'REJECTED', why: '이미 배달을 시작해서 취소할 수 없어요'),
        ],
        refunds: [
          {
            'state': 'COMPLETED',
            'pgResult': 'SUCCESS',
            'amount': 2980,
            'completedAt': '2026-11-21T06:20:00Z',
          },
        ],
      )
      ..['c-wd'] = c('c-wd', 'CANCEL', 'WITHDRAWN', '2026-10-30T02:02:00Z');
    await t.pumpWidget(testApp(const [], claims: repo));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    final router = GoRouter.of(t.element(find.byType(Scaffold).first));
    Future<void> shot(String name) => expectLater(
      find.byType(CustomerApp),
      matchesGoldenFile(File('$_dir/cl-$name.png').uri),
    );
    unawaited(router.push('/claims'));
    await t.pumpAndSettle();
    await shot('list');
    for (final id in ['c-prog', 'c-fee', 'c-done']) {
      unawaited(router.push('/claims/$id'));
      for (var k = 0; k < 6; k++) {
        await t.pump(const Duration(milliseconds: 300));
      }
      await shot(id);
      router.pop();
      await t.pump(const Duration(milliseconds: 500));
    }
  });
}

final class _OutOfArea extends MockAddressRepository {
  _OutOfArea() : super(latency: Duration.zero);

  @override
  Future<Address> guest(String guestAddressId) async => Address(
    addressId: guestAddressId,
    version: 1,
    roadAddress: '제주 제주시 연동 312-1',
    detailAddress: '201호',
    serviceability: Serviceability.outOfArea,
  );
}

/// 회원 주소록이 빈 목(캡처용).
final class _NoMemberAddresses extends MockAddressRepository {
  _NoMemberAddresses() : super(latency: Duration.zero);

  @override
  Future<AddressBook> book() async {
    final b = await super.book();
    return AddressBook(
      addresses: [
        for (final a in b.addresses)
          if (a.addressId != 'addr-1') a,
      ],
      context: const ShoppingContext(version: 1),
    );
  }
}
