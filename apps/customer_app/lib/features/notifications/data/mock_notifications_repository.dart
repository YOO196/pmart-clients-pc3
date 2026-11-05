import 'dart:collection';

import 'package:pmart_api_notification/pmart_api_notification.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../domain/notifications.dart';
import 'notifications_repository.dart';

/// 목 알림함·수신 설정. 데이터는 계약 JSON(`Notification`·`NotificationSettings`)으로 두고 생성 모델로 읽는다.
/// 목적지 참조는 주문 목(`order-seed-*`, `dlv-*`)에 맞춘다.
final class MockNotificationsRepository implements NotificationsRepository {
  MockNotificationsRepository({
    this.latency = const Duration(milliseconds: 200),
    this.pageSize = 20,
    List<Map<String, dynamic>>? notices,
    Map<String, dynamic>? settings,
  }) : notices = notices ?? seedNotices(),
       settingsJson = settings ?? seedSettings();

  final Duration latency;
  final int pageSize;

  /// 최신 순 알림(계약 `Notification` JSON).
  final List<Map<String, dynamic>> notices;

  /// 계약 `NotificationSettings` JSON.
  final Map<String, dynamic> settingsJson;

  /// 다음 목록 조회에서 던질 실패(앞에서부터 하나씩).
  final listFailures = Queue<PmartFailure>();

  /// 다음 단건 조회(짝 조회 포함)에서 던질 실패.
  final getFailures = Queue<PmartFailure>();

  /// 다음 읽음 처리에서 던질 실패. [readFailureApplies] 면 서버는 반영한 뒤 응답만 잃은 것처럼 한다.
  final readFailures = Queue<PmartFailure>();
  bool readFailureApplies = false;

  /// 다음 설정 변경의 응답을 정해 둔다. [SettingChangeUnknown] 은 [unknownApplies] 면 서버는 반영한 것처럼 한다.
  final changeReplies = Queue<SettingChangeOutcome>();
  bool unknownApplies = true;

  /// true 면 변경을 접수(ACCEPTED)만 하고 결과 조회 때 반영한다.
  bool acceptOnly = false;

  final listCursors = <String?>[];
  final readKeys = <String>[];
  final changeKeys = <String>[];
  final changeBodies = <List<NoticeSettingChange>>[];
  final expectedVersions = <int?>[];
  int settingsReads = 0;

  final _byKey = <String, SettingChangeOutcome>{};
  final _accepted = <String, List<NoticeSettingChange>>{};
  int _seq = 0;

  Future<void> _wait() => Future<void>.delayed(latency);

  @override
  Future<NoticePage> list({String? cursor}) async {
    await _wait();
    listCursors.add(cursor);
    if (listFailures.isNotEmpty) throw listFailures.removeFirst();
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = (start + pageSize).clamp(0, notices.length);
    final body = api.ListMyNotifications200Response.fromJson({
      'items': notices.sublist(start, end),
      'unreadCount': notices.where((n) => n['state'] == 'NOTICE_UNREAD').length,
      'page': {
        'nextCursor': end < notices.length ? '$end' : null,
        'size': pageSize,
      },
    });
    return NoticePage(
      items: [for (final n in body.items!) noticeFromContract(n)],
      unreadCount: body.unreadCount,
      nextCursor: body.page?.nextCursor,
    );
  }

  Map<String, dynamic> _find(String id) => notices.firstWhere(
    (n) => n['notificationId'] == id,
    orElse: () => throw const ProblemFailure(
      Problem(status: 404, code: ProblemCode.notFound),
    ),
  );

  @override
  Future<InboxNotice> get(String notificationId) async {
    await _wait();
    if (getFailures.isNotEmpty) throw getFailures.removeFirst();
    return noticeFromContract(api.Notification.fromJson(_find(notificationId)));
  }

