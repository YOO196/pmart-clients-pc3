import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart' show initPmartFormatting;

import 'support/app_harness.dart';

/// 화면 전환 애니메이션(사용자 2026-11-21 "주문상세 들어가는 것도, 마이페이지 항목 전부 — 뒤로 가는 것도 한 쌍으로").
/// go_router 의 builder 경로가 전환 없는 페이지로 만들어지던 것을 CupertinoPage(오른쪽에서 밀려 들어옴)로.
void main() {
  setUpAll(initPmartFormatting);

  for (final path in [
    '/orders/O-1',
    '/claims',
    '/me/wishlist',
    '/me/coupons',
    '/reviews',
    '/addresses',
    '/notifications',
    '/support',
    '/me/terms',
    '/cart',
  ]) {
    testWidgets('$path 는 밀려 들어오고, 뒤로 가면 밀려 나간다', (t) async {
      await t.pumpWidget(testApp(const []));
      await t.pumpAndSettle();
      final router = GoRouter.of(t.element(find.byType(Scaffold).first));
      unawaited(router.push(path));
      await t.pump();
      await t.pump(const Duration(milliseconds: 120));
      expect(
        find.byType(CupertinoPageTransition),
        findsWidgets,
        reason: '들어가기',
      );
      await t.pumpAndSettle();
      router.pop();
      await t.pump();
      await t.pump(const Duration(milliseconds: 120));
      expect(find.byType(CupertinoPageTransition), findsWidgets, reason: '뒤로');
      await t.pumpAndSettle();
    });
  }

  testWidgets('하단 탭 전환은 미끄러지지 않는다', (t) async {
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 120));
    expect(find.byType(CupertinoPageTransition), findsNothing);
    await t.pumpAndSettle();
  });
  testWidgets('마이 → 주문내역은 밀려 들어오는 화면, 뒤로 가면 마이', (t) async {
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-orders')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 120));
    expect(find.byType(CupertinoPageTransition), findsWidgets);
    await t.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('my-orders')), findsOneWidget);
  });

  for (final tab in ['카테고리', '찜', '주문내역', '마이페이지']) {
    testWidgets('$tab 탭에서 뒤로 → 홈 탭(앱을 닫지 않음)', (t) async {
      await t.pumpWidget(testApp(const []));
      await t.pumpAndSettle();
      await t.tap(find.text(tab).last);
      await t.pumpAndSettle();
      NavigationBar bar() =>
          t.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar().selectedIndex, isNot(0));
      final handled = await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(handled, isTrue);
      expect(bar().selectedIndex, 0);
    });
  }
}
