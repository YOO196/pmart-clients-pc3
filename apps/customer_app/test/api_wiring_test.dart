import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';

import 'package:customer_app/features/cart/data/cart_repository.dart';
import 'package:customer_app/features/cart/data/mock_cart_repository.dart';
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
      (_, _) async => const FakeReply(200, body: MockCartRepository.fixture),
    );

    final summary = await repoWith(adapter).summary('cart-mock-1');

    expect(summary.cartId, 'cart-mock-1');
    expect(summary.lineCount, 2);
    expect(summary.selectedItemAmount, 23960);
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
      repoWith(adapter).summary('c'),
      throwsA(isA<ContractViolationFailure>()),
    );
  });

  test('404 Problem 은 code 로 구분된다', () async {
    final adapter = FakeAdapter(
      (_, _) async =>
          FakeReply.problem(404, problemBody('NOT_FOUND', status: 404)),
    );

    await expectLater(
      repoWith(adapter).summary('nope'),
      throwsA(
        isA<ProblemFailure>().having(
          (f) => f.problem.code,
          'code',
          ProblemCode.notFound,
        ),
      ),
    );
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
