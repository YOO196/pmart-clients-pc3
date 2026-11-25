import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart' show GoRouter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:pmart_core/pmart_core.dart';

import 'package:customer_app/app.dart';
import 'package:customer_app/features/address/data/mock_address_repository.dart';
import 'package:customer_app/features/address/data/geocoding_repository.dart';
import 'package:customer_app/features/address/presentation/address_controller.dart';
import 'package:customer_app/features/address/presentation/address_screens.dart';
import 'package:customer_app/features/address/presentation/map_pick_screen.dart';
import 'package:customer_app/features/address/presentation/postcode_screen.dart';
import 'package:customer_app/features/auth/data/mock_auth_repository.dart';
import 'package:customer_app/features/auth/presentation/auth_controller.dart';
import 'package:customer_app/features/cart/data/cart_repository.dart';
import 'package:customer_app/features/cart/data/mock_cart_repository.dart';
import 'package:customer_app/features/cart/presentation/cart_controller.dart';
import 'package:customer_app/features/checkout/data/checkout_repository.dart';
import 'package:customer_app/features/checkout/data/mock_checkout_repository.dart';
import 'package:customer_app/features/checkout/presentation/checkout_controller.dart';
import 'package:customer_app/features/claims/data/claims_repository.dart';
import 'package:customer_app/features/coupons/data/coupon_repository.dart';
import 'package:customer_app/features/coupons/presentation/coupon_controller.dart';
import 'package:customer_app/features/claims/data/mock_claims_repository.dart';
import 'package:customer_app/features/claims/presentation/claims_controller.dart';
import 'package:customer_app/features/catalog/data/catalog_repository.dart';
import 'package:customer_app/features/catalog/data/mock_catalog_repository.dart';
import 'package:customer_app/features/catalog/presentation/catalog_providers.dart';
import 'package:customer_app/features/notifications/data/mock_notifications_repository.dart';
import 'package:customer_app/features/notifications/data/notifications_repository.dart';
import 'package:customer_app/features/notifications/presentation/notifications_controller.dart';
import 'package:customer_app/features/orders/data/mock_orders_repository.dart';
import 'package:customer_app/features/orders/data/orders_repository.dart';
import 'package:customer_app/features/orders/presentation/orders_providers.dart';
import 'package:customer_app/features/payment/presentation/payment_controller.dart';
import 'package:customer_app/features/wishlist/data/wishlist_repository.dart';
import 'package:customer_app/features/wishlist/presentation/wishlist_controller.dart';
import 'package:customer_app/features/profile/data/mock_profile_repository.dart';
import 'package:customer_app/features/redelivery/data/mock_redelivery_payments_repository.dart';
import 'package:customer_app/features/redelivery/data/redelivery_payments_repository.dart';
import 'package:customer_app/features/redelivery/presentation/redelivery_controller.dart';
import 'package:customer_app/features/profile/data/profile_repository.dart';
import 'package:customer_app/features/profile/presentation/profile_controller.dart';
import 'package:customer_app/features/reviews/data/mock_reviews_repository.dart';
import 'package:customer_app/features/reviews/data/reviews_repository.dart';
import 'package:customer_app/features/reviews/presentation/reviews_controller.dart';
import 'package:customer_app/features/start/presentation/start_controller.dart';
import 'package:customer_app/shared/providers.dart';

