import 'dart:async';

import 'package:dio/dio.dart' show Dio;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/app.dart';
import 'package:customer_app/features/auth/domain/auth.dart';
import 'package:customer_app/features/auth/presentation/auth_controller.dart';
import 'package:customer_app/features/notifications/presentation/notifications_screens.dart';
import 'package:customer_app/features/push/data/push_source.dart';
import 'package:customer_app/features/push/data/push_tokens_repository.dart';
import 'package:customer_app/features/push/domain/push_route.dart';
import 'package:customer_app/features/push/presentation/push_controller.dart';
import 'package:customer_app/features/orders/presentation/orders_screens.dart'
    show OrderDetailScreen;
import 'package:customer_app/shared/providers.dart';

import 'package:customer_app/features/start/presentation/start_controller.dart'
    show StartStep, startStepProvider;

import 'support/app_harness.dart';

/// 단말 쪽 푸시를 흉내 낸다(Firebase 없음).
final class FakePushSource implements PushSource {
  FakePushSource({this.available = true, this.permission = true});

  bool available;
  bool permission;
  String? current = 'tok-1';
  int permissionAsks = 0;
  int deletes = 0;
  final refreshes = StreamController<String>.broadcast();
  final opens = StreamController<Map<String, String>>.broadcast();
  final receives = StreamController<void>.broadcast();

  @override
  Future<bool> ready() async => available;

  @override
  Future<bool> requestPermission() async {
    permissionAsks++;
    return permission;
  }

  @override
  Future<String?> token() async => current;

  @override
  Stream<String> get tokenRefreshes => refreshes.stream;

  @override
  Future<void> deleteToken() async {
    deletes++;
  }

  @override
  Stream<Map<String, String>> get opened => opens.stream;

  @override
  Stream<void> get received => receives.stream;
}

