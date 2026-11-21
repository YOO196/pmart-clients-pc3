import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/auth/data/auth_repository.dart'
    show SocialTokenSource;
import 'package:customer_app/features/auth/data/mock_auth_repository.dart';
import 'package:customer_app/features/auth/domain/auth.dart';
import 'package:customer_app/features/auth/presentation/auth_controller.dart';
import 'package:pmart_core/pmart_core.dart' show PmartEnv;

import 'support/app_harness.dart';

/// 로그인 중 휴대폰 확인(AUTH_IDENTITY — auth 0.6.0, 백엔드 회신 2026-11-20 reply-br64-phone-identity).
void main() {
  setUpAll(initPmartFormatting);

  Future<void> openLogin(WidgetTester t, MockAuthRepository auth) async {
    t.view
      ..physicalSize = const Size(800, 1800)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const [], auth: auth));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
  }

  Future<void> enterPhone(WidgetTester t) async {
    await t.enterText(find.byKey(const ValueKey('id-phone')), '01012345678');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('id-next')));
    await t.pumpAndSettle();
  }

  bool member(WidgetTester t) =>
      ProviderScope.containerOf(t.element(find.byType(Scaffold).first))
              .read(sessionProvider)
          is MemberSession;

  testWidgets('확인 번호가 없는 기존 회원: 번호 → 보낼 문자 안내 → 보냈어요 → 회원', (t) async {
    final auth = MockAuthRepository(latency: Duration.zero)
      ..requireIdentity = true;
    await openLogin(t, auth);
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('login-identity')), findsOneWidget);
    expect(member(t), isFalse);
    await enterPhone(t);
    expect(auth.identityStarts, ['01012345678']);
    expect(
      t.widget<Text>(find.byKey(const ValueKey('id-send-to'))).data,
      '1666-3538',
    );
    expect(
      t.widget<Text>(find.byKey(const ValueKey('id-send-text'))).data,
      '482913',
    );

    await t.tap(find.byKey(const ValueKey('id-sent')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-identity')), findsNothing);
    expect(member(t), isTrue);
  });

  testWidgets('아직 문자가 확인되지 않으면 남은 횟수를 보이고 그 단계에 남는다', (t) async {
    final auth = MockAuthRepository(latency: Duration.zero)
      ..requireIdentity = true
      ..identityPendingNext = true;
    await openLogin(t, auth);
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    await enterPhone(t);
    await t.tap(find.byKey(const ValueKey('id-sent')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('id-pending')), findsOneWidget);
    expect(find.byKey(const ValueKey('id-sent')), findsOneWidget);
    expect(member(t), isFalse);
  });

  testWidgets('이미 가입된 번호(R3): 제공자·가입일·가린 이메일 안내 + 그 제공자로 로그인', (t) async {
    final auth = MockAuthRepository(latency: Duration.zero)
      ..requireIdentity = true
      ..identityConflictNext = 'IDENTITY_ALREADY_REGISTERED';
    await openLogin(t, auth);
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    await enterPhone(t);
    await t.tap(find.byKey(const ValueKey('id-sent')));
    await t.pumpAndSettle();
    expect(find.textContaining('카카오'), findsWidgets);
    expect(find.textContaining('h***@k***'), findsOneWidget);
    expect(find.byKey(const ValueKey('id-login-with')), findsOneWidget);
    expect(member(t), isFalse);
  });

  testWidgets('탈퇴한 번호(R4): 다시 가입할 수 있는 날짜를 보인다', (t) async {
    final auth = MockAuthRepository(latency: Duration.zero)
      ..requireIdentity = true
      ..identityConflictNext = 'IDENTITY_REJOIN_BLOCKED';
    await openLogin(t, auth);
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    await enterPhone(t);
    await t.tap(find.byKey(const ValueKey('id-sent')));
    await t.pumpAndSettle();
    expect(find.textContaining('2026년 12월 10일'), findsOneWidget);
    expect(member(t), isFalse);
  });

  testWidgets('새 가입(R1): 필수 동의 → 휴대폰 확인 → 회원', (t) async {
    final auth = MockAuthRepository(latency: Duration.zero)
      ..requireIdentity = true;
    await openLogin(t, auth);
    await t.tap(find.byKey(const ValueKey('login-naver')));
    await t.pumpAndSettle();
    for (final c in MockAuthRepository.requiredConsents) {
      await t.tap(find.byKey(ValueKey('consent-$c')));
      await t.pump();
    }
    await t.tap(find.byKey(const ValueKey('consent-submit')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-identity')), findsOneWidget);
    // 새 가입 단계 2/3(약관 동의 E안의 단계 표시).
    expect(find.byKey(const ValueKey('signup-steps-2')), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('가입하려면 휴대폰 번호를\n확인해 주세요'), findsOneWidget);
    await enterPhone(t);
    await t.tap(find.byKey(const ValueKey('id-sent')));
    await t.pumpAndSettle();
    expect(member(t), isTrue);
  });

  testWidgets('로그인 화면은 화면 폭 전체를 쓴다(실기기처럼 목 안내가 없어도 왼쪽에 붙지 않는다)', (t) async {
    t.view
      ..physicalSize = const Size(800, 1800)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp(
        const [],
        env: PmartEnv.local,
        auth: MockAuthRepository(latency: Duration.zero),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    final scroll = find.descendant(
      of: find.byType(LayoutBuilder),
      matching: find.byType(SingleChildScrollView),
    );
    final width = t.getSize(scroll.first).width;
    expect(width, t.view.physicalSize.width / t.view.devicePixelRatio);
    // 로고가 가운데
    expect(t.getCenter(find.text('바로픽')).dx, closeTo(width / 2, 1));
  });
  // 네이버 프로필 사진(auth 0.8.0·0.10.1, BR-70): 교환 응답으로 받은 주소를 로그인·동의 완료·휴대폰 확인 세 곳에 실어 보낸다.
  testWidgets('네이버 프로필 사진 주소를 로그인·동의 완료·휴대폰 확인("보냈어요") 세 곳에 같이 보낸다', (t) async {
    const photo = 'https://phinf.pstatic.net/mock/profile.jpg';
    final auth = MockAuthRepository(latency: Duration.zero)
      ..requireIdentity = true;
    t.view
      ..physicalSize = const Size(800, 1800)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp([
        socialTokenSourceProvider.overrideWithValue(const _WithPhoto(photo)),
      ], auth: auth),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-naver')));
    await t.pumpAndSettle();
    for (final c in MockAuthRepository.requiredConsents) {
      await t.tap(find.byKey(ValueKey('consent-$c')));
      await t.pump();
    }
    await t.tap(find.byKey(const ValueKey('consent-submit')));
    await t.pumpAndSettle();
    await enterPhone(t);
    await t.tap(find.byKey(const ValueKey('id-sent')));
    await t.pumpAndSettle();
    expect(member(t), isTrue);
    // 로그인 → 동의 완료 → "보냈어요" — 셋 다 같은 주소
    expect(auth.profileImageUrls, [photo, photo, photo]);
  });
}

/// 프로필 사진 주소가 딸린 제공자 응답(네이버 교환 결과처럼).
final class _WithPhoto implements SocialTokenSource {
  @override
  Future<void> abandonSignup(SocialProvider provider) async {}

  const _WithPhoto(this.photo);

  final String photo;

  @override
  Future<SocialCredential?> obtain(
    SocialProvider provider, {
    bool withdrawal = false,
  }) async =>
      SocialCredential('token-${provider.name}', profileImageUrl: photo);

  @override
  Future<SocialCredential?> obtainSilently(SocialProvider provider) async =>
      null;

  @override
  Future<void> forget(SocialProvider provider, {bool revoke = false}) async {}
}
