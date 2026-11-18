import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 단말 푸시(FCM)의 단말 쪽 — 초기화·알림 권한·토큰·받은 푸시. 화면·컨트롤러는 이 인터페이스에만 기댄다.
///
/// 토큰 값은 서버 등록에만 쓴다. 로그·오류 문구·분석 이벤트에 남기지 않는다.
abstract interface class PushSource {
  /// 푸시를 쓸 수 있게 준비한다. 쓸 수 없으면 false(목 모드, `google-services.json` 없는 빌드 등) —
  /// false 면 나머지를 부르지 않는다.
  Future<bool> ready();

  /// 알림 권한(Android 13+ 는 물어본다). 허용이면 true.
  Future<bool> requestPermission();

  /// 지금 단말의 FCM 등록 토큰. 받지 못하면 null.
  Future<String?> token();

  /// 토큰이 바뀔 때마다 새 토큰.
  Stream<String> get tokenRefreshes;

  /// 이 단말의 토큰을 버린다(로그아웃·세션 종료) — 서버에 남은 옛 토큰으로는 더 오지 않게.
  Future<void> deleteToken();

  /// 푸시를 눌러 앱이 열렸다(꺼져 있다가 열린 경우 포함). 값은 그 푸시의 `data`(문자열만).
  Stream<Map<String, String>> get opened;

  /// 앱을 보고 있는 동안 푸시를 받았다(Android 는 이때 알림을 띄우지 않아 Firebase 구현이 로컬 알림으로 띄운다).
  Stream<void> get received;
}

/// Android 알림 채널 — 앱을 보고 있을 때 띄우는 로컬 알림과, 앱이 뒤에 있을 때 FCM 이 띄우는 알림이 같이 쓴다
/// (AndroidManifest default_notification_channel_id). 사용자가 휴대폰 설정에서 이 채널을 따로 켜고 끌 수 있다.
const pushChannelId = 'pmart_orders';

/// 푸시 없음(목 모드·시험).
final class NoPushSource implements PushSource {
  const NoPushSource();

  @override
  Future<bool> ready() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<String?> token() async => null;

  @override
  Stream<String> get tokenRefreshes => const Stream.empty();

  @override
  Future<void> deleteToken() async {}

  @override
  Stream<Map<String, String>> get opened => const Stream.empty();

  @override
  Stream<void> get received => const Stream.empty();
}

/// Firebase Cloud Messaging(Android). 설정은 `android/app/google-services.json`(git 제외)에서 읽는다 —
/// FlutterFire CLI·`firebase_options.dart` 를 쓰지 않아 Firebase 프로젝트를 바꿀 때 그 파일만 바꾸면 된다.
/// 파일 없이 빌드한 앱은 초기화가 실패하고 푸시 없이 돈다.
final class FirebasePushSource implements PushSource {
  Future<bool>? _ready;

  @override
  Future<bool> ready() => _ready ??= _init();

  final _local = FlutterLocalNotificationsPlugin();

  /// 앱을 보고 있을 때 띄운 로컬 알림을 눌렀다 — 그 푸시의 data.
  final _localTaps = StreamController<Map<String, String>>.broadcast();

  /// 로컬 알림으로 앱이 열렸을 때(꺼져 있다가) 그 data — [opened] 가 처음에 한 번 낸다.
  Map<String, String>? _launchedFromLocal;

  Future<bool> _init() async {
    try {
      await Firebase.initializeApp();
    } on Object {
      return false;
    }
    // 로컬 알림이 안 돼도 푸시(앱이 뒤에 있을 때)는 된다 — 실패해도 준비는 끝낸다.
    try {
      await _initLocal();
    } on Object {
      // 앱을 보고 있을 때만 알림이 안 뜬다(알림함은 그대로).
    }
    return true;
  }

  Future<void> _initLocal() async {
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (r) {
        if (_decode(r.payload) case final data?) _localTaps.add(data);
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            pushChannelId,
            '주문·배송 알림',
            description: '배송 출발·완료, 주문 취소, 환불 같은 알림',
            importance: Importance.high,
          ),
        );
    final launch = await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _launchedFromLocal = _decode(launch!.notificationResponse?.payload);
    }
    // 앱을 보고 있을 때 온 푸시는 Android 가 띄우지 않는다 — 서버가 보낸 제목·본문 그대로 앱이 띄운다.
    FirebaseMessaging.onMessage.listen((m) {
      final n = m.notification;
      if (n == null) return;
      unawaited(
        _local.show(
          id: (m.messageId ?? '${DateTime.now().microsecondsSinceEpoch}')
              .hashCode,
          title: n.title,
          body: n.body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              pushChannelId,
              '주문·배송 알림',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          payload: jsonEncode(_data(m)),
        ),
      );
    });
  }

  static Map<String, String>? _decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final v = jsonDecode(payload);
      if (v is! Map) return null;
      return {
        for (final e in v.entries)
          if ((e.key, e.value) case (final String k, final String val)) k: val,
      };
    } on FormatException {
      return null;
    }
  }

  @override
  Future<bool> requestPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  // firebase_messaging 17 은 getToken·onTokenRefresh·deleteToken 을 "쓰지 말 것"으로 표시하고
  // register()·onRegistered(값이 FCM 토큰이 아니라 Firebase 설치 ID)를 권한다. 서버 계약
  // (`PushTokenRegistration.token` = FCM 등록 토큰, FCM HTTP v1 로 발송)은 토큰을 받으므로 토큰 API 를 그대로 쓴다.
  // 설치 ID 로 바꿀지는 백엔드 답을 받은 뒤(질문 2026-11-17 customer-push-fcm Q8).
  @override
  // ignore: deprecated_member_use
  Future<String?> token() => FirebaseMessaging.instance.getToken();

  @override
  Stream<String> get tokenRefreshes =>
      // ignore: deprecated_member_use
      FirebaseMessaging.instance.onTokenRefresh;

  @override
  // ignore: deprecated_member_use
  Future<void> deleteToken() => FirebaseMessaging.instance.deleteToken();

  @override
  Stream<Map<String, String>> get opened async* {
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) yield _data(initial);
    // 앱을 보고 있을 때 띄운 로컬 알림으로 앱이 열린 경우(그 사이 앱이 꺼졌다가).
    if (_launchedFromLocal case final data?) {
      _launchedFromLocal = null;
      yield data;
    }
    // FCM 이 띄운 알림 누름 + 앱이 띄운 로컬 알림 누름 — 둘 다 같은 화면 이동.
    final merged = StreamController<Map<String, String>>();
    final subs = [
      FirebaseMessaging.onMessageOpenedApp
          .map(_data)
          .listen(merged.add, onError: merged.addError),
      _localTaps.stream.listen(merged.add, onError: merged.addError),
    ];
    merged.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
    };
    yield* merged.stream;
  }

  /// FCM data 는 문자열 값만 온다 — 다른 값은 버린다.
  static Map<String, String> _data(RemoteMessage m) => {
    for (final e in m.data.entries)
      if (e.value case final String v) e.key: v,
  };

  @override
  Stream<void> get received => FirebaseMessaging.onMessage.map<void>((_) {});
}
