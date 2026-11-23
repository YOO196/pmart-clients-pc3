import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../domain/claims.dart';
import 'claims_controller.dart';
import 'claims_screens.dart' show ClaimTypeChip, claimStateText;

/// 마이 "취소·반품 내역"(claim 0.6.0 `GET /claims`, BR-33). 최근 순, 끝 가까이서 다음 쪽.
/// 초안 08 목록 B(회색 바탕 흰 카드 + 월별 머리) + D(빈 상태·다음 쪽 실패). 카드를 누르면 클레임 상세.
class MyClaimsScreen extends ConsumerWidget {
  const MyClaimsScreen({super.key});

  /// 남은 줄이 이만큼일 때 다음 쪽을 미리 부른다.
  static const autoLoadAhead = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final value = ref.watch(myClaimsProvider);
    final empty = value.value?.items.isEmpty ?? false;
    return Scaffold(
      backgroundColor: empty ? null : scheme.surfaceContainer,
      appBar: AppBar(title: Text(l10n.myClaimsTitle)),
      body: UiStateView<MyClaimsState>(
        loading: (_) => const PmartListSkeleton(),
        state: uiStateOf(value, isEmpty: (s) => s.items.isEmpty),
        onRetry: () => ref.invalidate(myClaimsProvider),
        empty: (_) => const _ClaimsEmpty(),
        ready: (context, list) {
          // 월별 머리: 접수 시각(서울)이 바뀌는 자리에. 접수 시각이 없으면 머리 없이 앞 묶음에 붙인다.
          String? monthOf(ClaimSummaryView c) => switch (c.openedAt) {
            final t? => DateFormat.yMMMM('ko').format(toSeoulWallClock(t)),
            null => null,
          };
          return ListView.builder(
            key: const ValueKey('my-claims-list'),
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: list.items.length + (list.hasMore ? 1 : 0),
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
              final c = list.items[i];
              final month = monthOf(c);
              final head =
                  month != null &&
                  (i == 0 || monthOf(list.items[i - 1]) != month);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (head)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                      child: Text(
                        month,
                        key: ValueKey('my-claims-month-$i'),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  _ClaimCard(claim: c),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// 초안 08 목록 B 카드: 종류 칩 · 접수 날짜 · ›, 굵은 상태 문장, 아래 환불(선 + "환불 완료 · 금액")
/// 또는 할 일·실패 분홍 띠. 철회·거절·반품 취소는 상태 문장을 회색으로.
class _ClaimCard extends StatelessWidget {
  const _ClaimCard({required this.claim});

  final ClaimSummaryView claim;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = claim;
    final refund = c.refund;
    final ended =
        c.state == ClaimState.withdrawn ||
        c.state == ClaimState.rejected ||
        c.state == ClaimState.cancelled;
    Widget band(String text, {String? action, Key? key}) => Container(
      key: key,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13.5,
                color: scheme.onTertiaryContainer,
              ),
            ),
          ),
          if (action != null)
            Text(
              '$action ›',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: scheme.tertiary,
              ),
            ),
        ],
      ),
    );
    Widget refundRow(String label, int amount, {required bool highlight}) =>
        Column(
          key: ValueKey('my-claim-refund-${c.claimId}'),
          children: [
            const SizedBox(height: 12),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                ),
                const Spacer(),
                Text(
                  formatKrw(amount),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: highlight ? scheme.primary : scheme.onSurface,
                  ),
                ),
              ],
            ),
          ],
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: ValueKey('my-claim-${c.claimId}'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/claims/${c.claimId}'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ClaimTypeChip(type: c.type),
                    const SizedBox(width: 8),
                    if (c.openedAt case final t?)
                      Text(
                        l10n.claimOpenedOn(
                          DateFormat(
                            'M.d(E)',
                            'ko',
                          ).format(toSeoulWallClock(t)),
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    const Spacer(),
                    PmartLineIcon(
                      PmartLineIcons.chevronRight,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  claimStateText(l10n, c.state, type: c.type),
                  key: ValueKey('my-claim-state-${c.claimId}'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: ended ? scheme.onSurfaceVariant : scheme.onSurface,
                  ),
                ),
                // 할 일(회수비 결제)·실패는 분홍 띠, 환불은 선 아래 금액(서버 값).
                if (c.state == ClaimState.feePending)
                  band(
                    l10n.claimFeeBand,
                    action: l10n.claimFeePay,
                    key: ValueKey('my-claim-fee-${c.claimId}'),
                  )
                else if (refund?.state == ClaimRefundState.failed)
                  band(
                    l10n.myClaimsRefundFailed,
                    key: ValueKey('my-claim-refund-${c.claimId}'),
                  )
                else if (refund?.state == ClaimRefundState.inProgress)
                  refundRow(
                    l10n.claimRefundInProgressLabel,
                    refund!.requestedAmount,
                    highlight: true,
                  )
                else if (refund?.state == ClaimRefundState.completed)
                  refundRow(
                    l10n.claimRefundDoneLabel,
                    refund!.refundedAmount,
                    highlight: false,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 초안 08 목록 D 빈 상태: 연보라 동그라미 영수증 + 제목 + 안내 + [주문내역 보기].
class _ClaimsEmpty extends StatelessWidget {
  const _ClaimsEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      key: const ValueKey('my-claims-empty'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 64),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: PmartBrand.lavender,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: PmartLineIcon(
                PmartLineIcons.receipt,
                size: 34,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              l10n.myClaimsEmpty,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.myClaimsEmptyGuide,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 14,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              key: const ValueKey('my-claims-orders'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 44),
                foregroundColor: scheme.onSurface,
                side: BorderSide(color: scheme.outlineVariant),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => context.go('/orders'),
              child: Text(l10n.myClaimsOrders),
            ),
          ],
        ),
      ),
    );
  }
}

/// 다음 쪽: 불러오는 중·실패 상자(초안 08 목록 D "다음 내역을 불러오지 못했어요" + [다시 불러오기]).
class _MoreFooter extends StatelessWidget {
  const _MoreFooter({required this.list, required this.onLoadMore});

  final MyClaimsState list;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    if (list.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final failed = list.loadMoreFailure != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: failed
            ? BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              )
            : null,
        child: Column(
          children: [
            if (failed) ...[
              Text(l10n.myClaimsLoadMoreFailed),
              const SizedBox(height: 8),
            ],
            OutlinedButton(
              key: const ValueKey('my-claims-load-more'),
              onPressed: onLoadMore,
              child: Text(failed ? l10n.myClaimsReload : l10n.loadMore),
            ),
          ],
        ),
      ),
    );
  }
}
