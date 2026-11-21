import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:pmart_core/pmart_core.dart' show PmartFailure, ProblemFailure;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/cart_icon_button.dart';
import '../../../shared/choice_sheet.dart';
import '../../../shared/notice.dart';
import '../../../shared/providers.dart'
    show imageOriginProvider, resolveImageUrl, withImageWidth;
import '../../../shared/ui_state_of.dart';
import '../../auth/domain/auth.dart' show MemberSession;
import '../../auth/presentation/auth_controller.dart' show sessionProvider;
import '../../catalog/domain/catalog.dart' show SaleOption;
import '../../catalog/presentation/catalog_providers.dart'
    show productDetailProvider;
import '../../checkout/presentation/checkout_controller.dart'
    show clockProvider;
import '../domain/reviews.dart';
import 'reviews_controller.dart';
import 'reviews_screens.dart'
    show ReviewStars, openReviewPhotoViewer, showReviewPolicyDialog;

/// 상품 리뷰 전체(레퍼런스 "상품리뷰 전체 보기"): 평점, 사진 리뷰 모음(2줄 + 모아보기), 리뷰 수·정책 안내,
/// 사진리뷰만·정렬(추천·최근 등록·별점 높은·별점 낮은 — 계약 sort), 옵션 필터(sku), 리뷰 카드(옵션 줄·도움돼요 — review 0.6.0).
/// 신고·프로필 그림은 계약에 없어 두지 않는다.
class ProductReviewsScreen extends ConsumerStatefulWidget {
  const ProductReviewsScreen({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<ProductReviewsScreen> createState() =>
      _ProductReviewsScreenState();
}

class _ProductReviewsScreenState extends ConsumerState<ProductReviewsScreen> {
  // 기본은 추천순(review 0.6.0 RECOMMENDED — 서버 기본은 NEWEST 라 늘 보낸다).
  late ReviewSort _sort;

  @override
  void initState() {
    super.initState();
    _sort = ReviewSort.recommended;
  }

  bool _photoOnly = false;

  /// 고른 옵션(review 0.6.0 sku). null = 옵션 전체.
  String? _sku;

  ProductReviewQuery get _query => (
    productId: widget.productId,
    sort: _sort,
    photoOnly: _photoOnly,
    sku: _sku,
  );

  Future<void> _pickOption(List<SaleOption> options) async {
    final l10n = AppLocalizations.of(context);
    // 옵션 전체는 빈 글로 나타낸다(시트 값은 null 을 고를 수 없다).
    final picked = await showChoiceSheet<String>(
      context,
      title: l10n.reviewOptionTitle,
      closeKey: const ValueKey('review-option-close'),
      selected: _sku ?? '',
      options: [
        ('', l10n.reviewOptionAll, const ValueKey('review-option-all')),
        for (final o in options)
          (o.sku, o.label ?? o.sku, ValueKey('review-option-${o.sku}')),
      ],
    );
    if (picked != null && mounted) {
      setState(() => _sku = picked.isEmpty ? null : picked);
    }
  }

  Future<void> _pickSort() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showChoiceSheet<ReviewSort>(
      context,
      title: l10n.sortTitle,
      closeKey: const ValueKey('review-sort-close'),
      selected: _sort,
      options: [
        for (final s in ReviewSort.values)
          (s, reviewSortLabel(l10n, s), ValueKey('review-sort-${s.name}')),
      ],
    );
    if (picked != null && mounted) setState(() => _sort = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final provider = productReviewListProvider(_query);
    final value = ref.watch(provider);
    final list = value.value;
    final now = ref.watch(clockProvider)();
    // 옵션 필터(review 0.6.0 sku): 옵션이 2개 이상인 상품에만.
    final options =
        ref.watch(productDetailProvider(widget.productId)).value?.options ??
        const <SaleOption>[];

    final header = <Widget>[
      if (list?.averageRating case final avg?)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(
            children: [
              Text(
                l10n.reviewAverage(avg.toStringAsFixed(1)),
                key: const ValueKey('review-average'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.star, size: 20, color: Color(0xFFFFC107)),
            ],
          ),
        ),
      _PhotoStrip(productId: widget.productId),
      Container(height: 8, color: theme.colorScheme.surfaceContainer),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Row(
          children: [
            Text(
              switch (list?.reviewCount) {
                final int n => l10n.reviewSectionCount(n),
                null => l10n.reviewSectionTitle,
              },
              key: const ValueKey('review-count'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            ActionChip(
              key: const ValueKey('review-policy-open'),
              label: Text(l10n.reviewPolicyShort),
              labelStyle: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
              backgroundColor: theme.colorScheme.surfaceContainer,
              side: BorderSide.none,
              shape: const StadiumBorder(),
              visualDensity: VisualDensity.compact,
              onPressed: () => showReviewPolicyDialog(context),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
        child: Row(
          children: [
            Checkbox(
              key: const ValueKey('review-photo-only'),
              value: _photoOnly,
              onChanged: (v) => setState(() => _photoOnly = v ?? false),
            ),
            GestureDetector(
              onTap: () => setState(() => _photoOnly = !_photoOnly),
              child: Text(
                l10n.reviewPhotoOnly,
                style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15),
              ),
            ),
            const Spacer(),
            TextButton(
              key: const ValueKey('review-sort-open'),
              onPressed: _pickSort,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurface,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    reviewSortLabel(l10n, _sort),
                    style: const TextStyle(fontSize: 15),
                  ),
                  const SizedBox(width: 2),
                  const PmartLineIcon(PmartLineIcons.chevronDown, size: 18),
                ],
              ),
            ),
          ],
        ),
      ),
      if (options.length >= 2)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              key: const ValueKey('review-option-open'),
              borderRadius: BorderRadius.circular(16),
              onTap: () => _pickOption(options),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      switch (_sku) {
                        null => l10n.reviewOptionAll,
                        final s =>
                          options.where((o) => o.sku == s).firstOrNull?.label ??
                              s,
                      },
                      key: const ValueKey('review-option-label'),
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                    ),
                    const SizedBox(width: 2),
                    const PmartLineIcon(PmartLineIcons.chevronDown, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      const Divider(height: 1),
    ];

    Widget body;
    if (list == null) {
      // 자리 표시(목록 모양)는 높이를 스스로 정하지 못한다 — 남은 높이를 그대로 준다.
      body = SliverFillRemaining(
        child: UiStateView<PagedList<ReviewView>>(
          loading: (_) => const PmartListSkeleton(rows: 3),
          state: uiStateOf(value, isEmpty: (p) => p.items.isEmpty),
          onRetry: () => ref.invalidate(provider),
          ready: (_, _) => const SizedBox.shrink(),
        ),
      );
    } else if (list.items.isEmpty) {
      body = SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          key: const ValueKey('product-reviews-empty'),
          child: Text(
            _photoOnly ? l10n.reviewPhotoOnlyEmpty : l10n.reviewSectionEmpty,
          ),
        ),
      );
    } else {
      final notifier = ref.read(provider.notifier);
      body = SliverList.builder(
        itemCount: list.items.length + 1,
        itemBuilder: (context, i) {
          // 끝에서 5개 안쪽이 그려지면 다음 쪽(서버 커서). 실패했으면 자동으로 다시 부르지 않는다(버튼으로).
          if (i >= list.items.length - 5 &&
              list.hasMore &&
              !list.loadingMore &&
              list.loadMoreFailure == null) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => notifier.loadMore(),
            );
          }
          if (i < list.items.length) {
            return ProductReviewCard(
              review: list.items[i],
              now: now,
              query: _query,
            );
          }
          if (list.loadingMore) {
            return const Padding(
              key: ValueKey('review-loading-more'),
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (list.loadMoreFailure != null) {
            return Center(
              child: TextButton(
                key: const ValueKey('review-load-more-retry'),
                onPressed: notifier.loadMore,
                child: Text(l10n.reviewRetry),
              ),
            );
          }
          return const SizedBox(height: 24);
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        title: Text(
          l10n.reviewAllTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            key: const ValueKey('review-go-home'),
            tooltip: l10n.navHome,
            icon: const PmartLineIcon(PmartLineIcons.home, size: 24),
            onPressed: () => context.go('/'),
          ),
          IconButton(
            key: const ValueKey('review-go-search'),
            tooltip: l10n.navSearch,
            icon: const PmartLineIcon(PmartLineIcons.search, size: 24),
            onPressed: () => context.go('/search'),
          ),
          const CartIconButton(),
          const SizedBox(width: 4),
        ],
      ),
      body: CustomScrollView(
        key: const ValueKey('product-reviews-list'),
        slivers: [
          SliverList.list(children: header),
          body,
        ],
      ),
    );
  }
}

