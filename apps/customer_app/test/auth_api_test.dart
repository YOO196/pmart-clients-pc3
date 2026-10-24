import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';

import 'package:customer_app/features/auth/data/auth_repository.dart';
import 'package:customer_app/features/auth/domain/auth.dart';
import 'package:customer_app/shared/providers.dart';

void main() {
  late TokenStore tokens;
  final deviceId = DeviceIdProvider(MemoryKeyValueStore());

  setUp(() async {
    tokens = TokenStore(MemoryKeyValueStore());
    // 남아 있는 토큰이 있어도 로그인 요청에는 붙이지 않는다.
    await tokens.save(const AuthTokens(accessToken: 'old', refreshToken: 'r'));
  });

  ApiAuthRepository repoWith(FakeAdapter adapter) => ApiAuthRepository(
    createPmartDio(
      baseUrl: 'http://test.invalid/api/v1',
      sourceSystem: sourceSystem,
      tokens: tokens,
      deviceId: deviceId,
      refresher: (_) async => null,
      adapter: adapter,
      delay: (_) async {},
    ),
    deviceId,
  );

  test('소셜 로그인은 공개 경로라 인증 헤더 없이 기기 ID·멱등 키를 보낸다', () async {
    final adapter = FakeAdapter(
      (_, _) async => const FakeReply(
        200,
        body: {
          'authRequestId': 'auth-1',
          'state': 'AUTH_MEMBER',
          'accountId': 'acct-1',
          'tokens': {
            'accessToken': 'a',
            'refreshToken': 'b',
            'accessTokenExpiresAt': '2026-10-24T10:00:00Z',
          },
          'nextAction': 'CART_MERGE_CONFIRM',
        },
      ),
    );

    final outcome = await repoWith(adapter).login(
      SocialProvider.kakao,
      'provider-token',
      purpose: LoginPurpose.checkout,
      key: IdempotencyKey('k-1'),
    );

    final member = outcome as LoginMember;
    expect(member.accountId, 'acct-1');
    expect(member.cartMergeConfirm, isTrue);
    final h = adapter.requests.single.headers;
    expect(h.containsKey('Authorization'), isFalse);
    expect(h['Idempotency-Key'], 'k-1');
    expect(h['X-Device-Id'], await deviceId.get());
  });

  test('423 은 제한이고 남은 시간은 서버 값이다', () async {
    final adapter = FakeAdapter(
      (_, _) async => FakeReply.problem(423, {
        ...problemBody('AUTH_RESTRICTED', status: 423),
        'retryAfterSeconds': 420,
      }),
    );

    final outcome = await repoWith(adapter).login(
      SocialProvider.naver,
      't',
      purpose: LoginPurpose.general,
      key: IdempotencyKey('k-2'),
    );

    expect((outcome as LoginRestricted).retryAfterSeconds, 420);
  });

  test('503 PROVIDER_UNAVAILABLE 은 제공자 장애, 그 밖의 503 은 결과 불명이다', () async {
    var call = 0;
    final adapter = FakeAdapter((_, _) async {
      call++;
      return FakeReply.problem(
        503,
        problemBody(
          call == 1 ? 'PROVIDER_UNAVAILABLE' : 'UNKNOWN_RESULT',
          status: 503,
        ),
      );
    });
    final repo = repoWith(adapter);

    Future<LoginOutcome> attempt(String k) => repo.login(
      SocialProvider.kakao,
      't',
      purpose: LoginPurpose.general,
      key: IdempotencyKey(k),
    );

    expect(await attempt('k-3'), isA<LoginProviderUnavailable>());
    expect(await attempt('k-4'), isA<LoginUnknown>());
  });
}
