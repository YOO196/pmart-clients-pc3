import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';

import 'package:customer_app/features/cart/data/cart_repository.dart';
import 'package:customer_app/features/cart/data/guest_session.dart';
import 'package:customer_app/features/cart/data/mock_cart_repository.dart';
import 'package:customer_app/shared/providers.dart';

/// 비회원 장바구니: 비회원 토큰(typ=GUEST)을 받아 /carts 를 부른다(ADR-0022). 네트워크는 쓰지 않는다.
void main() {
  const base = 'http://test.invalid/api/v1';
  late MemoryKeyValueStore store;
  late TokenStore guestTokens;
  late DeviceIdProvider deviceId;

  setUp(() {
    store = MemoryKeyValueStore();
    guestTokens = TokenStore(store, refreshKey: guestRefreshKey);
    deviceId = DeviceIdProvider(store);
  });

  Map<String, Object?> guestSession(String n) => {
    'guestId': 'GST-$n',
    'tokens': {
      'accessToken': 'g-access-$n',
      'refreshToken': 'g-refresh-$n',
      'accessTokenExpiresAt': '2026-10-30T13:00:00Z',
    },
  };

  ApiCartRepository repoWith(FakeAdapter adapter) {
    final dio = createPmartDio(
      baseUrl: base,
      sourceSystem: sourceSystem,
      tokens: guestTokens,
      deviceId: deviceId,
      refresher: (_) async => null,
      adapter: adapter,
      delay: (_) async {},
    );
    dio.interceptors.insert(
      0,
      GuestSessionInterceptor(
        tokens: guestTokens,
        start: guestSessionStarter(
          baseUrl: base,
          sourceSystem: sourceSystem,
          deviceId: deviceId,
          adapter: adapter,
        ),
      ),
    );
    return ApiCartRepository(dio);
  }

  FakeAdapter server() {
    var sessions = 0;
    return FakeAdapter((o, _) async {
      if (o.path.endsWith('/auth/guest-sessions')) {
        sessions++;
        return FakeReply(201, body: guestSession('$sessions'));
      }
      return FakeReply(201, body: MockCartRepository().cartJson());
    });
  }

  test('비회원 토큰이 없으면 먼저 비회원 세션을 받고, 그 토큰으로 장바구니를 연다', () async {
    final adapter = server();

    await repoWith(adapter).open();

    final [session, cart] = adapter.requests;
    expect(session.method, 'POST');
    expect(session.uri.toString(), '$base/auth/guest-sessions');
    expect(session.headers['Authorization'], isNull);
    expect(session.headers['X-Device-Id'], await deviceId.get());
    expect(session.headers['Idempotency-Key'], isNotEmpty);
    expect(cart.uri.toString(), '$base/carts');
    expect(cart.headers['Authorization'], 'Bearer g-access-1');
    expect(await store.read(guestRefreshKey), 'g-refresh-1');
    // 회원 토큰 자리는 건드리지 않는다.
    expect(await store.read(TokenStore.defaultRefreshKey), isNull);
  });

  test('동시에 여러 요청이 와도 비회원 세션은 한 번만 만든다', () async {
    final adapter = server();
    final repo = repoWith(adapter);

    await Future.wait([repo.open(), repo.get('cart-mock-1')]);

    expect(
      adapter.requests.where((r) => r.path.endsWith('/auth/guest-sessions')),
      hasLength(1),
    );
    expect(
      adapter.requests
          .where((r) => !r.path.endsWith('/auth/guest-sessions'))
          .map((r) => r.headers['Authorization']),
      everyElement('Bearer g-access-1'),
    );
  });

  test(
    '저장된 비회원 refresh token 이 있으면 새 세션을 만들지 않는다(갱신은 401 때 인증 인터셉터가)',
    () async {
      await store.write(guestRefreshKey, 'g-refresh-old');
      final adapter = server();

      await repoWith(adapter).open();

      expect(adapter.requests.single.uri.toString(), '$base/carts');
    },
  );

  test('비회원 세션을 받지 못하면 장바구니 요청을 보내지 않고 실패한다', () async {
    final adapter = FakeAdapter(
      (_, _) async =>
          const FakeReply.transport(DioExceptionType.connectionError),
    );

    await expectLater(repoWith(adapter).open(), throwsA(isA<PmartFailure>()));
    expect(adapter.requests, hasLength(1));
    expect(guestTokens.accessToken, isNull);
  });
}
