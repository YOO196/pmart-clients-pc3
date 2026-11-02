import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/app.dart';
import 'package:customer_app/features/auth/data/mock_auth_repository.dart';
import 'package:customer_app/features/auth/domain/auth.dart';
import 'package:customer_app/features/auth/presentation/auth_controller.dart';

import 'support/app_harness.dart';

/// 앱 사용 중 세션 종료(갱신 거절) 처리 — 백엔드 요청 2026-11-02 세션 만료 §3.
void main() {
  setUpAll(initPmartFormatting);

  Future<ProviderContainer> loginAsMember(WidgetTester t, List<Override> overrides) async {
    await t.pumpWidget(testApp(overrides));
    await t.pumpAndSettle();
    await t.tap(find.text('마이').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    final container = ProviderScope.containerOf(t.element(find.byType(CustomerApp)));
    expect(container.read(sessionProvider), isA<MemberSession>());
    return container;
  }

  /// 목 저장소는 지연 타이머를 쓰므로 위젯 테스트에서는 펌프로 시간을 보내야 끝난다(바로 await 하면 멈춘다).
  Future<void> settle(WidgetTester t, Future<void> work) async {
    unawaited(work);
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    await t.pumpAndSettle();
  }

  testWidgets('세션이 끝나면 조용한 재로그인으로 회원을 이어가고 짧게 알린다', (t) async {
    final source = MockSocialTokenSource();
    final container = await loginAsMember(t, [
      socialTokenSourceProvider.overrideWithValue(source),
    ]);

    await settle(t, container.read(sessionProvider.notifier).expired());

    expect(container.read(sessionProvider), isA<MemberSession>());
    expect(source.silentAttempts, 1);
    expect(find.byKey(const ValueKey('session-renewed')), findsOneWidget);
    expect(find.byKey(const ValueKey('session-expired')), findsNothing);
  });

  testWidgets('조용한 재로그인이 안 되면 비회원으로 바꾸고 "다시 로그인" 안내 → 로그인 화면', (t) async {
    final source = MockSocialTokenSource(silentUnavailable: {SocialProvider.kakao});
    final container = await loginAsMember(t, [
      socialTokenSourceProvider.overrideWithValue(source),
    ]);

    await settle(t, container.read(sessionProvider.notifier).expired());

    expect(container.read(sessionProvider), isA<GuestSession>());
    expect(find.byKey(const ValueKey('session-expired')), findsOneWidget);
    expect(find.text('로그인이 만료됐어요. 다시 로그인해 주세요'), findsOneWidget);

    await t.tap(
      find.descendant(
        of: find.byKey(const ValueKey('session-expired')),
        matching: find.text('로그인'),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-kakao')), findsOneWidget);
  });

  testWidgets('동시에 여러 요청이 만료를 알려도 조용한 재로그인은 한 번만 한다', (t) async {
    final source = MockSocialTokenSource();
    final container = await loginAsMember(t, [
      socialTokenSourceProvider.overrideWithValue(source),
    ]);

    final ctl = container.read(sessionProvider.notifier);
    await settle(t, Future.wait([ctl.expired(), ctl.expired(), ctl.expired()]));

    expect(source.silentAttempts, 1);
    expect(container.read(sessionProvider), isA<MemberSession>());
  });

  testWidgets('비회원일 때 만료 알림이 와도 아무것도 하지 않는다', (t) async {
    final source = MockSocialTokenSource();
    await t.pumpWidget(testApp([socialTokenSourceProvider.overrideWithValue(source)]));
    await t.pumpAndSettle();
    final container = ProviderScope.containerOf(t.element(find.byType(CustomerApp)));

    await settle(t, container.read(sessionProvider.notifier).expired());

    expect(source.silentAttempts, 0);
    expect(find.byKey(const ValueKey('session-expired')), findsNothing);
  });
}