/// 목 모드 앱. 둘러보기는 [catalog](기본: 지연 없는 목)를 쓰고 [overrides] 를 더한다.
Widget testApp(
  List<Override> overrides, {
  // 화면이 환경에 따라 다른 것(목 안내 문장 등)을 실기기 환경으로 볼 때.
  PmartEnv env = PmartEnv.mock,
  CatalogRepository? catalog,
  CartRepository? cart,
  CheckoutRepository? checkout,
  OrdersRepository? orders,
  ClaimsRepository? claims,
  MockAuthRepository? auth,
  ProfileRepository? profile,

  /// 찜(기본: 지연 없는 목 — 카드·상세의 하트가 로그인 뒤 찜 ID 를 읽는다).
  WishlistRepository? wishlist,

  /// 쿠폰(기본: 지연 없는 목). 목 주문서(checkout 목)가 이 쿠폰함으로 할인을 흉내 낸다.
  CouponRepository? coupons,
  NotificationsRepository? notifications,
  ReviewsRepository? reviews,
  FakeAddressPicker? addressPicker,
  MockAddressRepository? address,

  /// 다시 배송비 결제(기본: 결제 건 없는 지연 없는 목). 목 결제 서비스(checkout 목)와 잇는다.
  RedeliveryPaymentsRepository? redelivery,

  /// 수량 ± 모아 보내기 대기. 기본 0(탭 직후 pumpAndSettle 로 반영). 모아 보내기를 시험할 때만 늘린다.
  Duration stepperDelay = Duration.zero,

  /// 처음 실행 단계를 켤지(기본 끔 — 홈에서 시작).
  bool startGate = false,
  List<Duration> profileRefreshDelays = const [],

  /// 기기 보안 저장소(앱을 다시 켜는 시험에서 같은 것을 넘긴다). 기본은 새 메모리 저장소.
  MemoryKeyValueStore? secure,
}) {
  final checkoutRepo =
      checkout ??
      // 슬롯·만료가 실제 시계에 따라 바뀌지 않게 서울 12:00 으로 고정한다.
      MockCheckoutRepository(
        latency: Duration.zero,
        now: () => DateTime.utc(2026, 10, 24, 3),
      );
  final redeliveryRepo =
      redelivery ??
      MockRedeliveryPaymentsRepository(latency: Duration.zero, seeded: false);
  if ((checkoutRepo, redeliveryRepo) case (
    final MockCheckoutRepository c,
    final MockRedeliveryPaymentsRepository r,
  )) {
    c.externals.add(r);
  }
  final couponRepo = coupons ?? MockCouponRepository(latency: Duration.zero);
  if ((checkoutRepo, couponRepo)
      case (final MockCheckoutRepository c, final MockCouponRepository m)
      when c.couponOf == null) {
    c.couponOf = m.couponJsonOf;
  }
  return ProviderScope(
    retry: (_, _) => null,
    overrides: [
      envProvider.overrideWithValue(env),
      onSessionExpiredProvider.overrideWith(
        (ref) => ref.read(sessionExpiryHandlerProvider),
      ),
      catalogRepositoryProvider.overrideWithValue(
        catalog ?? MockCatalogRepository(latency: Duration.zero),
      ),
      cartRepositoryProvider.overrideWithValue(
        cart ??
            // 장바구니 최소주문 막힘(사용자 2026-11-21)은 cart_min_order_test 에서 본다. 다른 시험은 주문 흐름을 보려고
            // 장바구니 쪽 최소 금액만 끈다(주문서 초안의 최소주문 판정은 그대로 15,000).
            MockCartRepository(latency: Duration.zero, minOrderAmount: 0),
      ),
      cartStepperDelayProvider.overrideWithValue(stepperDelay),
      authRepositoryProvider.overrideWithValue(
        auth ?? MockAuthRepository(latency: Duration.zero),
      ),
      addressRepositoryProvider.overrideWithValue(
        address ?? MockAddressRepository(latency: Duration.zero),
      ),
      checkoutRepositoryProvider.overrideWithValue(checkoutRepo),
      redeliveryPaymentsRepositoryProvider.overrideWithValue(redeliveryRepo),
      redeliveryPollPolicyProvider.overrideWithValue((
        interval: Duration.zero,
        attempts: 3,
      )),
      ordersRepositoryProvider.overrideWithValue(
        orders ?? MockOrdersRepository(latency: Duration.zero),
      ),
      // 주문 상세가 처리 내역(GET /claims?orderId=)을 받으므로 지연 없는 목을 늘 둔다.
      claimsRepositoryProvider.overrideWithValue(
        claims ??
            MockClaimsRepository(
              latency: Duration.zero,
              orders: switch (orders) {
                final MockOrdersRepository m => m,
                _ => null,
              },
            ),
      ),
      profileRepositoryProvider.overrideWithValue(
        profile ?? MockProfileRepository(latency: Duration.zero),
      ),
      // 시험은 프로필 다시 읽기 타이머를 두지 않는다(남은 타이머로 깨지지 않게). 다시 읽기 시험은 따로 바꿔 끼운다.
      profileRefreshDelaysProvider.overrideWithValue(profileRefreshDelays),
      wishlistRepositoryProvider.overrideWithValue(
        wishlist ?? MockWishlistRepository(latency: Duration.zero),
      ),
      couponRepositoryProvider.overrideWithValue(couponRepo),
      notificationsRepositoryProvider.overrideWithValue(
        notifications ?? MockNotificationsRepository(latency: Duration.zero),
      ),
      // 상품 상세·주문 상세가 리뷰를 조회하므로 지연 없는 목을 늘 둔다.
      reviewsRepositoryProvider.overrideWithValue(
        reviews ?? MockReviewsRepository(latency: Duration.zero),
      ),
      noticePollPolicyProvider.overrideWithValue((
        interval: Duration.zero,
        attempts: 3,
      )),
      // 주소 검색(웹뷰)·카카오 지도는 시험에서 띄울 수 없어 가짜로 바꾼다.
      ...(addressPicker ?? FakeAddressPicker()).overrides,
      // 보안 저장소 대신 메모리 저장소(플랫폼 채널 없음).
      secureStoreProvider.overrideWithValue(secure ?? MemoryKeyValueStore()),
      paymentPollPolicyProvider.overrideWithValue((
        interval: Duration.zero,
        attempts: 3,
      )),
      tokenStoreProvider.overrideWithValue(TokenStore(MemoryKeyValueStore())),
      // 처음 실행 단계(환영·로그인/둘러보기·주소)는 그 시험(start_flow_test)에서만 켠다.
      startGateEnabledProvider.overrideWithValue(startGate),
      ...overrides,
    ],
    child: const CustomerApp(),
  );
}

