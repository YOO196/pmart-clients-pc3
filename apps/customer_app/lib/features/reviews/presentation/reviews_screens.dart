import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../../address/presentation/address_screens.dart' show LoginRequired;
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../catalog/presentation/catalog_providers.dart'
    show productDetailProvider;
import '../../claims/presentation/claims_controller.dart'
    show CommandDone, CommandOutcome, CommandRejected, CommandUnknown;
import '../domain/reviews.dart';
import 'reviews_controller.dart';

/// 별점 표시(읽기 전용).
class ReviewStars extends StatelessWidget {
  const ReviewStars({super.key, required this.rating, this.size = 16});

  final int rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.reviewStar(rating),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= reviewRatingMax; i++)
            Icon(
              i <= rating ? Icons.star : Icons.star_border,
              size: size,
              color: Theme.of(context).colorScheme.primary,
            ),
        ],
      ),
    );
  }
}

/// 상품 이름. 주문 당시 사본([title])이 있으면 그것을, 없으면 상품 정보를 조회한다. 실패는 실패 문구로 보인다.
class _ProductName extends ConsumerWidget {
  const _ProductName({this.productId, this.title, this.style});

  final String? productId;
  final String? title;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (title case final t?) return Text(t, style: style);
    final id = productId;
    if (id == null) return Text(l10n.reviewProductFailed, style: style);
    return Text(switch (ref.watch(productDetailProvider(id))) {
      AsyncData(:final value) => value.name,
      AsyncError() => l10n.reviewProductFailed,
      _ => l10n.reviewProductLoading,
    }, style: style);
  }
}

Future<void> openReviewWrite(BuildContext context, ReviewTarget target) =>
    context.push('/reviews/write', extra: target);

/// 작성·등록 뒤 다시 읽어야 하는 목록들.
void invalidateReviewLists(WidgetRef ref, ReviewTarget target) {
  ref.invalidate(writableReviewsProvider);
  ref.invalidate(myReviewsProvider);
  ref.invalidate(orderReviewEligibilitiesProvider(target.orderId));
  if (target.productId case final p?) {
    ref.invalidate(productReviewsProvider(p));
  }
}

/// SCR-REVIEW-LIST-001. 리뷰 쓰기(작성 가능 품목) / 내가 쓴 리뷰. 정상 0건과 조회 실패를 구분한다.
class ReviewManageScreen extends ConsumerWidget {
  const ReviewManageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final member = ref.watch(sessionProvider) is MemberSession;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.reviewManageTitle),
          bottom: member
              ? TabBar(
                  tabs: [
                    Tab(
                      key: const ValueKey('review-tab-write'),
                      text: l10n.reviewTabWrite,
                    ),
                    Tab(
                      key: const ValueKey('review-tab-mine'),
                      text: l10n.reviewTabMine,
                    ),
                  ],
                )
              : null,
        ),
        // 비회원은 조회하지 않고 로그인 안내만 보인다.
        body: member
            ? const TabBarView(children: [_WritableTab(), _MineTab()])
            : LoginRequired(message: l10n.reviewLoginNeeded),
      ),
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.list, required this.onLoadMore});

  final PagedList<Object?> list;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!list.hasMore && list.loadMoreFailure == null) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        if (list.loadMoreFailure != null)
          Text(
            l10n.reviewLoadMoreFailed,
            key: const ValueKey('review-load-more-failed'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (list.hasMore)
          TextButton(
            key: const ValueKey('review-load-more'),
            onPressed: list.loadingMore ? null : onLoadMore,
            child: Text(l10n.loadMore),
          ),
      ],
    );
  }
}

class _WritableTab extends ConsumerWidget {
  const _WritableTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(writableReviewsProvider);
    return UiStateView<PagedList<ReviewEligibility>?>(
      state: uiStateOf(value, isEmpty: (p) => p == null || p.items.isEmpty),
      onRetry: () => ref.invalidate(writableReviewsProvider),
      empty: (_) => Center(
        key: const ValueKey('review-writable-empty'),
        child: Text(l10n.reviewWritableEmpty),
      ),
      ready: (context, list) => RefreshIndicator(
        onRefresh: () => ref.refresh(writableReviewsProvider.future),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final e in list!.items) _WritableCard(eligibility: e),
            _LoadMoreFooter(
              list: list,
              onLoadMore: () =>
                  ref.read(writableReviewsProvider.notifier).loadMore(),
            ),
          ],
        ),
      ),
    );
  }
}

/// 작성 가능 품목 카드. 별을 누르면 그 별점으로 작성 화면을 연다(레퍼런스의 흐름).
class _WritableCard extends ConsumerWidget {
  const _WritableCard({required this.eligibility});

  final ReviewEligibility eligibility;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final e = eligibility;
    Future<void> open([int? rating]) async {
      final target = ReviewTarget.of(e, initialRating: rating);
      await openReviewWrite(context, target);
    }

