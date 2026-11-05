import 'package:flutter/foundation.dart';

/// 알림 종류(계약 `Category`).
enum NoticeCategory {
  order,
  payment,
  delivery,
  claim,
  refund,
  dispatch,
  caseFile,
  marketing,
  system,
}

/// 수신 채널(계약 `Channel`). 알림톡은 승인 전이라 서버가 거절할 수 있다(CHANNEL_NOT_APPROVED).
enum NoticeChannel { appPush, inApp, kakaoAlimtalk, sms }

/// 알림을 열 때 이동할 최신 목적지 종류(계약 `Destination.type`).
enum NoticeDestinationType {
  order,
  delivery,
  claim,
  refund,
  dispatchOffer,
  caseFile,
  notice,
  none,
}

@immutable
class NoticeDestination {
  const NoticeDestination({this.type, this.ref});

  /// 모르는 값이면 null(이동하지 않는다).
  final NoticeDestinationType? type;
  final String? ref;
}

/// 알림함의 알림 한 건(계약 `Notification`). 본문은 발송 당시 사실이고 최신 상태는 목적지에서 조회한다.
@immutable
class InboxNotice {
  const InboxNotice({
    required this.notificationId,
    required this.category,
    required this.title,
    required this.read,
    required this.createdAt,
    this.body,
    this.destination,
    this.readAt,
  });

  final String notificationId;
  final NoticeCategory category;
  final String title;
  final String? body;
  final NoticeDestination? destination;

  /// 서버 `state == NOTICE_READ`. 읽음은 배송 수령·거래 확정의 근거가 아니다.
  final bool read;
  final DateTime createdAt;
  final DateTime? readAt;

  @override
  String toString() => 'InboxNotice($notificationId, read=$read)';
}

/// 알림함 한 쪽. [nextCursor] 가 있으면 다음 쪽이 있다.
@immutable
class NoticePage {
  const NoticePage({required this.items, this.unreadCount, this.nextCursor});

  final List<InboxNotice> items;
  final int? unreadCount;
  final String? nextCursor;
}

/// 알림을 눌렀을 때 갈 앱 경로. 앱에 화면이 없는 목적지(환불·공지 등)나 참조가 없으면 null(알림 상세에 머문다).
///
/// - REFUND: 계약에 `ref` 가 환불 ID 인지 클레임 ID 인지 정해져 있지 않아 이동하지 않는다.
/// - DISPATCH_OFFER·CASE: 라이더·운영자용 목적지다.
String? noticeRoute(NoticeDestination? d) {
  final ref = d?.ref;
  if (d == null || ref == null || ref.isEmpty) return null;
  final id = Uri.encodeComponent(ref);
  return switch (d.type) {
    NoticeDestinationType.order => '/orders/$id',
    NoticeDestinationType.delivery => '/deliveries/$id',
    NoticeDestinationType.claim => '/claims/$id',
    _ => null,
  };
}

/// 수신 설정 한 줄(계약 `NotificationSettings.items[]`).
@immutable
class NoticeSettingItem {
  const NoticeSettingItem({
    required this.category,
    required this.channel,
    required this.enabled,
    required this.locked,
  });

  final NoticeCategory category;
  final NoticeChannel channel;
  final bool enabled;

  /// 거래 안내는 끌 수 없다(서버 값).
  final bool locked;
}

enum MarketingConsent { agreed, withdrawn, unknown }

enum OsPermission { granted, denied, unknown }

/// 앱 수신 설정(계약 `NotificationSettings`). 마케팅 동의·OS 권한은 참조 값이다.
@immutable
class NoticeSettings {
  const NoticeSettings({
    required this.items,
    this.version,
    this.marketingConsent,
    this.osPermission,
  });

  final int? version;
  final List<NoticeSettingItem> items;
  final MarketingConsent? marketingConsent;
  final OsPermission? osPermission;
}

/// 설정 변경 한 건(계약 `changes[]`).
@immutable
class NoticeSettingChange {
  const NoticeSettingChange({
    required this.category,
    required this.channel,
    required this.enabled,
  });

  final NoticeCategory category;
  final NoticeChannel channel;
  final bool enabled;
}

/// 설정 변경 결과. [SettingChangeApplied] 만 "바뀜"이다.
@immutable
sealed class SettingChangeOutcome {
  const SettingChangeOutcome();
}

final class SettingChangeApplied extends SettingChangeOutcome {
  const SettingChangeApplied();
}

/// 접수됐지만 반영을 아직 확인하지 못했다(ACCEPTED). 요청 ID 로 다시 조회한다.
final class SettingChangePending extends SettingChangeOutcome {
  const SettingChangePending(this.requestId);

  final String requestId;
}

final class SettingChangeRejected extends SettingChangeOutcome {
  const SettingChangeRejected(this.code);

  final String code;
}

/// 반영 여부를 모른다(응답 유실·5xx·UNKNOWN_RESULT). 같은 키로만 다시 확인한다.
final class SettingChangeUnknown extends SettingChangeOutcome {
  const SettingChangeUnknown();
}

/// 알림 설정 변경의 Problem 코드(계약 422).
abstract final class NoticeProblemCode {
  static const transactionalCannotDisable = 'TRANSACTIONAL_CANNOT_DISABLE';
  static const channelNotApproved = 'CHANNEL_NOT_APPROVED';
}
