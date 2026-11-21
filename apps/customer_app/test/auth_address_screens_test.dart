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
    await t.tap(find.byKey(const ValueKey('address-search')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('f-detail')), '101동');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('address-save')));
    await t.pumpAndSettle();

    expect(find.textContaining('주소를 저장했어요'), findsOneWidget);
    expect(find.textContaining('배달 가능 지역이에요'), findsWidgets);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    // 주소 이름 칸은 레퍼런스(2-7-1)에 없어 뺐다 — 목록은 도로명으로 보인다.
    expect(find.text('서울 송파구 올림픽로 300'), findsOneWidget);
  });

  testWidgets('회원은 로그인 뒤 서버 주소록이 보인다', (t) async {
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
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
    await t.tap(find.text('마이페이지').last);
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
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('login-google')));
    await t.pumpAndSettle();

    expect(find.textContaining('10분 뒤'), findsOneWidget);
    // 레퍼런스 2-3: 동그란 소셜 단추(InkWell)
    final kakao = t.widget<InkWell>(find.byKey(const ValueKey('login-kakao')));
    expect(kakao.onTap, isNull);
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
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();

    // 마이(원래 화면)로 돌아온다.
    expect(find.byKey(const ValueKey('my-login')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-message')), findsNothing);
  });

  testWidgets('재동의(기존 회원)는 바뀐 약관 안내 + 선택 항목(마케팅)은 기본 해제 — 고른 값이 그대로 간다', (
    t,
  ) async {
    final auth = MockAuthRepository(latency: Duration.zero)
      ..reconsentNext = true;
    await t.pumpWidget(testApp(const [], auth: auth));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-naver')));
    await t.pumpAndSettle();

    expect(find.text('약관이 바뀌었어요. 계속 이용하려면 다시 동의해 주세요'), findsOneWidget);
    const marketing = 'MARKETING:2026-11-17';
    expect(find.text('[선택] 마케팅 정보 수신'), findsOneWidget);
    expect(find.byKey(const ValueKey('consent-on-$marketing')), findsNothing);
    // 재동의는 가입 단계 표시가 없다.
    expect(find.byKey(const ValueKey('signup-steps-1')), findsNothing);
    await t.tap(find.byKey(const ValueKey('consent-$marketing')));
    await t.pump();
    // 약관 동의 E안(2026-11-21): 필수를 하나씩 체크해야 단추가 켜진다.
    for (final c in MockAuthRepository.requiredConsents) {
      await t.tap(find.byKey(ValueKey('consent-$c')));
      await t.pump();
    }
    await t.tap(find.byKey(const ValueKey('consent-submit')));
    await t.pumpAndSettle();

    final sent = auth.completions.single.consents;
    expect(sent.firstWhere((d) => d.item == marketing).agreed, isTrue);
    expect(sent.where((d) => d.agreed), hasLength(4));
  });

  testWidgets('필수를 모두 체크해야 [동의하고 계속하기]가 켜지고, 약관 전체 동의는 모두 체크·해제한다', (t) async {
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-naver')));
    await t.pumpAndSettle();

    FilledButton submit() =>
        t.widget<FilledButton>(find.byKey(const ValueKey('consent-submit')));
    // 새 가입: 단계 1/3. 처음엔 아무것도 체크 안 됨 — 단추 꺼짐.
    expect(find.byKey(const ValueKey('signup-steps-1')), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(submit().onPressed, isNull);
    // 전체 동의 → 모두 체크(선택 포함), 다시 누르면 모두 해제.
    await t.ensureVisible(find.byKey(const ValueKey('consent-all')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('consent-all')));
    await t.pump();
    for (final c in [
      ...MockAuthRepository.requiredConsents,
      ...MockAuthRepository.optionalConsents,
    ]) {
      expect(find.byKey(ValueKey('consent-on-$c')), findsOneWidget);
    }
    expect(submit().onPressed, isNotNull);
    await t.tap(find.byKey(const ValueKey('consent-all')));
    await t.pump();
    expect(submit().onPressed, isNull);
    // 필수만 체크 — 단추 켜짐, 전체 동의는 꺼진 채.
    for (final c in MockAuthRepository.requiredConsents) {
      await t.ensureVisible(find.byKey(ValueKey('consent-$c')));
      await t.tap(find.byKey(ValueKey('consent-$c')));
      await t.pump();
    }
    expect(submit().onPressed, isNotNull);
    expect(find.byKey(const ValueKey('consent-all-on')), findsNothing);

    await t.tap(find.byKey(const ValueKey('consent-submit')));
    await t.pumpAndSettle();

    // 새로 가입한 계정은 내 정보(이름)부터 받는다. 저장 전에는 닫히지 않는다.
    // 휴대폰 번호는 여기서 보이기만 하고, "번호 확인"(OCTOMO) 화면에서 넣고 확인한다(customer 0.9.0).
    expect(find.text('내 정보 등록'), findsOneWidget);
    expect(find.byKey(const ValueKey('signup-steps-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('info-later')), findsNothing);
    expect(find.byKey(const ValueKey('info-phone-verify')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('info-save')));
    await t.pumpAndSettle();
    expect(find.text('이름을 입력해 주세요(30자 이내)'), findsOneWidget);

    await t.enterText(find.byKey(const ValueKey('info-name')), ' 김피마 ');
    await t.tap(find.byKey(const ValueKey('info-save')));
    await t.pumpAndSettle();

    // 번호 없이 이름만 저장된다. 보낸 본문에 phone 이 없다(목은 phone 이 오면 서버처럼 거절한다).
    expect(find.byKey(const ValueKey('my-account')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('my-info')),
        matching: find.text('김피마'),
      ),
      findsOneWidget,
    );

    // 마이 → 내 정보: 이름을 바꾸면 그대로 저장된다.
    await t.tap(find.byKey(const ValueKey('my-info')));
    await t.pumpAndSettle();
    // 마이의 내 정보는 가입 단계 표시가 없다.
    expect(find.byKey(const ValueKey('signup-steps-3')), findsNothing);
    // 내 정보 F안: 이름 줄 › → 시트에서 고친다. 서버가 확정하면 시트가 닫히고 줄에 새 이름.
    await t.tap(find.byKey(const ValueKey('info-name-row')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('info-name')), '박피마');
    await t.tap(find.byKey(const ValueKey('info-save')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('info-save')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('info-name-row')),
        matching: find.text('박피마'),
      ),
      findsOneWidget,
    );
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

    await t.enterText(find.byKey(const ValueKey('info-name')), '김피마');
    await t.tap(find.byKey(const ValueKey('info-save')));
    await t.pumpAndSettle();
    expect(find.text('내 정보 저장은 아직 준비 중이에요'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('info-later')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('my-account')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('my-info')),
        matching: find.text('이름을 등록해 주세요'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('새 주소 저장은 저장 결과와 배송 가능 판정을 따로 알린다', (t) async {
    final picker = FakeAddressPicker(road: '제주 제주시 첨단로 1');
    // 입력 칸이 많아 화면을 키운다(목록 지연 생성으로 버튼이 안 만들어지지 않게).
    t.view
      ..physicalSize = const Size(800, 1800)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(testApp(const [], addressPicker: picker));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
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
    // 상세주소가 비어 있으면 [주소 등록]이 꺼져 있다(레퍼런스 2-7-1, 사용자 결정 2026-11-20).
    expect(
      t
          .widget<CommandButton>(find.byKey(const ValueKey('address-save')))
          .onPressed,
      isNull,
    );

    await t.tap(find.byKey(const ValueKey('address-search')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('f-detail')), '1층');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('address-save')));
    await t.pumpAndSettle();

    expect(find.textContaining('주소를 저장했어요'), findsOneWidget);
    expect(find.textContaining('아직 배달하지 않는 지역이에요'), findsWidgets);
  });
}
