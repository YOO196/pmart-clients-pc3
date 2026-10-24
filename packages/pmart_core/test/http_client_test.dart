import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';

import 'package:pmart_core/testing.dart';

void main() {
  late TokenStore tokens;
  late List<Duration> delays;

  setUp(() async {
    tokens = TokenStore(MemoryKeyValueStore());
    await tokens.save(
      const AuthTokens(accessToken: 'access-1', refreshToken: 'refresh-1'),
    );
    delays = [];
  });

  Dio build(
    FakeAdapter adapter, {
    TokenRefresher? refresher,
    void Function()? onSessionExpired,
    DeviceIdProvider? deviceId,
  }) => createPmartDio(
    baseUrl: 'http://test.invalid/api/v1',
    sourceSystem: 'customer-app',
    tokens: tokens,
    refresher: refresher ?? (_) async => null,
    onSessionExpired: onSessionExpired,
    deviceId: deviceId,
    adapter: adapter,
    delay: (d) async => delays.add(d),
  );

  group('요청 헤더', () {
    test('변경 요청에 멱등 키·출처·인증·기기 ID·기대 버전을 붙인다', () async {
      final adapter = FakeAdapter(
        (_, _) async => FakeReply(202, body: commandBody('ACCEPTED')),
      );
      final dio = build(
        adapter,
        deviceId: DeviceIdProvider(MemoryKeyValueStore()),
      );
      final key = IdempotencyKey('key-abc');

      await dio.post<dynamic>(
        '/carts/c1/items',
        data: {'sku': 'E-00000001'},
        options: commandOptions(key, expectedVersion: 7),
      );

      final h = adapter.requests.single.headers;
      expect(h['Idempotency-Key'], 'key-abc');
      expect(h['X-Source-System'], 'customer-app');
      expect(h['Authorization'], 'Bearer access-1');
      expect(h['X-Expected-Version'], '7');
      expect(h['X-Device-Id'], isA<String>());
      expect(h.containsKey('traceparent'), isFalse);
    });

    test('조회 요청에는 멱등 키를 붙이지 않는다', () async {
      final adapter = FakeAdapter(
        (_, _) async => const FakeReply(200, body: {}),
      );
      await build(adapter).get<dynamic>('/carts/c1');

      expect(
        adapter.requests.single.headers.containsKey('Idempotency-Key'),
        isFalse,
      );
    });

    test('멱등 키 없는 변경 요청은 보내지 않는다', () async {
      final adapter = FakeAdapter((_, _) async => const FakeReply(200));

      await expectLater(
        build(adapter).post<dynamic>('/carts/c1/items'),
        throwsA(
          isA<DioException>().having(
            (e) => e.error,
            'error',
            isA<StateError>(),
          ),
        ),
      );
      expect(adapter.requests, isEmpty);
    });

    test('공개 경로에는 인증 헤더를 붙이지 않는다', () async {
      final adapter = FakeAdapter(
        (_, _) async => const FakeReply(200, body: {}),
      );
      await build(adapter).get<dynamic>('/auth/x', options: publicOptions());

      expect(
        adapter.requests.single.headers.containsKey('Authorization'),
        isFalse,
      );
    });
  });

  group('429·재시도', () {
    test('429 는 Retry-After 만큼 기다린 뒤 같은 멱등 키로 다시 보낸다', () async {
      final adapter = FakeAdapter(
        (_, i) async => i == 0
            ? FakeReply.problem(
                429,
                problemBody('RATE_LIMITED', status: 429, retryable: true),
                headers: {'retry-after': '2'},
              )
            : FakeReply(202, body: commandBody('APPLIED')),
      );
      final key = IdempotencyKey.generate();

      final res = await build(adapter)
          .post<dynamic>('/x', options: commandOptions(key));

      expect(res.statusCode, 202);
      expect(delays, [const Duration(seconds: 2)]);
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.map((r) => r.headers['Idempotency-Key']).toSet(),
        {key.value},
      );
    });

    test('Retry-After 가 상한(30초)보다 길면 기다리지 않고 오류로 넘긴다', () async {
      final adapter = FakeAdapter(
        (_, _) async => FakeReply.problem(
          429,
          problemBody('RATE_LIMITED', status: 429),
          headers: {'retry-after': '120'},
        ),
      );

      await expectLater(
        build(adapter).get<dynamic>('/x'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.requests, hasLength(1));
      expect(delays, isEmpty);
    });

    test('retryable=true Problem 은 지수 백오프로 최대 3회 재시도한다', () async {
      final adapter = FakeAdapter(
        (_, _) async => FakeReply.problem(
          503,
          problemBody('DEPENDENCY_UNAVAILABLE', status: 503, retryable: true),
        ),
      );

      await expectLater(
        build(adapter).get<dynamic>('/x'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.requests, hasLength(4));
      expect(delays, const [
        Duration(milliseconds: 500),
        Duration(milliseconds: 1000),
        Duration(milliseconds: 2000),
      ]);
    });

    test('retryable=false Problem 은 재시도하지 않는다', () async {
      final adapter = FakeAdapter(
        (_, _) async => FakeReply.problem(409, problemBody('VERSION_CONFLICT')),
      );

      await expectLater(
        build(adapter).get<dynamic>('/x'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.requests, hasLength(1));
    });

    test('변경 요청의 타임아웃은 재전송하지 않는다', () async {
      final adapter = FakeAdapter(
        (_, _) async =>
            const FakeReply.transport(DioExceptionType.receiveTimeout),
      );

      await expectLater(
        build(adapter).post<dynamic>(
          '/x',
          options: commandOptions(IdempotencyKey.generate()),
        ),
        throwsA(isA<DioException>()),
      );
      expect(adapter.requests, hasLength(1));
    });
  });

  group('401 토큰 갱신', () {
    test('동시에 401 을 받아도 갱신은 한 번만 하고 새 토큰으로 다시 보낸다', () async {
      var refreshCalls = 0;
      final gate = Completer<void>();
      final adapter = FakeAdapter((o, _) async {
        if (o.headers['Authorization'] == 'Bearer access-2') {
          return const FakeReply(200, body: {});
        }
        return const FakeReply(401);
      });
      final dio = build(
        adapter,
        refresher: (refresh) async {
          refreshCalls++;
          expect(refresh, 'refresh-1');
          await gate.future;
          return const AuthTokens(
            accessToken: 'access-2',
            refreshToken: 'refresh-2',
          );
        },
      );

      final calls = [dio.get<dynamic>('/a'), dio.get<dynamic>('/b')];
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      final results = await Future.wait(calls);

      expect(refreshCalls, 1);
      expect(results.map((r) => r.statusCode), [200, 200]);
      expect(await tokens.readRefreshToken(), 'refresh-2');
    });

    test('옛 토큰으로 보낸 요청이 갱신 뒤 401 을 받으면 다시 갱신하지 않고 새 토큰으로 보낸다', () async {
      var refreshCalls = 0;
      final adapter = FakeAdapter((o, i) async {
        if (i == 0) {
          // 이 요청이 서버에 가 있는 동안 다른 요청이 갱신을 끝냈다.
          await tokens.save(
            const AuthTokens(
              accessToken: 'access-2',
              refreshToken: 'refresh-2',
            ),
          );
          return const FakeReply(401);
        }
        return o.headers['Authorization'] == 'Bearer access-2'
            ? const FakeReply(200, body: {})
            : const FakeReply(401);
      });
      final dio = build(
        adapter,
        refresher: (_) async {
          refreshCalls++;
          return null;
        },
      );

      final res = await dio.get<dynamic>('/a');

      expect(res.statusCode, 200);
      expect(refreshCalls, 0);
      expect(await tokens.readRefreshToken(), 'refresh-2');
    });

    test('갱신이 거절되면 토큰을 지우고 세션 만료로 끝낸다', () async {
      var expired = 0;
      final adapter = FakeAdapter((_, _) async => const FakeReply(401));
      final dio = build(adapter, onSessionExpired: () => expired++);

      final failure = await pmartGuard(() => dio.get<dynamic>('/a'))
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(failure, isA<SessionExpiredFailure>());
      expect(expired, 1);
      expect(tokens.accessToken, isNull);
      expect(await tokens.readRefreshToken(), isNull);
    });

    test('갱신 뒤 다시 401 이면 반복하지 않는다', () async {
      var refreshCalls = 0;
      final adapter = FakeAdapter((_, _) async => const FakeReply(401));
      final dio = build(
        adapter,
        refresher: (_) async {
          refreshCalls++;
          return const AuthTokens(accessToken: 'a', refreshToken: 'r');
        },
      );

      await expectLater(dio.get<dynamic>('/a'), throwsA(isA<DioException>()));
      expect(refreshCalls, 1);
      expect(adapter.requests, hasLength(2));
    });
  });

  group('실패 분류', () {
    Future<PmartFailure> failureOf(
      FakeReply reply, {
      bool mutation = false,
    }) async {
      final dio = build(FakeAdapter((_, _) async => reply));
      try {
        await pmartGuard(
          () => mutation
              ? dio.post<dynamic>(
                  '/x',
                  options: commandOptions(IdempotencyKey.generate()),
                )
              : dio.get<dynamic>('/x'),
        );
      } on PmartFailure catch (f) {
        return f;
      }
      fail('실패가 나야 한다');
    }

    test('변경 요청 타임아웃은 결과 불명이다(실패 아님)', () async {
      expect(
        await failureOf(
          const FakeReply.transport(DioExceptionType.receiveTimeout),
          mutation: true,
        ),
        isA<UnknownResultFailure>(),
      );
    });

    test('조회 요청 타임아웃은 네트워크 실패다', () async {
      expect(
        await failureOf(
          const FakeReply.transport(DioExceptionType.connectionTimeout),
        ),
        isA<NetworkFailure>(),
      );
    });

    test('변경 요청의 Problem 아닌 5xx 는 결과 불명이다', () async {
      expect(
        await failureOf(
          const FakeReply(502, body: 'bad gateway', contentType: 'text/html'),
          mutation: true,
        ),
        isA<UnknownResultFailure>(),
      );
    });

    test('UNKNOWN_RESULT Problem 은 변경 요청이면 결과 불명이다', () async {
      expect(
        await failureOf(
          FakeReply.problem(503, problemBody('UNKNOWN_RESULT', status: 503)),
          mutation: true,
        ),
        isA<UnknownResultFailure>(),
      );
    });

    test('2xx 인데 모델로 읽지 못하면: 조회는 계약 위반, 변경은 결과 불명', () {
      DioException deserializeError(String method) {
        final options = RequestOptions(path: '/x', method: method);
        return DioException(
          requestOptions: options,
          response: Response<dynamic>(requestOptions: options, statusCode: 200),
          type: DioExceptionType.unknown,
          error: const FormatException('missing cartId'),
        );
      }

      expect(
        PmartFailure.fromDioException(deserializeError('GET')),
        isA<ContractViolationFailure>(),
      );
      expect(
        PmartFailure.fromDioException(deserializeError('POST')),
        isA<UnknownResultFailure>(),
      );
    });

    test('Problem 은 code 와 X-Request-Id 를 보존한다', () async {
      final f = await failureOf(
        FakeReply.problem(
          409,
          problemBody('VERSION_CONFLICT'),
          headers: {'x-request-id': 'rid-9'},
        ),
      );
      expect(f, isA<ProblemFailure>());
      expect((f as ProblemFailure).problem.code, ProblemCode.versionConflict);
      expect(f.requestId, 'rid-9');
    });
  });
}