String reviewSortLabel(AppLocalizations l10n, ReviewSort s) => switch (s) {
  ReviewSort.recommended => l10n.reviewSortRecommended,
  ReviewSort.newest => l10n.reviewSortNewest,
  ReviewSort.ratingDesc => l10n.reviewSortRatingDesc,
  ReviewSort.ratingAsc => l10n.reviewSortRatingAsc,
};

/// "오늘·어제·N일 전·N개월 전", 1년이 넘으면 날짜(서울 달력 기준).
String reviewRelativeDate(AppLocalizations l10n, DateTime at, DateTime now) {
  final a = toSeoulWallClock(at);
  final n = toSeoulWallClock(now);
  final days = DateTime.utc(
    n.year,
    n.month,
    n.day,
  ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
  if (days <= 0) return l10n.reviewToday;
  if (days == 1) return l10n.reviewYesterday;
  if (days < 30) return l10n.reviewDaysAgo(days);
  if (days < 365) return l10n.reviewMonthsAgo(days ~/ 30);
  return DateFormat('y.M.d', 'ko').format(a);
}

/// 리뷰 카드(레퍼런스): 작성자(서버가 가린 값)·별점·날짜, 사진(크게), 본문.
class ProductReviewCard extends ConsumerWidget {
  const ProductReviewCard({
    super.key,
    required this.review,
    required this.now,
    this.query,
  });

  final ReviewView review;
  final DateTime now;

  /// 이 카드가 있는 목록(도움돼요를 누르면 그 목록의 값을 서버 값으로 바꾼다). 없으면 도움돼요를 두지 않는다.
  final ProductReviewQuery? query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final r = review;
    final origin = ref.watch(imageOriginProvider);
    final urls = [for (final u in r.photoUrls) resolveImageUrl(u, origin)];
    // 같은 계정이 쓴 리뷰면 여기서 바로 고칠 수 있게 한다(사용자 2026-11-20). 못 읽었으면 단추 없이 — 목록은 그대로.
    final mine = ref.watch(myWrittenReviewsProvider).value?[r.reviewId];
    // 옵션 줄: 리뷰의 SKU → 지금 상품 옵션 이름(옵션이 2개 이상일 때만). 못 찾으면 줄 없음.
    final options =
        ref.watch(productDetailProvider(r.productId)).value?.options ??
        const <SaleOption>[];
    final optionLabel = options.length >= 2
        ? options.where((o) => o.sku == r.sku).firstOrNull?.label
        : null;
    return Container(
      key: ValueKey('product-review-${r.reviewId}'),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.authorMasked ?? l10n.reviewAuthorUnknown,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (mine != null)
                TextButton(
                  key: ValueKey('product-review-edit-${r.reviewId}'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                  ),
                  // 내 리뷰 화면(수정·삭제 — 고칠 수 있는지는 서버 상태·기한대로).
                  onPressed: () async {
                    await context.push(
                      '/reviews/mine/${r.reviewId}',
                      extra: mine,
                    );
                    // 고쳤거나 지웠을 수 있다 — 이 상품의 목록을 서버 기준으로 다시 읽는다.
                    ref.invalidate(productReviewListProvider);
                    ref.invalidate(productReviewsProvider(r.productId));
                    ref.invalidate(myWrittenReviewsProvider);
                  },
                  child: Text(l10n.reviewEdit),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              ReviewStars(rating: r.rating, size: 15),
              const SizedBox(width: 6),
              Text(
                reviewRelativeDate(l10n, r.createdAt, now),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (urls.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 130,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: urls.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, i) => _Photo(
                  key: ValueKey('review-photo-${r.reviewId}-$i'),
                  url: urls[i],
                  size: 130,
                  radius: 8,
                  label: l10n.reviewPhotoLabel(i + 1),
                  onTap: urls[i] == null
                      ? null
                      : () => openReviewPhotoViewer(context, urls, initial: i),
                ),
              ),
            ),
          ],
          if (optionLabel case final o?) ...[
            const SizedBox(height: 6),
            Text(
              l10n.reviewOptionLine(o),
              key: ValueKey('product-review-option-${r.reviewId}'),
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (r.text case final t? when t.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              t,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: 15,
                height: 1.45,
              ),
            ),
          ],
          // 도움돼요(review 0.6.0): 서버 값이 있을 때만. 내 리뷰는 수만, 남의 리뷰는 회원만 누른다.
          if ((query, r.helpfulCount) case (final q?, final int count)) ...[
            const SizedBox(height: 12),
            if (mine != null)
              Text(
                l10n.reviewHelpfulMine(count),
                key: ValueKey('product-review-helpful-mine-${r.reviewId}'),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              _HelpfulButton(review: r, query: q, count: count),
          ],
        ],
      ),
    );
  }
}

