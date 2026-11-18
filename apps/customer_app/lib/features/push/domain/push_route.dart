import '../../notifications/domain/notifications.dart';

/// 푸시를 눌렀을 때 갈 앱 경로 — 알림함에서 그 알림을 누른 것과 같게(백엔드 요청 2026-11-17 customer-push-fcm).
///
/// 푸시 `data`(문자열): `notificationId`·`templateKey`·`destinationType`(ORDER·REFUND …)·`destinationRef`.
/// - 목적지가 앱 화면이면 그 화면([noticeRoute] — REFUND 는 클레임, ORDER 는 주문 상세).
/// - 목적지가 없거나 모르는 값이면 그 알림 상세, `notificationId` 도 없으면 알림함.
String pushRoute(Map<String, String> data) {
  final destination = NoticeDestination(
    type: _destinationType(data['destinationType']),
    ref: data['destinationRef'],
  );
  if (noticeRoute(destination, templateKey: data['templateKey'])
      case final route?) {
    return route;
  }
  final id = data['notificationId'];
  if (id != null && id.isNotEmpty) {
    return '/notifications/${Uri.encodeComponent(id)}';
  }
  return '/notifications';
}

/// 계약 `Destination.type` 문자열 → 앱 목적지. 모르는 값은 null(이동하지 않는다).
NoticeDestinationType? _destinationType(String? v) => switch (v) {
  'ORDER' => NoticeDestinationType.order,
  'DELIVERY' => NoticeDestinationType.delivery,
  'CLAIM' => NoticeDestinationType.claim,
  'REFUND' => NoticeDestinationType.refund,
  'INQUIRY' => NoticeDestinationType.inquiry,
  'NOTICE' => NoticeDestinationType.notice,
  _ => null,
};
