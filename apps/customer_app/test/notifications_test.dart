import 'package:dio/dio.dart' show Dio, DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/claims/presentation/claims_screens.dart';
import 'package:customer_app/features/notifications/data/mock_notifications_repository.dart';
import 'package:customer_app/features/notifications/data/notifications_repository.dart';
import 'package:customer_app/features/notifications/domain/notifications.dart';
import 'package:customer_app/features/notifications/presentation/notifications_screens.dart';
import 'package:customer_app/features/orders/presentation/orders_screens.dart';
import 'package:customer_app/shared/providers.dart' show sourceSystem;

import 'support/app_harness.dart';

/// 알림함·알림 이동·수신 설정(고객앱 레퍼런스 반영 B, 2026-11-04).
void main() {
  setUpAll(initPmartFormatting);

  Future<void> bigScreen(WidgetTester t) async {
    t.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  /// 로그인 뒤 마이페이지 → 알림(또는 알림 설정).
  Future<void> open(
    WidgetTester t,
    MockNotificationsRepository repo, {
    bool settings = false,
    bool login = true,
  }) async {
    await bigScreen(t);
    await t.pumpWidget(testApp(const [], notifications: repo));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    if (login) {
      await t.tap(find.byKey(const ValueKey('my-login')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('login-kakao')));
      await t.pumpAndSettle();
    }
    await t.tap(
      find.byKey(
        ValueKey(settings ? 'my-notification-settings' : 'my-notifications'),
      ),
    );
    await t.pumpAndSettle();
  }

  Finder card(String id) => find.byKey(ValueKey('notice-$id'));
  Finder dot(String id) => find.byKey(ValueKey('notice-unread-$id'));

  Future<void> back(WidgetTester t) async {
    await t.tap(find.byType(BackButton).last);
    await t.pumpAndSettle();
  }

  group('목적지 → 앱 경로', () {
    test('주문·배송·클레임·환불만 이동하고 나머지는 상세에 머문다', () {
      String? r(NoticeDestinationType? type, [String? ref = 'x-1']) =>
          noticeRoute(NoticeDestination(type: type, ref: ref));
      expect(r(NoticeDestinationType.order), '/orders/x-1');
      expect(r(NoticeDestinationType.delivery), '/deliveries/x-1');
      expect(r(NoticeDestinationType.claim), '/claims/x-1');
      // REFUND 의 ref 는 claimId — 클레임 처리 내역으로 간다(백엔드 회신 2026-11-05 §1)
      expect(r(NoticeDestinationType.refund), '/claims/x-1');
      for (final t in [
        NoticeDestinationType.dispatchOffer,
        NoticeDestinationType.caseFile,
        NoticeDestinationType.notice,
        NoticeDestinationType.none,
        null,
      ]) {
        expect(r(t), isNull, reason: '$t');
      }
      expect(r(NoticeDestinationType.order, null), isNull);
      expect(r(NoticeDestinationType.order, ''), isNull);
      expect(noticeRoute(null), isNull);
    });
  });

  group('알림함', () {
    testWidgets('비회원은 조회하지 않고 로그인 안내를 보인다', (t) async {
      final repo = MockNotificationsRepository(latency: Duration.zero);
      await open(t, repo, login: false);
      expect(find.byKey(const ValueKey('go-login')), findsOneWidget);
      expect(repo.listCursors, isEmpty);

      await t.tap(find.byKey(const ValueKey('notice-settings')));
      await t.pumpAndSettle();
      expect(find.byType(NotificationSettingsScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('go-login')), findsOneWidget);
      expect(repo.settingsReads, 0);
    });

    testWidgets('홈 종 아이콘으로 들어간다', (t) async {
      await bigScreen(t);
      await t.pumpWidget(testApp(const []));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('home-notifications')));
      await t.pumpAndSettle();
      expect(find.byType(NotificationCenterScreen), findsOneWidget);
    });

    testWidgets('목록: 제목·본문·시각, 안 읽은 것만 점', (t) async {
      final repo = MockNotificationsRepository(latency: Duration.zero);
      await open(t, repo);
      for (final id in ['ntf-6', 'ntf-5', 'ntf-4', 'ntf-3', 'ntf-2', 'ntf-1']) {
        expect(card(id), findsOneWidget, reason: id);
      }
      expect(find.text('곧 도착해요'), findsOneWidget);
      expect(find.textContaining('라이더가 근처에 있어요'), findsOneWidget);
      // 2026-10-24T03:20Z = 서울 12:20
      expect(find.textContaining('12:20'), findsOneWidget);
      for (final id in ['ntf-6', 'ntf-5', 'ntf-4']) {
        expect(dot(id), findsOneWidget, reason: id);
      }
      for (final id in ['ntf-3', 'ntf-2', 'ntf-1']) {
        expect(dot(id), findsNothing, reason: id);
      }
      expect(find.byKey(const ValueKey('notices-more')), findsNothing);
    });

    testWidgets('조회 실패는 "알림 없음"이 아니라 오류', (t) async {
      final repo = MockNotificationsRepository(latency: Duration.zero)
        ..listFailures.add(
          const NetworkFailure(DioExceptionType.connectionError),
        );
      await open(t, repo);
      expect(find.byKey(const ValueKey('ui-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('notices-empty')), findsNothing);
      expect(card('ntf-6'), findsNothing);
    });

    testWidgets('정상 0건만 빈 화면', (t) async {
      final repo = MockNotificationsRepository(
        latency: Duration.zero,
        notices: [],
      );
      await open(t, repo);
      expect(find.byKey(const ValueKey('notices-empty')), findsOneWidget);
    });

    testWidgets('다음 쪽은 서버 커서로, 실패해도 받은 목록은 남는다', (t) async {
      final repo = MockNotificationsRepository(
        latency: Duration.zero,
        pageSize: 4,
      );
      await open(t, repo);
      expect(card('ntf-3'), findsOneWidget);
      expect(card('ntf-2'), findsNothing);

      repo.listFailures.add(
        const NetworkFailure(DioExceptionType.receiveTimeout),
      );
      await t.ensureVisible(find.byKey(const ValueKey('notices-more')));
      await t.tap(find.byKey(const ValueKey('notices-more')));
      await t.pumpAndSettle();
      expect(repo.listCursors.last, '4');
      expect(find.byKey(const ValueKey('notices-more-failed')), findsOneWidget);
      expect(card('ntf-6'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('notices-more-retry')));
      await t.pumpAndSettle();
      expect(card('ntf-2'), findsOneWidget);
      expect(card('ntf-1'), findsOneWidget);
      expect(find.byKey(const ValueKey('notices-more')), findsNothing);
      expect(find.byKey(const ValueKey('notices-more-failed')), findsNothing);
    });
  });

  group('알림 누르기', () {
    testWidgets('배송 → 배송현황, 읽음은 서버 응답으로 반영', (t) async {
      final repo = MockNotificationsRepository(latency: Duration.zero);
      await open(t, repo);
      await t.tap(card('ntf-6'));
      await t.pumpAndSettle();
      expect(find.byType(TrackingScreen), findsOneWidget);
      expect(repo.readKeys, hasLength(1));

      await back(t);
      expect(dot('ntf-6'), findsNothing);
    });

    testWidgets('주문 → 주문 상세, 클레임 → 처리 내역', (t) async {
      final repo = MockNotificationsRepository(latency: Duration.zero);
      await open(t, repo);
      await t.tap(card('ntf-5'));
      await t.pumpAndSettle();
      final detail = t.widget<OrderDetailScreen>(
        find.byType(OrderDetailScreen),
      );
      expect(detail.orderId, 'order-seed-1');

      await back(t);
      await t.tap(card('ntf-2'));
      await t.pumpAndSettle();
      final claim = t.widget<ClaimScreen>(find.byType(ClaimScreen));
      expect(claim.claimId, 'claim-1');
      // 이미 읽은 알림은 읽음 처리를 보내지 않는다.
      expect(repo.readKeys, hasLength(1));
    });

    testWidgets('배달 완료 알림은 서버 목적지(주문 상세)로 간다', (t) async {
      final repo = MockNotificationsRepository(latency: Duration.zero);
      await open(t, repo);
      await t.ensureVisible(card('ntf-1'));
      await t.tap(card('ntf-1'));
      await t.pumpAndSettle();
      final detail = t.widget<OrderDetailScreen>(
        find.byType(OrderDetailScreen),
      );
      expect(detail.orderId, 'order-seed-3');
      expect(find.byType(TrackingScreen), findsNothing);
    });

    testWidgets('환불 알림은 ref(claimId)의 클레임 처리 내역으로 간다', (t) async {
      final repo = MockNotificationsRepository(latency: Duration.zero);
      await open(t, repo);
      await t.tap(card('ntf-3'));
      await t.pumpAndSettle();
      final claim = t.widget<ClaimScreen>(find.byType(ClaimScreen));
      expect(claim.claimId, 'claim-1');
      expect(find.byType(NotificationDetailScreen), findsNothing);
    });

    testWidgets('공지처럼 앱 화면이 없는 목적지는 알림 상세에 머문다', (t) async {
      final repo = MockNotificationsRepository(latency: Duration.zero);
      await open(t, repo);
      await t.tap(card('ntf-4'));
      await t.pumpAndSettle();
      expect(find.byType(NotificationDetailScreen), findsOneWidget);
      expect(find.text('서비스 점검 안내'), findsWidgets);
      await back(t);
      expect(dot('ntf-4'), findsNothing);
    });

    testWidgets('읽음 결과 불명 → 단건 조회로 확인(재전송 없음)', (t) async {
      final repo = MockNotificationsRepository(latency: Duration.zero)
        ..readFailureApplies = true
        ..readFailures.add(const UnknownResultFailure(httpStatus: 503));
      await open(t, repo);
      await t.tap(card('ntf-4'));
      await t.pumpAndSettle();
      await back(t);
      expect(repo.readKeys, hasLength(1));
      expect(dot('ntf-4'), findsNothing);
      expect(find.byKey(const ValueKey('notice-checking-ntf-4')), findsNothing);
    });

    testWidgets('조회까지 실패하면 "읽음 확인 중", 다시 누르면 조회만 한다', (t) async {
      final repo = MockNotificationsRepository(latency: Duration.zero)
        ..readFailures.add(
          const UnknownResultFailure(
            transport: DioExceptionType.receiveTimeout,
          ),
        );
      await open(t, repo);
      repo.getFailures.add(
        const NetworkFailure(DioExceptionType.connectionError),
      );
      await t.tap(card('ntf-5'));
      await t.pumpAndSettle();
      await back(t);
      expect(
        find.byKey(const ValueKey('notice-checking-ntf-5')),
        findsOneWidget,
      );
      expect(dot('ntf-5'), findsOneWidget);

      await t.tap(card('ntf-5'));
      await t.pumpAndSettle();
      await back(t);
      expect(repo.readKeys, hasLength(1));
      // 서버는 반영하지 않았다 → 안 읽음 그대로, 확인 중은 풀린다.
      expect(find.byKey(const ValueKey('notice-checking-ntf-5')), findsNothing);
      expect(dot('ntf-5'), findsOneWidget);
    });
  });

  group('알림 설정', () {
    Finder sw(String id) => find.byKey(ValueKey('setting-switch-$id'));
    bool on(WidgetTester t, String id) => t.widget<Switch>(sw(id)).value;

    testWidgets('거래 안내는 잠금, 마케팅 동의·기기 권한은 서버 값 표시만', (t) async {
      final repo = MockNotificationsRepository(latency: Duration.zero);
      await open(t, repo, settings: true);
      expect(t.widget<Switch>(sw('order-appPush')).onChanged, isNull);
      expect(on(t, 'order-appPush'), isTrue);
      expect(t.widget<Switch>(sw('marketing-appPush')).onChanged, isNotNull);
      expect(find.text('동의 안 함'), findsOneWidget);
      expect(find.text('알 수 없음'), findsOneWidget);
    });

    testWidgets('반영(APPLIED) → 서버 값으로 다시 그림, 키·버전 전송', (t) async {
      final repo = MockNotificationsRepository(latency: Duration.zero);
      await open(t, repo, settings: true);
      expect(on(t, 'marketing-appPush'), isFalse);
      await t.tap(sw('marketing-appPush'));
      await t.pumpAndSettle();
      expect(on(t, 'marketing-appPush'), isTrue);
      expect(find.text('알림 설정을 바꿨어요'), findsOneWidget);
      expect(repo.changeKeys, hasLength(1));
      expect(repo.expectedVersions, [1]);
      expect(repo.changeBodies.single.single.enabled, isTrue);
    });

    testWidgets('접수(ACCEPTED) → 결과 조회로 반영 확인', (t) async {
      final repo = MockNotificationsRepository(latency: Duration.zero)
        ..acceptOnly = true;
      await open(t, repo, settings: true);
      await t.tap(sw('system-appPush'));
      await t.pumpAndSettle();
      expect(on(t, 'system-appPush'), isFalse);
      expect(find.text('알림 설정을 바꿨어요'), findsOneWidget);
    });

    testWidgets('거절은 서버 값 그대로, Problem code 로 안내', (t) async {
      final repo = MockNotificationsRepository(latency: Duration.zero);
      await open(t, repo, settings: true);
      await t.tap(sw('marketing-kakaoAlimtalk'));
      await t.pumpAndSettle();
      expect(on(t, 'marketing-kakaoAlimtalk'), isFalse);
      expect(find.text('아직 이 방법으로는 알림을 보낼 수 없어요'), findsOneWidget);

      // 다른 기기에서 바뀌었다 → VERSION_CONFLICT → 최신 설정을 다시 읽는다.
      repo.settingsJson['version'] = 9;
      final reads = repo.settingsReads;
      await t.tap(sw('marketing-sms'));
      await t.pumpAndSettle();
      expect(on(t, 'marketing-sms'), isFalse);
      expect(find.text('설정이 그사이 바뀌었어요. 최신 설정을 불러왔어요'), findsOneWidget);
      expect(repo.settingsReads, reads + 1);
    });

    testWidgets('결과 불명 → 같은 키로 한 번 더, 그래도 모르면 "확인 중"', (t) async {
      final repo = MockNotificationsRepository(latency: Duration.zero)
        ..unknownApplies = false
        ..changeReplies.addAll([
          const SettingChangeUnknown(),
          const SettingChangeUnknown(),
        ]);
      await open(t, repo, settings: true);
      await t.tap(sw('marketing-appPush'));
      await t.pumpAndSettle();
      expect(repo.changeKeys, hasLength(2));
      expect(repo.changeKeys.toSet(), hasLength(1));
      expect(
        find.byKey(const ValueKey('setting-checking-marketing-appPush')),
        findsOneWidget,
      );
      expect(sw('marketing-appPush'), findsNothing);
      expect(find.text('반영됐는지 확인하지 못했어요. 잠시 뒤 다시 확인해 주세요'), findsOneWidget);

      await t.tap(
        find.byKey(const ValueKey('setting-recheck-marketing-appPush')),
      );
      await t.pumpAndSettle();
      expect(repo.changeKeys, hasLength(3));
      expect(repo.changeKeys.toSet(), hasLength(1));
      expect(on(t, 'marketing-appPush'), isTrue);
    });

    testWidgets('결과 불명이었지만 서버가 반영했으면 같은 키 재전송이 원결과를 준다', (t) async {
      final repo = MockNotificationsRepository(latency: Duration.zero)
        ..changeReplies.add(const SettingChangeUnknown());
      await open(t, repo, settings: true);
      await t.tap(sw('marketing-appPush'));
      await t.pumpAndSettle();
      expect(repo.changeKeys.toSet(), hasLength(1));
      expect(on(t, 'marketing-appPush'), isTrue);
      expect(repo.settingsJson['version'], 2);
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

    final notice = MockNotificationsRepository.seedNotices().first;

    test('목록: 커서·안 읽음 수·목적지를 계약대로 읽는다', () async {
      final adapter = FakeAdapter(
        (o, _) async => FakeReply(
          200,
          body: {
            'items': [notice],
            'unreadCount': 3,
            'page': {'nextCursor': 'c-2', 'size': 50},
          },
        ),
      );
      final page = await ApiNotificationsRepository(dioWith(adapter))
          .list(cursor: 'c-1');
      expect(adapter.requests.single.path, endsWith('/me/notifications'));
      expect(adapter.requests.single.queryParameters['cursor'], 'c-1');
      expect(page.nextCursor, 'c-2');
      expect(page.unreadCount, 3);
      expect(
        page.items.single.destination?.type,
        NoticeDestinationType.delivery,
      );
      expect(page.items.single.read, isFalse);
    });

    test('읽음 처리는 Idempotency-Key·X-Source-System 을 붙인다', () async {
      final adapter = FakeAdapter(
        (o, _) async =>
            FakeReply(200, body: {...notice, 'state': 'NOTICE_READ'}),
      );
      final key = IdempotencyKey.generate();
      final n = await ApiNotificationsRepository(dioWith(adapter))
          .markRead('ntf-6', key: key);
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.path, endsWith('/me/notifications/ntf-6/reads'));
      expect(req.headers['Idempotency-Key'], key.value);
      expect(req.headers['X-Source-System'], sourceSystem);
      expect(n.read, isTrue);
    });

    test('설정 변경: 4값과 422 code 를 구분한다', () async {
      Map<String, dynamic> cmd(String status) => {
        'status': status,
        'requestId': 'nsc-1',
        if (status == 'REJECTED') 'nextAction': 'TRANSACTIONAL_CANNOT_DISABLE',
      };
      const change = [
        NoticeSettingChange(
          category: NoticeCategory.marketing,
          channel: NoticeChannel.sms,
          enabled: true,
        ),
      ];
      Future<SettingChangeOutcome> send(FakeReply reply) =>
          ApiNotificationsRepository(
            dioWith(FakeAdapter((o, _) async => reply)),
          ).changeSettings(
            change,
            expectedVersion: 3,
            key: IdempotencyKey.generate(),
          );

      expect(
        await send(FakeReply(200, body: cmd('APPLIED'))),
        isA<SettingChangeApplied>(),
      );
      expect(
        await send(FakeReply(200, body: cmd('ACCEPTED'))),
        isA<SettingChangePending>().having((p) => p.requestId, 'id', 'nsc-1'),
      );
      expect(
        await send(FakeReply(200, body: cmd('UNKNOWN_RESULT'))),
        isA<SettingChangeUnknown>(),
      );
      expect(
        await send(FakeReply(200, body: cmd('REJECTED'))),
        isA<SettingChangeRejected>().having(
          (r) => r.code,
          'code',
          NoticeProblemCode.transactionalCannotDisable,
        ),
      );
      expect(
        await send(
          FakeReply.problem(
            422,
            problemBody(NoticeProblemCode.channelNotApproved, status: 422),
          ),
        ),
        isA<SettingChangeRejected>().having(
          (r) => r.code,
          'code',
          NoticeProblemCode.channelNotApproved,
        ),
      );
      expect(await send(const FakeReply(503)), isA<SettingChangeUnknown>());
    });

    test('설정 변경 요청 헤더·본문', () async {
      final adapter = FakeAdapter(
        (o, _) async => const FakeReply(
          200,
          body: {'status': 'APPLIED', 'requestId': 'nsc-1'},
        ),
      );
      final key = IdempotencyKey.generate();
      await ApiNotificationsRepository(dioWith(adapter)).changeSettings(
        const [
          NoticeSettingChange(
            category: NoticeCategory.marketing,
            channel: NoticeChannel.appPush,
            enabled: false,
          ),
        ],
        expectedVersion: 7,
        key: key,
      );
      final req = adapter.requests.single;
      expect(req.path, endsWith('/me/notification-setting-changes'));
      expect(req.headers['Idempotency-Key'], key.value);
      expect(req.headers['X-Source-System'], sourceSystem);
      expect('${req.headers['X-Expected-Version']}', '7');
      expect(req.data.toString(), contains('MARKETING'));
      expect(req.data.toString(), contains('APP_PUSH'));
    });
  });
}
