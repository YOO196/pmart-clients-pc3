import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_api_order/pmart_api_order.dart' as order_api;
import 'package:pmart_api_promotion/pmart_api_promotion.dart' as api;
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/checkout/data/checkout_repository.dart';
import 'package:customer_app/features/checkout/data/mock_checkout_repository.dart';
import 'package:customer_app/features/checkout/domain/checkout.dart';
import 'package:customer_app/features/checkout/presentation/checkout_controller.dart';
import 'package:customer_app/features/coupons/data/coupon_repository.dart';
import 'package:customer_app/features/coupons/domain/coupon.dart';
import 'package:customer_app/features/coupons/presentation/coupon_controller.dart';

import 'support/app_harness.dart';
import 'support/member_checkout.dart';

/// 쿠폰·기간 할인(promotion 0.2.0·order 0.18.0, ADR-0082) — 목 저장소 기준. 실서버 확인은 아니다.
void main() {
  setUpAll(initPmartFormatting);
  final now = DateTime.utc(2026, 11, 21, 3);

  group('계약 → 화면 모델', () {
    test('쿠폰: 정률·최대 할인액·상태를 그대로 옮긴다', () {
      final c = couponFromContract(
        api.Coupon.fromJson({
          'couponId': 'C-1',
          'promotionId': 'P-1',
          'name': '10% 할인',
          'discount': {'type': 'RATE', 'value': 10, 'maxAmount': 5000},
          'minOrderAmount': 20000,
          'status': 'USED',
          'issuedAt': '2026-11-20T01:00:00Z',
          'validUntil': '2026-11-26T14:59:59Z',
          'usedOrderId': 'O-1',
        }),
      );
      expect(c.discount.type, CouponDiscountType.rate);
      expect(c.discount.maxAmount, 5000);
      expect(c.status, CouponStatus.used);
      expect(c.usedOrderId, 'O-1');
    });

    test('행사: 총 수량이 없으면 남은 수량 null(0·마감이 아니다)', () {
      final c = campaignFromContract(
        api.CouponCampaign.fromJson({
          'promotionId': 'P-1',
          'name': '3천원',
          'discount': {'type': 'AMOUNT', 'value': 3000},
          'minOrderAmount': 15000,
          'perCustomerLimit': 2,
          'myIssuedCount': 1,
          'remaining': null,
          'endsAt': '2026-11-30T14:59:59Z',
        }),
      );
      expect(c.remaining, isNull);
      expect(c.soldOut, isFalse);
      expect(c.reachedLimit, isFalse);
    });

    test('견적: 정가·기간 할인·쿠폰 결과와 차단 사유 COUPON_NOT_APPLICABLE', () {
      final d = draftFromContract(
        order_api.OrderDraft.fromJson({
          'draftId': 'D-1',
          'version': 1,
          'status': 'DRAFT',
          'nextAction': 'REVIEW',
          'quote': {
            'quoteVersion': 1,
            'baseItemAmount': 20000,
            'promotionDiscount': 1500,
            'itemAmount': 18500,
            'couponDiscount': 0,
            'coupon': {
              'couponId': 'C-1',
              'applicable': false,
              'reason': 'MIN_ORDER_NOT_MET',
              'name': '3천원',
            },
            'deliveryTip': 3000,
            'deliveryTipReason': 'STANDARD',
            'bagFee': 100,
            'totalAmount': 21600,
          },
          'blockers': [
            {'code': 'COUPON_NOT_APPLICABLE', 'detail': 'MIN_ORDER_NOT_MET'},
          ],
        }),
      );
      final q = d.quote!;
      expect(q.listItemAmount, 20000);
      expect(q.promotionDiscount, 1500);
      expect(q.coupon!.applicable, isFalse);
      expect(q.coupon!.reason, 'MIN_ORDER_NOT_MET');
      expect(d.blockers, [DraftBlocker.couponNotApplicable]);
    });

    test('주문서 요청에 couponId 를 싣는다', () {
      final r = draftRequestToContract(
        const DraftRequest(
          purchaseIntentId: 'pi-1',
          lines: [DraftLine(cartItemId: 'ci-1', sku: 'S-1', quantity: 1)],
          shoppingAddressId: 'a-1',
          mode: DeliveryMode.single,
          outOfStock: OutOfStockPreference.cancelOutOfStockOnly,
          couponId: 'C-9',
        ),
      );
      expect(r.couponId, 'C-9');
    });
  });

  group('주문서 쿠폰', () {
    late MockCheckoutRepository checkout;
    late MockCouponRepository coupons;

    setUp(() {
      checkout = MockCheckoutRepository(latency: Duration.zero, now: () => now);
      coupons = MockCouponRepository(latency: Duration.zero, now: () => now);
      checkout.couponOf = coupons.couponJsonOf;
    });

    test('쿠폰을 고르면 새 의도로 주문서를 다시 만들고, 할인은 서버 견적 값이다', () async {
      final c = await memberContainer(
        checkout: checkout,
        now: () => now,
        extra: [couponRepositoryProvider.overrideWithValue(coupons)],
      );
      await setMilk(c, 6);
      final ctl = c.read(draftControllerProvider.notifier);
      await ctl.enter();
      final before = c.read(draftControllerProvider).requireValue!;
      expect(before.request.couponId, isNull);

      await ctl.changeCoupon('CPN-MOCK-1');
      final after = c.read(draftControllerProvider).requireValue!;
      expect(after.request.couponId, 'CPN-MOCK-1');
      expect(
        after.request.purchaseIntentId,
        isNot(before.request.purchaseIntentId),
      );
      expect(after.draft.draftId, isNot(before.draft.draftId));
      expect(after.draft.quote!.couponDiscount, 7000);
      expect(after.draft.quote!.coupon!.applicable, isTrue);
      expect(after.canPay, isTrue);

      // 빼면 쿠폰 없이 다시.
      await ctl.changeCoupon(null);
      final removed = c.read(draftControllerProvider).requireValue!;
      expect(removed.request.couponId, isNull);
      expect(removed.draft.quote!.couponDiscount, 0);
    });

    test('최소 주문금액 미달 쿠폰: 차단 사유로 결제를 막는다', () async {
      final c = await memberContainer(
        checkout: checkout,
        now: () => now,
        extra: [couponRepositoryProvider.overrideWithValue(coupons)],
      );
      await setMilk(c, 6);
      final ctl = c.read(draftControllerProvider.notifier);
      await ctl.enter();
      await ctl.changeCoupon('CPN-MOCK-2'); // 최소 30,000원
      final s = c.read(draftControllerProvider).requireValue!;
      expect(s.draft.blockers, contains(DraftBlocker.couponNotApplicable));
      expect(s.draft.quote!.coupon!.reason, 'MIN_ORDER_NOT_MET');
      expect(s.canPay, isFalse);
    });

    test('결제 진입 422 COUPON_NOT_APPLICABLE 은 거절로 받는다', () async {
      final c = await memberContainer(
        checkout: checkout,
        now: () => now,
        extra: [couponRepositoryProvider.overrideWithValue(coupons)],
      );
      await setMilk(c, 6);
      final ctl = c.read(draftControllerProvider.notifier);
      await ctl.enter();
      await ctl.changeCoupon('CPN-MOCK-1');
      checkout.rejectNextCheckout = CheckoutProblemCode.couponNotApplicable;
      final start = await ctl.pay();
      expect(
        start,
        isA<CheckoutRejected>().having(
          (r) => r.code,
          'code',
          CheckoutProblemCode.couponNotApplicable,
        ),
      );
    });

    test('새 주문하기는 지난 쿠폰을 비운다', () async {
      final c = await memberContainer(
        checkout: checkout,
        now: () => now,
        extra: [couponRepositoryProvider.overrideWithValue(coupons)],
      );
      c.read(checkoutSetupProvider.notifier).setCoupon('CPN-MOCK-1');
      c.read(checkoutSetupProvider.notifier).begin();
      expect(c.read(checkoutSetupProvider).couponId, isNull);
    });
  });

  group('화면', () {
    Future<void> toOrderSheet(
      WidgetTester t,
      MockCheckoutRepository checkout,
      MockCouponRepository coupons,
    ) async {
      t.view
        ..physicalSize = const Size(800, 2400)
        ..devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        testApp(checkout: checkout, coupons: coupons, [
          clockProvider.overrideWithValue(() => now),
          draftPollPolicyProvider.overrideWithValue((
            interval: Duration.zero,
            attempts: 3,
          )),
        ]),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('장바구니').last);
      await t.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await t.tap(find.byKey(const ValueKey('cart-inc-ci-1')));
        await t.pumpAndSettle();
      }
      await t.tap(find.byKey(const ValueKey('cart-order')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('login-kakao')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('mode-single')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('mode-single')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('cart-order')));
      await t.pumpAndSettle();
    }

    testWidgets('주문서: 보유 수 → 고르기 → 할인 적용됨·금액 줄(서버 값) → 빼기', (t) async {
      final checkout = MockCheckoutRepository(
        latency: Duration.zero,
        now: () => now,
      );
      final coupons = MockCouponRepository(
        latency: Duration.zero,
        now: () => now,
      );
      await toOrderSheet(t, checkout, coupons);

      final open = find.byKey(const ValueKey('coupon-open'));
      await t.ensureVisible(open);
      await t.pumpAndSettle();
      expect(find.text('2개 보유'), findsOneWidget);
      expect(find.text('쿠폰 선택'), findsOneWidget);

      await t.tap(open);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('coupon-pick')), findsOneWidget);
      expect(find.text('사용 안 함'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('coupon-CPN-MOCK-1')));
      await t.pump();
      expect(find.text('1개 사용'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('coupon-pick-use')));
      await t.pumpAndSettle();

      expect(find.byKey(const ValueKey('coupon-pick')), findsNothing);
      expect(find.textContaining('할인 적용됨'), findsOneWidget);
      final row = find.byKey(const ValueKey('amount-coupon'));
      await t.ensureVisible(row);
      expect(
        find.descendant(of: row, matching: find.text('-7,000원')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('[목] 첫 주문 7천원 할인')),
        findsOneWidget,
      );

      // 고르기에서 다시 눌러 빼고 사용하기 → 쿠폰 없는 주문서.
      await t.ensureVisible(open);
      await t.tap(open);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('coupon-CPN-MOCK-1')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('coupon-pick-use')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('amount-coupon')), findsNothing);
      expect(find.text('쿠폰 선택'), findsOneWidget);
    });

    testWidgets('쓸 수 없는 쿠폰: 사유(서버)와 쿠폰 빼기, 결제 버튼은 사유 문구', (t) async {
      final checkout = MockCheckoutRepository(
        latency: Duration.zero,
        now: () => now,
      );
      final coupons = MockCouponRepository(
        latency: Duration.zero,
        now: () => now,
      );
      await toOrderSheet(t, checkout, coupons);
      final open = find.byKey(const ValueKey('coupon-open'));
      await t.ensureVisible(open);
      await t.tap(open);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('coupon-CPN-MOCK-2')));
      await t.tap(find.byKey(const ValueKey('coupon-pick-use')));
      await t.pumpAndSettle();

      expect(find.byKey(const ValueKey('coupon-reason')), findsOneWidget);
      expect(find.text('최소 주문금액이 모자라 쓸 수 없어요'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('pay')),
          matching: find.text('쿠폰을 쓸 수 없어요'),
        ),
        findsOneWidget,
      );
      await t.ensureVisible(find.byKey(const ValueKey('coupon-remove')));
      await t.tap(find.byKey(const ValueKey('coupon-remove')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('coupon-reason')), findsNothing);
      expect(find.text('쿠폰 선택'), findsOneWidget);
    });

    Future<void> openBox(WidgetTester t, MockCouponRepository coupons) async {
      t.view
        ..physicalSize = const Size(800, 2000)
        ..devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        testApp(coupons: coupons, [clockProvider.overrideWithValue(() => now)]),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('마이페이지').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('my-login')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('login-kakao')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('my-coupons')));
      await t.tap(find.byKey(const ValueKey('my-coupons')));
      await t.pumpAndSettle();
    }

    testWidgets('쿠폰함: 받기 → 받음, 마감 행사는 누를 수 없다, 사용 가능에 새 쿠폰', (t) async {
      final coupons = MockCouponRepository(
        latency: Duration.zero,
        now: () => now,
      );
      await openBox(t, coupons);
      expect(find.byKey(const ValueKey('coupon-box')), findsOneWidget);

      final soldOut = find.byKey(
        const ValueKey('campaign-download-PRM-MOCK-2'),
      );
      // 초안 10-B: 마감은 회색 동그라미 "마감" — 누를 자리가 없다.
      expect(
        find.descendant(of: soldOut, matching: find.text('마감')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: soldOut, matching: find.byType(InkWell)),
        findsNothing,
      );
      // 받을 수 있는 것만 센다(마감 제외).
      expect(
        find.textContaining('받을 수 있는 쿠폰 1장', findRichText: true),
        findsOneWidget,
      );

      await t.tap(find.byKey(const ValueKey('campaign-download-PRM-MOCK-1')));
      await t.pumpAndSettle();
      expect(find.text('쿠폰을 받았어요'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('campaign-download-PRM-MOCK-1')),
          matching: find.text('받음'),
        ),
        findsOneWidget,
      );
      expect(coupons.downloadKeys, hasLength(1));

      await t.tap(find.byKey(const ValueKey('coupon-tab-available')));
      await t.pumpAndSettle();
      expect(find.text('[목] 주말 장보기 3천원 할인'), findsOneWidget);
    });

    // 초안 10-B [모두 받기]: 받을 수 있는 행사만 하나씩 차례로, 끝나면 한 번에 알림. 받을 게 없으면 버튼 없음.
    testWidgets('모두 받기: 받을 수 있는 것만 차례로 받고 한 번에 알린다', (t) async {
      Map<String, Object?> camp(String id, {int remaining = 50}) => {
        'promotionId': id,
        'name': '[목] $id',
        'discount': {'type': 'AMOUNT', 'value': 1000},
        'minOrderAmount': 0,
        'perCustomerLimit': 1,
        'myIssuedCount': 0,
        'remaining': remaining,
        'endsAt': '2026-11-30T14:59:59Z',
        'useDays': 3,
        'useUntil': null,
      };
      final coupons = MockCouponRepository(
        latency: Duration.zero,
        now: () => now,
        campaigns: [camp('P-A'), camp('P-B'), camp('P-C', remaining: 0)],
      );
      await openBox(t, coupons);
      expect(find.text('금액 조건 없음 · 3일간 사용'), findsNWidgets(3));
      await t.tap(find.byKey(const ValueKey('coupon-download-all')));
      await t.pumpAndSettle();
      expect(coupons.downloadKeys, hasLength(2));
      expect(find.text('쿠폰 2장을 받았어요'), findsOneWidget);
      expect(find.byKey(const ValueKey('coupon-download-all')), findsNothing);
    });

    // 초안 10-C·D: 탭에 사용 가능 장수, 만료 가까운 순·기한 칩, 지난 쿠폰은 도장 + 쓴 주문 보기, 빈 상태 → 쿠폰 받기 탭.
    testWidgets('사용 가능 장수·기한 칩·지난 쿠폰 도장·빈 상태', (t) async {
      final coupons = MockCouponRepository(
        latency: Duration.zero,
        now: () => now,
      );
      await openBox(t, coupons);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('coupon-tab-available')),
          matching: find.textContaining('사용 가능 2'),
        ),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('coupon-tab-available')));
      await t.pumpAndSettle();
      expect(find.text('11.25(수)까지'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('coupon-tab-past')));
      await t.pumpAndSettle();
      expect(find.text('사용함'), findsOneWidget);
      // BR-85: 쓴 날(서버 usedAt) — 2026-11-08 12:00 서울.
      expect(find.text('11.8(일)에 사용'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('coupon-used-order-CPN-MOCK-3')),
        findsOneWidget,
      );
    });

    testWidgets('사용 가능 쿠폰이 없으면 [쿠폰 받으러 가기] → 쿠폰 받기 탭', (t) async {
      final empty = MockCouponRepository(
        latency: Duration.zero,
        now: () => now,
        coupons: const [],
      );
      await openBox(t, empty);
      await t.tap(find.byKey(const ValueKey('coupon-tab-available')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('coupon-available-empty')),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('coupon-empty-action')));
      await t.pumpAndSettle();
      expect(
        DefaultTabController.of(
          t.element(find.byKey(const ValueKey('coupon-tab-download'))),
        ).index,
        0,
      );
    });

    testWidgets('받기 결과를 모르면 같은 키로 다시 보낸다', (t) async {
      final coupons = MockCouponRepository(
        latency: Duration.zero,
        now: () => now,
      )..failNextDownload = const UnknownResultFailure(requestId: 'x');
      await openBox(t, coupons);
      await t.tap(find.byKey(const ValueKey('campaign-download-PRM-MOCK-1')));
      await t.pumpAndSettle();
      expect(coupons.downloadKeys, hasLength(2));
      expect(coupons.downloadKeys.toSet(), hasLength(1));
      expect(find.text('쿠폰을 받았어요'), findsOneWidget);
    });

    testWidgets('이미 받은 쿠폰(422 COUPON_LIMIT_REACHED)은 코드로 안내', (t) async {
      final coupons =
          MockCouponRepository(latency: Duration.zero, now: () => now)
            ..failNextDownload = const ProblemFailure(
              Problem(status: 422, code: CouponProblemCode.limitReached),
            );
      await openBox(t, coupons);
      await t.tap(find.byKey(const ValueKey('campaign-download-PRM-MOCK-1')));
      await t.pumpAndSettle();
      expect(find.text('이미 받은 쿠폰이에요'), findsOneWidget);
    });

    testWidgets('조회 실패는 "쿠폰 없음"이 아니다', (t) async {
      final coupons =
          MockCouponRepository(latency: Duration.zero, now: () => now)
            ..failNextRead = const ProblemFailure(
              Problem(status: 503, code: 'DEPENDENCY_UNAVAILABLE'),
            );
      await openBox(t, coupons);
      expect(
        find.byKey(const ValueKey('coupon-campaigns-empty')),
        findsNothing,
      );
      expect(find.text('지금 받을 수 있는 쿠폰이 없어요'), findsNothing);
    });
  });
}
