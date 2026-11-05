import 'package:dio/dio.dart';
import 'package:pmart_api_notification/pmart_api_notification.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../domain/notifications.dart';

/// 본인 알림함·수신 설정(notification-service inbox·settings 태그). 회원 토큰이 필요하다.
abstract interface class NotificationsRepository {
  /// `GET /me/notifications`. 실패는 [PmartFailure] 로 던진다(빈 목록으로 바꾸지 않는다).
  Future<NoticePage> list({String? cursor});

  /// `GET /me/notifications/{id}`. 읽음 처리 결과를 모를 때의 짝 조회이기도 하다.
  Future<InboxNotice> get(String notificationId);

  /// `POST /me/notifications/{id}/reads`. 서버가 돌려준 알림(읽음 상태)을 준다.
  /// 결과 불명은 [UnknownResultFailure] 로 던진다(호출 측이 [get] 으로 확인한다).
  Future<InboxNotice> markRead(
    String notificationId, {
    required IdempotencyKey key,
  });

  /// `GET /me/notification-settings`.
  Future<NoticeSettings> settings();

  /// `POST /me/notification-setting-changes`. 결과 불명은 같은 [key] 재전송·[settingChange] 짝 조회로 해소한다.
  Future<SettingChangeOutcome> changeSettings(
    List<NoticeSettingChange> changes, {
    int? expectedVersion,
    required IdempotencyKey key,
  });

  /// `GET /me/notification-setting-changes/{requestId}`.
  Future<SettingChangeOutcome> settingChange(String requestId);
}

final class ApiNotificationsRepository implements NotificationsRepository {
  ApiNotificationsRepository(Dio dio)
    : _inbox = api.PmartApiNotification(dio: dio).getInboxApi(),
      _settings = api.PmartApiNotification(dio: dio).getSettingsApi();

  final api.InboxApi _inbox;
  final api.SettingsApi _settings;

  @override
  Future<NoticePage> list({String? cursor}) async {
    final res = await pmartGuard(
      () => _inbox.listMyNotifications(cursor: cursor),
    );
    final body =
        res.data ?? (throw const ContractViolationFailure('알림함 본문 없음'));
    return NoticePage(
      items: [
        for (final n in body.items ?? const <api.Notification>[])
          noticeFromContract(n),
      ],
      unreadCount: body.unreadCount,
      nextCursor: switch (body.page?.nextCursor) {
        final c? when c.isNotEmpty => c,
        _ => null,
      },
    );
  }

  @override
  Future<InboxNotice> get(String notificationId) async {
    final res = await pmartGuard(
      () => _inbox.getMyNotification(notificationId: notificationId),
    );
    return noticeFromContract(
      res.data ?? (throw const ContractViolationFailure('알림 본문 없음')),
    );
  }

  @override
  Future<InboxNotice> markRead(
    String notificationId, {
    required IdempotencyKey key,
  }) async {
    final res = await pmartGuard(
      () => _inbox.markNotificationRead(
        notificationId: notificationId,
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        extra: commandOptions(key).extra,
      ),
    );
    // 200 인데 본문이 없으면 반영 여부를 본문으로 확인할 수 없다 → 짝 조회로.
    return noticeFromContract(
      res.data ?? (throw UnknownResultFailure(requestId: key.value)),
    );
  }

  @override
  Future<NoticeSettings> settings() async {
    final res = await pmartGuard(() => _settings.getMyNotificationSettings());
    return settingsFromContract(
      res.data ?? (throw const ContractViolationFailure('알림 설정 본문 없음')),
    );
  }

  @override
  Future<SettingChangeOutcome> changeSettings(
    List<NoticeSettingChange> changes, {
    int? expectedVersion,
    required IdempotencyKey key,
  }) async {
    try {
      final res = await pmartGuard(
        () => _settings.changeMyNotificationSettings(
          idempotencyKey: key.value,
          xSourceSystem: sourceSystem,
          xExpectedVersion: expectedVersion,
          changeMyNotificationSettingsRequest:
              api.ChangeMyNotificationSettingsRequest(
                changes: [
                  for (final c in changes)
                    api.ChangeMyNotificationSettingsRequestChangesInner(
                      category: categoryToContract(c.category),
                      channel: channelToContract(c.channel),
                      enabled: c.enabled,
                    ),
                ],
              ),
          extra: commandOptions(key, expectedVersion: expectedVersion).extra,
        ),
      );
      return settingChangeFromContract(res.data);
    } on PmartFailure catch (f) {
      return settingChangeFailure(f);
    }
  }

  @override
  Future<SettingChangeOutcome> settingChange(String requestId) async {
    final res = await pmartGuard(
      () => _settings.getMyNotificationSettingChange(requestId: requestId),
    );
    return settingChangeFromContract(res.data);
  }
}

SettingChangeOutcome settingChangeFromContract(
  api.ChangeMyNotificationSettings200Response? r,
) => switch (r?.status) {
  api.ChangeMyNotificationSettings200ResponseStatusEnum.APPLIED =>
    const SettingChangeApplied(),
  api.ChangeMyNotificationSettings200ResponseStatusEnum.ACCEPTED =>
    SettingChangePending(r!.requestId),
  api.ChangeMyNotificationSettings200ResponseStatusEnum.REJECTED =>
    SettingChangeRejected(r!.nextAction ?? ProblemCode.domainRejected),
  _ => const SettingChangeUnknown(),
};

