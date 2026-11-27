import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:pmart_core/pmart_core.dart'
    show IdempotencyKey, PmartFailure, ProblemFailure, UnknownResultFailure;
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
    // 태블릿 나란히 보기 레퍼런스 "사진리뷰만" 폭 112px / 우리 127px × 16.
    final rowText = theme.textTheme.bodyLarge?.copyWith(fontSize: 14.2);
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
                // 태블릿 나란히 보기(같은 밀도) 레퍼런스 글 폭 100px / 우리 104px × 17.
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 16.3,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                Icons.star_rounded,
                size: 22.5,
                color: Color(0xFFFFB300),
              ),
            ],
          ),
        ),
      ReviewPhotoGrid(
        productId: widget.productId,
        showMore: true,
        cell: 100,
        gap: 3,
        bottom: 14,
      ),
      Container(height: 11, color: scheme.surfaceContainer),
      Padding(
        padding: const EdgeInsets.fromLTRB(16.7, 15, 16.7, 8),
        child: Row(
          children: [
            Text(
              switch (list?.reviewCount) {
                final int n => l10n.reviewSectionCount(n),
                null => l10n.reviewSectionTitle,
              },
              key: const ValueKey('review-count'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 16.5,
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
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ];
    // [사진리뷰만 … 최신순] 줄: 내리면 접혀 사라지고, 조금이라도 올리면 위 막대 아래로 다시 펼쳐진다
    // (사용자 2026-11-26 "스크롤 내리면 접히고 위로 올리면 펼쳐지게").
    final filterBar = ColoredBox(
      key: const ValueKey('review-filter-bar'),
      color: scheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.7, 4, 10, 2),
            child: Row(
              children: [
                // [✓ 사진리뷰만](레퍼런스 — 24dp 검은 네모 체크). 누를 때마다 서버 조건(withPhotoOnly)으로 다시 읽는다.
                InkWell(
                  key: const ValueKey('review-filter-photo-toggle'),
                  onTap: () => setState(() => _photoOnly = !_photoOnly),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          checked: _photoOnly,
                          child: Container(
                            key: const ValueKey('review-filter-photo-box'),
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: _photoOnly ? scheme.onSurface : null,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: _photoOnly
                                    ? scheme.onSurface
                                    : const Color(0xFFBDBDBD),
                                width: 1.5,
                              ),
                            ),
                            child: _photoOnly
                                ? PmartLineIcon(
                                    PmartLineIcons.check,
                                    size: 16,
                                    color: scheme.surface,
                                    strokeWidth: 2.2,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 9),
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
          const Divider(height: 1, color: reviewLineColor),
        ],
      ),
    );
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
            onPressed: () => context.push('/search'),
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
          SliverFloatingHeader(child: filterBar),
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

/// 리뷰 줄·도움돼요 테두리(레퍼런스 2026-11-26 — 아주 옅은 회색).
const reviewLineColor = Color(0xFFEFEFEF);

/// 리뷰 카드(사용자 레퍼런스 2026-11-26 "상품리뷰 전체 보기"):
/// 프로필 동그라미 · 이름(굵게)·재구매 / 노란 별 · 오늘·어제 · 오른쪽 옅은 신고하기 → 사진(157 정사각형, 누르면 사진만 크게)
/// → 본문 → 상품 이름·옵션(회색) → [👍 도움돼요].
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
  Widget build(BuildContext context, WidgetRef ref) => Container(
    key: ValueKey('product-review-${review.reviewId}'),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: reviewLineColor)),
    ),
    padding: const EdgeInsets.fromLTRB(16.7, 21, 16.7, 17.5),
    child: _ReviewContent(review: review, now: now, query: query),
  );
}

/// 카드·사진리뷰 상세가 같이 쓰는 리뷰 본문. [photos] 가 false 면 사진 줄을 뺀다(상세는 사진을 아래에 크게).
class _ReviewContent extends ConsumerWidget {
  const _ReviewContent({
    required this.review,
    required this.now,
    required this.query,
    this.photos = true,
  });

