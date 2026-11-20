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
    await t.tap(find.byKey(const ValueKey('review-photos-more')));
    await t.pumpAndSettle();
    await shot('review-photos');
    await t.tap(find.byKey(const ValueKey('review-photos-close')));
    await t.pumpAndSettle();

    await go('/cart');
    await shot('cart');
    await t.tap(find.byKey(const ValueKey('cart-fee-info')));
    await t.pumpAndSettle();
    await shot('cart-fee-dialog');
    await t.tap(find.byKey(const ValueKey('cart-fee-ok')));
    await t.pumpAndSettle();
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

    await go('/my');
    await shot('my');
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
    final member = MockCartRepository(latency: Duration.zero);
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

    await t.tap(find.text('장바구니').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('cart-order')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await shot('choose');
    await t.tap(find.byKey(const ValueKey('merge-confirm')));
    await shot('result');
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
