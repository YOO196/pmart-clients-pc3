import 'dart:convert';

import 'package:dio/dio.dart' show Dio;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/checkout/data/mock_checkout_repository.dart';
import 'package:customer_app/features/checkout/presentation/checkout_controller.dart';
import 'package:customer_app/features/profile/data/consents_repository.dart';
import 'package:customer_app/features/profile/presentation/consents_screens.dart';
import 'package:customer_app/shared/providers.dart' show sourceSystem;

import 'support/app_harness.dart';

/// 로그인해 있는 고객의 재동의(주문 전)·설정 마케팅 동의(customer 0.3.0, 백엔드 알림 2026-11-17 consents §3, CU-1). 목 모드.
void main() {
  setUpAll(initPmartFormatting);
  final now = DateTime.utc(2026, 10, 24, 3);

  late MockConsentsRepository consents;
  late MockCheckoutRepository checkout;
  setUp(() {
    consents = MockConsentsRepository();
    checkout = MockCheckoutRepository(latency: Duration.zero, now: () => now);
  });

  Widget app() => testApp(checkout: checkout, [
    clockProvider.overrideWithValue(() => now),
    consentsRepositoryProvider.overrideWithValue(consents),
    draftPollPolicyProvider.overrideWithValue((
      interval: Duration.zero,
      attempts: 3,
    )),
  ]);

  Future<void> toDeliveryNext(WidgetTester t) async {
    t.view
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    await t.tap(find.text('장바구니').last);
    await t.pumpAndSettle();
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
  }

  testWidgets('필수 동의가 지금 버전이면 재동의 없이 다음 단계', (t) async {
    await toDeliveryNext(t);
    expect(find.byKey(const ValueKey('reconsent-body')), findsNothing);
    expect(find.byKey(const ValueKey('delivery-min-order')), findsOneWidget);
  });

  testWidgets('약관이 바뀐 고객: 재동의 화면 → 필수 모두 체크해야 버튼 → 서버 버전으로 보낸 뒤 다음 단계', (
    t,
  ) async {
    consents.outdated = true;
    await toDeliveryNext(t);
    expect(find.byKey(const ValueKey('reconsent-body')), findsOneWidget);
    // 아래 시트(레퍼런스 13-9): 필수는 줄마다 [보기]만 있고, [전체 동의하고 계속하기] 한 번으로 모두 동의한다.
    final submit = find.byKey(const ValueKey('reconsent-submit'));
    for (final type in [
      ConsentWire.terms,
      ConsentWire.privacy,
      ConsentWire.age14,
    ]) {
      expect(find.byKey(ValueKey('reconsent-$type')), findsOneWidget);
    }
    expect(
      find.byKey(const ValueKey('reconsent-${ConsentWire.location}')),
      findsNothing,
    );
    expect(t.widget<FilledButton>(submit).onPressed, isNotNull);
    await t.tap(submit);
    await t.pumpAndSettle();

    final sent = consents.changes.single.$1;
    expect(
      sent.where((c) => c.type == ConsentWire.terms).single.version,
      '2026-11-17',
    );
    // 선택(마케팅)은 끈 것도 false 로 보낸다.
    expect(
      sent.where((c) => c.type == ConsentWire.marketing).single.agreed,
      isFalse,
    );
    // 위치 약관(현재 위치 기능에서만 필수)은 재동의에서 묻지도 보내지도 않는다.
    expect(sent.where((c) => c.type == ConsentWire.location), isEmpty);
    expect(consents.outdated, isFalse);
    expect(find.byKey(const ValueKey('reconsent-body')), findsNothing);
    expect(find.byKey(const ValueKey('delivery-min-order')), findsOneWidget);
  });

  testWidgets('재동의에서 나가면 다음 단계로 넘어가지 않는다', (t) async {
    consents.outdated = true;
    await toDeliveryNext(t);
    await t.tap(find.byKey(const ValueKey('reconsent-close')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('delivery-min-order')), findsNothing);
    expect(find.byKey(const ValueKey('cart-receive')), findsOneWidget);
  });

  testWidgets('결과를 모르면 같은 키로 한 번 더 보낸다', (t) async {
    consents.outdated = true;
    consents.failNextChange = const UnknownResultFailure();
    await toDeliveryNext(t);
    await t.tap(find.byKey(const ValueKey('reconsent-submit')));
    await t.pumpAndSettle();
    expect(consents.changes, hasLength(2));
    expect(consents.changes[0].$2, consents.changes[1].$2);
  });

  testWidgets('설정: 마케팅 동의 스위치 → 서버가 APPLIED 한 뒤 켜짐', (t) async {
    t.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-notification-settings')));
    await t.pumpAndSettle();

    final tile = find.byKey(const ValueKey('settings-marketing-consent'));
    await t.ensureVisible(tile);
    expect(t.widget<SwitchListTile>(tile).value, isFalse);
    await t.tap(tile);
    await t.pumpAndSettle();
    expect(consents.changes.single.$1.single.agreed, isTrue);
    expect(consents.marketingAgreed, isTrue);
    expect(t.widget<SwitchListTile>(tile).value, isTrue);
  });

  test('API: POST /me/consent-changes 본문·멱등 키·출처 헤더', () async {
    final adapter = FakeAdapter(
      (_, _) async =>
          const FakeReply(200, body: {'status': 'APPLIED', 'requestId': 'r-1'}),
    );
    final Dio dio = createPmartDio(
      baseUrl: 'http://test.invalid/api/v1',
      sourceSystem: sourceSystem,
      tokens: TokenStore(MemoryKeyValueStore()),
      refresher: (_) async => null,
      adapter: adapter,
      delay: (_) async {},
    );
    final key = IdempotencyKey.generate();
    final status = await ApiConsentsRepository(dio).change([
      const ConsentChange(ConsentWire.marketing, '2026-11-17', agreed: true),
    ], key: key);
    final sent = adapter.requests.single;
    expect(sent.path, endsWith('/me/consent-changes'));
    expect(sent.headers['Idempotency-Key'], key.value);
    expect(sent.headers['X-Source-System'], sourceSystem);
    expect(jsonDecode(sent.data as String), {
      'changes': [
        {'consentType': 'MARKETING', 'version': '2026-11-17', 'agreed': true},
      ],
    });
    expect(status, CommandStatus.applied);
  });
}
