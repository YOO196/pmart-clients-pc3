// Google 프로필(이름·이메일·사진) 표시 — 백엔드 안내 2026-10-31, ADR-0024.
// 서버가 로그인마다 최신으로 바꾸고 앱은 표시만 한다. 없는 값은 "정보 없음"/기본 아바타(다른 값으로 채우지 않는다).
import 'dart:typed_data';

import 'package:customer_app/features/orders/presentation/my_screen.dart';
import 'package:customer_app/features/profile/data/mock_profile_repository.dart';
import 'package:customer_app/features/profile/data/profile_repository.dart';
import 'package:customer_app/features/profile/domain/profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  await t.tap(find.text('마이').last);
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
          matching: find.text('홍길동 · hong@example.com'),
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
      final card = find.byKey(const ValueKey('info-google'));
      expect(
        find.descendant(of: card, matching: find.text('홍길동')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text('hong@example.com (확인된 이메일)'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.byKey(const ValueKey('profile-avatar-image')),
        ),
        findsOneWidget,
      );
      // 같은 v 는 다시 받지 않는다(캐시).
      expect(profile.imageReads, 1);
      // 이름 입력 칸은 nickname(내 정보 이름)이고 Google 이름으로 덮지 않는다.
      expect(
        t
            .widget<TextFormField>(find.byKey(const ValueKey('info-name')))
            .controller
            ?.text,
        '김피마',
      );
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
      final card = find.byKey(const ValueKey('info-google'));
      expect(
        find.descendant(of: card, matching: find.text('이름 정보 없음')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('이메일 정보 없음')),
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
          of: find.byKey(const ValueKey('info-google')),
          matching: find.text('hong@example.com'),
        ),
        findsOneWidget,
      );
    });
  });
}
