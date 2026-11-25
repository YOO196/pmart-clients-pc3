import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_api_storefront/pmart_api_storefront.dart' as sf;
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/auth/data/mock_auth_repository.dart';
import 'package:customer_app/features/auth/domain/auth.dart';
import 'package:customer_app/features/auth/presentation/auth_controller.dart';
import 'package:customer_app/features/cart/data/mock_cart_repository.dart';
import 'package:customer_app/features/cart/domain/cart.dart';
import 'package:customer_app/features/catalog/data/catalog_repository.dart';
import 'package:customer_app/features/catalog/data/mock_catalog_repository.dart';
import 'package:customer_app/features/catalog/domain/catalog.dart';
import 'package:customer_app/features/catalog/presentation/home_providers.dart';
import 'package:customer_app/features/checkout/data/mock_checkout_repository.dart';
import 'package:customer_app/features/checkout/domain/checkout.dart';
import 'package:customer_app/features/checkout/presentation/checkout_controller.dart';
import 'package:customer_app/features/orders/data/mock_orders_repository.dart';
import 'package:customer_app/features/orders/domain/orders.dart';
import 'package:customer_app/features/orders/presentation/orders_providers.dart';
import 'package:customer_app/shared/order_status.dart';
import 'package:customer_app/shared/providers.dart';
import 'package:customer_app/shared/shopping_context.dart';

import 'support/app_harness.dart';

/// 배송 방식 조회가 실패한다.
base class _OptionsDown extends MockCheckoutRepository {
  _OptionsDown()
    : super(latency: Duration.zero, now: () => DateTime.utc(2026, 10, 24, 3));

  @override
  Future<List<DeliveryOption>> options(String mfcId, {int? itemAmount}) async =>
      throw const NetworkFailure(DioExceptionType.connectionTimeout);
}

/// 주문 목록 조회가 실패한다(상태 [down] 만, 없으면 전부).
base class _OrdersDown extends MockOrdersRepository {
  _OrdersDown({this.down}) : super(latency: Duration.zero);

  final Set<OrderStatus>? down;

  @override
  Future<OrderPage> list({
    String? cursor,
    OrderStatus? status,
    String? from,
    String? q,
  }) {
    if (down == null || down!.contains(status)) {
      throw const NetworkFailure(DioExceptionType.connectionError);
    }
    return super.list(cursor: cursor, status: status, from: from, q: q);
  }
}

/// 홈 응답을 테스트가 정한 때에 준다.
final class _GatedHome extends MockCatalogRepository {
  _GatedHome() : super(latency: Duration.zero);

  final gate = Completer<void>();

  @override
  Future<HomeView> home({String? mfcId, HomeTab? tab}) async {
    await gate.future;
    return super.home(mfcId: mfcId, tab: tab);
  }
}

/// 랭킹 탭만 실패한다.
final class _RankingDown extends MockCatalogRepository {
  _RankingDown() : super(latency: Duration.zero);

  @override
  Future<HomeView> home({String? mfcId, HomeTab? tab}) async {
    if (tab == HomeTab.ranking) {
      throw const NetworkFailure(DioExceptionType.connectionError);
    }
    return super.home(mfcId: mfcId, tab: tab);
  }
}

/// 담기를 서버가 거절한다.
base class _RejectingCart extends MockCartRepository {
  _RejectingCart() : super(latency: Duration.zero);

  final adds = <String>[];

  @override
  Future<CartChangeOutcome> change(
    String cartId,
    CartChange change, {
    required IdempotencyKey key,
    required int expectedVersion,
  }) async {
    if (change is AddItem) {
      adds.add(change.sku);
      return const CartChangeRejected(CartProblemCode.skuNotSaleable);
    }
    return super.change(
      cartId,
      change,
      key: key,
      expectedVersion: expectedVersion,
    );
  }
}

