import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../domain/claims.dart';
import 'claims_controller.dart';
import 'claims_screens.dart' show claimStateText, claimTypeText;

/// 마이 "취소·반품 내역"(claim 0.6.0 `GET /claims`, BR-33). 최근 순, 끝 가까이서 다음 쪽.
/// 줄을 누르면 클레임 상세(`/claims/{id}` — 환불 상세 포함).
class MyClaimsScreen extends ConsumerWidget {
  const MyClaimsScreen({super.key});

  /// 남은 줄이 이만큼일 때 다음 쪽을 미리 부른다.
  static const autoLoadAhead = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(myClaimsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.myClaimsTitle)),
      body: UiStateView<MyClaimsState>(
        loading: (_) => const PmartListSkeleton(),
        state: uiStateOf(value, isEmpty: (s) => s.items.isEmpty),
        onRetry: () => ref.invalidate(myClaimsProvider),
        empty: (_) => Center(
          key: const ValueKey('my-claims-empty'),
          child: Text(l10n.myClaimsEmpty),
        ),
        ready: (context, list) => ListView.separated(
          key: const ValueKey('my-claims-list'),
          itemCount: list.items.length + (list.hasMore ? 1 : 0),
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final more = ref.read(myClaimsProvider.notifier).loadMore;
            if (i == list.items.length) {
              return _MoreFooter(list: list, onLoadMore: more);
            }
            if (i >= list.items.length - autoLoadAhead &&
                list.hasMore &&
                !list.loadingMore &&
                list.loadMoreFailure == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) => more());
            }
            return _ClaimRow(claim: list.items[i]);
          },
        ),
      ),
    );
  }
}

class _ClaimRow extends StatelessWidget {
  const _ClaimRow({required this.claim});

  final ClaimSummaryView claim;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final refund = claim.refund;
    final refundText = switch (refund?.state) {
      ClaimRefundState.inProgress => l10n.myClaimsRefundInProgress(
        formatKrw(refund!.requestedAmount),
      ),
      ClaimRefundState.completed => l10n.myClaimsRefundCompleted(
        formatKrw(refund!.refundedAmount),
      ),
      ClaimRefundState.failed => l10n.myClaimsRefundFailed,
      _ => null,
    };
    final theme = Theme.of(context);
    return ListTile(
      key: ValueKey('my-claim-${claim.claimId}'),
      title: Text(claimTypeText(l10n, claim.type)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              claimStateText(l10n, claim.state, type: claim.type),
              if (claim.openedAt case final t?)
                l10n.claimOpenedAt(formatSeoulDateTime(t)),
            ].join(' · '),
          ),
          if (refundText != null)
            Text(
              refundText,
              key: ValueKey('my-claim-refund-${claim.claimId}'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: refund?.state == ClaimRefundState.failed
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
      trailing: const PmartLineIcon(PmartLineIcons.chevronRight),
      onTap: () => context.push('/claims/${claim.claimId}'),
    );
  }
}

class _MoreFooter extends StatelessWidget {
  const _MoreFooter({required this.list, required this.onLoadMore});

  final MyClaimsState list;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (list.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          if (list.loadMoreFailure != null) Text(l10n.myClaimsLoadMoreFailed),
          OutlinedButton(
            key: const ValueKey('my-claims-load-more'),
            onPressed: onLoadMore,
            child: Text(l10n.loadMore),
          ),
        ],
      ),
    );
  }
}
