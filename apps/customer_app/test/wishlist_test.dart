import 'dart:async';

import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_api_customer/pmart_api_customer.dart' as api;
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/auth/presentation/login_screen.dart';
import 'package:customer_app/features/catalog/presentation/product_detail_screen.dart';
import 'package:customer_app/features/wishlist/data/wishlist_repository.dart';
import 'package:customer_app/features/wishlist/domain/wishlist.dart';
import 'package:customer_app/features/wishlist/presentation/wishlist_controller.dart';

import 'support/app_harness.dart';

/// 찜(customer 0.13.0, ADR-0081 — 백엔드 요청 2026-11-20 wishlist).
void main() {
  setUpAll(initPmartFormatting);

  Finder key(String k) => find.byKey(ValueKey(k));

  MockWishlistRepository repo0({
    List<Map<String, Object?>>? seed,
    int? limit,
  }) => MockWishlistRepository(
    latency: Duration.zero,
    seed: seed,
    limit: limit ?? 200,
  );

  Future<void> start(WidgetTester t, MockWishlistRepository repo) async {
    t.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const [], wishlist: repo));
    await t.pumpAndSettle();
  }

  Future<void> login(WidgetTester t) async {
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(key('my-login'));
    await t.pumpAndSettle();
    await t.tap(key('login-kakao'));
    await t.pumpAndSettle();
  }

  Future<void> openDetail(WidgetTester t, String id) async {
    unawaited(
      GoRouter.of(t.element(find.byType(NavigationBar))).push('/products/$id'),
    );
    await t.pumpAndSettle();
  }

  Set<String>? ids(WidgetTester t) =>
      ProviderScope.containerOf(t.element(find.byType(Scaffold).first))
          .read(wishlistIdsProvider)
          .value;

  testWidgets('비회원: 찜 ID 를 부르지 않고, 하트를 누르면 로그인 안내', (t) async {
    final repo = repo0();
    await start(t, repo);
    await openDetail(t, 'P-0001');
    expect(repo.idReads, 0);

    await t.tap(key('detail-wish'));
    await t.pumpAndSettle();
    expect(repo.addKeys, isEmpty);
    expect(find.text('로그인하면 찜할 수 있어요'), findsOneWidget);
    await t.tap(find.text('로그인'));
    await t.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('회원: 로그인 때 한 번 읽고, 하트는 서버가 반영한 뒤에만 바뀐다(찜 → 빼기)', (t) async {
    final repo = repo0();
    await start(t, repo);
    await login(t);
    expect(repo.idReads, 1);
    expect(ids(t), {'P-0002', 'P-0004'});

    await openDetail(t, 'P-0001');
    await t.tap(key('detail-wish'));
    await t.pumpAndSettle();
    expect(repo.addKeys, hasLength(1));
    expect(ids(t), contains('P-0001'));
    expect(find.text('찜했어요'), findsOneWidget);

    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
    await t.tap(key('detail-wish'));
    await t.pumpAndSettle();
    expect(repo.removeKeys, hasLength(1));
    expect(ids(t), isNot(contains('P-0001')));
    expect(find.text('찜에서 뺐어요'), findsOneWidget);
    // 카드마다 다시 묻지 않는다.
    expect(repo.idReads, 1);
  });

  testWidgets('실패하면 하트가 바뀌지 않는다, 최대 개수는 서버 값으로 안내', (t) async {
    final repo = repo0(limit: 2)
      ..failNext = const NetworkFailure(DioExceptionType.connectionError);
    await start(t, repo);
    await login(t);
    await openDetail(t, 'P-0001');

    await t.tap(key('detail-wish'));
    await t.pumpAndSettle();
    expect(ids(t), isNot(contains('P-0001')));
    expect(find.text('처리하지 못했어요. 잠시 후 다시 시도해 주세요'), findsOneWidget);

    // 이미 2개(최대 2개) — 서버가 422 로 거절한다.
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
    await t.tap(key('detail-wish'));
    await t.pumpAndSettle();
    expect(ids(t), isNot(contains('P-0001')));
    expect(find.text('찜은 2개까지 할 수 있어요'), findsOneWidget);
  });

  testWidgets('찜 ID 조회 실패는 "찜 없음"이 아니다 — 누르면 보내지 않고 다시 읽는다', (t) async {
    final repo = repo0()
      ..failNextRead = const NetworkFailure(DioExceptionType.connectionError);
    await start(t, repo);
    await login(t);
    await openDetail(t, 'P-0002'); // 실제로는 찜한 상품
    await t.tap(key('detail-wish'));
    await t.pumpAndSettle();
    expect(repo.addKeys, isEmpty);
    expect(repo.removeKeys, isEmpty);
    expect(find.text('찜 정보를 불러오지 못했어요. 다시 눌러 주세요'), findsOneWidget);
    // 다시 읽혀 이제 안다.
    expect(ids(t), contains('P-0002'));
  });

  testWidgets('마이 → 찜한 상품: 품절·판매 종료는 남기고 표시, 하트로 빼면 목록에서 빠진다', (t) async {
    final repo = repo0();
    await start(t, repo);
    await login(t);
    await t.ensureVisible(key('my-wishlist'));
    await t.tap(key('my-wishlist'));
    await t.pumpAndSettle();

    expect(key('wishlist'), findsOneWidget);
    String count() =>
        t.widget<Text>(key('wishlist-count')).textSpan!.toPlainText();
    expect(count(), '전체 2개');
    expect(t.widget<Text>(key('wish-name-P-0002')).data, '그릭요거트 플레인 400g');
    // 초안 07 v2 B-1: 품절은 사진에 어두운 막 + 글, + 없음. 판매 중은 사진 위 +.
    expect(
      find.descendant(of: key('wish-state-P-0004'), matching: find.text('품절')),
      findsOneWidget,
    );
    expect(key('wish-state-P-0002'), findsNothing);
    expect(key('wish-add-P-0002'), findsOneWidget);
    expect(key('wish-add-P-0004'), findsNothing);

    await t.tap(key('wish-heart-P-0004'));
    await t.pumpAndSettle();
    expect(key('wish-P-0004'), findsNothing);
    expect(count(), '전체 1개');

    await t.tap(key('wish-P-0002'));
    await t.pumpAndSettle();
    expect(find.byType(ProductDetailScreen), findsOneWidget);
  });

  // 초안 07-C [담기]: 카드 + 와 같은 규칙 — 옵션을 확인하고 하나면 바로 장바구니에.
  testWidgets('찜한 상품 +: 옵션 하나면 바로 담고 "− N +" 알약으로, 0 이면 + 로 접힌다', (t) async {
    final repo = repo0();
    await start(t, repo);
    await login(t);
    await t.ensureVisible(key('my-wishlist'));
    await t.tap(key('my-wishlist'));
    await t.pumpAndSettle();
    await t.tap(key('wish-add-P-0002'));
    await t.pumpAndSettle();
    expect(find.byType(ProductDetailScreen), findsNothing);
    // 담기면 + 자리가 "− 1 +" 알약(장바구니 서버 수량).
    final pill = key('wish-qty-P-0002');
    expect(pill, findsOneWidget);
    expect(find.descendant(of: pill, matching: find.text('1')), findsOneWidget);
    await t.tap(find.descendant(of: pill, matching: key('wish-qty-plus')));
    await t.pumpAndSettle();
    expect(find.descendant(of: pill, matching: find.text('2')), findsOneWidget);
    await t.tap(find.descendant(of: pill, matching: key('wish-qty-minus')));
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: pill, matching: key('wish-qty-minus')));
    await t.pumpAndSettle();
    // 0 이 되면 장바구니에서 빠지고 + 로 접힌다.
    expect(pill, findsNothing);
    expect(key('wish-add-P-0002'), findsOneWidget);
  });

  // 초안 07-E: 빈 상태는 하트 동그라미 + 안내 + [상품 둘러보기], 비회원은 같은 틀에 [로그인].
  testWidgets('찜한 상품 빈 상태·비회원 안내', (t) async {
    final repo = repo0(seed: const []);
    await start(t, repo);
    unawaited(
      GoRouter.of(t.element(find.byType(Scaffold).first)).push('/me/wishlist'),
    );
    await t.pumpAndSettle();
    expect(key('wishlist-guest'), findsOneWidget);
    expect(find.text('로그인하면 찜할 수 있어요'), findsOneWidget);
    await t.tap(key('wishlist-login'));
    await t.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    await t.tap(key('login-kakao'));
    await t.pumpAndSettle();
    if (key('wishlist').evaluate().isEmpty) {
      await t.tap(find.text('마이페이지').last);
      await t.pumpAndSettle();
    }
    if (key('wishlist').evaluate().isEmpty) {
      await t.ensureVisible(key('my-wishlist'));
      await t.tap(key('my-wishlist'));
      await t.pumpAndSettle();
    }
    expect(key('wishlist-empty'), findsOneWidget);
    expect(find.text('찜한 상품이 없어요'), findsOneWidget);
    await t.tap(key('wishlist-browse'));
    await t.pumpAndSettle();
    expect(key('wishlist'), findsNothing);
  });

  testWidgets('찜한 상품: 상품 정보를 못 읽은 줄은 지어내지 않고 그 말만, 조회 실패는 빈 목록이 아니다', (
    t,
  ) async {
    final repo = repo0(
      seed: [
        {
          'productId': 'P-gone',
          'addedAt': '2026-10-20T03:00:00Z',
          'name': null,
          'imageUrl': null,
          'price': null,
          'saleState': 'UNKNOWN',
        },
      ],
    );
    await start(t, repo);
    await login(t);
    repo.failNextRead = const NetworkFailure(DioExceptionType.connectionError);
    await t.ensureVisible(key('my-wishlist'));
    await t.tap(key('my-wishlist'));
    await t.pumpAndSettle();
    expect(key('ui-error'), findsOneWidget);
    expect(key('wishlist-empty'), findsNothing);

    await t.tap(find.text('다시 시도하기').first);
    await t.pumpAndSettle();
    expect(t.widget<Text>(key('wish-name-P-gone')).data, '상품 정보를 불러오지 못했어요');
  });

  test('계약 → 앱: 모르는 판매 상태는 UNKNOWN, 빈 이름·사진은 없음', () {
    final page = wishlistPageFromContract(
      api.ListWishlistItems200Response.fromJson({
        'items': [
          {
            'productId': 'p-1',
            'addedAt': '2026-11-20T01:00:00Z',
            'name': ' ',
            'imageUrl': '',
            'price': null,
            'saleState': 'ENDED',
          },
        ],
        'total': 7,
        'limit': 200,
      }),
    );
    expect(page.total, 7);
    expect(page.limit, 200);
    expect(page.items.single.saleState, WishSaleState.ended);
    expect(page.items.single.name, isNull);
    expect(page.items.single.imageUrl, isNull);
    expect(page.items.single.infoMissing, isTrue);
    expect(WishSaleState.fromWire('SOMETHING'), WishSaleState.unknown);
  });
}