/// 담기 요청을 센다.
base class _CountingCart extends MockCartRepository {
  _CountingCart() : super(latency: Duration.zero);

  final adds = <String>[];
  final setQuantities = <int>[];

  @override
  Future<CartChangeOutcome> change(
    String cartId,
    CartChange change, {
    required IdempotencyKey key,
    required int expectedVersion,
  }) {
    if (change is AddItem) adds.add(change.sku);
    if (change is SetQuantity) setQuantities.add(change.quantity);
    return super.change(
      cartId,
      change,
      key: key,
      expectedVersion: expectedVersion,
    );
  }
}

/// 계약 그대로의 배송 방식(최소 주문·배달팁 구간·운영 시간 없음 — BR-96 전 실서버 모양).
final class _NoGuide extends MockCheckoutRepository {
  _NoGuide() : super(latency: Duration.zero);

  @override
  Future<List<DeliveryOption>> options(String mfcId, {int? itemAmount}) async =>
      [
        for (final o in await super.options(mfcId, itemAmount: itemAmount))
          DeliveryOption(
            o.mode,
            availability: o.availability,
            reason: o.reason,
            eta: o.eta,
            tip: o.tip,
            earliestSlot: o.earliestSlot,
          ),
      ];
}

Future<void> _login(WidgetTester t) async {
  await t.tap(find.text('마이페이지').last);
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('my-login')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('login-kakao')));
  await t.pumpAndSettle();
  await t.tap(find.text('홈').last);
  await t.pumpAndSettle();
}