/// 도움돼요 버튼(review 0.6.0, BR-76). 회원만 누른다 — 비회원은 로그인 안내. 누른 상태·수는 서버가 준 값.
class _HelpfulButton extends ConsumerStatefulWidget {
  const _HelpfulButton({
    required this.review,
    required this.query,
    required this.count,
  });

  final ReviewView review;
  final ProductReviewQuery query;
  final int count;

  @override
  ConsumerState<_HelpfulButton> createState() => _HelpfulButtonState();
}

class _HelpfulButtonState extends ConsumerState<_HelpfulButton> {
  bool _busy = false;

  Future<void> _tap() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (ref.read(sessionProvider) is! MemberSession) {
      messenger.notice(
        l10n.reviewHelpfulLoginNeeded,
        action: SnackBarAction(
          label: l10n.loginTitle,
          onPressed: () => context.push('/login'),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(productReviewListProvider(widget.query).notifier)
          .toggleHelpful(widget.review.reviewId);
    } on ProblemFailure catch (f) {
      messenger.notice(switch (f.problem.code) {
        ReviewHelpfulProblemCode.ownReview => l10n.reviewHelpfulOwn,
        ReviewHelpfulProblemCode.notPublished => l10n.reviewHelpfulNotPublished,
        _ => l10n.reviewHelpfulFailed,
      });
    } on PmartFailure {
      messenger.notice(l10n.reviewHelpfulFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = widget.review.helpedByMe ?? false;
    return Semantics(
      button: true,
      selected: on,
      child: InkWell(
        key: ValueKey('product-review-helpful-${widget.review.reviewId}'),
        borderRadius: BorderRadius.circular(16),
        onTap: _busy ? null : _tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: on ? scheme.primaryContainer : null,
            border: Border.all(
              color: on ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Text(
            l10n.reviewHelpful(widget.count),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13,
              color: on ? scheme.primary : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// 사진 리뷰 모음: 사진 리뷰만(withPhotoOnly)의 첫 쪽 사진을 2줄 × 3칸 + "모아보기".
class _PhotoStrip extends ConsumerWidget {
  const _PhotoStrip({required this.productId});

  final String productId;

  static const tile = 88.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final provider = productReviewListProvider((
      productId: productId,
      sort: ReviewSort.newest,
      photoOnly: true,
      sku: null,
    ));
    final value = ref.watch(provider);
    final list = value.value;
    if (list == null) {
      if (value is AsyncError) {
        return Padding(
          key: const ValueKey('review-photos-failed'),
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.reviewPhotosFailed,
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
      return const SizedBox.shrink();
    }
    final origin = ref.watch(imageOriginProvider);
    final urls = [
      for (final r in list.items)
        for (final u in r.photoUrls) resolveImageUrl(u, origin),
    ];
    // 사진 리뷰가 없다는 서버 답 — 자리를 두지 않는다.
    if (urls.isEmpty) return const SizedBox.shrink();
    final shown = urls.take(6).toList();
    Widget cell(int i) => _Photo(
      key: ValueKey('review-strip-$i'),
      url: shown[i],
      size: tile,
      radius: 6,
      label: l10n.reviewPhotoLabel(i + 1),
      onTap: shown[i] == null
          ? null
          : () => openReviewPhotoViewer(context, urls, initial: i),
    );
    return Padding(
      key: const ValueKey('review-photo-strip'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final row in [0, 1])
                if (row * 3 < shown.length)
                  Padding(
                    padding: EdgeInsets.only(top: row == 0 ? 0 : 4),
                    child: Row(
                      children: [
                        for (var c = 0; c < 3; c++)
                          if (row * 3 + c < shown.length)
                            Padding(
                              padding: EdgeInsets.only(left: c == 0 ? 0 : 4),
                              child: cell(row * 3 + c),
                            ),
                      ],
                    ),
                  ),
            ],
          ),
          const Spacer(),
          InkWell(
            key: const ValueKey('review-photos-more'),
            customBorder: const CircleBorder(),
            onTap: () => context.push('/products/$productId/review-photos'),
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.surfaceContainer,
                  ),
                  child: const Center(
                    child: PmartLineIcon(PmartLineIcons.chevronRight, size: 22),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.reviewPhotosMore,
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 사진리뷰 모아보기 — 사진 리뷰만 목록의 사진을 3칸 격자로(끝에 닿으면 다음 쪽).
class ReviewPhotosScreen extends ConsumerWidget {
  const ReviewPhotosScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final provider = productReviewListProvider((
      productId: productId,
      sort: ReviewSort.newest,
      photoOnly: true,
      sku: null,
    ));
    final origin = ref.watch(imageOriginProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('review-photos-close'),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const PmartLineIcon(PmartLineIcons.close, size: 24),
          onPressed: () => context.pop(),
        ),
        title: Text(l10n.reviewPhotosTitle),
      ),
      body: UiStateView<PagedList<ReviewView>>(
        state: uiStateOf(ref.watch(provider), isEmpty: (p) => p.items.isEmpty),
        onRetry: () => ref.invalidate(provider),
        empty: (_) => Center(child: Text(l10n.reviewPhotoOnlyEmpty)),
        ready: (context, list) {
          final urls = [
            for (final r in list.items)
              for (final u in r.photoUrls) resolveImageUrl(u, origin),
          ];
          final notifier = ref.read(provider.notifier);
          return GridView.builder(
            key: const ValueKey('review-photos-grid'),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: urls.length,
            itemBuilder: (context, i) {
              if (i >= urls.length - 6 &&
                  list.hasMore &&
                  !list.loadingMore &&
                  list.loadMoreFailure == null) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => notifier.loadMore(),
                );
              }
              return LayoutBuilder(
                builder: (context, c) => _Photo(
                  url: urls[i],
                  size: c.maxWidth,
                  radius: 0,
                  label: l10n.reviewPhotoLabel(i + 1),
                  onTap: urls[i] == null
                      ? null
                      : () => openReviewPhotoViewer(context, urls, initial: i),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({
    super.key,
    required this.url,
    required this.size,
    required this.radius,
    required this.label,
    this.onTap,
  });

  final String? url;
  final double size;
  final double radius;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget placeholder() => ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: PmartLineIcon(
          PmartLineIcons.camera,
          size: 20,
          color: theme.colorScheme.outline,
        ),
      ),
    );
    final px = size * MediaQuery.devicePixelRatioOf(context);
    return Semantics(
      image: true,
      button: onTap != null,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: SizedBox.square(
            dimension: size,
            child: url == null
                ? placeholder()
                // 축소본(?w=240/480)·그릴 크기로만 디코딩(요청 2026-11-20).
                : Image.network(
                    withImageWidth(url, px)!,
                    fit: BoxFit.cover,
                    cacheWidth: px.round(),
                    errorBuilder: (_, _, _) => placeholder(),
                  ),
          ),
        ),
      ),
    );
  }
}