/// 501 은 "아직 지원하지 않음"이 확정된 응답이다(변경 요청의 5xx 라도 결과 불명으로 두지 않는다).
SettingChangeOutcome settingChangeFailure(PmartFailure f) => switch (f) {
  UnknownResultFailure(:final httpStatus, :final problem)
      when httpStatus == 501 ||
          problem?.status == 501 ||
          problem?.code == ProblemCode.unsupportedAction =>
    const SettingChangeRejected(ProblemCode.unsupportedAction),
  ProblemFailure(:final problem) => SettingChangeRejected(problem.code),
  _ => const SettingChangeUnknown(),
};

InboxNotice noticeFromContract(api.Notification n) => InboxNotice(
  notificationId: n.notificationId,
  category: categoryFromContract(n.category),
  title: n.title,
  body: switch (n.body) {
    final b? when b.trim().isNotEmpty => b,
    _ => null,
  },
  destination: switch (n.destination) {
    final d? => NoticeDestination(
      type: switch (d.type) {
        api.DestinationTypeEnum.ORDER => NoticeDestinationType.order,
        api.DestinationTypeEnum.DELIVERY => NoticeDestinationType.delivery,
        api.DestinationTypeEnum.CLAIM => NoticeDestinationType.claim,
        api.DestinationTypeEnum.REFUND => NoticeDestinationType.refund,
        api.DestinationTypeEnum.DISPATCH_OFFER =>
          NoticeDestinationType.dispatchOffer,
        api.DestinationTypeEnum.CASE => NoticeDestinationType.caseFile,
        api.DestinationTypeEnum.NOTICE => NoticeDestinationType.notice,
        api.DestinationTypeEnum.NONE => NoticeDestinationType.none,
        null => null,
      },
      ref: d.ref,
    ),
    null => null,
  },
  read: n.state == api.NotificationStateEnum.NOTICE_READ,
  createdAt: n.createdAt,
  readAt: n.readAt,
);

NoticeSettings settingsFromContract(
  api.NotificationSettings s,
) => NoticeSettings(
  version: s.version,
  items: [
    for (final i in s.items ?? const <api.NotificationSettingsItemsInner>[])
      NoticeSettingItem(
        category: categoryFromContract(
          i.category ??
              (throw const ContractViolationFailure('설정 category 없음')),
        ),
        channel: channelFromContract(
          i.channel ?? (throw const ContractViolationFailure('설정 channel 없음')),
        ),
        enabled:
            i.enabled ??
            (throw const ContractViolationFailure('설정 enabled 없음')),
        locked: i.locked ?? false,
      ),
  ],
  marketingConsent: switch (s.marketingConsent) {
    api.NotificationSettingsMarketingConsentEnum.AGREED =>
      MarketingConsent.agreed,
    api.NotificationSettingsMarketingConsentEnum.WITHDRAWN =>
      MarketingConsent.withdrawn,
    api.NotificationSettingsMarketingConsentEnum.UNKNOWN =>
      MarketingConsent.unknown,
    null => null,
  },
  osPermission: switch (s.osPermission) {
    api.NotificationSettingsOsPermissionEnum.GRANTED => OsPermission.granted,
    api.NotificationSettingsOsPermissionEnum.DENIED => OsPermission.denied,
    api.NotificationSettingsOsPermissionEnum.UNKNOWN => OsPermission.unknown,
    null => null,
  },
);

NoticeCategory categoryFromContract(api.Category c) => switch (c) {
  api.Category.ORDER => NoticeCategory.order,
  api.Category.PAYMENT => NoticeCategory.payment,
  api.Category.DELIVERY => NoticeCategory.delivery,
  api.Category.CLAIM => NoticeCategory.claim,
  api.Category.REFUND => NoticeCategory.refund,
  api.Category.DISPATCH => NoticeCategory.dispatch,
  api.Category.CASE => NoticeCategory.caseFile,
  api.Category.MARKETING => NoticeCategory.marketing,
  api.Category.SYSTEM => NoticeCategory.system,
};

api.Category categoryToContract(NoticeCategory c) => switch (c) {
  NoticeCategory.order => api.Category.ORDER,
  NoticeCategory.payment => api.Category.PAYMENT,
  NoticeCategory.delivery => api.Category.DELIVERY,
  NoticeCategory.claim => api.Category.CLAIM,
  NoticeCategory.refund => api.Category.REFUND,
  NoticeCategory.dispatch => api.Category.DISPATCH,
  NoticeCategory.caseFile => api.Category.CASE,
  NoticeCategory.marketing => api.Category.MARKETING,
  NoticeCategory.system => api.Category.SYSTEM,
};

NoticeChannel channelFromContract(api.Channel c) => switch (c) {
  api.Channel.APP_PUSH => NoticeChannel.appPush,
  api.Channel.IN_APP => NoticeChannel.inApp,
  api.Channel.KAKAO_ALIMTALK => NoticeChannel.kakaoAlimtalk,
  api.Channel.SMS => NoticeChannel.sms,
};

api.Channel channelToContract(NoticeChannel c) => switch (c) {
  NoticeChannel.appPush => api.Channel.APP_PUSH,
  NoticeChannel.inApp => api.Channel.IN_APP,
  NoticeChannel.kakaoAlimtalk => api.Channel.KAKAO_ALIMTALK,
  NoticeChannel.sms => api.Channel.SMS,
};
