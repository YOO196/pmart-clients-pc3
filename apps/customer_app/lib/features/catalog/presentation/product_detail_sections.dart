import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers.dart';
import '../../checkout/presentation/checkout_controller.dart'
    show clockProvider;
import '../../../shared/shopping_context.dart' show currentMfcIdProvider;
import '../../reviews/domain/reviews.dart';
import '../../reviews/presentation/product_reviews_screen.dart'
    show ProductReviewCard, openReviewPhotoDetail;
import '../../reviews/presentation/reviews_controller.dart';
import '../../reviews/presentation/reviews_screens.dart'
    show showReviewPolicyDialog;
import '../domain/catalog.dart';
import 'catalog_providers.dart';
import 'widgets/discount_price.dart';
import 'widgets/product_tile_card.dart';
import 'widgets/quick_add_button.dart';
import '../../../shared/network_image.dart';

// 상품 상세 새 화면(사용자 레퍼런스 2026-11-25 `5. 상품페이지 전체`)의 구획들.
// 레퍼런스는 540px 폭 = 411dp(1dp ≈ 1.314px) — 아래 치수는 그 실측을 dp 로 옮긴 것.

/// 같은 카테고리 상품(검색 — 서버 정렬). 이 상품은 뺀다. 실패는 그 구획만 숨긴다(상세 본문은 그대로).
typedef CategoryShelfKey = ({
  String categoryId,
  SortKey sort,
  String excludeId,
});

final categoryShelfProvider = FutureProvider.autoDispose
    .family<List<ProductTile>, CategoryShelfKey>((ref, k) async {
      final page = await ref
          .watch(catalogRepositoryProvider)
          .search(
            ProductQuery(categoryId: k.categoryId, sort: k.sort),
            mfcId: ref.watch(currentMfcIdProvider),
          );
      return [
        for (final t in page.items)
          if (t.productId != k.excludeId) t,
      ];
    });

/// "다른 사람들이 함께 구매한 상품"(storefront 0.19.0 BR-100 R5). "함께 본 상품"은 서버가 조회 기록을 모으지 않아
/// 없다(회신 2026-11-25) — 목에서만 같은 카테고리 상품으로 흉내 내고 실서버는 null(구획을 그리지 않는다).
enum RelatedKind { viewedTogether, boughtTogether }

final relatedProductsProvider = FutureProvider.autoDispose
    .family<
      List<ProductTile>?,
      ({String productId, String? categoryId, RelatedKind kind})
    >((ref, k) async {
      final mock = ref.watch(envProvider) == PmartEnv.mock;
      switch (k.kind) {
        case RelatedKind.boughtTogether:
          return ref
              .watch(catalogRepositoryProvider)
              .boughtTogether(
                k.productId,
                mfcId: ref.watch(currentMfcIdProvider),
              );
        case RelatedKind.viewedTogether:
          if (!mock || k.categoryId == null) return null;
          return ref.watch(
            categoryShelfProvider((
              categoryId: k.categoryId!,
              sort: SortKey.newest,
              excludeId: k.productId,
            )).future,
          );
      }
    });

/// 상품페이지 배너 — 배너 자리 `PRODUCT_DETAIL`(storefront 0.17.0 BR-100 R9, 모든 상품 공통).
/// 편성 전에는 빈 목록이라 그 칸을 뺀다. 목은 홈 배너로 흉내 낸다.
final productPageBannersProvider = FutureProvider.autoDispose<List<HomeBanner>>(
  (ref) async {
    if (ref.watch(envProvider) == PmartEnv.mock) {
      return (await ref.watch(homeProvider.future)).banners;
    }
    return ref
        .watch(catalogRepositoryProvider)
        .banners(placement: 'PRODUCT_DETAIL');
  },
);

/// 구획 사이 굵은 띠(레퍼런스 약 10dp 연회색).
class DetailBand extends StatelessWidget {
  const DetailBand({super.key});

  @override
  Widget build(BuildContext context) => const PmartSectionGap(height: 10);
}

