import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/auth/data/mock_auth_repository.dart';
import 'package:customer_app/features/auth/domain/auth.dart';
import 'package:customer_app/features/auth/presentation/auth_controller.dart';
import 'package:customer_app/features/profile/data/mock_profile_repository.dart';

import 'support/app_harness.dart';

void main() {
  setUpAll(initPmartFormatting);

  testWidgets('비회원도 로그인 없이 배송지를 등록하고 쇼핑 주소로 쓴다', (t) async {
    // 입력 칸이 많아 화면을 키운다(목록 지연 생성으로 버튼이 안 만들어지지 않게).
    t.view
      ..physicalSize = const Size(800, 1800)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    expect(find.text('주소를 설정해 주세요'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('home-address')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('go-login')), findsNothing);

    await t.tap(find.byKey(const ValueKey('address-add')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('f-label')), '우리집');
    await t.enterText(find.byKey(const ValueKey('f-road')), '서울 송파구 올림픽로 300');
    await t.enterText(find.byKey(const ValueKey('f-detail')), '101동');
    await t.enterText(find.byKey(const ValueKey('f-name')), '김피마');
    await t.enterText(find.byKey(const ValueKey('f-phone')), '01000000000');
    await t.tap(find.byKey(const ValueKey('address-save')));
    await t.pumpAndSettle();

    expect(find.textContaining('주소를 저장했어요'), findsOneWidget);
    expect(find.textContaining('배달 가능 지역이에요'), findsWidgets);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.text('우리집'), findsOneWidget);
  });

  testWidgets('회원은 로그인 뒤 서버 주소록이 보인다', (t) async {
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await t.tap(find.text('마이').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    await t.tap(find.text('홈').last);
    await t.pumpAndSettle();
    expect(find.text('집'), findsOneWidget);
  });

  testWidgets('Android 로그인 화면에는 애플 로그인 버튼이 없다(ADR-0002)', (t) async {
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await t.tap(find.text('마이').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('login-apple')), findsNothing);
    expect(find.text('Apple로 계속하기'), findsNothing);
    for (final p in ['kakao', 'naver', 'google']) {
      expect(find.byKey(ValueKey('login-$p')), findsOneWidget);
    }
  });

  testWidgets('로그인 제한 중에는 버튼이 막히고 서버의 남은 시간을 보인다', (t) async {
    await t.pumpWidget(
      testApp(
        const [],
        auth: MockAuthRepository(
          latency: Duration.zero,
          restricted: {SocialProvider.google},
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('마이').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('login-google')));
    await t.pumpAndSettle();

    expect(find.textContaining('10분 뒤'), findsOneWidget);
    final kakao = t.widget<FilledButton>(
      find.byKey(const ValueKey('login-kakao')),
    );
    expect(kakao.onPressed, isNull);
  });

  testWidgets('제공자 화면에서 취소하면 원래 화면으로 돌아간다', (t) async {
    await t.pumpWidget(
      testApp([
        socialTokenSourceProvider.overrideWithValue(
          MockSocialTokenSource(cancelled: {SocialProvider.kakao}),
        ),
      ]),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('마이').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();

    // 마이(원래 화면)로 돌아온다.
    expect(find.byKey(const ValueKey('my-login')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-message')), findsNothing);
  });

  testWidgets('필수 동의를 모두 골라야 시작할 수 있다', (t) async {
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await t.tap(find.text('마이').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-naver')));
    await t.pumpAndSettle();

    FilledButton submit() =>
        t.widget<FilledButton>(find.byKey(const ValueKey('consent-submit')));
    expect(submit().onPressed, isNull);
    for (final c in MockAuthRepository.requiredConsents) {
      await t.tap(find.byKey(ValueKey('consent-$c')));
      await t.pump();
    }
    expect(submit().onPressed, isNotNull);

    await t.tap(find.byKey(const ValueKey('consent-submit')));
    await t.pumpAndSettle();

    // 새로 가입한 계정은 내 정보(이름·휴대폰 번호)부터 받는다. 저장 전에는 닫히지 않는다.
    expect(find.text('내 정보 등록'), findsOneWidget);
    expect(find.byKey(const ValueKey('info-later')), findsNothing);
    await t.enterText(find.byKey(const ValueKey('info-phone')), '0101234');
    await t.tap(find.byKey(const ValueKey('info-save')));
    await t.pumpAndSettle();
    expect(find.text('이름을 입력해 주세요(30자 이내)'), findsOneWidget);
    expect(find.textContaining('휴대폰 번호를 확인해 주세요'), findsOneWidget);

    await t.enterText(find.byKey(const ValueKey('info-name')), ' 김피마 ');
    await t.enterText(
      find.byKey(const ValueKey('info-phone')),
      '010-1234-5678',
    );
    await t.tap(find.byKey(const ValueKey('info-save')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('my-account')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('my-info')),
        matching: find.text('김피마 · 010-****-5678'),
      ),
      findsOneWidget,
    );

    // 마이 → 내 정보: 이름만 바꾸면 번호는 비워 둔 채 저장된다.
    await t.tap(find.byKey(const ValueKey('my-info')));
    await t.pumpAndSettle();
    expect(find.text('지금 번호 010-****-5678. 바꿀 때만 입력해 주세요'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('info-name')), '박피마');
    await t.tap(find.byKey(const ValueKey('info-save')));
    await t.pumpAndSettle();
    expect(find.text('박피마 · 010-****-5678'), findsOneWidget);
  });

  testWidgets('가입 직후 내 정보 저장을 서버가 아직 제공하지 않으면(501) 나중에 하기로 가입을 마친다', (t) async {
    await t.pumpWidget(
      testApp(
        const [],
        profile: MockProfileRepository(latency: Duration.zero)
          ..unsupported = true,
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('마이').last);
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

    await t.enterText(find.byKey(const ValueKey('info-name')), '김피마');
    await t.enterText(find.byKey(const ValueKey('info-phone')), '01012345678');
    await t.tap(find.byKey(const ValueKey('info-save')));
    await t.pumpAndSettle();
    expect(find.text('내 정보 저장은 아직 준비 중이에요'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('info-later')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('my-account')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('my-info')),
        matching: find.text('이름·휴대폰 번호를 등록해 주세요'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('새 주소 저장은 저장 결과와 배송 가능 판정을 따로 알린다', (t) async {
    // 입력 칸이 많아 화면을 키운다(목록 지연 생성으로 버튼이 안 만들어지지 않게).
    t.view
      ..physicalSize = const Size(800, 1800)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await t.tap(find.text('마이').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    await t.tap(find.text('홈').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('home-address')));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('address-add')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('address-save')));
    await t.pumpAndSettle();
    expect(find.text('입력해 주세요'), findsWidgets);

    await t.enterText(find.byKey(const ValueKey('f-road')), '제주 제주시 첨단로 1');
    await t.enterText(find.byKey(const ValueKey('f-detail')), '1층');
    await t.enterText(find.byKey(const ValueKey('f-name')), '김피마');
    await t.enterText(find.byKey(const ValueKey('f-phone')), '010-0000-0000');
    await t.tap(find.byKey(const ValueKey('address-save')));
    await t.pumpAndSettle();

    expect(find.textContaining('주소를 저장했어요'), findsOneWidget);
    expect(find.textContaining('아직 배달하지 않는 지역이에요'), findsWidgets);
  });
}