    return Card(
      key: ValueKey('review-writable-${e.orderLineId}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProductName(
              productId: e.productId,
              style: theme.textTheme.titleMedium,
            ),
            Text(
              [
                if (e.deliveredAt case final t?)
                  l10n.reviewDeliveredAt(formatSeoulDateTime(t)),
                // 기한은 서버 eligibleUntil 을 그대로 보인다(남은 일수를 앱이 세지 않는다).
                if (e.eligibleUntil case final t?)
                  l10n.reviewDeadline(formatSeoulDateTime(t)),
              ].join(' · '),
              key: ValueKey('review-deadline-${e.orderLineId}'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 1; i <= reviewRatingMax; i++)
                  IconButton(
                    key: ValueKey('review-quick-star-${e.orderLineId}-$i'),
                    tooltip: l10n.reviewStar(i),
                    icon: const Icon(Icons.star_border),
                    onPressed: () => open(i),
                  ),
                const Spacer(),
                TextButton(
                  key: ValueKey('review-write-${e.orderLineId}'),
                  onPressed: () => open(),
                  child: Text(l10n.reviewWrite),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MineTab extends ConsumerWidget {
  const _MineTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(myReviewsProvider);
    return UiStateView<PagedList<ReviewEligibility>?>(
      state: uiStateOf(value, isEmpty: (p) => p == null || p.items.isEmpty),
      onRetry: () => ref.invalidate(myReviewsProvider),
      empty: (_) => Center(
        key: const ValueKey('review-mine-empty'),
        child: Text(l10n.reviewMineEmpty),
      ),
      ready: (context, list) => RefreshIndicator(
        onRefresh: () => ref.refresh(myReviewsProvider.future),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final e in list!.items) _MyReviewCard(eligibility: e),
            _LoadMoreFooter(
              list: list,
              onLoadMore: () => ref.read(myReviewsProvider.notifier).loadMore(),
            ),
          ],
        ),
      ),
    );
  }
}

String reviewStateText(AppLocalizations l10n, ReviewState s) => switch (s) {
  ReviewState.published => l10n.reviewStatePublished,
  ReviewState.submitPending => l10n.reviewStatePending,
  ReviewState.locked => l10n.reviewStateLocked,
  _ => l10n.reviewStateOther,
};

class _MyReviewCard extends ConsumerWidget {
  const _MyReviewCard({required this.eligibility});

  final ReviewEligibility eligibility;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final id = eligibility.reviewId!;
    final provider = reviewProvider(id);
    final value = ref.watch(provider);
    return Card(
      key: ValueKey('review-mine-$id'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProductName(
              productId: eligibility.productId,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            switch (value) {
              AsyncData(value: final r) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ReviewStars(rating: r.rating),
                      const SizedBox(width: 8),
                      Text(
                        reviewStateText(l10n, r.state),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  Text(
                    l10n.reviewWrittenAt(formatSeoulDateTime(r.createdAt)),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (r.text case final t? when t.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(t),
                    ),
                ],
              ),
              AsyncError() => Row(
                key: ValueKey('review-mine-failed-$id'),
                children: [
                  Expanded(
                    child: Text(
                      l10n.reviewLoadFailed,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(provider),
                    child: Text(l10n.reviewRetry),
                  ),
                ],
              ),
              _ => const LinearProgressIndicator(),
            },
          ],
        ),
      ),
    );
  }
}

/// SCR-REVIEW-EDIT-001(작성). 별점 → 본문(계약 최대 1,000자). 사진은 업로드 API 가 없어(BR-07) 받지 않는다.
/// 등록 결과는 서버 응답으로만 보인다: 등록됨 / 거절(코드별 안내) / 확인 중(같은 키로만 다시 확인).
class ReviewWriteScreen extends ConsumerStatefulWidget {
  const ReviewWriteScreen({super.key, required this.target});

  final ReviewTarget target;

  @override
  ConsumerState<ReviewWriteScreen> createState() => _ReviewWriteScreenState();
}

