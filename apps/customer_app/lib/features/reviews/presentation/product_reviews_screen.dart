import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:pmart_core/pmart_core.dart'
    show IdempotencyKey, PmartFailure, ProblemFailure, UnknownResultFailure;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/big_button_text.dart';
import '../../../shared/cart_icon_button.dart';
import '../../../shared/choice_sheet.dart';
import '../../../shared/notice.dart';
import '../../../shared/providers.dart'
    show imageOriginProvider, resolveImageUrl, withImageWidth;
import '../../../shared/ui_state_of.dart';
import '../../auth/domain/auth.dart' show MemberSession;
import '../../auth/presentation/auth_controller.dart' show sessionProvider;
import '../../catalog/presentation/product_detail_screen.dart'
    show showProductBuySheet;
import '../../catalog/presentation/product_detail_sections.dart'
    show ReviewPhotoGrid;
import '../../catalog/presentation/catalog_providers.dart'
    show productDetailProvider;
import '../../checkout/presentation/checkout_controller.dart'
    show clockProvider;
import '../../wishlist/presentation/wish_heart_button.dart';
import '../domain/reviews.dart';
import 'reviews_controller.dart';
import 'reviews_screens.dart'
    show ReviewStars, openReviewPhotoViewer, showReviewPolicyDialog;
