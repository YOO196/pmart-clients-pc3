import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import 'package:customer_app/features/auth/data/auth_repository.dart';
import 'package:customer_app/features/auth/data/kakao_naver_token_sources.dart';
import 'package:customer_app/features/auth/domain/auth.dart';

/// 백엔드 요청 2026-11-21 "로그인 버튼마다 계정 고르기·다시 로그인" R2: 카카오계정 로그인 화면 + prompt=login,
/// 앱 로그아웃 때 카카오 SDK logout. 앱 연결 끊기는 서버가 한다(앱은 끊지 않는다).
void main() {
  OAuthToken token(String? idToken) => OAuthToken(
    'access',
    DateTime.now().add(const Duration(hours: 1)),
    'refresh',
    DateTime.now().add(const Duration(days: 30)),
    null,
    idToken: idToken,
  );

  test('로그인은 매번 다시 로그인 화면(prompt=login) — 동의 다시 묻기(consent)가 아니다', () {
    expect(kakaoLoginPrompts, [Prompt.login]);
  });

  test('로그인 버튼마다 카카오계정 로그인을 부르고 ID 토큰을 넘긴다', () async {
    var calls = 0;
    final source = KakaoSocialTokenSource(
      login: () async {
        calls++;
        return token('id-token');
      },
      logout: () async {},
    );
    expect((await source.obtain(SocialProvider.kakao))?.token, 'id-token');
    expect((await source.obtain(SocialProvider.kakao))?.token, 'id-token');
    expect(calls, 2, reason: '저장된 로그인으로 건너뛰지 않는다');
  });

  test('로그인 화면을 닫으면 취소(null)', () async {
    final source = KakaoSocialTokenSource(
      login: () async => throw PlatformException(code: 'CANCELED'),
      logout: () async {},
    );
    expect(await source.obtain(SocialProvider.kakao), isNull);
  });

  test('ID 토큰이 없으면(OIDC 꺼짐) 설정 문제', () async {
    final source = KakaoSocialTokenSource(
      login: () async => token(null),
      logout: () async {},
    );
    expect(
      source.obtain(SocialProvider.kakao),
      throwsA(
        isA<Exception>().having(
          (e) => e,
          'not down',
          isNot(isA<SocialProviderDown>()),
        ),
      ),
    );
  });

  test('로그아웃·탈퇴 때 카카오 SDK logout — 실패해도 던지지 않는다', () async {
    var logouts = 0;
    final source = KakaoSocialTokenSource(
      login: () async => token('id'),
      logout: () async {
        logouts++;
        throw Exception('offline');
      },
    );
    await source.forget(SocialProvider.kakao);
    await source.forget(SocialProvider.kakao, revoke: true);
    expect(logouts, 2);
    // 다른 제공자는 건드리지 않는다
    await source.forget(SocialProvider.google);
    expect(logouts, 2);
  });
}
