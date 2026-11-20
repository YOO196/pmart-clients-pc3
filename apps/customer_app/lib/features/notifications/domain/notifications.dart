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

  /// 고객센터 문의(notification 0.2.0, ref = inquiryId).
  inquiry,
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
    this.templateKey,
  });

  final String notificationId;
  final NoticeCategory category;
  final String title;
  final String? body;
  final NoticeDestination? destination;

  /// 알림 종류(notification 0.4.4 `templateKey` — 예 REVIEW_REQUESTED). 모르는 값·없음이면 목적지 기본 동작.
  final String? templateKey;

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

/// 리뷰 요청 알림 종류(배송 완료 1시간 뒤, 알림함만 — notification 0.4.2·0.4.4).
const reviewRequestedTemplate = 'REVIEW_REQUESTED';

/// 쿠폰 도착 알림 종류(notification 2026-11-21, ADR-0082 5단계) — 가입 축하·직원 지정·배차 불가 보상.
/// 서버 목적지는 없거나(NONE) 취소된 주문이지만 문구가 "쿠폰함에서 확인해 주세요"라 앱이 쿠폰함을 연다
/// (백엔드 회신 2026-11-21 reply-coupons-questions — 앱이 templateKey 로 열어도 된다).
const couponTemplates = {
  'COUPON_SIGNUP',
  'COUPON_ISSUED',
  'COUPON_COMPENSATION',
};

/// 알림을 눌렀을 때 갈 앱 경로. 앱에 화면이 없는 목적지(공지 등)나 참조가 없으면 null(알림 상세에 머문다).
///
/// - REFUND: `ref` 는 claimId 다(notification-service 0.1.1 `Destination.ref`). 환불은 클레임 아래에서 보므로
///   클레임 처리 내역으로 간다.
/// - INQUIRY: `ref` 는 inquiryId 다(notification 0.2.0 — 고객센터 답변 알림). 내 문의 상세로 간다.
/// - DISPATCH_OFFER·CASE: 라이더·운영자용 목적지다.
String? noticeRoute(NoticeDestination? d, {String? templateKey}) {
  if (couponTemplates.contains(templateKey)) return '/me/coupons';
  final ref = d?.ref;
  if (d == null || ref == null || ref.isEmpty) return null;
  final id = Uri.encodeComponent(ref);
  // 리뷰 요청(notification 0.4.4): 목적지는 주문이지만 그 주문의 리뷰 쓰기로 간다.
  if (templateKey == reviewRequestedTemplate &&
      d.type == NoticeDestinationType.order) {
    return '/orders/$id/review';
  }
  return switch (d.type) {
    NoticeDestinationType.order => '/orders/$id',
    NoticeDestinationType.delivery => '/deliveries/$id',
    NoticeDestinationType.claim ||
    NoticeDestinationType.refund => '/claims/$id',
    NoticeDestinationType.inquiry => '/support/inquiries/$id',
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