class _ReviewWriteScreenState extends ConsumerState<ReviewWriteScreen> {
  late final ReviewSubmitter _submitter = ReviewSubmitter(
    ref.read(reviewsRepositoryProvider),
    widget.target,
  );
  final _text = TextEditingController();
  late int? _rating = widget.target.initialRating;
  bool _busy = false;
  CommandOutcome<ReviewView>? _outcome;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final rating = _rating;
    if (rating == null || _busy) return;
    setState(() => _busy = true);
    final text = _text.text.trim();
    final outcome = await _submitter.submit(
      rating: rating,
      text: text.isEmpty ? null : text,
    );
    if (!mounted) return;
    if (outcome is CommandDone<ReviewView>) {
      invalidateReviewLists(ref, widget.target);
    }
    setState(() {
      _busy = false;
      _outcome = outcome;
    });
  }

  String _rejectText(AppLocalizations l10n, String code) => switch (code) {
    ReviewProblemCode.notEligible => l10n.reviewRejectedNotEligible,
    ReviewProblemCode.eligibilityExpired => l10n.reviewRejectedExpired,
    ReviewProblemCode.alreadyReviewed => l10n.reviewRejectedAlready,
    ReviewProblemCode.rewriteAfterDeleteForbidden => l10n.reviewRejectedDeleted,
    _ => l10n.reviewRejected,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final member = ref.watch(sessionProvider) is MemberSession;
    final t = widget.target;
    final outcome = _outcome;
    if (!member) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.reviewWrite)),
        body: LoginRequired(message: l10n.reviewLoginNeeded),
      );
    }
    if (outcome case CommandDone(value: final r)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.reviewWrite)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  r.state == ReviewState.submitPending
                      ? l10n.reviewSubmitPending
                      : l10n.reviewPublished,
                  key: const ValueKey('review-result-done'),
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                ReviewStars(rating: r.rating, size: 24),
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('review-result-ok'),
                  onPressed: () => context.pop(),
                  child: Text(l10n.reviewDone),
                ),
              ],
            ),
          ),
        ),
      );
    }
    // 결과를 모르는 요청을 보관 중이면 입력을 잠근다(다시 확인은 같은 키·같은 본문이어야 한다).
    final locked = _busy || _submitter.pending;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.reviewWrite),
        leading: IconButton(
          key: const ValueKey('review-close'),
          icon: const Icon(Icons.close),
          tooltip: l10n.reviewCancel,
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ProductName(
            productId: t.productId,
            title: t.title,
            style: theme.textTheme.titleMedium,
          ),
          if (t.eligibleUntil case final u?)
            Text(
              l10n.reviewDeadline(formatSeoulDateTime(u)),
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 12),
          Text(l10n.reviewRatingHint),
          Row(
            children: [
              for (var i = 1; i <= reviewRatingMax; i++)
                IconButton(
                  key: ValueKey('review-star-$i'),
                  tooltip: l10n.reviewStar(i),
                  iconSize: 36,
                  color: theme.colorScheme.primary,
                  icon: Icon(
                    i <= (_rating ?? 0) ? Icons.star : Icons.star_border,
                  ),
                  onPressed: locked ? null : () => setState(() => _rating = i),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('review-text'),
            controller: _text,
            enabled: !locked,
            minLines: 5,
            maxLines: 10,
            maxLength: reviewTextMaxLength,
            decoration: InputDecoration(
              hintText: l10n.reviewTextHint,
              border: const OutlineInputBorder(),
            ),
          ),
          Text(l10n.reviewPhotoNotReady, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          // 정책 문구: Commerce 업무 문서 15장 [확정 정책](품목당 1건, 배송완료 후 14일, 최초 등록 후 3일 수정, 삭제 후 재작성 불가).
          ExpansionTile(
            key: const ValueKey('review-policy'),
            tilePadding: EdgeInsets.zero,
            title: Text(l10n.reviewPolicyTitle),
            children: [
              for (final line in [
                l10n.reviewPolicyOnePerItem,
                l10n.reviewPolicyDeadline,
                l10n.reviewPolicyEdit,
                l10n.reviewPolicyDelete,
              ])
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('· $line', style: theme.textTheme.bodySmall),
                ),
            ],
          ),
          const SizedBox(height: 16),
          switch (outcome) {
            CommandRejected(:final code) => Text(
              _rejectText(l10n, code),
              key: const ValueKey('review-result-rejected'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
            CommandUnknown() => Row(
              key: const ValueKey('review-result-unknown'),
              children: [
                Expanded(child: Text(l10n.reviewUnknown)),
                TextButton(
                  key: const ValueKey('review-recheck'),
                  onPressed: _busy ? null : _submit,
                  child: Text(l10n.reviewRecheck),
                ),
              ],
            ),
            _ => const SizedBox.shrink(),
          },
          if (_busy)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l10n.reviewSubmitting),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => context.pop(),
                  child: Text(l10n.reviewCancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('review-submit'),
                  // 확인 중에는 새 등록을 막는다("다시 확인"만 같은 키로 보낸다).
                  onPressed: locked || _rating == null ? null : _submit,
                  child: Text(l10n.reviewSubmit),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _reviewItem(BuildContext context, AppLocalizations l10n, ReviewView r) {
  final theme = Theme.of(context);
  return Padding(
    key: ValueKey('product-review-${r.reviewId}'),
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ReviewStars(rating: r.rating),
            const SizedBox(width: 8),
            Text(
              [
                r.authorMasked ?? l10n.reviewAuthorUnknown,
                formatSeoulDateTime(r.createdAt),
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        if (r.text case final t? when t.isNotEmpty) Text(t),
      ],
    ),
  );
}

/// 상품 상세의 리뷰 미리보기(첫 묶음 앞 몇 건). 조회 실패는 "리뷰 없음"이 아니라 실패 + 다시 시도.
class ProductReviewsPreview extends ConsumerWidget {
  const ProductReviewsPreview({super.key, required this.productId});

  final String productId;

  static const previewCount = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final provider = productReviewsProvider(productId);
    final value = ref.watch(provider);
    final list = value.value;
    return Column(
      key: const ValueKey('product-reviews'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(switch (list?.reviewCount) {
          final int n => l10n.reviewSectionCount(n),
          null => l10n.reviewSectionTitle,
        }, style: theme.textTheme.titleMedium),
        switch (value) {
          AsyncError() when list == null => Row(
            key: const ValueKey('product-reviews-failed'),
            children: [
              Expanded(
                child: Text(
                  l10n.reviewLoadFailed,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
              TextButton(
                onPressed: () => ref.invalidate(provider),
                child: Text(l10n.reviewRetry),
              ),
            ],
          ),
          _ when list == null => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          ),
          _ when list.items.isEmpty => Text(
            l10n.reviewSectionEmpty,
            key: const ValueKey('product-reviews-empty'),
          ),
          _ => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in list.items.take(previewCount))
                _reviewItem(context, l10n, r),
              if (list.items.length > previewCount || list.hasMore)
                TextButton(
                  key: const ValueKey('product-reviews-all'),
                  onPressed: () => context.push('/products/$productId/reviews'),
                  child: Text(l10n.reviewSeeAll),
                ),
            ],
          ),
        },
      ],
    );
  }
}

/// 상품 리뷰 전체(`GET /products/{id}/reviews`, 커서로 더 보기).
class ProductReviewsScreen extends ConsumerWidget {
  const ProductReviewsScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final provider = productReviewsProvider(productId);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.reviewsTitle)),
      body: UiStateView<PagedList<ReviewView>>(
        state: uiStateOf(ref.watch(provider), isEmpty: (p) => p.items.isEmpty),
        onRetry: () => ref.invalidate(provider),
        empty: (_) => Center(child: Text(l10n.reviewSectionEmpty)),
        ready: (context, list) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (list.reviewCount case final n?)
              Text(
                l10n.reviewSectionCount(n),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            for (final r in list.items) _reviewItem(context, l10n, r),
            _LoadMoreFooter(
              list: list,
              onLoadMore: () => ref.read(provider.notifier).loadMore(),
            ),
          ],
        ),
      ),
    );
  }
}