/// 구획 제목(레퍼런스 20 굵게, 왼쪽 16.7). [accent] 는 앞쪽 파란 글(예 "아이스크림" 인기상품).
class DetailSectionTitle extends StatelessWidget {
  const DetailSectionTitle(
    this.text, {
    super.key,
    this.accent,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16.7, 22, 16.7, 12),
  });

  final String text;
  final String? accent;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 실측: 제목 21 굵게(레퍼런스 2026-11-26 "믿고 구매하는 평점 좋은 상품" 글 폭 420/455.7 × 23).
    final style = theme.textTheme.titleLarge?.copyWith(
      fontSize: 21,
      fontWeight: FontWeight.w800,
    );
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (accent != null)
                    TextSpan(
                      text: accent,
                      style: const TextStyle(color: Color(0xFF2C7BEA)),
                    ),
                  TextSpan(text: text),
                ],
              ),
              style: style,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// "전체 보기 ›" 작은 글 링크.
class DetailSeeAll extends StatelessWidget {
  const DetailSeeAll({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.sectionViewAll,
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15),
          ),
          const PmartLineIcon(PmartLineIcons.chevronRight, size: 16),
        ],
      ),
    );
  }
}

/// 가로 진열(레퍼런스 "다른 사람들이 함께 본 상품" — 칸 111dp, 사이 8, 왼쪽 16.7).
class DetailProductRail extends StatelessWidget {
  const DetailProductRail({super.key, required this.items, this.railKey});

  final List<ProductTile> items;
  final Key? railKey;

  static const _w = 111.0;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: ProductTileCard.heightFor(context, _w),
    child: ListView.separated(
      key: railKey,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16.7),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, i) => SizedBox(
        width: _w,
        child: ProductTileCard(
          tile: items[i],
          rail: true,
          look: TileLook.detailRail,
          onTap: () => context.push('/products/${items[i].productId}'),
        ),
      ),
    ),
  );
}

/// 세 줄 가로 묶음(레퍼런스 "평점 좋은 상품"·"함께 구매한 상품"·"인기상품"): 사진 115dp 왼쪽 + 글 오른쪽,
/// 한 묶음(열) 폭 304dp, 줄 간격 126dp. 열을 옆으로 넘긴다.
class DetailRowGrid extends StatelessWidget {
  const DetailRowGrid({super.key, required this.items, this.gridKey});

  final List<ProductTile> items;
  final Key? gridKey;

  static const _colW = 304.0;
  static const _rowH = 126.0;

