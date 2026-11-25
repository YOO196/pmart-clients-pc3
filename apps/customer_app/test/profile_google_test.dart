// Google 프로필(이름·이메일·사진) 표시 — 백엔드 안내 2026-10-31, ADR-0024.
// 서버가 로그인마다 최신으로 바꾸고 앱은 표시만 한다. 없는 값은 "정보 없음"/기본 아바타(다른 값으로 채우지 않는다).
import 'dart:typed_data';

import 'package:customer_app/features/orders/presentation/my_screen.dart';
import 'package:customer_app/features/profile/data/mock_profile_repository.dart';
import 'package:customer_app/features/profile/data/profile_repository.dart';
import 'package:customer_app/features/profile/domain/profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/features/auth/domain/auth.dart'
    show SocialProvider;
import 'package:pmart_api_customer/pmart_api_customer.dart' as api;

import 'support/app_harness.dart';

// 1×1 PNG(투명). MemoryImage 로 그릴 수 있는 최소 바이트.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
]);

Future<void> _loginKakao(WidgetTester t) async {
  await t.tap(find.text('마이페이지').last);
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('my-login')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('login-kakao')));
  await t.pumpAndSettle();
  // 프로필이 온 뒤 만들어진 사진 조회(목 Timer(0))는 다음 pump 에서 끝난다.
  await t.pumpAndSettle();
}