/// 주문 상세의 리뷰 영역: 이 주문에서 서버가 작성 가능이라고 준 품목만 "리뷰 쓰기"를 보인다.
/// 비회원·자격 없음이면 영역을 두지 않는다. 조회 실패는 "쓸 리뷰 없음"이 아니라 실패 + 다시 시도.
class OrderReviewsSection extends ConsumerWidget {
  const OrderReviewsSection({
    super.key,
    required this.orderId,
    required this.lineTitles,
  });

  final String orderId;

  /// orderLineId → 주문 당시 상품명 사본.
  final Map<String, String> lineTitles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final provider = orderReviewEligibilitiesProvider(orderId);
    final value = ref.watch(provider);
    if (value.hasError && !value.hasValue) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Row(
          key: const ValueKey('order-reviews-failed'),
          children: [
            Expanded(
              child: Text(
                l10n.orderReviewFailed,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(provider),
              child: Text(l10n.reviewRetry),
            ),
          ],
        ),
      );
    }
    final items = [
      for (final e in value.value ?? const <ReviewEligibility>[])
        if (e.writable || e.written) e,
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('order-reviews'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(l10n.orderReviewTitle, style: theme.textTheme.titleMedium),
        for (final e in items)
          ListTile(
            key: ValueKey('order-review-${e.orderLineId}'),
            contentPadding: EdgeInsets.zero,
            title: _ProductName(
              productId: e.productId,
              title: lineTitles[e.orderLineId],
            ),
            subtitle: e.writable && e.eligibleUntil != null
                ? Text(
                    l10n.reviewDeadline(formatSeoulDateTime(e.eligibleUntil!)),
                  )
                : null,
            trailing: e.writable
                ? TextButton(
                    key: ValueKey('order-review-write-${e.orderLineId}'),
                    onPressed: () => openReviewWrite(
                      context,
                      ReviewTarget.of(e, title: lineTitles[e.orderLineId]),
                    ),
                    child: Text(l10n.reviewWrite),
                  )
                : Text(l10n.orderReviewWritten),
          ),
      ],
    );
  }
}