  @override
  Widget build(BuildContext context) {
    final cols = (items.length / 3).ceil();
    return SizedBox(
      height: _rowH * math.min(3, items.length),
      child: ListView.builder(
        key: gridKey,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 16.7, right: 8),
        itemCount: cols,
        itemBuilder: (context, c) => SizedBox(
          width: _colW,
          child: Column(
            children: [
              for (var r = 0; r < 3 && c * 3 + r < items.length; r++)
                SizedBox(
                  height: _rowH,
                  child: _RowCard(tile: items[c * 3 + r]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({required this.tile});

  final ProductTile tile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = tile;
    return InkWell(
      key: ValueKey('row-card-${t.productId}'),
      onTap: () => context.push('/products/${t.productId}'),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 11, right: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ProductImage(url: t.imageUrl, size: 115, radius: 7),
                if (QuickAddButton.offeredFor(t))
                  Positioned(
                    right: 5,
                    bottom: 5,
                    child: QuickAddButton(tile: t, size: 30, iconSize: 20),
                  ),
              ],
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Text(
                    keepWordsTogether(t.name),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    // 실측: 이름 14.8 보통(레퍼런스 2026-11-26 한글 글자 높이 22/23.8 × 16).
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 14.8,
                      height: 1.3,
                      fontWeight: FontWeight.w400,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (t.discount case final d?)
                    DiscountPriceText(
                      price: d.salePrice,
                      ratePercent: d.ratePercent,
                      showBase: false,
                      rateColor: const Color(0xFFFF3E3E),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  else
                    Text(
                      switch (t.basePrice) {
                        final int p => formatKrw(p),
                        null => l10n.priceUnavailable,
                      },
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  if (t.rating != null) ...[
                    const SizedBox(height: 3),
                    RatingLine(rating: t.rating, count: t.reviewCount),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [상품설명 | 리뷰 N] 탭(레퍼런스 — 누르면 그 구획으로 내려간다. 고른 쪽 굵게 + 아래 검은 줄).
class DetailTabs extends StatelessWidget {
  const DetailTabs({
    super.key,
    required this.reviewCount,
    required this.onDescription,
    required this.onReviews,
    required this.reviewsSelected,
  });

  final int? reviewCount;
  final VoidCallback onDescription;
  final VoidCallback onReviews;
  final bool reviewsSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget tab(String text, bool on, VoidCallback onTap, Key key) => Expanded(
      child: InkWell(
        key: key,
        onTap: onTap,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: on ? scheme.onSurface : Colors.transparent,
                width: 2.4,
              ),
            ),
          ),
          child: Text(
            text,
            style: theme.textTheme.titleMedium?.copyWith(
              // 레퍼런스 2026-11-26 "상품설명" 폭 100/107.5 × 18.3.
              fontSize: 17,
              fontWeight: on ? FontWeight.w700 : FontWeight.w400,
              color: on ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16.7),
      decoration: null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            tab(
              l10n.productTabDescription,
              !reviewsSelected,
              onDescription,
              const ValueKey('detail-tab-description'),
            ),
            tab(
              switch (reviewCount) {
                final int n => l10n.productTabReviews(formatCountKo(n)),
                null => l10n.reviewSectionTitle,
              },
              reviewsSelected,
              onReviews,
              const ValueKey('detail-tab-reviews'),
            ),
          ],
        ),
      ),
    );
  }
}

String formatCountKo(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// 서버 `notices` 한 줄("이름: 값")을 둘로 나눈다(상품정보제공고시 글줄 — 표시만). 콜론이 없으면 이름 없이 값만.
({String? label, String value}) splitNotice(String line) {
  final i = line.indexOf(':');
  if (i <= 0) return (label: null, value: line.trim());
  return (
    label: line.substring(0, i).trim(),
    value: line.substring(i + 1).trim(),
  );
}

/// "구매 전 참고해주세요" 상자(레퍼런스 — 연회색 둥근 상자, 보관방법·소비기한/제조일, [더보기 ›]).
/// 값은 서버 글 그대로: 보관방법 = `storageGuide`, 소비기한/제조일 = notices 중 이름에 "소비기한"이 든 줄(칸은 BR-100 R1).
class PurchaseNoteBox extends StatelessWidget {
  const PurchaseNoteBox({super.key, required this.product, this.onMore});

  final ProductDetail product;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // 소비기한/제조일: 서버 칸 `expiryGuide`(product-content 0.9.0 BR-100 R1). 옛 응답이면 notices 줄.
    final expiry =
        product.expiryGuide ??
        product.notices
            .map(splitNotice)
            .where((n) => n.label?.contains('소비기한') ?? false)
            .firstOrNull
            ?.value;
    final rows = <(String, String)>[
      if (product.storageGuide case final g?) (l10n.productStorageShort, g),
      if (expiry != null) (l10n.productExpiryShort, expiry),
    ];
    if (rows.isEmpty && onMore == null) return const SizedBox.shrink();
    // 실측: 이름·값 16.5(줄 22dp), 제목 18.5, 상자 좌우 21.
    final label = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 16.3,
      height: 1.34,
      color: scheme.onSurfaceVariant,
    );
    final value = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 16.8,
      height: 1.34,
    );
    return Container(
      key: const ValueKey('purchase-note-box'),
      margin: const EdgeInsets.fromLTRB(21, 22, 21, 0),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.productPurchaseNoteTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 18.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          for (final (k, v) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 122, child: Text(k, style: label)),
                  Expanded(child: Text(v, style: value)),
                ],
              ),
            ),
          if (onMore != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: OutlinedButton(
                key: const ValueKey('purchase-note-more'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: scheme.surface,
                  foregroundColor: scheme.onSurface,
                  side: BorderSide(color: scheme.outlineVariant),
                  shape: const StadiumBorder(),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onMore,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.productMore,
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                    ),
                    const PmartLineIcon(PmartLineIcons.chevronRight, size: 15),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 상품설명(레퍼런스 — 가운데 큰 제목 → 설명 → 사진들, 처음엔 접혀 있고 [상품설명 펼치기 ⌄]).
class CollapsibleDescription extends StatefulWidget {
  const CollapsibleDescription({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  /// 접혔을 때 보이는 높이(레퍼런스: 제목·첫 사진 일부까지 약 460dp).
  static const collapsedHeight = 460.0;

  @override
  State<CollapsibleDescription> createState() => _CollapsibleDescriptionState();
}

class _CollapsibleDescriptionState extends State<CollapsibleDescription> {
  bool _open = false;

  /// 내용 높이(첫 그림 뒤 잰 값). 접는 높이보다 짧으면 접지 않고 버튼도 두지 않는다.
  double? _height;
  final _contentKey = GlobalKey();

  void _measure() {
    final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    final h = box?.size.height;
    if (h != null && h != _height && mounted) setState(() => _height = h);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final content = Column(
      key: _contentKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 60),
        Text(
          widget.title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 34),
        ...widget.children,
        const SizedBox(height: 40),
      ],
    );
    final long = (_height ?? 0) > CollapsibleDescription.collapsedHeight;
    return Column(
      key: const ValueKey('product-description'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_open || !long)
          content
        else
          SizedBox(
            height: CollapsibleDescription.collapsedHeight,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topCenter,
                maxHeight: double.infinity,
                child: content,
              ),
            ),
          ),
        if (long)
          Padding(
            padding: const EdgeInsets.fromLTRB(16.7, 10, 16.7, 28),
            child: SizedBox(
              height: 53,
              child: OutlinedButton(
                key: const ValueKey('product-description-toggle'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.onSurface,
                  side: BorderSide(color: scheme.outlineVariant, width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onPressed: () => setState(() => _open = !_open),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _open
                          ? l10n.productDescriptionCollapse
                          : l10n.productDescriptionExpand,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 2),
                    PmartLineIcon(
                      _open
                          ? PmartLineIcons.chevronUp
                          : PmartLineIcons.chevronDown,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 상품 상세 아래쪽 리뷰 구획(레퍼런스): "평점 4.9 ★" · 사진 2줄 격자(옆으로 넘김) · "리뷰 N개 [리뷰정책 안내] 전체 보기 ›" ·
/// 리뷰 3개 · [리뷰 전체 보기 ›]. 조회 실패는 실패 + 다시 시도("리뷰 없음"으로 바꾸지 않는다).
class DetailReviewSection extends ConsumerWidget {
  const DetailReviewSection({
    super.key,
    required this.productId,
    required this.rating,
  });

  final String productId;
  final RatingSummary? rating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = (
      productId: productId,
      sort: ReviewSort.newest,
      photoOnly: false,
      sku: null,
    );
    final value = ref.watch(productReviewListProvider(query));
    final list = value.value;
    void openAll() => context.push('/products/$productId/reviews');
    final count = list?.reviewCount ?? rating?.count;
    final now = ref.watch(clockProvider)();
    return Column(
      key: const ValueKey('product-reviews'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rating case final r?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16.7, 22, 16.7, 10),
            child: Row(
              children: [
                Text(
                  l10n.productRatingTitle(r.average.toStringAsFixed(1)),
                  key: const ValueKey('product-reviews-rating'),
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
        ReviewPhotoGrid(productId: productId),
        const DetailBand(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16.7, 22, 16.7, 6),
          child: Row(
            children: [
              Text(
                switch (count) {
                  final int n => l10n.reviewSectionCount(n),
                  null => l10n.reviewSectionTitle,
                },
                key: const ValueKey('product-reviews-count'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: scheme.surfaceContainer,
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const ValueKey('product-reviews-policy'),
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
              const Spacer(),
              DetailSeeAll(
                key: const ValueKey('product-reviews-all'),
                onTap: openAll,
              ),
            ],
          ),
        ),
        switch (value) {
          AsyncError() when list == null => Padding(
            key: const ValueKey('product-reviews-failed'),
            padding: const EdgeInsets.all(16.7),
            child: Row(
              children: [
                Expanded(child: Text(l10n.reviewLoadFailed)),
                TextButton(
                  onPressed: () =>
                      ref.invalidate(productReviewListProvider(query)),
                  child: Text(l10n.reviewRetry),
                ),
              ],
            ),
          ),
          _ when list == null => const SizedBox(height: 80),
          _ when list.items.isEmpty => Padding(
            padding: const EdgeInsets.all(16.7),
            child: Text(
              l10n.reviewSectionEmpty,
              key: const ValueKey('product-reviews-empty'),
            ),
          ),
          _ => Column(
            key: const ValueKey('product-reviews-preview'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, r) in list.items.take(3).indexed) ...[
                if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                ProductReviewCard(review: r, now: now, query: query),
              ],
            ],
          ),
        },
        if (list != null && list.items.isNotEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 28),
              child: SizedBox(
                height: 40,
                child: OutlinedButton(
                  key: const ValueKey('product-reviews-all-button'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.onSurface,
                    side: BorderSide(color: scheme.outlineVariant, width: 1.2),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                  onPressed: openAll,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.productReviewsAll,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const PmartLineIcon(
                        PmartLineIcons.chevronRight,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 사진 후기 2줄 격자(레퍼런스 — 칸 106dp, 사이 3, 옆으로 넘김). 사진 리뷰가 없으면 자리를 두지 않는다.
class ReviewPhotoGrid extends ConsumerWidget {
  const ReviewPhotoGrid({
    super.key,
    required this.productId,
    this.showMore = false,
  });

  final String productId;

  /// 사진 리뷰가 더 있으면 끝에 [+ 더보기] 칸(사진리뷰 모아보기로). 리뷰 전체 보기에서만.
  final bool showMore;

  static const _cell = 106.0;
  // 레퍼런스 2026-11-26: 사진 사이 거의 붙음(3px/1080).
  static const _gap = 1.5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = (
      productId: productId,
      sort: ReviewSort.newest,
      photoOnly: true,
      sku: null,
    );
    final list = ref.watch(productReviewListProvider(query)).value;
    if (list == null) return const SizedBox.shrink();
    final origin = ref.watch(imageOriginProvider);
    final photos = [
      for (final r in list.items)
        for (final (i, u) in r.photoUrls.indexed)
          (review: r, index: i, url: resolveImageUrl(u, origin)),
    ];
    if (photos.isEmpty) return const SizedBox.shrink();
    final more = showMore && (photos.length > 8 || list.hasMore);
    final cols = ((photos.length + (more ? 1 : 0)) / 2).ceil();
    return Padding(
      key: const ValueKey('review-photo-strip'),
      padding: const EdgeInsets.only(bottom: 22),
      child: SizedBox(
        height: _cell * 2 + _gap,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16.7),
          itemCount: cols,
          separatorBuilder: (_, _) => const SizedBox(width: _gap),
          itemBuilder: (context, c) => Column(
            children: [
              for (var r = 0; r < 2 && c * 2 + r <= photos.length; r++)
                if (c * 2 + r == photos.length) ...[
                  if (more) ...[
                    if (r > 0) const SizedBox(height: _gap),
                    _MoreCell(productId: productId, size: _cell),
                  ],
                ] else ...[
                  if (r > 0) const SizedBox(height: _gap),
                  GestureDetector(
                    onTap: () => openReviewPhotoDetail(
                      context,
                      review: photos[c * 2 + r].review,
                      initial: photos[c * 2 + r].index,
                      query: query,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: switch (photos[c * 2 + r].url) {
                        final u? => pmartNetworkImage(
                          u,
                          width: _cell,
                          height: _cell,
                          fit: BoxFit.cover,
                          cacheWidth:
                              (_cell * MediaQuery.devicePixelRatioOf(context))
                                  .round(),
                          errorBuilder: (_, _, _) => _blank(context),
                        ),
                        null => _blank(context),
                      },
                    ),
                  ),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _blank(BuildContext context) => Container(
    width: _cell,
    height: _cell,
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
  );
}

class _MoreCell extends StatelessWidget {
  const _MoreCell({required this.productId, required this.size});

  final String productId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Material(
      key: const ValueKey('review-photos-more'),
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: () => context.push('/products/$productId/review-photos'),
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: Text(
              l10n.reviewPhotoMoreOverlay,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 아래 "상세정보 ›" / "반품·교환 안내 ›" 줄(레퍼런스 — 높이 약 64dp, 글 16).
class DetailInfoRow extends StatelessWidget {
  const DetailInfoRow({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 16.7),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(fontSize: 17),
              ),
            ),
            const PmartLineIcon(PmartLineIcons.chevronRight, size: 20),
          ],
        ),
      ),
    );
  }
}

/// 글 한 덩어리를 보여 주는 시트(반품·교환 안내 등).
Future<void> showDetailTextSheet(
  BuildContext context, {
  required String title,
  required Widget body,
}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  builder: (context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(context)
                        .closeButtonTooltip,
                    icon: const PmartLineIcon(PmartLineIcons.close, size: 24),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              body,
            ],
          ),
        ),
      ),
    );
  },
);

/// 상품정보제공고시 표 — 서버 `legalInfo`(product-content 0.9.0 BR-100 R1), 옛 응답이면 notices 줄을 나눈 것.
class NoticeTable extends StatelessWidget {
  const NoticeTable({super.key, required this.rows});

  final List<({String? label, String value})> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      key: const ValueKey('product-notice-table'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final n in rows)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: n.label == null
                ? Text(n.value, style: theme.textTheme.bodyMedium)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(
                          n.label!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(n.value, style: theme.textTheme.bodyMedium),
                      ),
                    ],
                  ),
          ),
      ],
    );
  }
}

/// "우리동네 PMart, 이렇게 관리해요"(레퍼런스 5 상품페이지 — 사용자 2026-11-25 이름 PMart).
/// 옆으로 넘기는 카드 268.6×245(바탕 #F4F5F7·모서리 7.6·사이 12): 위 그림 152 → 제목(굵게) → 설명 두 줄.
/// 그림은 아직 없어 레퍼런스 빈 그림처럼 회색 바탕에 흐린 "PMart"(고정 문구 — 서버·백오피스 설정 없음).
/// 관리 카드(storefront 0.20.0 `GET /storefront/care-cards`, BR-102 — 백오피스 편성). 목은 고정 2장(그림 없음).
final careCardsProvider = FutureProvider.autoDispose<CareCards>((ref) {
  ref.keepAlive();
  return ref.watch(catalogRepositoryProvider).careCards();
});

class TownCareSection extends ConsumerWidget {
  const TownCareSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final origin = ref.watch(imageOriginProvider);
    final value = ref.watch(careCardsProvider).value;
    // 읽는 중·실패·빈 목록이면 구획을 뺀다(지어내지 않는다).
    if (value == null || value.items.isEmpty) return const SizedBox.shrink();
    final cards = value.items;
    final px = 268.6 * MediaQuery.devicePixelRatioOf(context);
    return Column(
      key: const ValueKey('town-care'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetailSectionTitle(value.title ?? ''),
        SizedBox(
          height: 245,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.7),
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12.2),
            itemBuilder: (context, i) {
              final card = cards[i];
              final image = resolveImageUrl(
                withImageWidth(card.imageUrl, px),
                origin,
              );
              return Container(
                width: 268.6,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F5F7),
                  borderRadius: BorderRadius.circular(7.6),
                  border: Border.all(color: const Color(0xFFECEDEF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 152,
                      width: double.infinity,
                      child: image == null
                          ? _CarePlaceholder(theme: theme)
                          : pmartNetworkImage(
                              image,
                              fit: BoxFit.cover,
                              cacheWidth: px.round(),
                              errorBuilder: (_, _, _) =>
                                  _CarePlaceholder(theme: theme),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16.7, 17, 16.7, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 15.5,
                              height: 1.3,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            card.body,
                            maxLines: 2,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 13.3,
                              height: 1.45,
                              // 레퍼런스: 설명도 진한 글자(가장 진한 화소 #18191B).
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 22),
      ],
    );
  }
}

/// 그림이 없거나 못 받았을 때(레퍼런스 빈 그림처럼 회색 + 흐린 "PMart").
class _CarePlaceholder extends StatelessWidget {
  const _CarePlaceholder({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      'PMart',
      style: theme.textTheme.titleLarge?.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: const Color(0xFFD9DADC),
      ),
    ),
  );
}
