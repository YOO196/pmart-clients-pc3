import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../../address/presentation/address_screens.dart' show LoginRequired;
import '../../profile/presentation/consents_screens.dart'
    show MarketingConsentTile;
import '../../checkout/presentation/checkout_controller.dart'
    show clockProvider;
import '../../push/presentation/push_controller.dart'
    show PushStatus, pushRegistrationProvider;
import '../domain/notifications.dart';
import 'notifications_controller.dart';
import '../../../shared/notice.dart';

/// SCR-NOTICE-001. 알림함(본인만). 알림 문구는 발송 당시 사실이고, 누르면 서버가 준 최신 목적지로 간다.
/// 푸시 수신은 없다(푸시 토큰 등록 경로 없음, BR-09 — notification 0.2.0 도 앱 알림함만). 그래서 화면을 열 때와
/// 앱이 다시 앞으로 올 때 목록을 다시 읽는다(백엔드 알림 2026-11-16 notification-inbox §3).
class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  ConsumerState<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState
    extends ConsumerState<NotificationCenterScreen> {
  AppLifecycleListener? _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onResume: () => ref.invalidate(inboxProvider),
    );
  }

  @override
  void dispose() {
    _listener?.dispose();
    super.dispose();
  }

  bool _bandClosed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(inboxProvider);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      appBar: AppBar(
        title: Text(l10n.noticeTitle),
        actions: [
          IconButton(
            key: const ValueKey('notice-settings'),
            icon: const PmartLineIcon(PmartLineIcons.settings, size: 23),
            tooltip: l10n.noticeSettingsTitle,
            onPressed: () => context.push('/notifications/settings'),
          ),
        ],
      ),
      body: switch (value) {
        AsyncData(value: null) => LoginRequired(
          message: l10n.noticeLoginNeeded,
        ),
        _ => UiStateView<InboxState?>(
          loading: (_) => const PmartListSkeleton(),
          state: uiStateOf(value, isEmpty: (s) => s!.items.isEmpty),
          onRetry: () => ref.invalidate(inboxProvider),
          empty: (_) => Center(
            key: const ValueKey('notices-empty'),
            child: Text(l10n.noticeEmpty),
          ),
          ready: (context, s) => RefreshIndicator(
            onRefresh: () => ref.refresh(inboxProvider.future),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // 레퍼런스 10-1: 알림 권한이 꺼져 있으면 맨 위 흰 띠(✕ 로 닫기, 누르면 기기 설정)
                if (!_bandClosed &&
                    ref.watch(pushRegistrationProvider) == PushStatus.denied)
                  _PushOffBand(
                    onClose: () => setState(() => _bandClosed = true),
                  ),
                for (final n in s!.items)
                  _NoticeCard(
                    notice: n,
                    checking: s.checking.contains(n.notificationId),
                  ),
                _MoreFooter(state: s),
              ],
            ),
          ),
        ),
      },
    );
  }
}

class _MoreFooter extends ConsumerWidget {
  const _MoreFooter({required this.state});

  final InboxState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final more = ref.read(inboxProvider.notifier).loadMore;
    final Widget child;
    if (state.loadingMore) {
      child = const CircularProgressIndicator();
    } else if (state.moreFailed) {
      child = Column(
        key: const ValueKey('notices-more-failed'),
        children: [
          Text(l10n.noticeMoreFailed),
          TextButton(
            key: const ValueKey('notices-more-retry'),
            onPressed: more,
            child: Text(l10n.noticeRetry),
          ),
        ],
      );
    } else if (state.nextCursor != null) {
      child = OutlinedButton(
        key: const ValueKey('notices-more'),
        onPressed: more,
        child: Text(l10n.noticeMore),
      );
    } else {
      return const SizedBox(height: 16);
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(child: child),
    );
  }
}