  final ReviewView review;
  final DateTime now;
  final ProductReviewQuery? query;
  final bool photos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final r = review;
    // 같은 계정이 쓴 리뷰면 여기서 바로 고칠 수 있게 한다(사용자 2026-11-20). 못 읽었으면 단추 없이 — 목록은 그대로.
    // 내 리뷰인지 알기 전(첫 로딩)에는 도움돼요 칸을 비워 둔다 — 버튼을 그렸다가 "N명에게 도움이 됐어요"로
    // 바뀌며 카드 높이가 흔들리던 것(사용자 2026-11-21). 칸 높이는 늘 같다(38).
    final written = ref.watch(myWrittenReviewsProvider);
    final mineKnown = written.hasValue || written.hasError;
    final mine = written.value?[r.reviewId];
    final showPhotos = photos && r.photoUrls.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 작성자 사진은 계약에 없다(BR-100 R4) — 회색 동그라미.
            Container(
              width: 36,
              height: 36,
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          r.authorMasked ?? l10n.reviewAuthorUnknown,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      // 재구매(review 0.9.0 repurchased — 서버가 true 일 때만).
                      if (r.repurchased == true) ...[
                        const SizedBox(width: 6),
                        ReviewRepurchasedTag(reviewId: r.reviewId),
                      ],
                    ],
                  ),
                  Row(
                    children: [
                      // 태블릿 레퍼런스 별 다섯 폭 126px / 우리 141px × 16.
                      ReviewStars(
                        rating: r.rating,
                        size: 14.3,
                        color: const Color(0xFFFFB300),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        reviewRelativeDate(l10n, r.createdAt, now),
                        key: ValueKey('product-review-date-${r.reviewId}'),
                        // 태블릿 레퍼런스 "어제" 높이 19px / 우리 21px × 13.5, 색 #65.
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12.2,
                          color: const Color(0xFF666666),
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
              _ReportLink(review: r),
          ],
        ),
        if (showPhotos) ...[const SizedBox(height: 10), _CardPhotos(review: r)],
        if (r.text case final t? when t.isNotEmpty) ...[
          SizedBox(height: showPhotos ? 7.5 : 14),
          _ReviewBody(text: t),
        ],
        _ReviewProductLine(review: r),
        // 레퍼런스 "B마트" 꼬리표 자리 — 우리 리뷰는 모두 바로픽 주문이라 "바로픽"(사용자 2026-11-26).
        const SizedBox(height: 9),
        const _StoreTag(),
        const SizedBox(height: 8.5),
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
    );
  }
}

/// 상품 이름 · 옵션(회색). 옵션은 리뷰의 SKU → 지금 상품 옵션 이름(옵션이 2개 이상일 때만).
/// 상품을 아직 못 읽었으면 줄 없음.
class _ReviewProductLine extends ConsumerWidget {
  const _ReviewProductLine({required this.review});
  final ReviewView review;

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
      padding: const EdgeInsets.only(top: 7),
      child: Text(
        [p.name, ?option].join(' · '),
        key: option == null
            ? null
            : ValueKey('product-review-option-${review.reviewId}'),
        semanticsLabel: option == null ? null : l10n.reviewOptionLine(option),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        // 태블릿 레퍼런스 높이 26px / 우리 29px × 15.5, 색 #5F.
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 14,
          color: const Color(0xFF5F5F5F),
        ),
      ),
    );
  }
}

/// 회색 작은 꼬리표 "바로픽"(레퍼런스 "B마트" 칸 62×30px · 글 높이 15px, 태블릿 1.875px/dp).
class _StoreTag extends StatelessWidget {
  const _StoreTag();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('review-store-tag'),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F2),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        AppLocalizations.of(context).brandName,
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF333333),
          height: 1.2,
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
        // 태블릿 레퍼런스 줄 간격 43px / 우리 49px × 17(줄 1.45 그대로).
        ?.copyWith(fontSize: 15, height: 1.45),
  );
}

