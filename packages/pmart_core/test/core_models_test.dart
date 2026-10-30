import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';

void main() {
  group('CommandResponse', () {
    test('ACCEPTED·UNKNOWN_RESULT 는 확정이 아니다', () {
      expect(CommandStatus.accepted.isFinal, isFalse);
      expect(CommandStatus.unknownResult.isFinal, isFalse);
      expect(CommandStatus.applied.isFinal, isTrue);
      expect(CommandStatus.rejected.isFinal, isTrue);
    });

    test('계약 필드를 읽고 확장 필드는 raw 로 보존한다', () {
      final r = CommandResponse.fromJson({
        'status': 'APPLIED',
        'requestId': 'k-1',
        'version': 3,
        'nextAction': 'QUERY_RESULT',
        'occurredAt': '2026-10-24T00:00:00Z',
        'cartVersion': 12,
      });
      expect(r.status, CommandStatus.applied);
      expect(r.version, 3);
      expect(r.occurredAt, DateTime.utc(2026, 10, 24));
      expect(r.raw['cartVersion'], 12);
    });

    test('모르는 status 는 조용히 넘기지 않는다', () {
      expect(
        () => CommandResponse.fromJson({'status': 'DONE', 'requestId': 'k'}),
        throwsFormatException,
      );
    });
  });

  group('ResultResolver', () {
    test('ACCEPTED 뒤 APPLIED 가 오면 확정한다', () async {
      final answers = [
        _cmd(CommandStatus.accepted),
        _cmd(CommandStatus.applied),
      ];
      final delays = <Duration>[];
      final resolution = await ResultResolver(delay: (d) async => delays.add(d))
          .resolve(() async => answers.removeAt(0));

      expect(resolution, isA<Resolved>());
      expect((resolution as Resolved).response.status, CommandStatus.applied);
      expect(delays, [const Duration(seconds: 2)]);
    });

    test('끝까지 확정되지 않으면 "아직 모름"이다(실패 아님)', () async {
      var calls = 0;
      final resolution =
          await ResultResolver(maxAttempts: 3, delay: (_) async {}).resolve(
            () async {
              calls++;
              return _cmd(CommandStatus.unknownResult);
            },
          );

      expect(calls, 3);
      expect(resolution, isA<StillUnknown>());
      expect(
        (resolution as StillUnknown).last?.status,
        CommandStatus.unknownResult,
      );
    });

    test('짝 조회가 실패해도 실패로 확정하지 않는다', () async {
      final resolution =
          await ResultResolver(maxAttempts: 2, delay: (_) async {}).resolve(
            () async =>
                throw const NetworkFailure(DioExceptionType.receiveTimeout),
          );

      expect(resolution, isA<StillUnknown>());
      expect((resolution as StillUnknown).lastFailure, isA<NetworkFailure>());
    });
  });

  group('저장소', () {
    test('진행 중 명령을 저장·삭제한다(같은 키는 덮어쓴다)', () async {
      final store = PendingCommandStore(MemoryKeyValueStore());
      final c = PendingCommand(
        requestId: 'k-1',
        kind: 'checkout',
        targetId: 'draft-1',
        startedAt: DateTime.utc(2026, 10, 24, 1),
      );
      await store.add(c);
      await store.add(c);
      expect((await store.list()).map((e) => e.requestId), ['k-1']);
      expect((await store.list()).single.startedAt, c.startedAt);

      await store.remove('k-1');
      expect(await store.list(), isEmpty);
    });

    test('기기 ID 는 한 번 만들면 바뀌지 않는다', () async {
      final kv = MemoryKeyValueStore();
      final first = await DeviceIdProvider(kv).get();
      final second = await DeviceIdProvider(kv).get();
      expect(first, second);
    });

    test('토큰은 문자열로 찍어도 드러나지 않는다', () {
      const t = AuthTokens(accessToken: 'secret-a', refreshToken: 'secret-r');
      expect('$t', isNot(contains('secret')));
    });
  });

  group('기타', () {
    test('Retry-After 초와 HTTP-date 를 읽는다', () {
      final now = DateTime.utc(2026, 10, 24, 8, 0, 0);
      expect(parseRetryAfter('5', now: now), const Duration(seconds: 5));
      expect(
        parseRetryAfter('Sat, 24 Oct 2026 08:00:10 GMT', now: now),
        const Duration(seconds: 10),
      );
      expect(parseRetryAfter('soon', now: now), isNull);
      expect(parseRetryAfter(null, now: now), isNull);
    });

    test('로그용 경로는 쿼리 값을 가린다', () {
      expect(
        redactPath(Uri.parse('http://h/api/v1/search?q=010-1234&page=2')),
        '/api/v1/search?q=***&page=***',
      );
      expect(
        redactHeaders({'Authorization': 'Bearer x', 'X-Source-System': 'a'}),
        {'Authorization': '***', 'X-Source-System': 'a'},
      );
    });

    test('PMART_ENV 는 mock/local 만 받는다', () {
      expect(PmartEnv.parse('mock'), PmartEnv.mock);
      expect(PmartEnv.parse('local'), PmartEnv.local);
      expect(() => PmartEnv.parse('prod'), throwsArgumentError);
      expect(
        apiBaseUrl(PmartEnv.local, androidEmulator: true),
        'http://10.0.2.2:8080/api/v1',
      );
    });

    test('PMART_API_BASE_URL 은 local 의 게이트웨이 주소를 바꾸고, mock 에는 영향이 없다', () {
      const lan = 'http://192.168.0.40:8080/api/v1';
      expect(
        apiBaseUrl(PmartEnv.local, androidEmulator: true, override: lan),
        lan,
      );
      expect(
        apiBaseUrl(PmartEnv.mock, override: lan),
        'http://mock.invalid/api/v1',
      );
    });

    test('멱등 키는 128자를 넘을 수 없다', () {
      expect(() => IdempotencyKey('x' * 129), throwsArgumentError);
      expect(IdempotencyKey.generate(), isNot(IdempotencyKey.generate()));
    });
  });
}

CommandResponse _cmd(CommandStatus s) =>
    CommandResponse(status: s, requestId: 'k-1');