PmartLineIcons _categoryIcon(NoticeCategory c) => switch (c) {
  NoticeCategory.order => PmartLineIcons.receipt,
  NoticeCategory.payment => PmartLineIcons.receipt,
  NoticeCategory.delivery => PmartLineIcons.scooter,
  NoticeCategory.claim => PmartLineIcons.refresh,
  NoticeCategory.refund => PmartLineIcons.refresh,
  NoticeCategory.dispatch => PmartLineIcons.scooter,
  NoticeCategory.caseFile => PmartLineIcons.headset,
  NoticeCategory.marketing => PmartLineIcons.bell,
  NoticeCategory.system => PmartLineIcons.info,
};

String noticeCategoryText(AppLocalizations l10n, NoticeCategory c) =>
    switch (c) {
      NoticeCategory.order => l10n.noticeCategoryOrder,
      NoticeCategory.payment => l10n.noticeCategoryPayment,
      NoticeCategory.delivery => l10n.noticeCategoryDelivery,
      NoticeCategory.claim => l10n.noticeCategoryClaim,
      NoticeCategory.refund => l10n.noticeCategoryRefund,
      NoticeCategory.dispatch => l10n.noticeCategoryDispatch,
      NoticeCategory.caseFile => l10n.noticeCategoryCase,
      NoticeCategory.marketing => l10n.noticeCategoryMarketing,
      NoticeCategory.system => l10n.noticeCategorySystem,
    };

String noticeChannelText(AppLocalizations l10n, NoticeChannel c) => switch (c) {
  NoticeChannel.appPush => l10n.noticeChannelAppPush,
  NoticeChannel.inApp => l10n.noticeChannelInApp,
  NoticeChannel.kakaoAlimtalk => l10n.noticeChannelKakao,
  NoticeChannel.sms => l10n.noticeChannelSms,
};

class _NoticeCard extends ConsumerWidget {
  const _NoticeCard({required this.notice, required this.checking});