/// 카드 사진: 157 정사각형(모서리 8), 여러 장이면 옆으로 넘긴다. 누르면 사진만 크게(검은 화면 "1 / N").
class _CardPhotos extends ConsumerWidget {
  const _CardPhotos({required this.review});
  final ReviewView review;

  /// 태블릿 레퍼런스 281px / 우리 300px × 160.
  static const _size = 150.0;

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
          label: l10n.reviewPhotoLabel(i + 1),
          onTap: () => openReviewPhotoViewer(context, urls, initial: i),
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
    // 레퍼런스 2026-11-26: 글 #29, 아이콘 높이 15.2 / 12.2, 테두리 아주 옅게.
    final fg = on ? scheme.primary : scheme.onSurface;
    return Semantics(
      button: true,
      selected: on,
      child: InkWell(
        key: ValueKey('product-review-helpful-${widget.review.reviewId}'),
        borderRadius: BorderRadius.circular(17),
        onTap: _busy ? null : _tap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.fromLTRB(15.5, 0, 13.5, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: on ? scheme.primary : reviewLineColor,
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PmartLineIcon(
                PmartLineIcons.thumbUp,
                size: 17,
                color: fg,
                strokeWidth: 2.1,
              ),
              const SizedBox(width: 6),
              Text(
                // 0 이면 숫자 없이 "도움돼요"(레퍼런스 2026-11-26).
                widget.count > 0
                    ? l10n.reviewHelpful(widget.count)
                    : l10n.reviewHelpfulZero,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 15,
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

/// 사진리뷰 상세 열기 — [query](사진 리뷰만 목록)의 리뷰를 한 장씩 옆으로 넘긴다. 처음은 [review].
Future<void> openReviewPhotoDetail(
  BuildContext context, {
  required ReviewView review,
  required ProductReviewQuery query,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => ReviewPhotoDetailScreen(review: review, query: query),
  ),
);

/// 사진리뷰 상세(사용자 레퍼런스 2026-11-26 "사진리뷰 4 / 285"): [X] 가운데 "사진리뷰 k / N"(N = 서버가 준 사진 리뷰 수),
/// 리뷰(작성자·별점·날짜·신고, 본문, 상품, 도움돼요) → 사진을 화면 폭 정사각형으로 → 아래는 회색. 옆으로 넘기면 다음 사진 리뷰.
/// 사진을 누르면 사진만 크게. 아래 구매 막대는 없다(레퍼런스).
class ReviewPhotoDetailScreen extends ConsumerStatefulWidget {
  const ReviewPhotoDetailScreen({
    super.key,
    required this.review,
    required this.query,
  });

  final ReviewView review;

  /// 사진 리뷰만 목록 — 넘기기·도움돼요(서버 값으로 바뀜)가 이 목록을 따른다.
  final ProductReviewQuery query;

  @override
  ConsumerState<ReviewPhotoDetailScreen> createState() =>
      _ReviewPhotoDetailScreenState();
}

class _ReviewPhotoDetailScreenState
    extends ConsumerState<ReviewPhotoDetailScreen> {
  PageController? _pages;
  int _index = 0;

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final provider = productReviewListProvider(widget.query);
    final list = ref.watch(provider).value;
    final now = ref.watch(clockProvider)();
    final items = [
      for (final r in list?.items ?? const <ReviewView>[])
        if (r.photoUrls.isNotEmpty) r,
    ];
    // 목록에 아직 없으면(다른 목록에서 연 경우) 받은 리뷰 한 건만.
    if (!items.any((r) => r.reviewId == widget.review.reviewId)) {
      items
        ..clear()
        ..add(widget.review);
    }
    if (_pages == null) {
      _index = items.indexWhere((r) => r.reviewId == widget.review.reviewId);
      _pages = PageController(initialPage: _index);
    }
    final total = switch (list?.reviewCount) {
      final int n when n >= items.length => n,
      _ => items.length,
    };
    return Scaffold(
      key: const ValueKey('review-photo-detail'),
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        toolbarHeight: 47,
        backgroundColor: theme.colorScheme.surface,
        leading: IconButton(
          key: const ValueKey('review-photo-detail-close'),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const PmartLineIcon(PmartLineIcons.close, size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: Text(
          l10n.reviewPhotoPageTitle(_index + 1, total),
          key: const ValueKey('review-photo-detail-title'),
          // 태블릿 레퍼런스 제목 높이 27px = 우리 16 제목.
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 16.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: PageView.builder(
        key: const ValueKey('review-photo-detail-pages'),
        controller: _pages,
        itemCount: items.length,
        onPageChanged: (i) {
          setState(() => _index = i);
          // 끝에서 3장 안이면 다음 쪽(서버 커서). 실패했으면 자동으로 다시 부르지 않는다.
          if (list != null &&
              i >= items.length - 3 &&
              list.hasMore &&
              !list.loadingMore &&
              list.loadMoreFailure == null) {
            ref.read(provider.notifier).loadMore();
          }
        },
        itemBuilder: (context, i) =>
            _PhotoReviewPage(review: items[i], now: now, query: widget.query),
      ),
    );
  }
}

class _PhotoReviewPage extends ConsumerWidget {
  const _PhotoReviewPage({
    required this.review,
    required this.now,
    required this.query,
  });

  final ReviewView review;
  final DateTime now;
  final ProductReviewQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final origin = ref.watch(imageOriginProvider);
    final r = review;
    final urls = [for (final u in r.photoUrls) resolveImageUrl(u, origin)];
    final width = MediaQuery.sizeOf(context).width;
    return SingleChildScrollView(
      key: ValueKey('review-photo-page-${r.reviewId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16.7, 20, 16.7, 26),
              child: _ReviewContent(
                review: r,
                now: now,
                query: query,
                photos: false,
              ),
            ),
          ),
          for (var i = 0; i < urls.length; i++)
            _Photo(
              key: ValueKey('review-photo-detail-${r.reviewId}-$i'),
              url: urls[i],
              size: width,
              radius: 0,
              label: l10n.reviewPhotoLabel(i + 1),
              onTap: () => openReviewPhotoViewer(context, urls, initial: i),
            ),
        ],
      ),
    );
  }
}

/// 사진리뷰 모아보기(사용자 레퍼런스 2026-11-26): [X] 가운데 굵은 제목, 3칸 격자에 큰 칸(2×2)이 섞인다 —
/// 작은 칸 6 → 왼쪽 큰 칸 + 오른쪽 작은 칸 2 → 작은 칸 6 → 오른쪽 큰 칸 + 왼쪽 작은 칸 2 를 되풀이. 사이 2.
/// 끝에 닿으면 다음 쪽. 누르면 그 리뷰의 사진리뷰 상세.
class ReviewPhotosScreen extends ConsumerWidget {
  const ReviewPhotosScreen({super.key, required this.productId});

  final String productId;

  static const _gap = 2.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
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
        toolbarHeight: 47,
        leading: IconButton(
          key: const ValueKey('review-photos-close'),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const PmartLineIcon(PmartLineIcons.close, size: 24),
          onPressed: () => context.pop(),
        ),
        centerTitle: true,
        title: Text(
          l10n.reviewPhotosTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 16.5,
            fontWeight: FontWeight.w700,
          ),
        ),
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
          final blocks = reviewPhotoBlocks(photos.length);
          return LayoutBuilder(
            builder: (context, c) {
              final cell = (c.maxWidth - _gap * 2) / 3;
              final big = cell * 2 + _gap;
              Widget tile(int i, double size) => _Photo(
                key: ValueKey('review-photos-grid-$i'),
                url: photos[i].url,
                size: size,
                radius: 0,
                label: l10n.reviewPhotoLabel(i + 1),
                onTap: () => openReviewPhotoDetail(
                  context,
                  review: photos[i].review,
                  query: query,
                ),
              );
              return ListView.separated(
                key: const ValueKey('review-photos-grid'),
                itemCount: blocks.length,
                separatorBuilder: (_, _) => const SizedBox(height: _gap),
                itemBuilder: (context, b) {
                  final block = blocks[b];
                  if (block.last >= photos.length - 6 &&
                      list.hasMore &&
                      !list.loadingMore &&
                      list.loadMoreFailure == null) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => notifier.loadMore(),
                    );
                  }
                  if (block.big == null) {
                    return Row(
                      children: [
                        for (final (k, i) in block.cells.indexed) ...[
                          if (k > 0) const SizedBox(width: _gap),
                          tile(i, cell),
                        ],
                      ],
                    );
                  }
                  final side = Column(
                    children: [
                      for (final (k, i) in block.cells.indexed) ...[
                        if (k > 0) const SizedBox(height: _gap),
                        tile(i, cell),
                      ],
                    ],
                  );
                  final bigTile = tile(block.big!, big);
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: block.bigLeft
                        ? [bigTile, const SizedBox(width: _gap), side]
                        : [side, const SizedBox(width: _gap), bigTile],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// 모아보기 격자의 한 덩어리: 작은 칸 줄(3칸) 또는 큰 칸(2×2) + 옆 작은 칸 2개.
typedef ReviewPhotoBlock = ({
  List<int> cells,
  int? big,
  bool bigLeft,
  int last,
});

/// 사진 [count] 장을 레퍼런스 순서(작은 줄 2 → 큰 칸 왼쪽 → 작은 줄 2 → 큰 칸 오른쪽 …)로 나눈다.
/// 큰 칸 덩어리를 채울 사진(3장)이 모자라면 작은 줄로 채운다.
List<ReviewPhotoBlock> reviewPhotoBlocks(int count) {
  final out = <ReviewPhotoBlock>[];
  var i = 0;
  var unit = 0; // 0,1 작은 줄 · 2 큰 칸 왼쪽 · 3,4 작은 줄 · 5 큰 칸 오른쪽
  while (i < count) {
    final step = unit % 6;
    if ((step == 2 || step == 5) && count - i >= 3) {
      final left = step == 2;
      out.add((cells: [i + 1, i + 2], big: i, bigLeft: left, last: i + 2));
      i += 3;
    } else {
      final end = (i + 3).clamp(0, count);
      out.add((
        cells: [for (var k = i; k < end; k++) k],
        big: null,
        bigLeft: true,
        last: end - 1,
      ));
      i = end;
    }
    unit++;
  }
  return out;
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

  /// 정사각형 한 변.
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
                // 축소본(?w=240/480/720)·그릴 크기로만 디코딩(요청 2026-11-20).
                : pmartNetworkImage(
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

class _ReportLink extends ConsumerWidget {
  const _ReportLink({required this.review});

  final ReviewView review;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final done =
        review.reportedByMe == true ||
        ref.watch(reportedReviewsProvider).contains(review.reviewId);
    // 태블릿 레퍼런스 신고하기 폭 74px / 우리 85px × 14, 색 #A0.
    final style = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 12.2,
      color: const Color(0xFFA0A0A0),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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

/// "재구매" 작은 표(review 0.9.0 `repurchased` true — 작성자가 이 상품을 서로 다른 주문 2번 이상 받음).
class ReviewRepurchasedTag extends StatelessWidget {
  const ReviewRepurchasedTag({super.key, required this.reviewId});

  final String reviewId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: ValueKey('review-repurchased-$reviewId'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        AppLocalizations.of(context).reviewRepurchased,
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
