import 'package:customer_app/features/auth/data/auth_repository.dart';
import 'package:customer_app/features/auth/data/google_token_source.dart'
    show SocialProviderMisconfigured;
import 'package:customer_app/features/auth/data/kakao_naver_token_sources.dart';
import 'package:customer_app/features/auth/data/mock_auth_repository.dart';
import 'package:customer_app/features/auth/domain/auth.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';

/// 네이버 로그인(BR-69, auth 0.10.0): 앱은 인가 코드까지만 받고 서버가 ID 토큰으로 바꾼다.
void main() {
  const granted = (code: 'code-1', codeVerifier: 'verifier-1');

  NaverSocialTokenSource source(
    MockAuthRepository repo, {
    NaverAuthorize? authorize,
    String clientId = 'client',
  }) => NaverSocialTokenSource(
    clientId: clientId,
    exchange: repo.exchangeNaverCode,
    authorize: authorize ?? (_) async => granted,
  );

  MockAuthRepository repo0() => MockAuthRepository(latency: Duration.zero);

  test('인가 코드를 서버에 넘겨 받은 ID 토큰을 providerToken 으로 쓴다', () async {
    final repo = repo0();
    final c = await source(repo).obtain(SocialProvider.naver);
    expect(c?.token, 'mock-naver-id-token');
    expect(repo.naverExchangeKeys, hasLength(1));
  });

  test('교환 응답의 프로필 사진 주소를 같이 넘긴다 — 없으면(null) 없이', () async {
    final repo = repo0();
    final c = await source(repo).obtain(SocialProvider.naver);
    expect(c?.profileImageUrl, 'https://phinf.pstatic.net/mock/profile.jpg');

    repo.naverProfileImageUrl = null;
    final none = await source(repo).obtain(SocialProvider.naver);
    expect(none?.token, 'mock-naver-id-token');
    expect(none?.profileImageUrl, isNull);
  });

  test('고객이 네이버 화면을 닫으면 취소(null) — 서버에 보내지 않는다', () async {
    final repo = repo0();
    final c = await source(
      repo,
      authorize: (_) async => null,
    ).obtain(SocialProvider.naver);
    expect(c, isNull);
    expect(repo.naverExchangeKeys, isEmpty);
  });

  test('교환 결과를 모르면 같은 키로 한 번 더 — 코드를 두 번 쓰지 않게', () async {
    final repo = repo0()
      ..failNextNaverExchange = const UnknownResultFailure(requestId: 'x');
    final c = await source(repo).obtain(SocialProvider.naver);
    expect(c?.token, 'mock-naver-id-token');
    expect(repo.naverExchangeKeys, hasLength(2));
    expect(repo.naverExchangeKeys.toSet(), hasLength(1));
  });

  test('네이버가 코드를 거절하면(401 PROVIDER_REJECTED) 제공자 장애로 알린다', () async {
    final repo = repo0()
      ..failNextNaverExchange = const ProblemFailure(
        Problem(status: 401, code: 'PROVIDER_REJECTED'),
      );
    await expectLater(
      source(repo).obtain(SocialProvider.naver),
      throwsA(isA<SocialProviderDown>()),
    );
  });

  test('서버에 네이버 secret 이 없으면(422 CONFIG_REQUIRED) 설정 문제로 알린다', () async {
    final repo = repo0()
      ..failNextNaverExchange = const ProblemFailure(
        Problem(status: 422, code: ProblemCode.configRequired),
      );
    await expectLater(
      source(repo).obtain(SocialProvider.naver),
      throwsA(isA<SocialProviderMisconfigured>()),
    );
  });

  test('인가 화면 오류(PlatformException)는 제공자 장애 — 서버에 보내지 않는다', () async {
    final repo = repo0();
    await expectLater(
      source(
        repo,
        authorize: (_) async => throw PlatformException(code: 'x'),
      ).obtain(SocialProvider.naver),
      throwsA(isA<SocialProviderDown>()),
    );
    expect(repo.naverExchangeKeys, isEmpty);
  });

  test('Client ID 가 없으면 화면을 띄우지 않고 설정 문제', () async {
    var asked = false;
    await expectLater(
      source(
        repo0(),
        clientId: '',
        authorize: (_) async {
          asked = true;
          return granted;
        },
      ).obtain(SocialProvider.naver),
      throwsA(isA<SocialProviderMisconfigured>()),
    );
    expect(asked, isFalse);
  });
}