  final InboxNotice notice;
  final bool checking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final n = notice;
    return Card(
      key: ValueKey('notice-${n.notificationId}'),
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      elevation: 1,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: () {
          // 읽음 처리는 이동을 막지 않는다. 결과는 목록에 서버 상태로 반영된다.
          ref.read(inboxProvider.notifier).open(n);
          context.push(
            noticeRoute(n.destination, templateKey: n.templateKey) ??
                '/notifications/${n.notificationId}',
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 16, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                child: PmartLineIcon(_categoryIcon(n.category), size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 14,
                        fontWeight: n.read
                            ? FontWeight.normal
                            : FontWeight.bold,
                      ),
                    ),
                    if (n.body case final b?)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        // 레퍼런스 10-1: 긴 본문은 세 줄 + 가운데 ⌄ 로 펼치기
                        child: _ExpandableBody(
                          key: ValueKey('notice-body-${n.notificationId}'),
                          text: b,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 13,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      [
                        noticeCategoryText(l10n, n.category),
                        // 레퍼런스 10-1: "1분 전"처럼 상대 시각(하루 넘으면 날짜)
                        relativeTimeText(
                          l10n,
                          n.createdAt,
                          ref.watch(clockProvider)(),
                        ),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    if (checking)
                      Text(
                        l10n.noticeReadChecking,
                        key: ValueKey('notice-checking-${n.notificationId}'),
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              if (!n.read)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Semantics(
                    label: l10n.noticeUnread,
                    child: Container(
                      key: ValueKey('notice-unread-${n.notificationId}'),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.tertiary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 앱에 화면이 없는 목적지(공지·환불 등)의 알림은 여기서 내용을 보인다.
class NotificationDetailScreen extends ConsumerWidget {
  const NotificationDetailScreen({super.key, required this.notificationId});

  final String notificationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final provider = noticeDetailProvider(notificationId);
    final value = ref.watch(provider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.noticeTitle)),
      body: switch (value) {
        AsyncData(value: null) => LoginRequired(
          message: l10n.noticeLoginNeeded,
        ),
        _ => UiStateView<InboxNotice?>(
          state: uiStateOf(value),
          onRetry: () => ref.invalidate(provider),
          ready: (context, n) => ListView(
            key: const ValueKey('notice-detail'),
            padding: const EdgeInsets.all(16),
            children: [
              Text(n!.title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                [
                  noticeCategoryText(l10n, n.category),
                  formatSeoulDateTime(n.createdAt),
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
              if (n.body case final b?) ...[
                const SizedBox(height: 16),
                Text(b),
              ],
              const SizedBox(height: 16),
              Text(l10n.noticeSnapshot, style: theme.textTheme.bodySmall),
              if (noticeRoute(n.destination, templateKey: n.templateKey)
                  case final route?) ...[
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('notice-go'),
                  onPressed: () => context.push(route),
                  child: Text(l10n.noticeGoDestination),
                ),
              ],
            ],
          ),
        ),
      },
    );
  }
}

/// 앱 수신 설정. 스위치는 서버가 확인한 값만 보인다(누른 순간 바뀌지 않는다).
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(noticeSettingsProvider);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: pmartLeftTitleSpacing,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        title: Text(l10n.noticeSettingsTitle),
      ),
      body: switch (value) {
        AsyncData(value: null) => LoginRequired(
          message: l10n.noticeSettingsLoginNeeded,
        ),
        _ => UiStateView<NoticeSettingsState?>(
          state: uiStateOf(value),
          onRetry: () => ref.invalidate(noticeSettingsProvider),
          ready: (context, s) => _SettingsBody(state: s!),
        ),
      },
    );
  }
}

class _SettingsBody extends ConsumerWidget {
  const _SettingsBody({required this.state});

  final NoticeSettingsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = state.settings;
    final byCategory = <NoticeCategory, List<NoticeSettingItem>>{};
    for (final i in settings.items) {
      (byCategory[i.category] ??= []).add(i);
    }
    String os(OsPermission? v) => switch (v) {
      OsPermission.granted => l10n.noticeValueGranted,
      OsPermission.denied => l10n.noticeValueDenied,
      OsPermission.unknown || null => l10n.noticeValueUnknown,
    };
    Widget groupTitle(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    Widget card(List<Widget> children) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: children),
        ),
      ),
    );
    return ListView(
      children: [
        if (byCategory.isEmpty)
          Padding(
            key: const ValueKey('settings-empty'),
            padding: const EdgeInsets.all(16),
            child: Text(l10n.noticeSettingsEmpty),
          ),
        // 레퍼런스 10 "환경설정": 회색 바탕 + 회색 묶음 제목 + 흰 둥근 카드
        for (final MapEntry(key: category, value: items)
            in byCategory.entries) ...[
          groupTitle(noticeCategoryText(l10n, category)),
          card([
            for (final item in items)
              _SettingRow(
                item: item,
                status: state.rows[settingRowKey(item.category, item.channel)],
              ),
          ]),
        ],
        groupTitle(l10n.noticeServiceGroup),
        card([
          ListTile(
            key: const ValueKey('settings-os-permission'),
            title: Text(l10n.noticeOsPermission),
            trailing: Text(os(settings.osPermission)),
          ),
          // 마케팅 동의는 customer 의 내 동의(MARKETING)로 켜고 끈다 — notification 의 값은 아직 UNKNOWN(CU-1 §3).
          const MarketingConsentTile(),
        ]),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Text(
            l10n.noticeReferenceNote,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _SettingRow extends ConsumerWidget {
  const _SettingRow({required this.item, required this.status});

  final NoticeSettingItem item;
  final SettingRowStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final id = '${item.category.name}-${item.channel.name}';
    final controller = ref.read(noticeSettingsProvider.notifier);
    final row = settingRowKey(item.category, item.channel);

    void report(SettingChangeOutcome outcome) {
      if (!context.mounted) return;
      final text = switch (outcome) {
        SettingChangeApplied() => l10n.noticeSettingApplied,
        SettingChangePending() => l10n.noticeSettingPending,
        SettingChangeUnknown() => l10n.noticeSettingUnknown,
        SettingChangeRejected(:final code) => switch (code) {
          NoticeProblemCode.transactionalCannotDisable =>
            l10n.noticeSettingLocked,
          NoticeProblemCode.channelNotApproved =>
            l10n.noticeSettingRejectedChannel,
          ProblemCode.versionConflict => l10n.noticeSettingRejectedVersion,
          ProblemCode.unsupportedAction =>
            l10n.noticeSettingRejectedUnsupported,
          _ => l10n.noticeSettingRejected,
        },
      };
      showNotice(context, text);
    }

    final Widget trailing = switch (status) {
      SettingRowStatus.sending => const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      SettingRowStatus.checking => TextButton(
        key: ValueKey('setting-recheck-$id'),
        onPressed: () async => report(await controller.recheck(row)),
        child: Text(l10n.noticeSettingRecheck),
      ),
      null => Switch(
        key: ValueKey('setting-switch-$id'),
        value: item.enabled,
        onChanged: item.locked
            ? null
            : (v) async => report(await controller.change(item, v)),
      ),
    };
    return ListTile(
      key: ValueKey('setting-$id'),
      titleTextStyle: Theme.of(context).textTheme.bodyLarge
          ?.copyWith(fontSize: 13.5),
      subtitleTextStyle: Theme.of(context).textTheme.bodySmall
          ?.copyWith(fontSize: 12),
      title: Text(noticeChannelText(l10n, item.channel)),
      subtitle: switch ((status, item.locked)) {
        (SettingRowStatus.checking, _) => Text(
          l10n.noticeSettingChecking,
          key: ValueKey('setting-checking-$id'),
        ),
        (_, true) => Text(l10n.noticeSettingLocked),
        _ => null,
      },
      trailing: trailing,
    );
  }
}

/// "방금 전·N분 전·N시간 전", 하루가 넘으면 서울 날짜·시각.
String relativeTimeText(AppLocalizations l10n, DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.isNegative || d.inMinutes < 1) return l10n.timeJustNow;
  if (d.inMinutes < 60) return l10n.timeMinutesAgo(d.inMinutes);
  if (d.inHours < 24) return l10n.timeHoursAgo(d.inHours);
  return formatSeoulDateTime(at);
}

/// "알림이 꺼져 있어요."(레퍼런스 10-1). 누르면 기기 앱 설정, ✕ 로 이번만 닫는다.
class _PushOffBand extends StatelessWidget {
  const _PushOffBand({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('notice-push-off'),
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 7),
      elevation: 1,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: () => Geolocator.openAppSettings(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.noticePushOffTitle,
                      style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.noticePushOffBody,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('notice-push-off-close'),
                tooltip: l10n.actionClose,
                icon: PmartLineIcon(
                  PmartLineIcons.close,
                  size: 20,
                  color: theme.colorScheme.outline,
                ),
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 세 줄까지 보이고, 넘치면 아래 가운데 ⌄(누르면 전부 / 다시 누르면 접기).
class _ExpandableBody extends StatefulWidget {
  const _ExpandableBody({super.key, required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_ExpandableBody> createState() => _ExpandableBodyState();
}

class _ExpandableBodyState extends State<_ExpandableBody> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        maxLines: 3,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: c.maxWidth);
      final long = painter.didExceedMaxLines;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.text,
            maxLines: _open ? null : 3,
            overflow: _open ? null : TextOverflow.ellipsis,
            style: widget.style,
          ),
          if (long)
            Center(
              child: InkResponse(
                key: const ValueKey('notice-body-toggle'),
                onTap: () => setState(() => _open = !_open),
                radius: 18,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: PmartLineIcon(
                    _open
                        ? PmartLineIcons.chevronUp
                        : PmartLineIcons.chevronDown,
                    size: 18,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