  @override
  Future<InboxNotice> markRead(
    String notificationId, {
    required IdempotencyKey key,
  }) async {
    await _wait();
    readKeys.add(key.value);
    if (readFailures.isNotEmpty) {
      final f = readFailures.removeFirst();
      if (readFailureApplies) _read(_find(notificationId));
      throw f;
    }
    final n = _find(notificationId);
    _read(n);
    return noticeFromContract(api.Notification.fromJson(n));
  }

  void _read(Map<String, dynamic> n) {
    if (n['state'] == 'NOTICE_READ') return; // 이미 읽음이면 멱등 성공.
    n['state'] = 'NOTICE_READ';
    n['readAt'] = DateTime.now().toUtc().toIso8601String();
  }

  @override
  Future<NoticeSettings> settings() async {
    await _wait();
    settingsReads++;
    return settingsFromContract(
      api.NotificationSettings.fromJson(settingsJson),
    );
  }

  @override
  Future<SettingChangeOutcome> changeSettings(
    List<NoticeSettingChange> changes, {
    int? expectedVersion,
    required IdempotencyKey key,
  }) async {
    await _wait();
    changeKeys.add(key.value);
    changeBodies.add(changes);
    expectedVersions.add(expectedVersion);
    if (_byKey[key.value] case final replay?) return replay;
    if (changeReplies.isNotEmpty) {
      final r = changeReplies.removeFirst();
      if (r is SettingChangeUnknown) {
        if (unknownApplies) {
          _byKey[key.value] = _apply(changes, expectedVersion);
        }
        return r;
      }
      return r;
    }
    if (acceptOnly) {
      final requestId = 'nsc-${++_seq}';
      _accepted[requestId] = changes;
      return _byKey[key.value] = SettingChangePending(requestId);
    }
    return _byKey[key.value] = _apply(changes, expectedVersion);
  }

  @override
  Future<SettingChangeOutcome> settingChange(String requestId) async {
    await _wait();
    final changes = _accepted.remove(requestId);
    if (changes == null) return const SettingChangeApplied();
    return _apply(changes, null);
  }

  SettingChangeOutcome _apply(
    List<NoticeSettingChange> changes,
    int? expectedVersion,
  ) {
    final version = settingsJson['version'] as int;
    if (expectedVersion != null && expectedVersion != version) {
      return const SettingChangeRejected(ProblemCode.versionConflict);
    }
    final items = (settingsJson['items'] as List).cast<Map<String, dynamic>>();
    for (final c in changes) {
      if (c.channel == NoticeChannel.kakaoAlimtalk) {
        return const SettingChangeRejected(
          NoticeProblemCode.channelNotApproved,
        );
      }
      final item = _item(items, c);
      if (item == null) {
        return const SettingChangeRejected(ProblemCode.notFound);
      }
      if (item['locked'] == true && !c.enabled) {
        return const SettingChangeRejected(
          NoticeProblemCode.transactionalCannotDisable,
        );
      }
    }
    for (final c in changes) {
      _item(items, c)!['enabled'] = c.enabled;
    }
    settingsJson['version'] = version + 1;
    return const SettingChangeApplied();
  }

  static Map<String, dynamic>? _item(
    List<Map<String, dynamic>> items,
    NoticeSettingChange c,
  ) {
    final category = categoryToContract(c.category).value;
    final channel = channelToContract(c.channel).value;
    for (final i in items) {
      if (i['category'] == category && i['channel'] == channel) return i;
    }
    return null;
  }

