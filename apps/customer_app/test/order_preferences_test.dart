import 'package:dio/dio.dart' show Dio, DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/checkout/data/mock_checkout_repository.dart';
import 'package:customer_app/features/checkout/data/order_preferences_repository.dart';
import 'package:customer_app/features/checkout/domain/checkout.dart';
import 'package:customer_app/features/checkout/presentation/checkout_controller.dart';
import 'package:customer_app/shared/providers.dart' show sourceSystem;

import 'support/app_harness.dart';

/// 품절 처리 "다음에도 적용"(customer 0.4.0 `/me/order-preferences`, 백엔드 알림 2026-11-18 gap-a §6). 목 모드.
void main() {
  setUpAll(initPmartFormatting);
  final now = DateTime.utc(2026, 10, 24, 3);

  late MockOrderPreferencesRepository prefs;
  late MockCheckoutRepository checkout;
  setUp(() {
    prefs = MockOrderPreferencesRepository();
    checkout = MockCheckoutRepository(latency: Duration.zero, now: () => now);
  });

  bool remembered(WidgetTester t) =>
      t
          .widget<CheckboxListTile>(find.byKey(const ValueKey('oos-remember')))
          .value ==
      true;

  OutOfStockPreference chosen(WidgetTester t) => t
      .widget<RadioGroup<OutOfStockPreference>>(
        find.byType(RadioGroup<OutOfStockPreference>),
      )
      .groupValue!;

  // 사용자 결정(2026-11-20): 수령방법은 장바구니에서, 품절 시 요청은 주문서의 시트에서 고른다.
  Future<void> toOosSheet(WidgetTester t) async {
    await t.pumpWidget(
      testApp(checkout: checkout, [
        clockProvider.overrideWithValue(() => now),
        orderPreferencesRepositoryProvider.overrideWithValue(prefs),
        draftPollPolicyProvider.overrideWithValue((
          interval: Duration.zero,
          attempts: 3,
        )),
      ]),
    );
    t.view
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpAndSettle();
    await t.tap(find.text('장바구니').last);
    await t.pumpAndSettle();
    // 최소 주문 금액을 넘긴다(목 장바구니 기본은 미달).
    for (var i = 0; i < 3; i++) {
      await t.tap(find.byKey(const ValueKey('cart-inc-ci-1')));
      await t.pumpAndSettle();
    }
    await t.tap(find.byKey(const ValueKey('cart-order')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('mode-single')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('mode-single')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('cart-order')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('change-oos')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('change-oos')));
    await t.pumpAndSettle();
  }

  Future<void> done(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey('oos-done')));
    await t.pumpAndSettle();
  }

  testWidgets('저장된 값이 없으면 앱 기본(품절만 취소)·체크 꺼짐, 저장하지 않는다', (t) async {
    await toOosSheet(t);
    expect(chosen(t), OutOfStockPreference.cancelOutOfStockOnly);
    expect(remembered(t), isFalse);
    await done(t);
    expect(prefs.saves, isEmpty);
  });

  testWidgets('저장된 값(전체 취소)을 기본으로 고르고 체크도 켠다', (t) async {
    prefs.stored = OutOfStockPreference.cancelAll;
    prefs.version = 3;
    await toOosSheet(t);
    expect(chosen(t), OutOfStockPreference.cancelAll);
    expect(remembered(t), isTrue);
  });

  testWidgets('"다음에도 적용"을 켜고 완료하면 고른 값을 저장한다(멱등 키)', (t) async {
    await toOosSheet(t);
    await t.tap(find.byKey(const ValueKey('oos-sheet-all')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('oos-remember')));
    await t.pump();
    await done(t);
    expect(prefs.saves.single.$1, OutOfStockPreference.cancelAll);
    expect(prefs.stored, OutOfStockPreference.cancelAll);
  });

  testWidgets('저장 결과를 모르면 같은 키로 한 번 더, 저장 실패는 주문을 막지 않고 알린다', (t) async {
    await toOosSheet(t);
    prefs.failNextSave = const UnknownResultFailure();
    await t.tap(find.byKey(const ValueKey('oos-remember')));
    await t.pump();
    await done(t);
    expect(prefs.saves, hasLength(2));
    expect(prefs.saves[0].$2, prefs.saves[1].$2);
  });

  testWidgets('저장 실패(연결 오류)는 알리고 주문서는 그대로 쓸 수 있다', (t) async {
    await toOosSheet(t);
    prefs.failNextSave = const NetworkFailure(DioExceptionType.connectionError);
    await t.tap(find.byKey(const ValueKey('oos-remember')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('oos-done')));
    await t.pump();
    expect(find.byKey(const ValueKey('oos-remember-failed')), findsOneWidget);
    await t.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '주문하기'), findsOneWidget);
  });
  test('API: GET·PUT /me/order-preferences, PUT 에 멱등 키·출처 헤더', () async {
    final adapter = FakeAdapter((o, _) async {
      if (o.method == 'GET') {
        return const FakeReply(
          200,
          body: {'outOfStockPreference': null, 'version': 0},
        );
      }
      return const FakeReply(
        200,
        body: {'outOfStockPreference': 'CANCEL_ALL', 'version': 1},
      );
    });
    final Dio dio = createPmartDio(
      baseUrl: 'http://test.invalid/api/v1',
      sourceSystem: sourceSystem,
      tokens: TokenStore(MemoryKeyValueStore()),
      refresher: (_) async => null,
      adapter: adapter,
      delay: (_) async {},
    );
    final repo = ApiOrderPreferencesRepository(dio);
    final none = await repo.get();
    expect(none.outOfStock, isNull);
    final key = IdempotencyKey.generate();
    final saved = await repo.save(OutOfStockPreference.cancelAll, key: key);
    expect(saved.outOfStock, OutOfStockPreference.cancelAll);
    final put = adapter.requests.last;
    expect(put.method, 'PUT');
    expect(put.path, endsWith('/me/order-preferences'));
    expect(put.headers['Idempotency-Key'], key.value);
    expect(put.headers['X-Source-System'], sourceSystem);
  });
}
