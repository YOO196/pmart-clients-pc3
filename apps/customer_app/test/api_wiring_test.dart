import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';

import 'package:customer_app/features/cart/data/cart_repository.dart';
import 'package:customer_app/features/cart/data/mock_cart_repository.dart';
import 'package:customer_app/features/cart/domain/cart.dart';
import 'package:customer_app/shared/providers.dart';

/// 생성 클라이언트(pmart_api_cart·auth) + pmart_core Dio 가 계약 모양 응답을 읽는지 본다.
/// 네트워크는 쓰지 않는다(FakeAdapter).
void main() {
  late TokenStore tokens;

  setUp(() async {
    tokens = TokenStore(MemoryKeyValueStore());
    await tokens.save(
      const AuthTokens(accessToken: 'a-1', refreshToken: 'r-1'),
    );
  });

  ApiCartRepository repoWith(FakeAdapter adapter) => ApiCartRepository(
    createPmartDio(
      baseUrl: 'http://test.invalid/api/v1',
      sourceSystem: sourceSystem,
      tokens: tokens,
      refresher: (_) async => null,
      adapter: adapter,
      delay: (_) async {},
    ),
  );

  test('GET /carts/{cartId} 응답을 생성 모델로 읽어 domain 으로 바꾼다', () async {
    final adapter = FakeAdapter(
      (_, _) async => FakeReply(200, body: MockCartRepository().cartJson()),
    );

    final cart = await repoWith(adapter).get('cart-mock-1');

    expect(cart.cartId, 'cart-mock-1');
    expect(cart.lines, hasLength(2));
    expect(cart.selectedItemAmount, 7940);
    final req = adapter.requests.single;
    expect(req.uri.toString(), 'http://test.invalid/api/v1/carts/cart-mock-1');
    expect(req.headers['Authorization'], 'Bearer a-1');
    expect(req.headers['X-Source-System'], 'customer-app');
  });

  test('필수 필드가 빠진 응답은 계약 위반으로 실패한다(빈 장바구니로 만들지 않음)', () async {
    final adapter = FakeAdapter(
      (_, _) async =>
          const FakeReply(200, body: {'cartId': 'c', 'items': <Object?>[]}),
    );

    await expectLater(
      repoWith(adapter).get('c'),
      throwsA(isA<ContractViolationFailure>()),
    );
  });

  test('404 Problem 은 code 로 구분된다', () async {
    final adapter = FakeAdapter(
      (_, _) async =>
          FakeReply.problem(404, problemBody('NOT_FOUND', status: 404)),
    );

    await expectLater(
      repoWith(adapter).get('nope'),
      throwsA(
        isA<ProblemFailure>().having(
          (f) => f.problem.code,
          'code',
          ProblemCode.notFound,
        ),
      ),
    );
  });

  group('장바구니 변경', () {
    final key = IdempotencyKey('k-1');

    test('담기는 멱등 키·기대 버전과 절대 수량을 보낸다', () async {
      final adapter = FakeAdapter(
        (_, _) async => const FakeReply(
          200,
          body: {
            'status': 'APPLIED',
            'requestId': 'k-1',
            'cartVersion': 4,
            'quantity': 3,
          },
        ),
      );

      final outcome = await repoWith(adapter).change(
        'cart-1',
        const AddItem(sku: 'E-00000001', quantity: 3),
        key: key,
        expectedVersion: 3,
      );

      expect(outcome, isA<CartChangeApplied>());
      expect((outcome as CartChangeApplied).cartVersion, 4);
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/api/v1/carts/cart-1/items');
      expect(req.headers['Idempotency-Key'], 'k-1');
      expect(req.headers['X-Expected-Version'], '3');
      final body = jsonDecode(req.data as String) as Map<String, dynamic>;
      expect(body, containsPair('quantity', 3));
      expect(body, containsPair('expectedVersion', 3));
    });

    test('503 REQUEST_RESULT_UNKNOWN 은 실패가 아니라 결과 불명이다', () async {
      final adapter = FakeAdapter(
        (_, _) async => FakeReply.problem(
          503,
          problemBody(CartProblemCode.requestResultUnknown, status: 503),
        ),
      );

      final outcome = await repoWith(adapter).change(
        'cart-1',
        const RemoveItem(cartItemId: 'ci-1'),
        key: key,
        expectedVersion: 3,
      );

      expect(outcome, isA<CartChangeUnknown>());
      expect(adapter.requests, hasLength(1), reason: '불명 결과를 자동 재전송하지 않는다');
    });

    test('타임아웃도 결과 불명이다', () async {
      final adapter = FakeAdapter(
        (_, _) async =>
            const FakeReply.transport(DioExceptionType.receiveTimeout),
      );

      final outcome = await repoWith(adapter).change(
        'cart-1',
        const SetQuantity(cartItemId: 'ci-1', quantity: 2),
        key: key,
        expectedVersion: 3,
      );

      expect(outcome, isA<CartChangeUnknown>());
    });

    test('409 CART_VERSION_CONFLICT 는 버전 충돌이다', () async {
      final adapter = FakeAdapter(
        (_, _) async => FakeReply.problem(
          409,
          problemBody(CartProblemCode.versionConflict),
        ),
      );

      final outcome = await repoWith(adapter).change(
        'cart-1',
        const SetSelected(cartItemId: 'ci-1', selected: false),
        key: key,
        expectedVersion: 3,
      );

      expect(outcome, isA<CartVersionConflict>());
    });

    test('422 상한 초과는 서버 limit 을 그대로 읽는다', () async {
      final adapter = FakeAdapter(
        (_, _) async => FakeReply.problem(422, {
          ...problemBody(CartProblemCode.quantityLimitExceeded, status: 422),
          'cartVersion': 3,
          'limit': {
            'baseProductId': 'P-1',
            'totalUnits': 12,
            'limitUnits': 10,
            'suggestedQuantity': 8,
          },
        }),
      );

      final outcome = await repoWith(adapter).change(
        'cart-1',
        const AddItem(sku: 'E-00000001', quantity: 12),
        key: key,
        expectedVersion: 3,
      );

      final r = outcome as CartChangeRejected;
      expect(r.code, CartProblemCode.quantityLimitExceeded);
      expect(r.limit?.limitUnits, 10);
      expect(r.limit?.suggestedQuantity, 8);
    });

    test('원결과 조회 404 는 미적용, 조회 실패는 아직 모름이다', () async {
      var call = 0;
      final adapter = FakeAdapter((_, _) async {
        call++;
        return call == 1
            ? FakeReply.problem(404, problemBody('NOT_FOUND', status: 404))
            : const FakeReply.transport(DioExceptionType.connectionTimeout);
      });
      final repo = repoWith(adapter);

      expect(await repo.lookup('cart-1', key), isA<CartChangeNotApplied>());
      expect(await repo.lookup('cart-1', key), isA<CartChangeUnknown>());
      expect(
        adapter.requests.first.uri.path,
        '/api/v1/carts/cart-1/change-requests/k-1',
      );
    });
  });

  group('토큰 갱신(POST /auth/tokens)', () {
    final deviceId = DeviceIdProvider(MemoryKeyValueStore());

    test('성공하면 새 토큰을 돌려주고 기기 ID·멱등 키를 보낸다', () async {
      final adapter = FakeAdapter(
        (_, _) async => const FakeReply(
          200,
          body: {
            'accessToken': 'a-2',
            'refreshToken': 'r-2',
            'accessTokenExpiresAt': '2026-10-24T09:00:00Z',
          },
        ),
      );
      final refresh = authRefresher(
        baseUrl: 'http://test.invalid/api/v1',
        deviceId: deviceId,
        adapter: adapter,
      );

      final next = await refresh('r-1');

      expect(next?.accessToken, 'a-2');
      expect(next?.refreshToken, 'r-2');
      final h = adapter.requests.single.headers;
      expect(h['Idempotency-Key'], isNotEmpty);
      expect(h['X-Device-Id'], await deviceId.get());
      expect(h.containsKey('Authorization'), isFalse);
    });

    test('401(재사용 감지 등)이면 null — 세션 만료로 처리된다', () async {
      final adapter = FakeAdapter(
        (_, _) async =>
            FakeReply.problem(401, problemBody('TOKEN_REUSED', status: 401)),
      );
      final refresh = authRefresher(
        baseUrl: 'http://test.invalid/api/v1',
        deviceId: deviceId,
        adapter: adapter,
      );

      expect(await refresh('r-1'), isNull);
    });

    test('네트워크 오류는 세션 만료로 단정하지 않고 예외로 올린다', () async {
      final adapter = FakeAdapter(
        (_, _) async =>
            const FakeReply.transport(DioExceptionType.connectionError),
      );
      final refresh = authRefresher(
        baseUrl: 'http://test.invalid/api/v1',
        deviceId: deviceId,
        adapter: adapter,
      );

      await expectLater(refresh('r-1'), throwsA(isA<PmartFailure>()));
    });
  });
}