void _tallView(WidgetTester t) {
  t.view
    ..physicalSize = const Size(800, 2400)
    ..devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  setUpAll(initPmartFormatting);

  group('홈 배송 방식 요약', () {
    testWidgets('지금 방식(알뜰 먼저)·예상시간·최소주문 한 줄, 배달팁 0원 줄, [배달안내] 시트(서버 값 그대로)', (
      t,
    ) async {
      _tallView(t);
      await t.pumpWidget(testApp(const []));
      await t.pumpAndSettle();

      expect(find.byKey(const ValueKey('home-delivery-card')), findsOneWidget);
      final now = find.byKey(const ValueKey('home-delivery-now'));
      expect(
        find.descendant(of: now, matching: find.textContaining('알뜰배달 60~120분')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: now, matching: find.textContaining('최소주문 15,000원')),
        findsOneWidget,
      );
      expect(find.text('30,000원부터 배달팁 0원'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-night-notice')), findsNothing);
      // 비회원은 쿠폰 줄이 없다.
      expect(find.byKey(const ValueKey('home-coupon')), findsNothing);

      await t.tap(find.byKey(const ValueKey('home-delivery-guide')));
      await t.pumpAndSettle();
      final sheet = find.byKey(const ValueKey('delivery-guide-sheet'));
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(
          of: sheet,
          matching: find.textContaining('배달 운영 시간 오전 8:00 ~ 오전 12:00'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('delivery-guide-single')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('delivery-guide-bundled')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('30~60분')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('배달팁 0원')),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: sheet, matching: find.text('4,000원')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('3,000원')),
        findsOneWidget,
      );
    });

    testWidgets('배달팁 구간·최소주문이 없으면(지금 실서버 계약) 그 조각을 빼고 기본 배달팁만', (t) async {
      _tallView(t);
      await t.pumpWidget(testApp(const [], checkout: _NoGuide()));
      await t.pumpAndSettle();

      expect(find.byKey(const ValueKey('home-delivery-now')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-free-tip')), findsNothing);
      await t.tap(find.byKey(const ValueKey('home-delivery-guide')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('delivery-guide-hours')), findsNothing);
      expect(find.text('기본 배달팁'), findsNWidgets(2));
      expect(find.text('배달팁 0원'), findsNothing);
    });

    testWidgets('회원: 쿠폰 줄을 누르면 "할인받고 주문해요" — [한번에 받기]로 받을 수 있는 쿠폰을 받는다', (
      t,
    ) async {
      _tallView(t);
      await t.pumpWidget(testApp(const []));
      await t.pumpAndSettle();
      await _login(t);

      final row = find.byKey(const ValueKey('home-coupon'));
      await t.ensureVisible(row);
      await t.pumpAndSettle();
      expect(
        find.descendant(of: row, matching: find.text('[목] 주말 장보기 3천원 할인')),
        findsOneWidget,
      );
      await t.tap(row);
      await t.pumpAndSettle();
      expect(find.text('할인받고 주문해요'), findsOneWidget);
      expect(find.byKey(const ValueKey('campaign-PRM-MOCK-1')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('coupon-sheet-all')));
      await t.pumpAndSettle();
      // 받은 뒤에는 받을 쿠폰이 없어 버튼이 잠기고, 홈 쿠폰 줄도 사라진다.
      expect(
        t
            .widget<FilledButton>(
              find.byKey(const ValueKey('coupon-sheet-all')),
            )
            .onPressed,
        isNull,
      );
      await t.tap(find.byKey(const ValueKey('coupon-sheet-close')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-coupon')), findsNothing);
    });

    testWidgets('심야(NIGHT_TIME)면 예약만 안내하고 가장 빠른 시간을 보인다', (t) async {
      final checkout =
          MockCheckoutRepository(
              latency: Duration.zero,
              now: () => DateTime.utc(2026, 10, 24, 3),
            )
            ..unavailable = {
              DeliveryMode.single: 'NIGHT_TIME',
              DeliveryMode.bundled: 'NIGHT_TIME',
            };
      await t.pumpWidget(testApp(const [], checkout: checkout));
      await t.pumpAndSettle();

      final notice = find.byKey(const ValueKey('home-night-notice'));
      expect(notice, findsOneWidget);
      expect(
        find.descendant(of: notice, matching: find.text('지금은 예약배달만 받을 수 있어요')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: notice, matching: find.textContaining('가장 빠른 시간')),
        findsOneWidget,
      );
      // 막힌 방식 대신 안내가 보인다.
      expect(find.byKey(const ValueKey('home-delivery-now')), findsNothing);
    });

    testWidgets('조회 실패는 0원·무료가 아니라 실패 한 줄이고 다시 확인할 수 있다', (t) async {
      await t.pumpWidget(testApp(const [], checkout: _OptionsDown()));
      await t.pumpAndSettle();

      expect(find.byKey(const ValueKey('home-delivery-card')), findsNothing);
      expect(
        find.byKey(const ValueKey('home-delivery-failed')),
        findsOneWidget,
      );
      expect(find.text('배송 정보를 불러오지 못했어요'), findsOneWidget);
      expect(find.textContaining('배달팁'), findsNothing);
      expect(find.textContaining('무료'), findsNothing);
      // 상품 진열은 그대로다(배송 안내가 배너 아래로 옮겨 한 화면 아래에 있다).
      await t.scrollUntilVisible(
        find.text('지금 많이 사는 상품'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('지금 많이 사는 상품'), findsOneWidget);
    });

    test('담당 센터가 없으면 묻지 않고 카드도 없다(null)', () async {
      final c = ProviderContainer(
        overrides: [
          envProvider.overrideWithValue(PmartEnv.mock),
          currentMfcIdProvider.overrideWithValue(null),
          checkoutRepositoryProvider.overrideWithValue(_OptionsDown()),
        ],
      );
      addTearDown(c.dispose);
      c.listen(homeDeliveryOptionsProvider, (_, _) {});
      expect(await c.read(homeDeliveryOptionsProvider.future), isNull);
    });
  });

  group('홈 고정 탭·전체보기', () {
    testWidgets('서버가 준 탭(홈·랭킹·신상품)을 보이고 랭킹은 순위 배지와 세로 목록이다', (t) async {
      _tallView(t);
      await t.pumpWidget(testApp(const []));
      await t.pumpAndSettle();

      expect(find.byKey(const ValueKey('home-tab-home')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-tab-ranking')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-tab-isNew')), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('home-tab-ranking')));
      await t.pumpAndSettle();
      expect(find.text('지금 TOP'), findsOneWidget);
      // 레퍼런스: 사진 위 굵은 순위 숫자("1")
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('tile-rank-') &&
              w.data == '1',
        ),
        findsOneWidget,
      );
      expect(find.text('지금 많이 사는 상품'), findsNothing);

      await t.tap(find.byKey(const ValueKey('home-tab-home')));
      await t.pumpAndSettle();
      expect(find.text('지금 많이 사는 상품'), findsOneWidget);
    });

    testWidgets('탭 조회 실패는 빈 탭이 아니라 실패 한 줄이다', (t) async {
      await t.pumpWidget(testApp(const [], catalog: _RankingDown()));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('home-tab-ranking')));
      await t.pumpAndSettle();

      expect(find.byKey(const ValueKey('home-tab-failed')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-tab-empty')), findsNothing);
      expect(find.text('보여줄 상품이 없어요'), findsNothing);
    });

    testWidgets('전체보기는 같은 영역 상품을 이어 받는다(다음 묶음)', (t) async {
      // 한 쪽 3개 — 이번 주 장보기(6개)가 두 쪽이 된다.
      await t.pumpWidget(
        testApp(
          const [],
          catalog: MockCatalogRepository(latency: Duration.zero, pageSize: 3),
        ),
      );
      await t.pumpAndSettle();

      await t.scrollUntilVisible(
        find.byKey(const ValueKey('section-view-all-S-WEEKLY')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.ensureVisible(
        find.byKey(const ValueKey('section-view-all-S-WEEKLY')),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('section-view-all-S-WEEKLY')));
      await t.pumpAndSettle();
      // 지금 많이 사는 상품(S-RANK)은 자동 랭킹(다음 묶음 없음 — ranking_theme_test)이라 테마 영역으로 본다.
      expect(find.text('이번 주 장보기'), findsOneWidget); // 화면 제목
      expect(find.byKey(const ValueKey('tile-P-0006')), findsNothing);

      final more = find.byKey(const ValueKey('load-more'));
      await t.scrollUntilVisible(
        more,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await t.pumpAndSettle();
      await t.ensureVisible(more);
      await t.pumpAndSettle();
      await t.tap(more);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('tile-P-0006')), findsOneWidget);
      // 판매중지는 전체보기에도 없다.
      expect(find.byKey(const ValueKey('tile-P-0008')), findsNothing);
    });

    test('viewAllRef 는 그대로 옮기고, 실패 영역에는 전체보기가 없다', () {
      final home = homeFromContract(
        sf.HomeLayout.fromJson({
          'layoutVersion': 1,
          'sections': [
            {
              'sectionId': 'A',
              'kind': 'RANKING',
              'title': 'a',
              'state': 'OK',
              'items': const <Object?>[],
              'viewAllRef': 'ref-a',
            },
            {'sectionId': 'B', 'kind': 'NEW', 'title': 'b', 'state': 'OK'},
            {
              'sectionId': 'C',
              'kind': 'NEW',
              'title': 'c',
              'state': 'UNAVAILABLE',
              'viewAllRef': 'ref-c',
            },
          ],
        }),
      );
      expect(home.sections[0].viewAllRef, 'ref-a');
      expect(home.sections[0].hasViewAll, isTrue);
      expect(home.sections[1].hasViewAll, isFalse);
      expect(home.sections[2].hasViewAll, isFalse);
    });
  });

  group('홈 진행 중 주문', () {
    testWidgets('비회원은 카드도 조회도 없다', (t) async {
      final orders = MockOrdersRepository(latency: Duration.zero);
      await t.pumpWidget(testApp(const [], orders: orders));
      await t.pumpAndSettle();

      expect(find.byKey(const ValueKey('home-order-card')), findsNothing);
      expect(find.byKey(const ValueKey('home-order-failed')), findsNothing);
      expect(orders.listStatuses, isEmpty);
    });

    testWidgets('회원은 진행 중 주문 상태와 서버 도착 예상을 보고, 누르면 주문 상세로 간다', (t) async {
      final orders = MockOrdersRepository(latency: Duration.zero);
      await t.pumpWidget(testApp(const [], orders: orders));
      await t.pumpAndSettle();
      await _login(t);

      final card = find.byKey(const ValueKey('home-order-card'));
      expect(card, findsOneWidget);
      // 초안 12 v2 H: 오른쪽 작은 알약 "12분 배달 중 ›" — 짧은 단계 말 + 서버 남은 분.
      // order-seed-1 은 일부 전달 — 남은 배송이 배달 중이라 "일부 전달" 같은 상태 이름 대신 배달 단계.
      expect(
        find.descendant(of: card, matching: find.text('배달 중')),
        findsOneWidget,
      );
      expect(find.text('일부 전달'), findsNothing);
      final eta = t.widget<Text>(
        find.descendant(
          of: card,
          matching: find.byKey(const ValueKey('home-order-eta')),
        ),
      );
      expect(eta.data, startsWith('12분'));
      // 계약 status 는 하나만 받으므로 진행 중 상태마다 물었다.
      expect(orders.listStatuses, containsAll(homeInProgressStatuses));

      // 4초 뒤 미끄러져 사라진다.
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      expect(card, findsNothing);

      // 다른 화면에 갔다가 홈으로 돌아오면 다시 나타난다.
      await t.tap(find.text('주문내역').last);
      await t.pumpAndSettle();
      await t.tap(find.text('홈').last);
      await t.pumpAndSettle();
      expect(card, findsOneWidget);

      await t.tap(card);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-order-card')), findsNothing);
    });

    testWidgets('조회 실패는 "주문 없음"이 아니라 실패 한 줄이다', (t) async {
      await t.pumpWidget(testApp(const [], orders: _OrdersDown()));
      await t.pumpAndSettle();
      await _login(t);

      expect(find.byKey(const ValueKey('home-order-card')), findsNothing);
      expect(find.byKey(const ValueKey('home-order-failed')), findsOneWidget);
      expect(find.text('주문 정보를 불러오지 못했어요'), findsOneWidget);
    });

    test('일부 상태 조회가 실패해도 찾은 주문은 보이고, 못 찾으면 오류다', () async {
      Future<AsyncValue<OrderListItem?>> run(MockOrdersRepository repo) async {
        final c = ProviderContainer(
          retry: (_, _) => null,
          overrides: [
            envProvider.overrideWithValue(PmartEnv.mock),
            secureStoreProvider.overrideWithValue(MemoryKeyValueStore()),
            tokenStoreProvider.overrideWithValue(
              TokenStore(MemoryKeyValueStore()),
            ),
            authRepositoryProvider.overrideWithValue(
              MockAuthRepository(latency: Duration.zero),
            ),
            ordersRepositoryProvider.overrideWithValue(repo),
          ],
        );
        addTearDown(c.dispose);
        final login = loginFlowProvider(LoginPurpose.general);
        c.listen(login, (_, _) {});
        await c.read(login.notifier).start(SocialProvider.kakao);
        c.listen(homeInProgressOrderProvider, (_, _) {});
        try {
          await c.read(homeInProgressOrderProvider.future);
        } on Object {
          // 아래에서 상태로 본다.
        }
        return c.read(homeInProgressOrderProvider);
      }

      // 배송 중 조회만 실패 → 일부 전달 주문(order-seed-1)은 보인다.
      final partial = await run(_OrdersDown(down: {OrderStatus.inDelivery}));
      expect(partial.value?.orderId, 'order-seed-1');

      // 찾을 수 있는 상태가 모두 실패 → 오류(null 이 아니다).
      final failed = await run(
        _OrdersDown(
          down: {
            OrderStatus.inDelivery,
            OrderStatus.partiallyDelivered,
            OrderStatus.confirmed,
          },
        ),
      );
      expect(failed.hasError, isTrue);
    });
  });

  group('상품 카드 + 바로 담기', () {
    Future<void> openSearch(WidgetTester t, String keyword) async {
      await openSearchScreen(t);
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('search-field')), keyword);
      await t.tap(find.byKey(const ValueKey('search-submit')));
      await t.pumpAndSettle();
    }

    testWidgets('옵션이 하나인 상품은 1개를 담고 서버 결과를 알린다', (t) async {
      final cart = _CountingCart();
      await t.pumpWidget(testApp(const [], cart: cart));
      await t.pumpAndSettle();
      await openSearch(t, '그릭요거트');

      // 목록 위 속성 줄이 생겨 아래로 밀릴 수 있다 — 보이게 한 뒤 누른다.

      await t.ensureVisible(find.byKey(const ValueKey('quick-add-P-0002')));

      await t.pumpAndSettle();

      await t.tap(find.byKey(const ValueKey('quick-add-P-0002')));
      await t.pumpAndSettle();
      expect(cart.adds, ['E-00000002']);
      // 성공은 화면을 가리는 알림 대신 아래 장바구니 막대가 알린다(사용자 2026-11-22).
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-cart-bar')),
          matching: find.text('장바구니에 담았어요'),
        ),
        findsOneWidget,
      );
      // 잠시 뒤 막대는 원래 줄("주문 가능" 등)로 돌아온다.
      await t.pump(const Duration(seconds: 2));
      await t.pumpAndSettle();
      expect(find.text('장바구니에 담았어요'), findsNothing);
      expect(find.byKey(const ValueKey('home-cart-sub')), findsOneWidget);
    });

    testWidgets('이미 담긴 상품은 누를 때마다 1개씩 늘린다(덮어쓰지 않고 서버 수량 + 1)', (t) async {
      final cart = _CountingCart();
      await t.pumpWidget(testApp(const [], cart: cart));
      await t.pumpAndSettle();
      await openSearch(t, '감자칩');

      // 목 장바구니에 감자칩 1개가 담겨 있다.
      // 목록 위 속성 줄이 생겨 아래로 밀릴 수 있다 — 보이게 한 뒤 누른다.
      await t.ensureVisible(find.byKey(const ValueKey('quick-add-P-0005')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('quick-add-P-0005')));
      await t.pumpAndSettle();
      expect(cart.adds, isEmpty);
      expect(cart.setQuantities, [2]);
      expect(find.text('장바구니에 2개 있어요'), findsOneWidget);

      // 목록 위 속성 줄이 생겨 아래로 밀릴 수 있다 — 보이게 한 뒤 누른다.

      await t.ensureVisible(find.byKey(const ValueKey('quick-add-P-0005')));

      await t.pumpAndSettle();

      await t.tap(find.byKey(const ValueKey('quick-add-P-0005')));
      await t.pumpAndSettle();
      expect(cart.setQuantities, [2, 3]);
      expect(find.text('장바구니에 3개 있어요'), findsOneWidget);
    });

    testWidgets('처음 담는 상품도 두 번 누르면 2개가 된다', (t) async {
      final cart = _CountingCart();
      await t.pumpWidget(testApp(const [], cart: cart));
      await t.pumpAndSettle();
      await openSearch(t, '그릭요거트');

      // 목록 위 속성 줄이 생겨 아래로 밀릴 수 있다 — 보이게 한 뒤 누른다.

      await t.ensureVisible(find.byKey(const ValueKey('quick-add-P-0002')));

      await t.pumpAndSettle();

      await t.tap(find.byKey(const ValueKey('quick-add-P-0002')));
      await t.pumpAndSettle();
      // 목록 위 속성 줄이 생겨 아래로 밀릴 수 있다 — 보이게 한 뒤 누른다.
      await t.ensureVisible(find.byKey(const ValueKey('quick-add-P-0002')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('quick-add-P-0002')));
      await t.pumpAndSettle();
      expect(cart.adds, ['E-00000002']);
      expect(cart.setQuantities, [2]);
      expect(find.text('장바구니에 2개 있어요'), findsOneWidget);
    });

    testWidgets('옵션이 여럿이면 담지 않고 상품 상세(옵션 선택)로 간다', (t) async {
      final cart = _CountingCart();
      await t.pumpWidget(testApp(const [], cart: cart));
      await t.pumpAndSettle();
      await openSearch(t, '서울우유');

      // 목록 위 속성 줄이 생겨 아래로 밀릴 수 있다 — 보이게 한 뒤 누른다.

      await t.ensureVisible(find.byKey(const ValueKey('quick-add-P-0001')));

      await t.pumpAndSettle();

      await t.tap(find.byKey(const ValueKey('quick-add-P-0001')));
      await t.pumpAndSettle();
      expect(cart.adds, isEmpty);
      // 상세에서 [구매하기] → 옵션 시트(사용자 레퍼런스 2026-11-25).
      await t.tap(find.byKey(const ValueKey('product-buy')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('option-B-00000011')), findsOneWidget);
    });

    testWidgets('서버가 거절하면 거절 사유를 알린다(담았다고 하지 않는다)', (t) async {
      final cart = _RejectingCart();
      await t.pumpWidget(testApp(const [], cart: cart));
      await t.pumpAndSettle();
      await openSearch(t, '양파');

      // 목록 위 속성 줄이 생겨 아래로 밀릴 수 있다 — 보이게 한 뒤 누른다.

      await t.ensureVisible(find.byKey(const ValueKey('quick-add-P-0007')));

      await t.pumpAndSettle();

      await t.tap(find.byKey(const ValueKey('quick-add-P-0007')));
      await t.pumpAndSettle();
      expect(cart.adds, ['E-00000007']);
      expect(find.text('지금 살 수 없는 상품이에요'), findsOneWidget);
      expect(find.text('장바구니에 담았어요'), findsNothing);
    });

    testWidgets('품절 카드에는 + 가 없다', (t) async {
      await t.pumpWidget(testApp(const []));
      await t.pumpAndSettle();
      await openSearch(t, '토마토');

      expect(find.byKey(const ValueKey('tile-P-0004')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-add-P-0004')), findsNothing);
    });
  });

  testWidgets('홈 첫 로딩은 원형 표시 대신 자리 표시 블록이다', (t) async {
    final catalog = _GatedHome();
    await t.pumpWidget(testApp(const [], catalog: catalog));
    await t.pump();

    expect(find.byKey(const ValueKey('home-skeleton')), findsOneWidget);
    expect(find.byKey(const ValueKey('ui-loading')), findsNothing);

    catalog.gate.complete();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-skeleton')), findsNothing);
    // 첫 진열 영역은 배송 카드·배너·검색창·카테고리 아래에 있다.
    await t.scrollUntilVisible(
      find.text('지금 많이 사는 상품'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    expect(find.text('지금 많이 사는 상품'), findsOneWidget);
  });

  // 백엔드 요청 2026-11-20 home-banners-themes(storefront 0.7.0).
  testWidgets(
    '배너: 위(HOME_TOP)는 넘기기, 중간(HOME_MIDDLE)은 첫 영역 아래, 누르면 영역 전체 보기·카테고리로',
    (t) async {
      _tallView(t);
      await t.pumpWidget(testApp(const []));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-banners-top')), findsOneWidget);
      await t.fling(
        find.byKey(const ValueKey('banner-BN-1')),
        const Offset(-600, 0),
        1500,
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('banner-BN-2')));
      await t.pumpAndSettle();
      expect(find.text('새로 들어왔어요'), findsWidgets);
      expect(find.byKey(const ValueKey('home-banners-top')), findsNothing);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('banner-BN-3')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.byKey(const ValueKey('banner-BN-3')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-banners-top')), findsNothing);
    },
  );
}
