import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/auth/data/mock_auth_repository.dart';
import 'package:customer_app/features/auth/domain/auth.dart';
import 'package:customer_app/features/auth/presentation/auth_controller.dart';

import 'support/app_harness.dart';

void main() {
  setUpAll(initPmartFormatting);

  testWidgets('비회원이 주소를 누르면 로그인 안내 → 로그인 뒤 주소록이 보인다', (t) async {
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    expect(find.text('주소를 설정해 주세요'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('home-address')));
    await t.pumpAndSettle();
    expect(find.text('주소를 저장하려면 로그인이 필요해요'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('go-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('address-addr-1')), findsOneWidget);
    expect(find.textContaining('배달 가능 지역이에요'), findsOneWidget);

    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.text('집'), findsOneWidget);
  });

  testWidgets('로그인 제한 중에는 버튼이 막히고 서버의 남은 시간을 보인다', (t) async {
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('home-address')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('go-login')));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('login-apple')));
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
    await t.tap(find.byKey(const ValueKey('home-address')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('go-login')));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();

    expect(find.text('주소를 저장하려면 로그인이 필요해요'), findsOneWidget);
    expect(find.byKey(const ValueKey('login-message')), findsNothing);
  });

  testWidgets('필수 동의를 모두 골라야 시작할 수 있다', (t) async {
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('home-address')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('go-login')));
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
    expect(find.byKey(const ValueKey('address-addr-1')), findsOneWidget);
  });

  testWidgets('새 주소 저장은 저장 결과와 배송 가능 판정을 따로 알린다', (t) async {
    // 입력 칸이 많아 화면을 키운다(목록 지연 생성으로 버튼이 안 만들어지지 않게).
    t.view
      ..physicalSize = const Size(800, 1800)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('home-address')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('go-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
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
