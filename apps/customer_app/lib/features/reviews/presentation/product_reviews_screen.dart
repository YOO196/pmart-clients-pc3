import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:pmart_core/pmart_core.dart' show PmartFailure, ProblemFailure;
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
import '../../catalog/domain/catalog.dart' show SaleOption;
import '../../catalog/presentation/catalog_providers.dart'
    show productDetailProvider;
import '../../checkout/presentation/checkout_controller.dart'
    show clockProvider;
import '../../wishlist/presentation/wish_heart_button.dart';
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
        for (final s in reviewSortChoices)
          (s, reviewSortLabel(l10n, s), ValueKey('review-sort-${s.name}')),
      ],
    );
    if (picked != null && mounted) setState(() => _sort = picked);
  }

  Future<void> _pickFilter() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showChoiceSheet<bool>(
      context,
      title: l10n.reviewFilter,
      closeKey: const ValueKey('review-filter-close'),
      selected: _photoOnly,
      options: [
        (false, l10n.reviewFilterAll, const ValueKey('review-filter-all')),
        (true, l10n.reviewFilterPhoto, const ValueKey('review-filter-photo')),
      ],
    );
    if (picked != null && mounted) setState(() => _photoOnly = picked);
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

    final scheme = theme.colorScheme;
    // 레퍼런스 4. 상품리뷰 전체 보기 - 상단을 재서 맞춤(2026-11-21): 공지·정렬·필터 줄 15.
    final rowText = theme.textTheme.bodyLarge?.copyWith(fontSize: 15);
    // 새 레퍼런스(4. 상품리뷰 전체 보기 - 상단, 2026-11-21): 공지 줄 → 사진 후기 4칸 → 회색 띠 →
    // "총 N개 · 정렬 ⌄ · 필터" → [상품 옵션 ⌄]. 신고·멤버스 표시는 계약에 없어 두지 않는다.
    final header = <Widget>[
      InkWell(
        key: const ValueKey('review-policy-open'),
        onTap: () => showReviewPolicyDialog(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  l10n.reviewNoticeTag,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(l10n.reviewNoticeTitle, style: rowText),
            ],
          ),
        ),
      ),
      _PhotoStrip(productId: widget.productId),
      Container(height: 8, color: scheme.surfaceContainer),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
        child: Row(
          children: [
            if (list?.averageRating case final avg?) ...[
              Icon(Icons.star_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 2),
              Text(
                avg.toStringAsFixed(1),
                key: const ValueKey('review-average'),
                semanticsLabel: l10n.reviewAverage(avg.toStringAsFixed(1)),
                style: rowText?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              switch (list?.reviewCount) {
                final int n => l10n.reviewTotalCount(n),
                null => l10n.reviewSectionTitle,
              },
              key: const ValueKey('review-count'),
              style: rowText,
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
            // 필터 = 사진 후기만 켜기·끄기(사용자 2026-11-21). 켜져 있으면 브랜드색.
            TextButton(
              key: const ValueKey('review-filter-open'),
              onPressed: _pickFilter,
              style: TextButton.styleFrom(
                foregroundColor: _photoOnly ? scheme.primary : scheme.onSurface,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.reviewFilter,
                    style: rowText?.copyWith(
                      color: _photoOnly ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 4),
                  PmartLineIcon(
                    PmartLineIcons.filter,
                    size: 18,
                    color: _photoOnly ? scheme.primary : scheme.onSurface,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      if (options.length >= 2)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              key: const ValueKey('review-option-open'),
              borderRadius: BorderRadius.circular(17),
              onTap: () => _pickOption(options),
              child: Container(
                height: 33,
                padding: const EdgeInsets.only(left: 12, right: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      switch (_sku) {
                        null => l10n.reviewOptionPlaceholder,
                        final s =>
                          options.where((o) => o.sku == s).firstOrNull?.label ??
                              s,
                      },
                      key: const ValueKey('review-option-label'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        color: _sku == null
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 2),
                    PmartLineIcon(
                      PmartLineIcons.chevronDown,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      const SizedBox(height: 14),
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
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ReviewAuthor(review: r),
              const Spacer(),
              if (mine != null)
                TextButton(
                  key: ValueKey('product-review-edit-${r.reviewId}'),
                  // 이름 줄 높이를 늘리지 않게 글자 높이만큼(내 리뷰를 알아낸 뒤 카드가 커지지 않게).
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 22),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
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
          _ReviewProductLine(review: r),
          if (r.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 7),
            _CardPhotos(review: r, query: query),
          ],
          if (r.text case final t? when t.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ReviewBody(text: t),
          ],
          const SizedBox(height: 14),
          _ReviewFooter(
            review: r,
            query: query,
            mine: mine != null,
            mineKnown: mineKnown,
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
  const _ReviewProductLine({required this.review, this.fontSize = 15});
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
        ?.copyWith(fontSize: 15, height: 1.4),
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
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final origin = ref.watch(imageOriginProvider);
    final r = review;
    final urls = [for (final u in r.photoUrls) resolveImageUrl(u, origin)];
    final shown = math.min(urls.length, 4);
    return LayoutBuilder(
      builder: (context, c) {
        final cell = (c.maxWidth - 6) / 4;
        return Row(
          children: [
            for (var i = 0; i < shown; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              _Photo(
                key: ValueKey('review-photo-${r.reviewId}-$i'),
                url: urls[i],
                size: cell,
                radius: 0,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(i == 0 ? 10 : 0),
                  right: Radius.circular(i == shown - 1 ? 10 : 0),
                ),
                label: l10n.reviewPhotoLabel(i + 1),
                overlay: i == 3 && urls.length > 4
                    ? l10n.reviewPhotoExtra(urls.length - 4)
                    : null,
                onTap: () => openReviewPhotoDetail(
                  context,
                  review: r,
                  initial: i,
                  query: query,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 도움돼요 버튼(review 0.6.0, BR-76): 테두리 알약(높이 34) + 엄지 아이콘 + "도움돼요 N"(15).
/// 회원만 누른다 — 비회원은 로그인 안내. 누른 상태·수는 서버가 준 값.
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

/// 사진 후기 모음: 사진 리뷰만(withPhotoOnly)의 첫 쪽 사진 4칸 줄. 4장을 넘으면 넷째 칸에 "+ 더보기"(모아보기 격자).
/// 사진을 누르면 그 리뷰의 "사진 후기".
class _PhotoStrip extends ConsumerWidget {
  const _PhotoStrip({required this.productId});

  final String productId;

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
    final photos = [
      for (final r in list.items)
        for (final (i, u) in r.photoUrls.indexed)
          (review: r, index: i, url: resolveImageUrl(u, origin)),
    ];
    // 사진 리뷰가 없다는 서버 답 — 자리를 두지 않는다.
    if (photos.isEmpty) return const SizedBox.shrink();
    final shown = math.min(photos.length, 4);
    final more = photos.length > 4 || list.hasMore;
    return Padding(
      key: const ValueKey('review-photo-strip'),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.reviewPhotoSectionTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final cell = (c.maxWidth - 6) / 4;
              return Row(
                children: [
                  for (var i = 0; i < shown; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    _Photo(
                      key: ValueKey(
                        i == 3 && more
                            ? 'review-photos-more'
                            : 'review-strip-$i',
                      ),
                      url: photos[i].url,
                      size: cell,
                      radius: 0,
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(i == 0 ? 10 : 0),
                        right: Radius.circular(i == shown - 1 ? 10 : 0),
                      ),
                      label: i == 3 && more
                          ? l10n.reviewPhotosTitle
                          : l10n.reviewPhotoLabel(i + 1),
                      overlay: i == 3 && more
                          ? l10n.reviewPhotoMoreOverlay
                          : null,
                      onTap: i == 3 && more
                          ? () => context.push(
                              '/products/$productId/review-photos',
                            )
                          : () => openReviewPhotoDetail(
                              context,
                              review: photos[i].review,
                              initial: photos[i].index,
                              query: query,
                            ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
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
    this.overlay,
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

  /// 사진 위 어두운 막 + 흰 글("+ 더보기"·"+1").
  final String? overlay;

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
        onTap: url == null && overlay == null ? null : onTap,
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
                  Image.network(
                    withImageWidth(url, px)!,
                    fit: BoxFit.cover,
                    cacheWidth: px.round(),
                    errorBuilder: (_, _, _) => placeholder(),
                  ),
                if (overlay case final o?)
                  ColoredBox(
                    color: dim,
                    child: Center(
                      child: Text(
                        o,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
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