/// 주소 검색 결과·지도 핀을 정해 두는 가짜. [road] 를 고르고, 지도는 [pin](없으면 시작 위치)으로 확인한다.
final class FakeAddressPicker {
  FakeAddressPicker({
    this.road = '서울 송파구 올림픽로 300',
    this.pin,
    MockGeocodingRepository? geocoding,
    this.customGeocoding,
  }) : geocoding = geocoding ?? MockGeocodingRepository(latency: Duration.zero);

  String? road;
  GeoPoint? pin;
  final MockGeocodingRepository geocoding;

  /// 목 대신 쓸 주소↔좌표 변환(예: 지번만 주는 위치). 있으면 [geocoding] 대신 이것을 쓴다.
  final GeocodingRepository? customGeocoding;
  final mapStarts = <GeoPoint>[];

  List<Override> get overrides => [
    geocodingRepositoryProvider.overrideWithValue(customGeocoding ?? geocoding),
    addressSearchProvider.overrideWithValue(
      (_) async => road == null
          ? null
          : PostcodeResult(roadAddress: road!, zoneNo: '05551'),
    ),
    mapPickProvider.overrideWithValue((_, initial, _) async {
      mapStarts.add(initial);
      return pin ?? initial;
    }),
  ];
}

/// 가로 진열 안의 상품을 화면에 보이게 한 뒤 누른다.
Future<void> tapTile(WidgetTester t, String productId) async {
  final tiles = find.byKey(ValueKey('tile-$productId'));
  // 홈 위쪽 카드(배송 요약·탭)에 밀려 아직 만들지 않은 영역이면 세로로 내려 찾는다.
  if (tiles.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      tiles,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  final tile = tiles.first;
  await t.ensureVisible(tile);
  await t.pumpAndSettle();
  await t.tap(tile);
  await t.pumpAndSettle();
}

/// 검색 화면 열기 — 하단 탭에서 검색이 빠졌다(가운데 = 찜, 2026-11-25). 화면 위 검색과 같은 경로를 push 한다.
Future<void> openSearchScreen(WidgetTester t) async {
  await t.pumpAndSettle();
  GoRouter.of(t.element(find.byType(Scaffold).first)).push('/search').ignore();
  await t.pumpAndSettle();
}