  /// 기본 알림함(최신 순). 배송 중 알림은 배송현황으로, 완료 뒤 알림은 주문 상세로 간다.
  static List<Map<String, dynamic>> seedNotices() => [
    {
      'notificationId': 'ntf-6',
      'category': 'DELIVERY',
      'title': '곧 도착해요',
      'body': '라이더가 근처에 있어요. 문 앞에서 기다려 주세요.',
      'destination': {'type': 'DELIVERY', 'ref': 'dlv-s2'},
      'sourceEventId': 'evt-6',
      'sourceEventType': 'DeliveryEtaUpdated',
      'state': 'NOTICE_UNREAD',
      'createdAt': '2026-10-24T03:20:00Z',
      'readAt': null,
    },
    {
      'notificationId': 'ntf-5',
      'category': 'ORDER',
      'title': '주문이 확정됐어요',
      'body': '상품을 준비하고 있어요.',
      'destination': {'type': 'ORDER', 'ref': 'order-seed-1'},
      'sourceEventId': 'evt-5',
      'sourceEventType': 'OrderConfirmed',
      'state': 'NOTICE_UNREAD',
      'createdAt': '2026-10-24T02:31:00Z',
      'readAt': null,
    },
    {
      'notificationId': 'ntf-4',
      'category': 'SYSTEM',
      'title': '서비스 점검 안내',
      'body': '10월 26일 새벽 2시부터 4시까지 주문이 잠시 멈춰요.',
      'destination': {'type': 'NOTICE', 'ref': 'notice-1026'},
      'sourceEventId': 'evt-4',
      'sourceEventType': 'NotificationRequested',
      'state': 'NOTICE_UNREAD',
      'createdAt': '2026-10-23T09:00:00Z',
      'readAt': null,
    },
    {
      'notificationId': 'ntf-3',
      'category': 'REFUND',
      'title': '환불을 마쳤어요',
      'body': '결제 수단에 따라 3~5영업일 뒤 반영돼요.',
      'destination': {'type': 'REFUND', 'ref': 'rf-claim-1'},
      'sourceEventId': 'evt-3',
      'sourceEventType': 'RefundResult',
      'state': 'NOTICE_READ',
      'createdAt': '2026-10-21T01:00:00Z',
      'readAt': '2026-10-21T02:00:00Z',
    },
    {
      'notificationId': 'ntf-2',
      'category': 'CLAIM',
      'title': '취소 요청을 처리했어요',
      'body': '요청하신 주문 취소가 처리됐어요.',
      'destination': {'type': 'CLAIM', 'ref': 'claim-1'},
      'sourceEventId': 'evt-2',
      'sourceEventType': 'ClaimDecided',
      'state': 'NOTICE_READ',
      'createdAt': '2026-10-20T07:00:00Z',
      'readAt': '2026-10-20T08:00:00Z',
    },
    {
      'notificationId': 'ntf-1',
      'category': 'DELIVERY',
      'title': '배달을 마쳤어요',
      'body': '주문하신 상품을 문 앞에 두었어요.',
      'destination': {'type': 'ORDER', 'ref': 'order-seed-3'},
      'sourceEventId': 'evt-1',
      'sourceEventType': 'DeliveryCompleted',
      'state': 'NOTICE_READ',
      'createdAt': '2026-10-20T06:30:00Z',
      'readAt': '2026-10-20T06:40:00Z',
    },
  ];

  /// 기본 수신 설정. 거래 안내(주문·결제·배송·취소/반품·환불)는 잠금, 마케팅·공지는 끌 수 있다.
  static Map<String, dynamic> seedSettings() => {
    'accountId': 'acct-mock-1',
    'version': 1,
    'items': [
      for (final c in ['ORDER', 'PAYMENT', 'DELIVERY', 'CLAIM', 'REFUND'])
        {'category': c, 'channel': 'APP_PUSH', 'enabled': true, 'locked': true},
      {
        'category': 'MARKETING',
        'channel': 'APP_PUSH',
        'enabled': false,
        'locked': false,
      },
      {
        'category': 'MARKETING',
        'channel': 'SMS',
        'enabled': false,
        'locked': false,
      },
      {
        'category': 'MARKETING',
        'channel': 'KAKAO_ALIMTALK',
        'enabled': false,
        'locked': false,
      },
      {
        'category': 'SYSTEM',
        'channel': 'APP_PUSH',
        'enabled': true,
        'locked': false,
      },
    ],
    'marketingConsent': 'WITHDRAWN',
    'osPermission': 'UNKNOWN',
  };
}