import '../../../shared/network_image.dart';

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
  // 기본은 최신순(사용자 2026-11-21). 정렬은 늘 보낸다.
  late ReviewSort _sort;

  @override
  void initState() {
    super.initState();
    _sort = ReviewSort.newest;
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

  Future<void> _pickSort() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showChoiceSheet<ReviewSort>(
      context,
      title: l10n.sortTitle,
      closeKey: const ValueKey('review-sort-close'),
      selected: _sort,
      options: [
        for (final s in reviewSortChoices)
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

    final scheme = theme.colorScheme;
    final rowText = theme.textTheme.bodyLarge?.copyWith(fontSize: 16);
    // 사용자 레퍼런스(2026-11-25 `6. 상품리뷰 전체 보기`): "평점 4.9 ★" → 사진 2줄 격자 → 띠 →
    // "리뷰 N개 [리뷰정책 안내]" → [✓ 사진리뷰만] … [최신순 ⌄] → 리뷰들. 아래 [찜 | 구매하기] 막대.
    final average = list?.averageRating;
    final header = <Widget>[
      if (average != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16.7, 14, 16.7, 10),
          child: Row(
            children: [
              Text(
                l10n.productRatingTitle(average.toStringAsFixed(1)),
                key: const ValueKey('review-average'),
                semanticsLabel: l10n.reviewAverage(average.toStringAsFixed(1)),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                Icons.star_rounded,
                size: 20,
                color: Color(0xFFFFB300),
              ),
            ],
          ),
        ),
      ReviewPhotoGrid(productId: widget.productId, showMore: true),
      Container(height: 10, color: scheme.surfaceContainer),
      Padding(
        padding: const EdgeInsets.fromLTRB(16.7, 20, 16.7, 4),
        child: Row(
          children: [
            Text(
              switch (list?.reviewCount) {
                final int n => l10n.reviewSectionCount(n),
                null => l10n.reviewSectionTitle,
              },
              key: const ValueKey('review-count'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: scheme.surfaceContainer,
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('review-policy-open'),
                onTap: () => showReviewPolicyDialog(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  child: Text(
                    l10n.productReviewPolicyChip,
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 10, 0),
        child: Row(
          children: [
            // [✓ 사진리뷰만](레퍼런스 — 검은 네모 체크). 누를 때마다 서버 조건(withPhotoOnly)으로 다시 읽는다.
            InkWell(
              key: const ValueKey('review-filter-photo-toggle'),
              onTap: () => setState(() => _photoOnly = !_photoOnly),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IgnorePointer(
                      child: Checkbox(
                        value: _photoOnly,
                        onChanged: (_) {},
                        activeColor: scheme.onSurface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    Text(l10n.reviewPhotoOnlyCheck, style: rowText),
                  ],
                ),
              ),
            ),
            const Spacer(),
            TextButton(
              key: const ValueKey('review-sort-open'),
              onPressed: _pickSort,
              style: TextButton.styleFrom(
                foregroundColor: scheme.onSurface,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(reviewSortLabel(l10n, _sort), style: rowText),
                  const SizedBox(width: 2),
                  const PmartLineIcon(PmartLineIcons.chevronDown, size: 18),
                ],
              ),
            ),
          ],
        ),
      ),
      Divider(height: 1, color: scheme.outlineVariant),
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
        // 레퍼런스 상단 막대 높이(약 47dp).
        toolbarHeight: 47,
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
      // 아래 막대(레퍼런스): 찜 하트 + [구매하기](상품 상세와 같은 시트).
      bottomNavigationBar: switch (ref.watch(
        productDetailProvider(widget.productId),
      )) {
        AsyncData(value: final p) => Material(
          color: scheme.surface,
          shape: Border(top: BorderSide(color: scheme.outlineVariant)),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 13, 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    height: 54,
                    child: Center(
                      child: WishHeartWithCount(
                        heartKey: const ValueKey('reviews-wish'),
                        productId: p.productId,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: FilledButton(
                        key: const ValueKey('reviews-buy'),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          textStyle: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        onPressed: () => showProductBuySheet(context, p),
                        child: Text(l10n.productBuy),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _ => null,
      },
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

/// 정렬 시트(사용자 2026-11-21): 최신순(기본)·도움돼요 많은순(계약 RECOMMENDED = 도움돼요 많은 순 → 최근 등록순)·
/// 별점 높은 순·별점 낮은 순(오후에 다시 넣음 — "원래 정렬 더 많았는데").
const reviewSortChoices = [
  ReviewSort.newest,
  ReviewSort.recommended,
  ReviewSort.ratingDesc,
  ReviewSort.ratingAsc,
];

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

/// 리뷰 날짜(레퍼런스: "2026.09.24", 서울 달력).
String reviewDate(DateTime at) =>
    DateFormat('yyyy.MM.dd', 'ko').format(toSeoulWallClock(at));

/// 리뷰 카드(새 레퍼런스 "4. 상품리뷰 전체 보기 - 리뷰 목록에서 보이는 전문", 2026-11-21):
/// 작성자(서버가 가린 값)·별점, 상품 이름·옵션(회색), 사진 4칸 줄, 본문 전문, 날짜 + 오른쪽 [👍 도움돼요 N].
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
    // 같은 계정이 쓴 리뷰면 여기서 바로 고칠 수 있게 한다(사용자 2026-11-20). 못 읽었으면 단추 없이 — 목록은 그대로.
    // 내 리뷰인지 알기 전(첫 로딩)에는 도움돼요 칸을 비워 둔다 — 버튼을 그렸다가 "N명에게 도움이 됐어요"로
    // 바뀌며 카드 높이가 흔들리던 것(사용자 2026-11-21). 칸 높이는 늘 같다(_ReviewFooter 35).
    final written = ref.watch(myWrittenReviewsProvider);
    final mineKnown = written.hasValue || written.hasError;
    final mine = written.value?[r.reviewId];
    return Container(
      key: ValueKey('product-review-${r.reviewId}'),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      // 사용자 레퍼런스(2026-11-25): 프로필 동그라미 · 이름(굵게) / 노란 별 · 오늘·어제 · 오른쪽 신고하기 →
      // 큰 사진 → 본문 → 옵션 이름(회색) → [👍 도움돼요].
      padding: const EdgeInsets.fromLTRB(16.7, 18, 16.7, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 작성자 사진은 계약에 없다(BR-100 R4) — 회색 동그라미.
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainer,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: PmartLineIcon(
                  PmartLineIcons.user,
                  size: 20,
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.authorMasked ?? l10n.reviewAuthorUnknown,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Row(
                      children: [
                        ReviewStars(
                          rating: r.rating,
                          size: 16,
                          color: const Color(0xFFFFB300),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          reviewRelativeDate(l10n, r.createdAt, now),
                          key: ValueKey('product-review-date-${r.reviewId}'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 13.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (mine != null)
                TextButton(
                  key: ValueKey('product-review-edit-${r.reviewId}'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 22),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () async {
                    await context.push(
                      '/reviews/mine/${r.reviewId}',
                      extra: mine,
                    );
                    ref.invalidate(productReviewListProvider);
                    ref.invalidate(productReviewsProvider(r.productId));
                    ref.invalidate(myWrittenReviewsProvider);
                  },
                  child: Text(l10n.reviewEdit),
                )
              else if (mineKnown)
                _ReportLink(review: r, divider: false),
            ],
          ),
          if (r.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 12),
            _CardPhotos(review: r, query: query),
          ],
          if (r.text case final t? when t.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ReviewBody(text: t),
          ],
          _ReviewProductLine(review: r),
          const SizedBox(height: 12),
          SizedBox(
            height: 38,
            child: Align(
              alignment: Alignment.centerLeft,
              child: !mineKnown
                  ? const SizedBox.shrink()
                  : switch ((query, r.helpfulCount)) {
                      (final q?, final int count) =>
                        mine != null
                            ? Text(
                                l10n.reviewHelpfulMine(count),
                                key: ValueKey(
                                  'product-review-helpful-mine-${r.reviewId}',
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              )
                            : _HelpfulButton(review: r, query: q, count: count),
                      _ => const SizedBox.shrink(),
                    },
            ),
          ),
        ],
      ),
    );
  }
}

/// 작성자 + 별점(레퍼런스 이름 줄 — 별점은 우리 리뷰의 서버 값이라 옆에 작게 둔다).
class _ReviewAuthor extends StatelessWidget {
  const _ReviewAuthor({required this.review, this.fontSize = 16});
  final ReviewView review;

  /// 목록 16, 사진 후기 화면 15(레퍼런스를 재서 맞춤).
  final double fontSize;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          review.authorMasked ?? l10n.reviewAuthorUnknown,
          style: theme.textTheme.bodyLarge?.copyWith(fontSize: fontSize),
        ),
        const SizedBox(width: 8),
        ReviewStars(rating: review.rating, size: 14),
      ],
    );
  }
}

/// 상품 이름 · 옵션(회색 15). 옵션은 리뷰의 SKU → 지금 상품 옵션 이름(옵션이 2개 이상일 때만).
/// 상품을 아직 못 읽었으면 줄 없음.
class _ReviewProductLine extends ConsumerWidget {
  const _ReviewProductLine({required this.review, this.fontSize = 15.5});
  final ReviewView review;

  /// 목록 15, 사진 후기 화면 14.
  final double fontSize;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = ref.watch(productDetailProvider(review.productId)).value;
    if (p == null) return const SizedBox.shrink();
    final options = p.options;
    final option = options.length >= 2
        ? options.where((o) => o.sku == review.sku).firstOrNull?.label
        : null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        [p.name, ?option].join(' · '),
        key: option == null
            ? null
            : ValueKey('product-review-option-${review.reviewId}'),
        semanticsLabel: option == null ? null : l10n.reviewOptionLine(option),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: fontSize,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ReviewBody extends StatelessWidget {
  const _ReviewBody({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodyLarge
        ?.copyWith(fontSize: 18, height: 1.45),
  );
}

/// 날짜(회색 15) + 오른쪽 도움돼요(review 0.6.0 — 서버 값이 있을 때만. 내 리뷰는 수만, 남의 리뷰는 회원만 누른다).
class _ReviewFooter extends StatelessWidget {
  const _ReviewFooter({
    required this.review,
    required this.query,
    required this.mine,
    this.mineKnown = true,
  });
  final ReviewView review;
  final ProductReviewQuery? query;
  final bool mine;

  /// 내 리뷰인지 알아냈는지. 모르는 동안은 도움돼요 자리를 비워 둔다(높이는 같다).
  final bool mineKnown;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final grey = theme.colorScheme.onSurfaceVariant;
    final r = review;
    return SizedBox(
      height: 35,
      child: Row(
        children: [
          Text(
            reviewDate(r.createdAt),
            key: ValueKey('product-review-date-${r.reviewId}'),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              color: grey,
            ),
          ),
          // 레퍼런스(상품리뷰 전체 보기 전문) "2026.09.24 | 신고하기" — 남의 리뷰만(BR-90).
          if (mineKnown && !mine) _ReportLink(review: r),
          const Spacer(),
          if (!mineKnown)
            const SizedBox.shrink()
          else if ((query, r.helpfulCount) case (final q?, final int count))
            mine
                ? Text(
                    l10n.reviewHelpfulMine(count),
                    key: ValueKey('product-review-helpful-mine-${r.reviewId}'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      color: grey,
                    ),
                  )
                : _HelpfulButton(review: r, query: q, count: count),
        ],
      ),
    );
  }
}

/// 카드 사진: 4칸 줄(사이 2, 바깥 모서리만 둥글게). 5장이면 넷째 칸에 "+1". 누르면 "사진 후기".
class _CardPhotos extends ConsumerWidget {
  const _CardPhotos({required this.review, required this.query});
  final ReviewView review;
  final ProductReviewQuery? query;

  /// 레퍼런스: 카드 사진 한 장 약 160dp 정사각형(모서리 8). 여러 장이면 옆으로 넘긴다.
  static const _size = 160.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final origin = ref.watch(imageOriginProvider);
    final r = review;
    final urls = [for (final u in r.photoUrls) resolveImageUrl(u, origin)];
    return SizedBox(
      height: _size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) => _Photo(
          key: ValueKey('review-photo-${r.reviewId}-$i'),
          url: urls[i],
          size: _size,
          radius: 8,
          borderRadius: BorderRadius.circular(8),
          label: l10n.reviewPhotoLabel(i + 1),
          onTap: () => openReviewPhotoDetail(
            context,
            review: r,
            initial: i,
            query: query,
          ),
        ),
      ),
    );
  }
}

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
    final fg = on ? scheme.primary : scheme.onSurface;
    return Semantics(
      button: true,
      selected: on,
      child: InkWell(
        key: ValueKey('product-review-helpful-${widget.review.reviewId}'),
        borderRadius: BorderRadius.circular(17),
        onTap: _busy ? null : _tap,
        child: Container(
          height: 35,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: on ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PmartLineIcon(
                PmartLineIcons.thumbUp,
                size: 15,
                color: fg,
                strokeWidth: 1.6,
              ),
              const SizedBox(width: 5),
              Text(
                l10n.reviewHelpful(widget.count),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "사진 후기" 열기 — 그 리뷰 한 건(큰 사진·작은 사진 줄·전문·도움돼요, 아래 [♡][구매하기]).
Future<void> openReviewPhotoDetail(
  BuildContext context, {
  required ReviewView review,
  int initial = 0,
  ProductReviewQuery? query,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) =>
        ReviewPhotoDetailScreen(review: review, initial: initial, query: query),
  ),
);

/// 사진 후기(새 레퍼런스 "4. 상품리뷰 전체 보기 - 리뷰 사진을 클릭했을때", 2026-11-21).
/// 큰 사진(3:4, 옆으로 넘김·누르면 확대 보기) → 작은 사진 줄(고른 것 ✓) → 작성자·별점, 상품·옵션, 전문, 날짜·도움돼요.
/// 아래 [♡ 찜][구매하기] — 구매하기는 그 상품 상세(옵션 고르기·담기는 상세에서, 사용자 2026-11-21).
class ReviewPhotoDetailScreen extends ConsumerStatefulWidget {
  const ReviewPhotoDetailScreen({
    super.key,
    required this.review,
    this.initial = 0,
    this.query,
  });

  final ReviewView review;
  final int initial;

  /// 리뷰가 있던 목록 — 도움돼요를 누르면 그 목록 값(서버 값)으로 바뀐다. 없으면 도움돼요 없음.
  final ProductReviewQuery? query;

  @override
  ConsumerState<ReviewPhotoDetailScreen> createState() =>
      _ReviewPhotoDetailScreenState();
}

class _ReviewPhotoDetailScreenState
    extends ConsumerState<ReviewPhotoDetailScreen> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final q = widget.query;
    // 도움돼요를 누르면 목록의 값이 바뀐다 — 그 값을 따라 그린다(없으면 받은 값).
    final r =
        switch (q) {
          final q? =>
            ref
                .watch(productReviewListProvider(q))
                .value
                ?.items
                .where((e) => e.reviewId == widget.review.reviewId)
                .firstOrNull,
          null => null,
        } ??
        widget.review;
    final written = ref.watch(myWrittenReviewsProvider);
    final mine = written.value?[r.reviewId] != null;
    final mineKnown = written.hasValue || written.hasError;
    final origin = ref.watch(imageOriginProvider);
    final urls = [for (final u in r.photoUrls) resolveImageUrl(u, origin)];
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      key: const ValueKey('review-photo-detail'),
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        title: Text(
          l10n.reviewPhotoDetailTitle,
          style: theme.appBarTheme.titleTextStyle?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: PageView.builder(
              key: const ValueKey('review-photo-detail-pages'),
              controller: _pages,
              itemCount: urls.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => _Photo(
                key: ValueKey('review-photo-detail-$i'),
                url: urls[i],
                size: width,
                height: width * 4 / 3,
                radius: 0,
                label: l10n.reviewPhotoLabel(i + 1),
                onTap: () => openReviewPhotoViewer(context, urls, initial: i),
              ),
            ),
          ),
          if (urls.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  for (var i = 0; i < urls.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    _Photo(
                      key: ValueKey('review-photo-detail-thumb-$i'),
                      url: urls[i],
                      size: 38,
                      radius: 3,
                      label: l10n.reviewPhotoLabel(i + 1),
                      selected: i == _index,
                      onTap: () => _pages.jumpToPage(i),
                    ),
                  ],
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ReviewAuthor(review: r, fontSize: 15),
                _ReviewProductLine(review: r, fontSize: 14),
                if (r.text case final t? when t.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _ReviewBody(text: t),
                ],
                const SizedBox(height: 14),
                _ReviewFooter(
                  review: r,
                  query: q,
                  mine: mine,
                  mineKnown: mineKnown,
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Center(
                  child: WishHeartButton(
                    key: const ValueKey('review-photo-detail-wish'),
                    productId: r.productId,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: BigButtonText(
                  child: FilledButton(
                    key: const ValueKey('review-photo-detail-buy'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: () {
                      final router = GoRouter.of(context);
                      Navigator.of(context).pop();
                      router.push(
                        '/products/${Uri.encodeComponent(r.productId)}',
                      );
                    },
                    child: Text(l10n.reviewBuy),
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

/// 사진리뷰 모아보기 — 사진 리뷰만 목록의 사진을 3칸 격자로(끝에 닿으면 다음 쪽). 누르면 그 리뷰의 "사진 후기".
class ReviewPhotosScreen extends ConsumerWidget {
  const ReviewPhotosScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final query = (
      productId: productId,
      sort: ReviewSort.newest,
      photoOnly: true,
      sku: null,
    );
    final provider = productReviewListProvider(query);
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
          final photos = [
            for (final r in list.items)
              for (final (i, u) in r.photoUrls.indexed)
                (review: r, index: i, url: resolveImageUrl(u, origin)),
          ];
          final notifier = ref.read(provider.notifier);
          return GridView.builder(
            key: const ValueKey('review-photos-grid'),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: photos.length,
            itemBuilder: (context, i) {
              if (i >= photos.length - 6 &&
                  list.hasMore &&
                  !list.loadingMore &&
                  list.loadMoreFailure == null) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => notifier.loadMore(),
                );
              }
              final p = photos[i];
              return LayoutBuilder(
                builder: (context, c) => _Photo(
                  key: ValueKey('review-photos-grid-$i'),
                  url: p.url,
                  size: c.maxWidth,
                  radius: 0,
                  label: l10n.reviewPhotoLabel(i + 1),
                  onTap: () => openReviewPhotoDetail(
                    context,
                    review: p.review,
                    initial: p.index,
                    query: query,
                  ),
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
    this.height,
    this.borderRadius,
    this.selected = false,
    this.onTap,
  });

  final String? url;
  final double size;

  /// 없으면 [size] (정사각형).
  final double? height;
  final double radius;

  /// 있으면 [radius] 대신(사진 줄의 바깥 모서리만 둥글게).
  final BorderRadius? borderRadius;
  final String label;

  /// 고른 사진(어두운 막 + ✓ — 사진 후기의 작은 사진 줄).
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final h = height ?? size;
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
    final dim = Colors.black.withValues(alpha: 0.45);
    return Semantics(
      image: true,
      button: onTap != null,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: url == null ? null : onTap,
        child: ClipRRect(
          borderRadius: borderRadius ?? BorderRadius.circular(radius),
          child: SizedBox(
            width: size,
            height: h,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (url == null)
                  placeholder()
                else
                  // 축소본(?w=240/480/720)·그릴 크기로만 디코딩(요청 2026-11-20).
                  pmartNetworkImage(
                    withImageWidth(url, px)!,
                    fit: BoxFit.cover,
                    cacheWidth: px.round(),
                    errorBuilder: (_, _, _) => placeholder(),
                  ),
                if (selected)
                  ColoredBox(
                    color: dim,
                    child: const Center(
                      child: PmartLineIcon(
                        PmartLineIcons.check,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 날짜 옆 "| 신고하기"(이미 신고했으면 "| 신고함"). 비회원은 로그인 안내.
class _ReportLink extends ConsumerWidget {
  const _ReportLink({required this.review, this.divider = true});

  final ReviewView review;

  /// 앞 세로줄(날짜 옆일 때). 카드 오른쪽 위에 둘 때는 없다.
  final bool divider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final grey = theme.colorScheme.onSurfaceVariant;
    final done =
        review.reportedByMe == true ||
        ref.watch(reportedReviewsProvider).contains(review.reviewId);
    final style = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      color: grey,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (divider)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              width: 1,
              height: 12,
              color: theme.colorScheme.outlineVariant,
            ),
          ),
        if (done)
          Text(
            l10n.reviewReported,
            key: ValueKey('product-review-reported-${review.reviewId}'),
            style: style,
          )
        else
          InkWell(
            key: ValueKey('product-review-report-${review.reviewId}'),
            onTap: () {
              if (ref.read(sessionProvider) is! MemberSession) {
                ScaffoldMessenger.of(context).notice(
                  l10n.reviewReportLoginNeeded,
                  action: SnackBarAction(
                    label: l10n.loginTitle,
                    onPressed: () => context.push('/login'),
                  ),
                );
                return;
              }
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => ReviewReportSheet(reviewId: review.reviewId),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(l10n.reviewReport, style: style),
            ),
          ),
      ],
    );
  }
}

/// 리뷰 신고 시트(BR-90, 사용자 결정 2026-11-23): 사유 5가지 중 하나, 기타면 글(300자) → [신고하기].
/// 서버가 확정(APPLIED)한 뒤에만 "신고가 접수됐어요". 결과를 모르면 시트를 닫지 않고 같은 키로 다시 보낸다.
class ReviewReportSheet extends ConsumerStatefulWidget {
  const ReviewReportSheet({super.key, required this.reviewId});

  final String reviewId;

  @override
  ConsumerState<ReviewReportSheet> createState() => _ReviewReportSheetState();
}

class _ReviewReportSheetState extends ConsumerState<ReviewReportSheet> {
  ReviewReportReason? _reason;
  final _detail = TextEditingController();
  bool _busy = false;
  bool _unknown = false;
  String? _message;

  /// 한 번 고른 내용의 키 — 결과를 모를 때 같은 키로 다시. 사유·글을 바꾸면 새 키.
  IdempotencyKey? _key;

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  String _label(AppLocalizations l10n, ReviewReportReason r) => switch (r) {
    ReviewReportReason.abuse => l10n.reviewReportAbuse,
    ReviewReportReason.ad => l10n.reviewReportAd,
    ReviewReportReason.irrelevant => l10n.reviewReportIrrelevant,
    ReviewReportReason.privacy => l10n.reviewReportPrivacy,
    ReviewReportReason.other => l10n.reviewReportOther,
  };

  bool get _canSend =>
      !_busy &&
      _reason != null &&
      (_reason != ReviewReportReason.other || _detail.text.trim().isNotEmpty);

  void _changed(VoidCallback f) => setState(() {
    f();
    if (!_unknown) _key = null;
  });

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    final reason = _reason;
    if (reason == null) return;
    final key = _key ??= IdempotencyKey.generate();
    setState(() {
      _busy = true;
      _message = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    void done(String notice) {
      ref.read(reportedReviewsProvider.notifier).add(widget.reviewId);
      navigator.pop();
      messenger.notice(notice);
    }

    try {
      await ref
          .read(reviewsRepositoryProvider)
          .report(
            widget.reviewId,
            reason: reason,
            detail: _detail.text.trim(),
            key: key,
          );
      if (!mounted) return;
      done(l10n.reviewReportDone);
    } on ProblemFailure catch (f) {
      if (!mounted) return;
      switch (f.problem.code) {
        case ReviewReportProblemCode.alreadyReported:
          done(l10n.reviewReportAlready);
        default:
          setState(() {
            _busy = false;
            _unknown = false;
            _key = null;
            _message = switch (f.problem.code) {
              ReviewReportProblemCode.ownReview => l10n.reviewReportOwn,
              ReviewReportProblemCode.notFound => l10n.reviewReportNotFound,
              _ => l10n.reviewReportFailed,
            };
          });
      }
    } on UnknownResultFailure {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _unknown = true;
        _message = l10n.reviewReportUnknown;
      });
    } on PmartFailure catch (f) {
      if (!mounted) return;
      // 보내기 전 실패(연결 등)는 다시 눌러도 같은 키 — 결과 불명일 수 있다.
      setState(() {
        _busy = false;
        _unknown = f is! ProblemFailure;
        _message = l10n.reviewReportFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locked = _busy || _unknown;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          key: const ValueKey('review-report-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.reviewReportTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.reviewReportNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (final r in ReviewReportReason.values)
              InkWell(
                key: ValueKey('review-report-${r.name}'),
                onTap: locked ? null : () => _changed(() => _reason = r),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _label(l10n, r),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: _reason == r
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (_reason == r)
                        PmartLineIcon(
                          PmartLineIcons.check,
                          size: 20,
                          color: scheme.primary,
                        ),
                    ],
                  ),
                ),
              ),
            if (_reason == ReviewReportReason.other)
              TextField(
                key: const ValueKey('review-report-detail'),
                controller: _detail,
                enabled: !locked,
                maxLength: reviewReportDetailMax,
                minLines: 2,
                maxLines: 4,
                onChanged: (_) => _changed(() {}),
                decoration: InputDecoration(
                  hintText: l10n.reviewReportDetailHint,
                ),
              ),
            if (_message case final m?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  m,
                  key: const ValueKey('review-report-message'),
                  style: TextStyle(color: scheme.error),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('review-report-send'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _unknown
                  ? (_busy ? null : _send)
                  : (_canSend ? _send : null),
              child: Text(
                _unknown ? l10n.reviewReportCheckAgain : l10n.reviewReportSend,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