void main() {
  group('계약 매핑', () {
    test(
      'Profile 의 name·email·emailVerified·profileImageUrl 을 읽고 빈 문자열은 없음으로 둔다',
      () {
        final p = profileFromContract(
          api.Profile(
            accountId: 'acct-1',
            version: 3,
            nickname: '김피마',
            name: '홍길동',
            email: 'hong@example.com',
            emailVerified: true,
            profileImageUrl: '/api/v1/me/profile-image?v=abc',
          ),
        );
        expect(p.name, '홍길동');
        expect(p.email, 'hong@example.com');
        expect(p.emailVerified, isTrue);
        expect(p.profileImageUrl, '/api/v1/me/profile-image?v=abc');
        expect(p.hasProfileImage, isTrue);

        final empty = profileFromContract(
          api.Profile(
            accountId: 'acct-2',
            version: 1,
            name: '',
            email: ' ',
            profileImageUrl: '',
          ),
        );
        expect(empty.name, isNull);
        expect(empty.email, isNull);
        expect(empty.emailVerified, isNull);
        expect(empty.profileImageUrl, isNull);
        expect(empty.hasProfileImage, isFalse);
      },
    );

    test('계정 줄 문구는 이름 · 이메일, 둘 다 없으면 null(제공자 SDK 계정 표시로 대신)', () {
      const base = Profile(accountId: 'a', version: 1);
      expect(providerAccountText(base), isNull);
      expect(providerAccountText(null), isNull);
      expect(
        providerAccountText(
          const Profile(
            accountId: 'a',
            version: 1,
            name: '홍길동',
            email: 'h@x.io',
          ),
        ),
        '홍길동 · h@x.io',
      );
      expect(
        providerAccountText(
          const Profile(accountId: 'a', version: 1, email: 'h@x.io'),
        ),
        'h@x.io',
      );
    });
  });

  group('화면', () {
    testWidgets('마이 계정 줄과 내 정보에 Google 이름·이메일·사진이 보인다(사진은 인증 조회 바이트로)', (
      t,
    ) async {
      final profile = MockProfileRepository(latency: Duration.zero)
        ..nickname = '김피마'
        ..name = '홍길동'
        ..email = 'hong@example.com'
        ..emailVerified = true
        ..profileImageUrl = '/api/v1/me/profile-image?v=abc'
        ..imageBytes = _png;
      await t.pumpWidget(testApp(const [], profile: profile));
      await t.pumpAndSettle();
      await _loginKakao(t);

      final account = find.byKey(const ValueKey('my-account'));
      expect(
        find.descendant(
          of: account,
          matching: find.text('hong@example.com'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: account,
          matching: find.byKey(const ValueKey('profile-avatar-image')),
        ),
        findsOneWidget,
      );
      expect(profile.imageReads, 1);

      await t.tap(find.byKey(const ValueKey('my-info')));
      await t.pumpAndSettle();
      // 내 정보 F안(2026-11-21): 가운데 로그인 계정 사진, 이메일 줄(읽기만), 로그인 계정 카드.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('info-avatar')),
          matching: find.byKey(const ValueKey('profile-avatar-image')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('info-email-row')),
          matching: find.text('hong@example.com'),
        ),
        findsOneWidget,
      );
      // 같은 v 는 다시 받지 않는다(캐시).
      expect(profile.imageReads, 1);
      // 이름 줄은 nickname(내 정보 이름)이고 Google 이름으로 덮지 않는다.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('info-name-row')),
          matching: find.text('김피마'),
        ),
        findsOneWidget,
      );
      // 이름 줄은 로그인 계정 이름(서버 name, 보기만), 닉네임 줄은 앱 이름(2026-11-25 나눔).
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('info-real-name-row')),
          matching: find.text('홍길동'),
        ),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('info-name-row')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextFormField>(find.byKey(const ValueKey('info-name')))
            .controller
            ?.text,
        '김피마',
      );
    });

    testWidgets(
      '가입 방식은 서버 프로필(socialProvider) 먼저 — 이메일 옆 배지·"○○로 로그인"·내 정보 배지',
      (t) async {
        // 백엔드 요청 2026-11-25: 네이버 계정인데 네이버가 준 연락처 이메일이 gmail 이라 구글처럼 보였다.
        // 세션 제공자(이 시험은 카카오로 로그인)보다 서버가 아는 가입 제공자를 먼저 쓴다.
        final profile = MockProfileRepository(latency: Duration.zero)
          ..name = '홍길동'
          ..email = 'hong@gmail.com'
          ..socialProvider = SocialProvider.naver;
        await t.pumpWidget(testApp(const [], profile: profile));
        await t.pumpAndSettle();
        await _loginKakao(t);

        final account = find.byKey(const ValueKey('my-account'));
        expect(
          find.descendant(
            of: account,
            // 앱 이름이 없어 위 줄이 계정 이름, 아래 줄은 이메일만(이름 두 번 안 보이게).
            matching: find.text('hong@gmail.com'),
          ),
          findsOneWidget,
        );
        final badge = find.byKey(const ValueKey('my-provider-badge'));
        expect(
          find.descendant(of: badge, matching: find.text('네이버')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: account, matching: find.text('네이버로 로그인했어요')),
          findsOneWidget,
        );

        await t.tap(find.byKey(const ValueKey('my-info')));
        await t.pumpAndSettle();
        expect(
          t
              .widget<Text>(find.byKey(const ValueKey('info-login-provider')))
              .data,
          '네이버',
        );
      },
    );

    testWidgets('가입 직후 서버가 이름·이메일을 늦게 넣으면(약 1초 뒤) 앱이 조금 뒤 다시 읽어 보인다(BR-103)', (
      t,
    ) async {
      final profile = MockProfileRepository(latency: Duration.zero)
        ..socialProvider = SocialProvider.naver;
      await t.pumpWidget(
        testApp(
          const [],
          profile: profile,
          profileRefreshDelays: const [Duration(seconds: 2)],
        ),
      );
      await t.pumpAndSettle();
      await _loginKakao(t);
      expect(find.textContaining('hong@naver.com'), findsNothing);
      // 서버 사건 반영 뒤
      profile
        ..name = '홍길동'
        ..email = 'hong@naver.com';
      await t.pump(const Duration(seconds: 2));
      await t.pumpAndSettle();
      expect(find.text('hong@naver.com'), findsOneWidget);
      expect(find.textContaining('홍길동'), findsOneWidget);
    });

    testWidgets('Google 값이 없으면 기본 아바타·"정보 없음"으로 두고, 계정 줄은 제공자 SDK 계정 표시를 쓴다', (
      t,
    ) async {
      final profile = MockProfileRepository(latency: Duration.zero)
        ..nickname = '김피마';
      await t.pumpWidget(testApp(const [], profile: profile));
      await t.pumpAndSettle();
      await _loginKakao(t);

      final account = find.byKey(const ValueKey('my-account'));
      expect(
        find.descendant(
          of: account,
          matching: find.text('mock-kakao@pmart.invalid'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: account,
          matching: find.byKey(const ValueKey('profile-avatar-default')),
        ),
        findsOneWidget,
      );
      expect(profile.imageReads, 0);

      await t.tap(find.byKey(const ValueKey('my-info')));
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('info-email-row')),
          matching: find.text('이메일 정보 없음'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('info-avatar')),
          matching: find.byKey(const ValueKey('profile-avatar-default')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('info-google')),
          matching: find.text('카카오'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('사진 주소는 있는데 사본이 아직 없으면(404) 기본 아바타로 둔다', (t) async {
      final profile = MockProfileRepository(latency: Duration.zero)
        ..name = '홍길동'
        ..email = 'hong@example.com'
        ..emailVerified = false
        ..profileImageUrl = '/api/v1/me/profile-image?v=abc';
      await t.pumpWidget(testApp(const [], profile: profile));
      await t.pumpAndSettle();
      await _loginKakao(t);

      final account = find.byKey(const ValueKey('my-account'));
      expect(
        find.descendant(
          of: account,
          matching: find.byKey(const ValueKey('profile-avatar-default')),
        ),
        findsOneWidget,
      );
      expect(profile.imageReads, 1);

      await t.tap(find.byKey(const ValueKey('my-info')));
      await t.pumpAndSettle();
      // 확인되지 않은 이메일은 꼬리표 없이 이메일만
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('info-email-row')),
          matching: find.text('hong@example.com'),
        ),
        findsOneWidget,
      );
    });
  });
}
