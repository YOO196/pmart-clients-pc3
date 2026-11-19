import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';

import 'package:customer_app/features/cart/data/cart_merge_repository.dart';
import 'package:customer_app/features/cart/data/guest_session.dart';
import 'package:customer_app/features/cart/data/mock_cart_repository.dart';
import 'package:customer_app/features/cart/domain/cart.dart';
import 'package:customer_app/features/cart/domain/cart_merge.dart';
import 'package:customer_app/features/cart/presentation/cart_merge_screen.dart';
import 'package:customer_app/shared/providers.dart' show sourceSystem;

import 'support/app_harness.dart';

/// 주문서 로그인 뒤 비회원 장바구니 병합(SCR-CART-MERGE-001, BR-50 회신 — cart 0.2.2). 목 모드.
void main() {
  Finder key(String k) => find.byKey(ValueKey(k));

  late MockCartRepository member;
  late MockCartRepository guest;
  late MockCartMergeRepository merges;

  setUp(() {
    member = MockCartRepository(latency: Duration.zero);
    guest = MockCartRepository(latency: Duration.zero, seeded: false)
      ..seedLine('E-00000002', 1) // ci-1
      ..seedLine('E-00000003', 2); // ci-2
    merges = MockCartMergeRepository(member: member, guest: guest);
  });

  /// 비회원으로 장바구니 → 주문하기 → 카카오 로그인(CHECKOUT).
  Future<void> toMerge(WidgetTester t) async {
    t.view
      ..physicalSize = const Size(800, 1800)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp(cart: member, [
        cartMergeRepositoryProvider.overrideWithValue(merges),
      ]),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('장바구니').last);
    await t.pumpAndSettle();
    await t.tap(key('cart-order'));
    await t.pumpAndSettle();
    await t.tap(key('login-kakao'));
    await t.pumpAndSettle();
  }

  bool onDelivery() => key('delivery-next').evaluate().isNotEmpty;

  testWidgets('비회원 장바구니가 비어 있으면 병합 화면 없이 바로 주문서', (t) async {
    guest = MockCartRepository(latency: Duration.zero, seeded: false);
    merges = MockCartMergeRepository(member: member, guest: guest);
    await toMerge(t);
    expect(key('cart-merge'), findsNothing);
    expect(onDelivery(), isTrue);
    expect(merges.requests, isEmpty);
  });

  testWidgets('품목이 있으면 확인 → 고른 것만 보내고 → 결과 → 주문 계속', (t) async {
    await toMerge(t);
    expect(key('cart-merge'), findsOneWidget);
    // 기본은 모두 고름. 하나 빼기
    expect(find.text('2개 담고 주문하기'), findsOneWidget);
    await t.tap(key('merge-item-ci-2'));
    await t.pump();
    expect(find.text('1개 담고 주문하기'), findsOneWidget);
    await t.tap(key('merge-confirm'));
    await t.pumpAndSettle();

    final (_, items) = merges.requests.single;
    expect(
      [for (final i in items) (i.sourceItemId, i.sku, i.quantity)],
      [('ci-1', 'E-00000002', 1)],
    );
    expect(key('merge-result'), findsOneWidget);
    expect(find.text('1개 상품을 내 장바구니에 담았어요'), findsOneWidget);
    expect(find.text('담음'), findsOneWidget);
    // 회원 장바구니에 더해졌다(서버가 합산)
    expect(
      (await t.runAsync(() => member.get(MockCartRepository.cartId)))!.lines
          .map((l) => l.sku),
      contains('E-00000002'),
    );
    await t.tap(key('merge-continue'));
    await t.pumpAndSettle();
    expect(onDelivery(), isTrue);
  });

  testWidgets('일부 거절: 이유를 보이고, 못 담은 것은 비회원 장바구니에 남는다고 안내', (t) async {
    merges.rejectSkus = {'E-00000003': 'QUANTITY_LIMIT_EXCEEDED'};
    await toMerge(t);
    await t.tap(key('merge-confirm'));
    await t.pumpAndSettle();
    expect(find.text('1개 상품만 담았어요'), findsOneWidget);
    expect(find.text('담지 못한 상품은 로그인 전 장바구니에 그대로 있어요.'), findsOneWidget);
    expect(key('merge-result-ci-2'), findsOneWidget);
    expect(find.text('담음'), findsOneWidget);
  });

  testWidgets('수량 조정: 한도로 못 담은 상품을 줄여 다시 담으면 나머지는 비회원 장바구니에 남는다', (t) async {
    merges.maxQuantity = {'E-00000003': 1};
    await toMerge(t);
    // 수량은 1 ~ 비회원 장바구니 수량(2)
    expect(t.widget<Text>(key('merge-qty-ci-2')).data, '2');
    await t.tap(key('merge-confirm'));
    await t.pumpAndSettle();
    expect(find.text('1개 상품만 담았어요'), findsOneWidget);

    await t.tap(key('merge-adjust'));
    await t.pumpAndSettle();
    // 옮긴 상품은 빠지고, 못 담은 것만 골라져 이유가 보인다
    expect(key('merge-item-ci-1'), findsNothing);
    expect(key('merge-reason-ci-2'), findsOneWidget);
    expect(find.text('1개 담고 주문하기'), findsOneWidget);
    await t.tap(key('merge-minus-ci-2'));
    await t.pump();
    expect(t.widget<Text>(key('merge-qty-ci-2')).data, '1');
    await t.tap(key('merge-confirm'));
    await t.pumpAndSettle();

    final (firstKey, _) = merges.requests[0];
    final (secondKey, items) = merges.requests[1];
    expect(secondKey, isNot(firstKey));
    expect(
      [for (final i in items) (i.sourceItemId, i.quantity)],
      [('ci-2', 1)],
    );
    expect(find.text('1개 상품을 내 장바구니에 담았어요'), findsOneWidget);
    final left = await t.runAsync(() => guest.get(MockCartRepository.cartId));
    expect(
      [for (final l in left!.lines) (l.sku, l.quantity)],
      [('E-00000003', 1)],
    );
  });

  testWidgets('담지 않고 주문하기는 병합을 부르지 않는다', (t) async {
    await toMerge(t);
    await t.tap(key('merge-skip'));
    await t.pumpAndSettle();
    expect(merges.requests, isEmpty);
    expect(onDelivery(), isTrue);
  });

  testWidgets('비회원 장바구니를 못 읽으면 빈 것으로 보지 않는다 — 다시 불러오기', (t) async {
    merges.failNextGuestRead = const NetworkFailure(
      DioExceptionType.connectionError,
    );
    await toMerge(t);
    expect(key('merge-load-error'), findsOneWidget);
    expect(onDelivery(), isFalse);
    await t.tap(key('merge-reload'));
    await t.pumpAndSettle();
    expect(key('merge-item-ci-1'), findsOneWidget);
  });

  testWidgets('결과 불명: 새로 합치지 않고 같은 키로만 다시 확인', (t) async {
    merges.nextOutcome = const MergeUnknown();
    await toMerge(t);
    await t.tap(key('merge-confirm'));
    await t.pumpAndSettle();
    expect(key('merge-unknown'), findsOneWidget);
    expect(key('merge-confirm'), findsNothing);
    expect(key('merge-skip'), findsNothing);
    await t.tap(key('merge-check-again'));
    await t.pumpAndSettle();
    expect(merges.requests, hasLength(2));
    expect(merges.requests[0].$1, merges.requests[1].$1);
    expect(key('merge-result'), findsOneWidget);
  });

  testWidgets('회원 장바구니가 그 사이 바뀌면 안내하고, 다시 누르면 새 키', (t) async {
    merges.nextOutcome = const MergeVersionConflict();
    await toMerge(t);
    await t.tap(key('merge-confirm'));
    await t.pumpAndSettle();
    expect(find.text('그 사이 장바구니가 바뀌었어요. 다시 눌러 주세요'), findsOneWidget);
    await t.tap(key('merge-confirm'));
    await t.pumpAndSettle();
    expect(merges.requests, hasLength(2));
    expect(merges.requests[0].$1, isNot(merges.requests[1].$1));
    expect(key('merge-result'), findsOneWidget);
  });

  group('ApiCartMergeRepository', () {
    const base = 'http://test.invalid/api/v1';
    late TokenStore guestTokens;
    late List<String?> refreshedWith;

    setUp(() async {
      guestTokens = TokenStore(
        MemoryKeyValueStore(),
        refreshKey: guestRefreshKey,
      );
      await guestTokens.save(
        const AuthTokens(accessToken: 'g-old', refreshToken: 'g-refresh'),
      );
      refreshedWith = [];
    });

    ApiCartMergeRepository repo(FakeAdapter adapter) {
      Dio dio() => createPmartDio(
        baseUrl: base,
        sourceSystem: sourceSystem,
        tokens: TokenStore(MemoryKeyValueStore()),
        refresher: (_) async => null,
        adapter: adapter,
        delay: (_) async {},
      );
      return ApiCartMergeRepository(
        memberDio: dio(),
        guestDio: dio(),
        guestTokens: guestTokens,
        refreshGuest: (r) async {
          refreshedWith.add(r);
          return const AuthTokens(accessToken: 'g-new', refreshToken: 'g-r2');
        },
      );
    }

    final guestCart = Cart(
      cartId: 'cart-guest',
      version: 4,
      isMember: false,
      lines: const [],
    );
    const items = [
      MergeItemRequest(sourceItemId: 'gi-1', sku: 'E-00000002', quantity: 1),
    ];
    final ok = {
      'mergeId': 'm-1',
      'state': 'MERGE_CONFIRMED',
      'targetCartId': 'cart-member',
      'sourceCartId': 'cart-guest',
      'items': [
        {
          'sourceItemId': 'gi-1',
          'sku': 'E-00000002',
          'requestedQuantity': 1,
          'result': 'MERGED',
          'mergedQuantity': 1,
        },
      ],
    };

    test('계약대로 보낸다(회원 장바구니·X-Guest-Token·키·버전)', () async {
      final adapter = FakeAdapter((_, _) async => FakeReply(200, body: ok));
      final key = IdempotencyKey.generate();
      final outcome = await repo(adapter).merge(
        memberCartId: 'cart-member',
        memberCartVersion: 7,
        guest: guestCart,
        items: items,
        key: key,
      );
      final sent = adapter.requests.single;
      expect(sent.path, endsWith('/carts/cart-member/merges'));
      expect(sent.headers['X-Guest-Token'], 'g-old');
      expect(sent.headers['Idempotency-Key'], key.value);
      expect(sent.headers['X-Source-System'], sourceSystem);
      expect(jsonDecode(sent.data as String), {
        'sourceCartId': 'cart-guest',
        'sourceCartVersion': 4,
        'expectedVersion': 7,
        'items': [
          {'sourceItemId': 'gi-1', 'sku': 'E-00000002', 'quantity': 1},
        ],
      });
      expect(
        outcome,
        isA<MergeAnswered>().having(
          (o) => o.result.state,
          'state',
          MergeState.confirmed,
        ),
      );
    });

    test('비회원 토큰 만료(403 FORBIDDEN_OWNER) → 갱신 뒤 같은 키로 한 번 더', () async {
      final adapter = FakeAdapter(
        (_, i) async => i == 0
            ? FakeReply.problem(
                403,
                problemBody('FORBIDDEN_OWNER', status: 403),
              )
            : FakeReply(200, body: ok),
      );
      final key = IdempotencyKey.generate();
      final outcome = await repo(adapter).merge(
        memberCartId: 'cart-member',
        memberCartVersion: 7,
        guest: guestCart,
        items: items,
        key: key,
      );
      expect(refreshedWith, ['g-refresh']);
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests[1].headers['X-Guest-Token'], 'g-new');
      expect(
        adapter.requests.map((r) => r.headers['Idempotency-Key']).toSet(),
        {key.value},
      );
      expect(outcome, isA<MergeAnswered>());
    });

    test('409 CART_VERSION_CONFLICT 는 반영 안 됨으로', () async {
      final adapter = FakeAdapter(
        (_, _) async =>
            FakeReply.problem(409, problemBody('CART_VERSION_CONFLICT')),
      );
      final outcome = await repo(adapter).merge(
        memberCartId: 'cart-member',
        memberCartVersion: 7,
        guest: guestCart,
        items: items,
        key: IdempotencyKey.generate(),
      );
      expect(outcome, isA<MergeVersionConflict>());
    });

    test('503 결과 불명 → 같은 키로 다시, 그래도 모르면 불명', () async {
      final adapter = FakeAdapter(
        (_, _) async => FakeReply.problem(
          503,
          problemBody('REQUEST_RESULT_UNKNOWN', status: 503),
        ),
      );
      final key = IdempotencyKey.generate();
      final outcome = await repo(adapter).merge(
        memberCartId: 'cart-member',
        memberCartVersion: 7,
        guest: guestCart,
        items: items,
        key: key,
      );
      expect(outcome, isA<MergeUnknown>());
      expect(
        adapter.requests.map((r) => r.headers['Idempotency-Key']).toSet(),
        {key.value},
      );
      expect(adapter.requests.length, greaterThanOrEqualTo(2));
    });
  });
}