/// 휴대폰 푸시(FCM) 토큰 등록 — notification 0.3.0 `/me/push-tokens`(BR-09). 실제 푸시 수신은 시험하지 않는다.
void main() {
  setUpAll(initPmartFormatting);

  List<Override> pushOverrides(
    FakePushSource source,
    MockPushTokensRepository repo,
  ) => [
    pushSourceProvider.overrideWithValue(source),
    pushTokensRepositoryProvider.overrideWithValue(repo),
    // 앱(main.dart)과 같게: 로그아웃 직전 서버에서 이 단말을 지운다
    beforeSignOutProvider.overrideWith(
      (ref) =>
          () => ref
              .read(pushRegistrationProvider.notifier)
              .unregisterBeforeSignOut(),
    ),
  ];

  Future<ProviderContainer> loginAsMember(
    WidgetTester t,
    List<Override> overrides,
  ) async {
    await t.pumpWidget(testApp(overrides));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    final container = ProviderScope.containerOf(
      t.element(find.byType(CustomerApp)),
    );
    expect(container.read(sessionProvider), isA<MemberSession>());
    return container;
  }

  testWidgets('비회원은 권한도 묻지 않고 등록하지 않는다 — 로그인하면 권한을 묻고 토큰을 서버에 등록', (t) async {
    final source = FakePushSource();
    final repo = MockPushTokensRepository();
    await t.pumpWidget(testApp(pushOverrides(source, repo)));
    await t.pumpAndSettle();
    expect(source.permissionAsks, 0);
    expect(repo.calls, isEmpty);

    final container = await loginAsMember(t, pushOverrides(source, repo));
    expect(source.permissionAsks, 1);
    expect(repo.registered, 'tok-1');
    expect(container.read(pushRegistrationProvider), PushStatus.registered);
  });

  testWidgets('토큰이 바뀌면 다시 등록한다', (t) async {
    final source = FakePushSource();
    final repo = MockPushTokensRepository();
    await loginAsMember(t, pushOverrides(source, repo));

    source.refreshes.add('tok-2');
    await t.pumpAndSettle();

    expect(repo.registered, 'tok-2');
    expect(repo.calls, ['register', 'register']);
  });

  testWidgets('알림 권한을 허용하지 않으면 등록하지 않는다', (t) async {
    final source = FakePushSource(permission: false);
    final repo = MockPushTokensRepository();
    final container = await loginAsMember(t, pushOverrides(source, repo));

    expect(repo.calls, isEmpty);
    expect(container.read(pushRegistrationProvider), PushStatus.denied);
  });

  testWidgets('푸시를 쓸 수 없는 빌드(설정 파일 없음 등)는 권한을 묻지 않고 그냥 간다', (t) async {
    final source = FakePushSource(available: false);
    final repo = MockPushTokensRepository();
    final container = await loginAsMember(t, pushOverrides(source, repo));

    expect(source.permissionAsks, 0);
    expect(repo.calls, isEmpty);
    expect(container.read(pushRegistrationProvider), PushStatus.unavailable);
  });

  testWidgets('등록 결과를 모르면 같은 요청을 한 번 더 보내고, 거절이면 실패로 둔다(화면은 막지 않음)', (t) async {
    final source = FakePushSource();
    final repo = MockPushTokensRepository()
      ..failNextRegister = const UnknownResultFailure(requestId: 'k');
    final container = await loginAsMember(t, pushOverrides(source, repo));
    expect(repo.calls, ['register', 'register']);
    expect(container.read(pushRegistrationProvider), PushStatus.registered);

    repo.failNextRegister = const ProblemFailure(
      Problem(status: 422, code: 'CONFIG_REQUIRED'),
    );
    source.refreshes.add('tok-3');
    await t.pumpAndSettle();
    expect(container.read(pushRegistrationProvider), PushStatus.failed);
    expect(repo.registered, 'tok-1');
  });

  testWidgets('로그아웃: 회원 토큰을 지우기 전에 서버에서 단말을 지우고, 단말 토큰도 버린다', (t) async {
    final source = FakePushSource();
    final repo = MockPushTokensRepository();
    final container = await loginAsMember(t, pushOverrides(source, repo));
    final tokens = container.read(tokenStoreProvider);
    expect(await tokens.readRefreshToken(), isNotNull);

    await container.read(sessionProvider.notifier).signOut();
    await t.pumpAndSettle();

    expect(repo.calls.last, 'unregister');
    expect(repo.registered, isNull);
    expect(source.deletes, 1);
    expect(await tokens.readRefreshToken(), isNull);
    expect(container.read(sessionProvider), isA<GuestSession>());
    expect(container.read(pushRegistrationProvider), PushStatus.off);
  });

  testWidgets('푸시를 누르면 목적지 화면(주문 상세)이 열린다', (t) async {
    final source = FakePushSource();
    final repo = MockPushTokensRepository();
    await loginAsMember(t, pushOverrides(source, repo));

    source.opens.add({
      'notificationId': 'ntf-1',
      'templateKey': 'ORDER_CANCELLED',
      'destinationType': 'ORDER',
      'destinationRef': 'order-seed-1',
    });
    await t.pumpAndSettle();

    final detail = t.widget<OrderDetailScreen>(find.byType(OrderDetailScreen));
    expect(detail.orderId, 'order-seed-1');
  });

  testWidgets(
    '시작 화면 중에 누른 푸시는 시작이 끝난 뒤 그 화면을 연다(사용자 2026-11-25 — 배송 알림이 첫 화면으로)',
    (t) async {
      final source = FakePushSource();
      final repo = MockPushTokensRepository();
      final step = _StepNotifier();
      await loginAsMember(t, [
        ...pushOverrides(source, repo),
        _stepProvider.overrideWith(() => step),
        startStepProvider.overrideWith((ref) => ref.watch(_stepProvider)),
      ]);
      step.set(StartStep.loading);
      await t.pump();
      source.opens.add({
        'destinationType': 'ORDER',
        'destinationRef': 'order-seed-1',
      });
      await t.pumpAndSettle();
      expect(find.byType(OrderDetailScreen), findsNothing);
      step.set(StartStep.ready);
      await t.pumpAndSettle();
      final detail = t.widget<OrderDetailScreen>(
        find.byType(OrderDetailScreen),
      );
      expect(detail.orderId, 'order-seed-1');
    },
  );

  testWidgets('목적지를 모르는 푸시는 알림함이 열린다', (t) async {
    final source = FakePushSource();
    final repo = MockPushTokensRepository();
    await loginAsMember(t, pushOverrides(source, repo));

    source.opens.add(const {'destinationType': 'SOMETHING_NEW'});
    await t.pumpAndSettle();

    expect(find.byType(NotificationCenterScreen), findsOneWidget);
  });

  group('푸시 data → 경로(알림함 목적지와 같게)', () {
    test('주문·배송·환불(클레임)·문의', () {
      expect(
        pushRoute(const {'destinationType': 'ORDER', 'destinationRef': 'o 1'}),
        '/orders/o%201',
      );
      expect(
        pushRoute(const {
          'destinationType': 'DELIVERY',
          'destinationRef': 'd1',
        }),
        '/deliveries/d1',
      );
      expect(
        pushRoute(const {'destinationType': 'REFUND', 'destinationRef': 'c1'}),
        '/claims/c1',
      );
      expect(
        pushRoute(const {'destinationType': 'CLAIM', 'destinationRef': 'c1'}),
        '/claims/c1',
      );
      expect(
        pushRoute(const {'destinationType': 'INQUIRY', 'destinationRef': 'q1'}),
        '/support/inquiries/q1',
      );
    });

    test('목적지 없음·화면 없는 목적지·참조 없음 → 그 알림 상세, 알림 ID 도 없으면 알림함', () {
      expect(
        pushRoute(const {'notificationId': 'n1', 'destinationType': 'NONE'}),
        '/notifications/n1',
      );
      expect(
        pushRoute(const {
          'notificationId': 'n1',
          'destinationType': 'NOTICE',
          'destinationRef': 'x',
        }),
        '/notifications/n1',
      );
      expect(
        pushRoute(const {'notificationId': 'n1', 'destinationType': 'ORDER'}),
        '/notifications/n1',
      );
      expect(pushRoute(const {}), '/notifications');
    });

    // 백엔드 알림 2026-11-19 notice-delivery-notifications·incident-reshipment (notification 0.5.1).
    test('배송 진행 알림(레퍼런스 10. 3-1~3-5)·사고 재발송은 목적지대로', () {
      String route(String key, String type, String ref) => pushRoute({
        'notificationId': 'n1',
        'templateKey': key,
        'destinationType': type,
        'destinationRef': ref,
      });
      expect(route('PREPARATION_STARTED', 'ORDER', 'o1'), '/orders/o1');
      expect(route('DELIVERY_STARTED', 'DELIVERY', 'd1'), '/deliveries/d1');
      expect(route('DELIVERY_HEADING', 'DELIVERY', 'd1'), '/deliveries/d1');
      expect(
        route('DELIVERY_ARRIVING_SOON', 'DELIVERY', 'd1'),
        '/deliveries/d1',
      );
      expect(route('DELIVERY_COMPLETED', 'ORDER', 'o1'), '/orders/o1');
      expect(
        route('DELIVERY_INCIDENT_RESHIPMENT', 'ORDER', 'o1'),
        '/orders/o1',
      );
      // 옛 배송 출발 알림(목적지 ORDER)은 주문 상세 그대로.
      expect(route('DELIVERY_STARTED', 'ORDER', 'o1'), '/orders/o1');
    });
  });

  group('API 연동', () {
    Dio dioWith(FakeAdapter adapter) => createPmartDio(
      baseUrl: 'http://test.invalid/api/v1',
      sourceSystem: sourceSystem,
      tokens: TokenStore(MemoryKeyValueStore()),
      refresher: (_) async => null,
      adapter: adapter,
      delay: (_) async {},
    );

    test(
      '등록: PUT /me/push-tokens/{기기 ID}, 본문 token·platform ANDROID, 멱등 키·출처 헤더',
      () async {
        final adapter = FakeAdapter(
          (o, _) async => FakeReply(
            200,
            body: {
              'deviceId': 'dev-1',
              'platform': 'ANDROID',
              'registeredAt': '2026-11-17T10:00:00Z',
              'updatedAt': '2026-11-17T10:00:00Z',
            },
          ),
        );
        final deviceId = DeviceIdProvider(MemoryKeyValueStore());
        final key = IdempotencyKey.generate();
        await ApiPushTokensRepository(
          dioWith(adapter),
          deviceId,
        ).register('tok-1', key: key);

        final sent = adapter.requests.single;
        expect(sent.method, 'PUT');
        expect(sent.path, endsWith('/me/push-tokens/${await deviceId.get()}'));
        expect(sent.headers['Idempotency-Key'], key.value);
        expect(sent.headers['X-Source-System'], sourceSystem);
        expect(sent.data, contains('"token":"tok-1"'));
        expect(sent.data, contains('"platform":"ANDROID"'));
      },
    );

    test('해제: DELETE /me/push-tokens/{기기 ID}, 204', () async {
      final adapter = FakeAdapter((o, _) async => const FakeReply(204));
      final deviceId = DeviceIdProvider(MemoryKeyValueStore());
      await ApiPushTokensRepository(
        dioWith(adapter),
        deviceId,
      ).unregister(key: IdempotencyKey.generate());

      final sent = adapter.requests.single;
      expect(sent.method, 'DELETE');
      expect(sent.path, endsWith('/me/push-tokens/${await deviceId.get()}'));
      expect(sent.headers['Idempotency-Key'], isNotEmpty);
    });

    test('설정 없음(422 CONFIG_REQUIRED)은 실패로 던진다 — 등록된 것으로 보지 않는다', () async {
      final adapter = FakeAdapter(
        (o, _) async => const FakeReply(
          422,
          body: {
            'type': 'about:blank',
            'title': 'x',
            'status': 422,
            'code': 'CONFIG_REQUIRED',
          },
        ),
      );
      await expectLater(
        ApiPushTokensRepository(
          dioWith(adapter),
          DeviceIdProvider(MemoryKeyValueStore()),
        ).register('tok-1', key: IdempotencyKey.generate()),
        throwsA(isA<ProblemFailure>()),
      );
    });
  });
}

final _stepProvider = NotifierProvider<_StepNotifier, StartStep>(
  _StepNotifier.new,
);

class _StepNotifier extends Notifier<StartStep> {
  @override
  StartStep build() => StartStep.ready;

  void set(StartStep v) => state = v;
}
