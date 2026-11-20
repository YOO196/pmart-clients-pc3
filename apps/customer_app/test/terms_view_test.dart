import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/auth/data/mock_auth_repository.dart';

import 'support/app_harness.dart';

/// 약관을 볼 수 있게(사용자 2026-11-20 "왜 약관 못 봐, 볼 수 있게 만들어야지").
void main() {
  setUpAll(initPmartFormatting);

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> big(WidgetTester t) async {
    t.view
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  testWidgets('로그인 동의 화면: 항목마다 [보기] → 그 버전의 본문, 뒤로 가면 동의 화면 그대로', (t) async {
    await big(t);
    await t.pumpWidget(
      testApp(const [], auth: MockAuthRepository(latency: Duration.zero)),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(key('my-login'));
    await t.pumpAndSettle();
    // 목: 네이버는 새 가입이라 필수 동의 화면이 나온다.
    await t.tap(key('login-naver'));
    await t.pumpAndSettle();
    expect(key('consent-submit'), findsOneWidget);
    // 고른 선택 항목은 본문을 보고 와도 남는다.
    await t.tap(key('consent-${MockAuthRepository.optionalConsents.first}'));
    await t.pump();

    for (final type in ['TERMS_OF_SERVICE', 'PRIVACY_POLICY', 'MARKETING']) {
      expect(key('consent-view-$type'), findsOneWidget, reason: type);
    }
    await t.tap(key('consent-view-TERMS_OF_SERVICE'));
    await t.pumpAndSettle();
    expect(key('consent-term'), findsOneWidget);
    expect(key('consent-term-body'), findsOneWidget);

    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(key('consent-term'), findsNothing);
    expect(key('consent-submit'), findsOneWidget);
    final marketing = t.widget<Checkbox>(
      key('consent-${MockAuthRepository.optionalConsents.first}'),
    );
    expect(marketing.value, isTrue);
  });

  testWidgets('마이 → 약관 및 정책: 비회원도 목록·본문을 보고, 뒤로 가면 목록', (t) async {
    await big(t);
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.ensureVisible(key('my-terms'));
    await t.tap(key('my-terms'));
    await t.pumpAndSettle();

    expect(key('terms-list'), findsOneWidget);
    expect(find.text('이용약관'), findsOneWidget);
    expect(find.text('위치기반서비스 이용약관'), findsOneWidget);

    await t.tap(key('terms-TERMS_OF_SERVICE'));
    await t.pumpAndSettle();
    expect(key('consent-term-body'), findsOneWidget);

    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(key('terms-list'), findsOneWidget);
  });

  testWidgets('처음 실행 환영 화면: 마케팅 수신도 > 로 본문을 연다', (t) async {
    await big(t);
    await t.pumpWidget(testApp(const [], startGate: true));
    await t.pumpAndSettle();
    await t.tap(key('start-agree-marketing-open'));
    await t.pumpAndSettle();
    expect(key('consent-term-body'), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(key('start-welcome'), findsOneWidget);
  });
}
