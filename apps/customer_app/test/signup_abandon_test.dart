import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart'
    show OAuthToken;
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/auth/data/kakao_naver_token_sources.dart';
import 'package:customer_app/features/auth/data/mock_auth_repository.dart';
import 'package:customer_app/features/auth/domain/auth.dart';
import 'package:customer_app/features/auth/presentation/auth_controller.dart';

import 'support/app_harness.dart';

/// 제공자 동의는 했지만 우리 가입을 끝내지 않고 그만두면 제공자 연결을 끊는다 — 다음 로그인 때 동의 화면이 다시 뜨게
/// (사용자 2026-11-21 "아직 동의만 하고 가입한 것도 아닌데 왜 못 물어"). 앱이 끊는 것은 카카오·구글(네이버는 BR-79).
void main() {
  setUpAll(initPmartFormatting);

  Future<MockSocialTokenSource> openLogin(
    WidgetTester t,
    MockAuthRepository auth,
  ) async {
    t.view
      ..physicalSize = const Size(800, 1800)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final source = MockSocialTokenSource();
    await t.pumpWidget(
      testApp([
        socialTokenSourceProvider.overrideWithValue(source),
      ], auth: auth),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    return source;
  }

  testWidgets('약관 동의 단계에서 닫으면 그 제공자의 가입 중단을 알린다', (t) async {
    final auth = MockAuthRepository(latency: Duration.zero);
    final source = await openLogin(t, auth);
    // 목 네이버 = 새 계정, 필수 동의 대기.
    await t.tap(find.byKey(const ValueKey('login-naver')));
    await t.pumpAndSettle();
    expect(source.abandoned, isEmpty, reason: '동의 단계에 들어간 것만으로는 끊지 않는다');
    await t.tap(find.byKey(const ValueKey('consent-close')));
    await t.pumpAndSettle();
    expect(source.abandoned, [SocialProvider.naver]);
  });

  testWidgets('가입을 끝내면(회원) 끊지 않는다', (t) async {
    final auth = MockAuthRepository(latency: Duration.zero);
    final source = await openLogin(t, auth);
    await t.tap(find.byKey(const ValueKey('login-naver')));
    await t.pumpAndSettle();
    for (final c in MockAuthRepository.requiredConsents) {
      await t.tap(find.byKey(ValueKey('consent-$c')));
      await t.pump();
    }
    await t.tap(find.byKey(const ValueKey('consent-submit')));
    await t.pumpAndSettle();
    // 회원이 되고 로그인 화면이 닫힌 뒤(가입 뒤 내 정보 화면이 떠 있을 수 있다)
    expect(source.abandoned, isEmpty);
  });

  testWidgets('기존 회원 로그인은 끊지 않는다', (t) async {
    final auth = MockAuthRepository(latency: Duration.zero);
    final source = await openLogin(t, auth);
    // 목 카카오 = 기존 회원.
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    expect(source.abandoned, isEmpty);
  });

  group('카카오', () {
    OAuthToken token() => OAuthToken(
      'access',
      DateTime.now().add(const Duration(hours: 1)),
      'refresh',
      DateTime.now().add(const Duration(days: 30)),
      null,
      idToken: 'id-token',
    );

    test('가입 중단이면 카카오 앱 연결을 끊는다', () async {
      var unlinks = 0;
      final source = KakaoSocialTokenSource(
        login: () async => token(),
        logout: () async {},
        unlink: () async => unlinks++,
      );
      await source.abandonSignup(SocialProvider.kakao);
      expect(unlinks, 1);
      await source.abandonSignup(SocialProvider.naver);
      expect(unlinks, 1, reason: '다른 제공자는 건드리지 않는다');
    });

    test('끊기 실패는 던지지 않는다', () async {
      final source = KakaoSocialTokenSource(
        login: () async => token(),
        logout: () async {},
        unlink: () async => throw Exception('offline'),
      );
      await expectLater(source.abandonSignup(SocialProvider.kakao), completes);
    });

    test('로그아웃은 연결을 끊지 않는다(이 기기 토큰만 지움)', () async {
      var unlinks = 0;
      var logouts = 0;
      final source = KakaoSocialTokenSource(
        login: () async => token(),
        logout: () async => logouts++,
        unlink: () async => unlinks++,
      );
      await source.forget(SocialProvider.kakao);
      expect((logouts, unlinks), (1, 0));
    });
  });
}
