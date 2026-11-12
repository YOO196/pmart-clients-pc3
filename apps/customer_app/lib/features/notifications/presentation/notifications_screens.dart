import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../../address/presentation/address_screens.dart' show LoginRequired;
import '../domain/notifications.dart';
import 'notifications_controller.dart';

/// SCR-NOTICE-001. 알림함(본인만). 알림 문구는 발송 당시 사실이고, 누르면 서버가 준 최신 목적지로 간다.
/// 푸시 수신은 없다(푸시 토큰 등록 경로 없음, BR-09).
class NotificationCenterScreen extends ConsumerWidget {
  const NotificationCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(inboxProvider);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      appBar: AppBar(
        title: Text(l10n.noticeTitle),
        actions: [
          IconButton(
            key: const ValueKey('notice-settings'),
            icon: const Icon(Icons.settings_outlined, size: 23),
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

IconData _categoryIcon(NoticeCategory c) => switch (c) {
  NoticeCategory.order => Icons.receipt_long_outlined,
  NoticeCategory.payment => Icons.credit_card_outlined,
  NoticeCategory.delivery => Icons.local_shipping_outlined,
  NoticeCategory.claim => Icons.assignment_return_outlined,
  NoticeCategory.refund => Icons.currency_exchange,
  NoticeCategory.dispatch => Icons.two_wheeler_outlined,
  NoticeCategory.caseFile => Icons.support_agent_outlined,
  NoticeCategory.marketing => Icons.campaign_outlined,
  NoticeCategory.system => Icons.info_outline,
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
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      elevation: 1,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: () {
          // 읽음 처리는 이동을 막지 않는다. 결과는 목록에 서버 상태로 반영된다.
          ref.read(inboxProvider.notifier).open(n);
          context.push(
            noticeRoute(n.destination) ?? '/notifications/${n.notificationId}',
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
                child: Icon(_categoryIcon(n.category), size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 14.5,
                        fontWeight: n.read
                            ? FontWeight.normal
                            : FontWeight.bold,
                      ),
                    ),
                    if (n.body case final b?)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          b,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      [
                        noticeCategoryText(l10n, n.category),
                        formatSeoulDateTime(n.createdAt),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
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
              if (noticeRoute(n.destination) case final route?) ...[
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
      appBar: AppBar(title: Text(l10n.noticeSettingsTitle)),
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
    String consent(MarketingConsent? v) => switch (v) {
      MarketingConsent.agreed => l10n.noticeValueAgreed,
      MarketingConsent.withdrawn => l10n.noticeValueWithdrawn,
      MarketingConsent.unknown || null => l10n.noticeValueUnknown,
    };
    return ListView(
      children: [
        if (byCategory.isEmpty)
          Padding(
            key: const ValueKey('settings-empty'),
            padding: const EdgeInsets.all(16),
            child: Text(l10n.noticeSettingsEmpty),
          ),
        for (final MapEntry(key: category, value: items)
            in byCategory.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              noticeCategoryText(l10n, category),
              style: theme.textTheme.titleSmall,
            ),
          ),
          for (final item in items)
            _SettingRow(
              item: item,
              status: state.rows[settingRowKey(item.category, item.channel)],
            ),
        ],
        const Divider(height: 32),
        ListTile(
          key: const ValueKey('settings-os-permission'),
          title: Text(l10n.noticeOsPermission),
          trailing: Text(os(settings.osPermission)),
        ),
        ListTile(
          key: const ValueKey('settings-marketing-consent'),
          title: Text(l10n.noticeMarketingConsent),
          trailing: Text(consent(settings.marketingConsent)),
        ),
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
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
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
