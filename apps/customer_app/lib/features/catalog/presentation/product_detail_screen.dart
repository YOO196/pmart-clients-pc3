import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/cart_icon_button.dart';
import '../../../shared/ui_state_of.dart';
import '../../wishlist/presentation/wish_heart_button.dart';
import '../domain/catalog.dart';
import 'catalog_providers.dart';
import '../../../shared/notice.dart';
import '../../cart/domain/cart.dart';
import '../../cart/presentation/cart_controller.dart';
import '../../cart/presentation/cart_messages.dart';
import 'widgets/content_image.dart';
import 'widgets/discount_price.dart';
import 'widgets/low_stock_toast.dart';
import 'widgets/product_tile_card.dart';
import 'home_providers.dart' show homeDeliveryOptionsProvider;
import 'home_screen.dart' show BannerPager, DeliveryGuideSheet, HomeCouponRow;
import 'product_detail_sections.dart';
import 'widgets/delivery_badges.dart';
import '../../checkout/domain/checkout.dart' show DeliveryMode;

/// SCR-PRODUCT-001·OPTION-001. 가격·가용은 사본이다. 구매 가능 확정은 장바구니·주문서 서버 판정.
class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({super.key, required this.productId, this.preview});

  final String productId;

  /// 카드에서 들어올 때 카드 값 — 상세 응답이 오기 전 첫 화면만 채운다(가격 확정·담기에 쓰지 않는다 — 담기는 응답 뒤).
  final ProductTile? preview;

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

/// "품절까지 N개 남았어요." 보이는 시간.
const lowStockToastDuration = Duration(seconds: 3);

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  String? _selectedSku;

  /// "품절까지 N개 남았어요."(레퍼런스 7-2) — 화면을 열 때 한 번, 몇 초 보이고 사라진다.
  int? _lowToast;
  bool _lowToastChecked = false;
  Timer? _lowToastTimer;

  void _maybeShowLowToast(ProductDetail p) {
    if (_lowToastChecked) return;
    _lowToastChecked = true;
    final left = lowStockLeft(p);
    if (left == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _lowToast = left);
      _lowToastTimer = Timer(lowStockToastDuration, () {
        if (mounted) setState(() => _lowToast = null);
      });
    });
  }

  @override
  void dispose() {
    _lowToastTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // 몇 분 붙잡아 둔 상세가 있으면 그것을 바로 보이고, 가격·재고는 뒤에서 다시 읽는다(R2).
    final provider = productDetailProvider(widget.productId);
    if (!ref.read(provider).hasValue) return;
    // 그리는 중에 다시 읽기를 걸면 다른 화면(리뷰 목록 — 옵션 이름)도 같은 값을 보고 있을 때 오류가 난다 — 첫 그림 뒤에.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(provider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = productDetailProvider(widget.productId);
    final watched = ref.watch(provider);
    // 다시 읽는 중에도 앞의 값을 보인다(로딩 화면으로 바꾸지 않음).
    final value = watched.isLoading && watched.hasValue
        ? AsyncData<ProductDetail>(watched.requireValue)
        : watched;
    final notFound = switch (value) {
      AsyncError(error: ProblemFailure(:final problem)) =>
        problem.code == ProblemCode.notFound ||
            problem.code == 'CONTENT_NOT_PUBLISHED',
      _ => false,
    };
    return Scaffold(
      appBar: AppBar(
        // 레퍼런스 상단 막대 높이(약 47dp). 뒤로 가기 바로 옆 브랜드 글자(사용자 레퍼런스 2026-11-26).
        toolbarHeight: 47,
        leadingWidth: 51,
        titleSpacing: 0,
        centerTitle: false,
        title: Text(
          l10n.brandName,
          key: const ValueKey('detail-brand'),
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
            color: Color(0xFF1B1D1E),
          ),
        ),
        actions: [
          IconButton(
            key: const ValueKey('detail-home'),
            visualDensity: VisualDensity.compact,
            tooltip: l10n.navHome,
            icon: const PmartLineIcon(PmartLineIcons.home, size: 23),
            onPressed: () => context.go('/'),
          ),
          IconButton(
            key: const ValueKey('detail-search'),
            visualDensity: VisualDensity.compact,
            tooltip: l10n.searchTitle,
            icon: const PmartLineIcon(PmartLineIcons.search, size: 23),
            onPressed: () => context.push('/search'),
          ),
          const CartIconButton(key: ValueKey('detail-cart')),
          const SizedBox(width: 6),
        ],
      ),
      body: notFound
          ? Center(child: Text(l10n.productNotFound))
          : switch ((value, widget.preview)) {
              // 응답 전: 카드 값으로 사진·이름·가격(R1). 담기는 응답 뒤에만 열린다(아래 바 없음).
              (AsyncLoading(), final ProductTile t) => _PreviewBody(tile: t),
              _ => UiStateView<ProductDetail>(
                loading: (_) => const PmartDetailSkeleton(),
                state: uiStateOf(value),
                onRetry: () => ref.invalidate(provider),
                ready: (context, p) {
                  _maybeShowLowToast(p);
                  return Stack(
                    children: [
                      Positioned.fill(child: _body(context, l10n, p)),
                      // 아래 막대 바로 위 가운데(레퍼런스 7-2 — 알약 아래 끝이 막대 위 선에 닿는다).
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: _lowToast == null ? 0 : 1,
                            duration: const Duration(milliseconds: 200),
                            child: Center(
                              child: _lowToast == null
                                  ? const SizedBox.shrink()
                                  : LowStockToast(
                                      key: const ValueKey(
                                        'product-low-stock-toast',
                                      ),
                                      count: _lowToast!,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            },
      // 아래 막대(레퍼런스): 찜 하트 + [구매하기] — 누르면 옵션·수량·담기 시트.
      bottomNavigationBar: switch (value) {
        AsyncData(value: final p) => Material(
          color: Theme.of(context).colorScheme.surface,
          shape: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              // 레퍼런스: 하트 가운데 30.9 · 버튼 왼쪽 63 · 오른쪽 13.4 · 위 11.7 · 아래 10.5.
              padding: const EdgeInsets.fromLTRB(10, 11.7, 13.4, 10.5),
              child: Row(
                children: [
                  SizedBox(
                    width: 42,
                    height: 54,
                    child: Center(
                      child: WishHeartWithCount(
                        heartKey: const ValueKey('detail-wish'),
                        productId: p.productId,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: FilledButton(
                        key: const ValueKey('product-buy'),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          textStyle: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        onPressed: () => _openBuySheet(p),
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
    );
  }

  SaleOption? _selected(ProductDetail p) =>
      p.options.where((o) => o.sku == _selectedSku).firstOrNull ??
      p.options.where((o) => o.canOfferAdd).firstOrNull;

  final _descriptionKey = GlobalKey();
  final _reviewsKey = GlobalKey();
  bool _reviewsTab = false;

  final _scroll = ScrollController();
  final _tabsKey = GlobalKey();

  /// 붙은 탭 아래 끝(화면 좌표). 탭이 아직 없으면 null.
  double? _tabsBottom() {
    final box = _tabsKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset(0, box.size.height)).dy;
  }

  double? _topOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero).dy;
  }

  /// 리뷰 구획 머리가 붙은 탭 아래까지 올라오면 [리뷰], 아니면 [상품설명](레퍼런스 — 스크롤 따라 바뀜).
  bool _jumping = false;
  void _syncTab() {
    if (_jumping) return;
    final bottom = _tabsBottom();
    final reviewsTop = _topOf(_reviewsKey);
    if (bottom == null || reviewsTop == null) return;
    final reviews = reviewsTop <= bottom + 1;
    if (reviews != _reviewsTab) setState(() => _reviewsTab = reviews);
  }

  Future<void> _scrollTo(GlobalKey key, {required bool reviews}) async {
    setState(() => _reviewsTab = reviews);
    final bottom = _tabsBottom();
    final top = _topOf(key);
    if (bottom == null || top == null || !_scroll.hasClients) return;
    // 구획 머리가 붙은 탭 바로 아래에 오도록.
    final target = (_scroll.offset + top - bottom).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _jumping = true;
    try {
      await _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } finally {
      _jumping = false;
    }
  }

  Future<void> _openBuySheet(ProductDetail p) =>
      showProductBuySheet(context, p);

  Widget _body(BuildContext context, AppLocalizations l10n, ProductDetail p) {
    final theme = Theme.of(context);
    final selected = _selected(p);
    final scheme = theme.colorScheme;
    // 평점: 상세 응답 rating(product-content 0.3.0 — BR-63, 집계와 같은 값). 비어 오면 그때만 평점 집계를 부른다.
    final rating =
        p.rating ?? ref.watch(productRatingProvider(p.productId)).value;
    final hasRating = rating != null;
    final reason = p.cannotBuyReason;
    // 대표 카테고리(맨 끝 노드) — 같은 카테고리 진열·"{이름} 인기상품".
    final categoryId = p.categoryPath.lastOrNull;
    final categoryName = categoryId == null
        ? null
        : ref
              .watch(categoriesProvider)
              .value
              ?.where((c) => c.categoryId == categoryId)
              .firstOrNull
              ?.name;
    // 원산지: 서버 칸 `origin`(product-content 0.9.0 BR-100 R1). 옛 응답이면 notices 의 "원산지:" 줄.
    final origin =
        p.origin ??
        p.notices
            .map(splitNotice)
            .where((n) => n.label == '원산지')
            .firstOrNull
            ?.value;
    final freeFrom = ref
        .watch(homeDeliveryOptionsProvider)
        .value
        ?.where((o) => o.available && o.mode != DeliveryMode.scheduled)
        .map((o) => o.freeTipFrom)
        .nonNulls
        .firstOrNull;
    final pad = const EdgeInsets.symmetric(horizontal: 16.7);
    Widget padded(Widget w) => Padding(padding: pad, child: w);

    Widget? shelf(
      String title,
      AsyncValue<List<ProductTile>?> v,
      Key key, {
      String? accent,
      bool rail = false,
    }) {
      final items = v.value;
      if (items == null || items.isEmpty) return null;
      return Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailSectionTitle(title, accent: accent),
          if (rail)
            DetailProductRail(items: items.take(10).toList())
          else
            DetailRowGrid(items: items.take(9).toList()),
          const SizedBox(height: 20),
        ],
      );
    }

    final viewed = categoryId == null
        ? null
        : shelf(
            l10n.productViewedTogether,
            ref.watch(
              relatedProductsProvider((
                productId: p.productId,
                categoryId: categoryId,
                kind: RelatedKind.viewedTogether,
              )),
            ),
            const ValueKey('shelf-viewed-together'),
            rail: true,
          );
    final topRated = categoryId == null
        ? null
        : shelf(
            l10n.productTopRated,
            ref.watch(
              categoryShelfProvider((
                categoryId: categoryId,
                sort: SortKey.rating,
                excludeId: p.productId,
              )),
            ),
            const ValueKey('shelf-top-rated'),
          );
    final bought = categoryId == null
        ? null
        : shelf(
            l10n.productBoughtTogether,
            ref.watch(
              relatedProductsProvider((
                productId: p.productId,
                categoryId: categoryId,
                kind: RelatedKind.boughtTogether,
              )),
            ),
            const ValueKey('shelf-bought-together'),
          );
    final popular = categoryId == null
        ? null
        : shelf(
            l10n.productCategoryPopular,
            ref.watch(
              categoryShelfProvider((
                categoryId: categoryId,
                sort: SortKey.popular,
                excludeId: p.productId,
              )),
            ),
            const ValueKey('shelf-category-popular'),
            accent: categoryName,
          );
    final banners = ref.watch(productPageBannersProvider).value ?? const [];

    final soldOut = reason == CannotBuyReason.soldOut;
    final before = <Widget>[
      // 사진(화면 폭 정사각형, 넓은 화면에서는 화면 높이 절반까지)
      LayoutBuilder(
        builder: (context, c) => Stack(
          children: [
            ProductImage(
              url: p.mainImageUrl,
              size: c.maxWidth,
              height: math.min(
                c.maxWidth,
                MediaQuery.sizeOf(context).height * 0.5,
              ),
              radius: 0,
            ),
            if (soldOut)
              Positioned.fill(
                child: ColoredBox(
                  key: const ValueKey('product-sold-out-cover'),
                  color: Colors.black.withValues(alpha: 0.42),
                  child: Center(
                    child: Text(
                      l10n.productSoldOutCover,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      if (reason != null && reason != CannotBuyReason.soldOut)
        Padding(
          padding: const EdgeInsets.fromLTRB(16.7, 14, 16.7, 0),
          child: _CannotBuyNotice(
            reason: reason,
            onRetry: () =>
                ref.invalidate(productDetailProvider(widget.productId)),
          ),
        ),
      // 이름 · 원산지 · 평점 칸 · 가격 · 단위가격(레퍼런스 순서)
      Padding(
        padding: const EdgeInsets.fromLTRB(16.7, 12, 16.7, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p.name,
              key: const ValueKey('product-name'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 16.7,
                height: 1.4,
                fontWeight: FontWeight.w400,
              ),
            ),
            if (origin != null)
              Text(
                l10n.productOriginLine(origin),
                key: const ValueKey('product-origin'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 16.2,
                  height: 1.4,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 8),
            Material(
              color: scheme.surface,
              shape: StadiumBorder(
                side: BorderSide(color: scheme.outlineVariant, width: 1.2),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('product-rating-pill'),
                // 누르면 바로 상품리뷰 전체 보기(사용자 2026-11-25). 아래 [리뷰] 탭은 이 화면의 리뷰 구획으로.
                onTap: hasRating
                    ? () => context.push('/products/${p.productId}/reviews')
                    : null,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasRating) ...[
                        const Icon(
                          Icons.star_rounded,
                          size: 17,
                          color: Color(0xFFFFB300),
                        ),
                        const SizedBox(width: 2),
                      ],
                      Flexible(
                        child: Text.rich(
                          hasRating
                              ? TextSpan(
                                  children: [
                                    TextSpan(
                                      text: rating.average.toStringAsFixed(1),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    TextSpan(
                                      text:
                                          ' ${l10n.reviewSectionCount(rating.count)}',
                                    ),
                                  ],
                                )
                              : TextSpan(text: l10n.ratingUnavailable),
                          key: const ValueKey('product-rating'),
                          semanticsLabel: ratingText(
                            l10n,
                            rating?.average,
                            rating?.count,
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 13.7,
                          ),
                        ),
                      ),
                      if (hasRating)
                        const PmartLineIcon(
                          PmartLineIcons.chevronRight,
                          size: 15,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (selected != null) ...[
              const SizedBox(height: 11),
              if ((selected.discount, selected.priceNotSet) case (
                final d?,
                false,
              ))
                DiscountPriceText(
                  key: const ValueKey('product-price'),
                  price: d.salePrice,
                  ratePercent: d.ratePercent,
                  base: selected.basePrice,
                  rateColor: const Color(0xFFFF3E3E),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontSize: 19.4,
                    fontWeight: FontWeight.w800,
                  ),
                )
              else
                Text(
                  _priceText(l10n, selected),
                  key: const ValueKey('product-price'),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontSize: 19.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              if (selected.unitPrice case final u?)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    l10n.unitPriceLine(
                      '${u.basis}${u.unitLabel}',
                      formatKrw(u.price),
                    ),
                    key: const ValueKey('product-unit-price'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13.4,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
      // 배달팁 0원 줄(홈과 같은 값 — BR-96)
      if (freeFrom != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16.7, 22, 16.7, 0),
          child: Material(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(11.4),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('product-free-tip'),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                useRootNavigator: true,
                isScrollControlled: true,
                builder: (_) => DeliveryGuideSheet(
                  options:
                      ref.read(homeDeliveryOptionsProvider).value ?? const [],
                ),
              ),
              child: SizedBox(
                height: 47,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
                  child: Row(
                    children: [
                      const ShieldPercentIcon(),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          l10n.homeFreeTipFrom(formatKrw(freeFrom)),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontSize: 15.2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const PmartLineIcon(
                        PmartLineIcons.chevronRight,
                        size: 17,
                        strokeWidth: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      // 쿠폰 줄(레퍼런스 "첫주문 7,000원 할인쿠폰" — 홈과 같은 서버 쿠폰 행사, 없으면 줄 없음).
      const Padding(
        padding: EdgeInsets.fromLTRB(16.7, 9.9, 16.7, 0),
        child: HomeCouponRow(key: ValueKey('product-coupon'), fontSize: 15.2),
      ),
      const SizedBox(height: 3.7),
      const DetailBand(),
      ?viewed,
      if (viewed != null) const DetailBand(),
      ?topRated,
      if (banners.isNotEmpty)
        SizedBox(
          key: const ValueKey('product-page-banner'),
          height: 91,
          child: BannerPager(banners: banners, onOpen: (_) {}),
        ),
    ];
    // [상품설명 | 리뷰 N] 탭 — 내려가면 위 막대 아래에 붙는다(레퍼런스 2026-11-26), 아래는 그 뒤 구획.
    final tabs = DetailTabs(
      reviewCount: rating?.count,
      reviewsSelected: _reviewsTab,
      onDescription: () => _scrollTo(_descriptionKey, reviews: false),
      onReviews: () => _scrollTo(_reviewsKey, reviews: true),
    );
    final after = <Widget>[
      KeyedSubtree(
        key: _descriptionKey,
        child: PurchaseNoteBox(product: p, onMore: () => _openInfo(p)),
      ),
      if (p.description != null || p.descriptionImageUrls.isNotEmpty)
        CollapsibleDescription(
          title: p.name,
          children: [
            if (p.description case final String d)
              padded(
                Text(
                  d,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
              ),
            if (p.descriptionImageUrls.isNotEmpty) ...[
              const SizedBox(height: 16),
              for (final (i, url) in p.descriptionImageUrls.indexed)
                padded(
                  ContentImage(key: ValueKey('description-image-$i'), url: url),
                ),
            ],
          ],
        )
      else
        const SizedBox(height: 24),
      const DetailBand(),
      // "우리동네 바로픽 마트, 이렇게 관리해요"(레퍼런스 5 — 사용자 2026-11-25 이름 "우리동네 바로픽 마트").
      const TownCareSection(),
      const DetailBand(),
      ?bought,
      if (bought != null) const DetailBand(),
      ?popular,
      if (popular != null) const DetailBand(),
      // 리뷰는 아래쪽(레퍼런스 — 사용자 2026-11-25 "리뷰 아래로 내려주고")
      KeyedSubtree(
        key: _reviewsKey,
        child: DetailReviewSection(productId: p.productId, rating: rating),
      ),
      const DetailBand(),
      DetailInfoRow(
        key: const ValueKey('product-info-row'),
        label: l10n.productDetailInfoRow,
        onTap: () => _openInfo(p),
      ),
      if (p.returnGuide case final String g)
        DetailInfoRow(
          key: const ValueKey('product-return-row'),
          label: l10n.productReturnInfo,
          onTap: () => showDetailTextSheet(
            context,
            title: l10n.productReturnInfo,
            body: Text(g, style: theme.textTheme.bodyMedium),
          ),
        ),
      const DetailBand(),
    ];
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.depth == 0 && n.metrics.axis == Axis.vertical) _syncTab();
        return false;
      },
      child: CustomScrollView(
        controller: _scroll,
        // 구획을 화면 밖으로 내려도 버리지 않는다(사용자 2026-11-25 폰: 내렸다 올리면 "막힌다" — 버린 선반이
        // 다시 읽는 동안 높이 0 이었다가 커지며 위치가 튀었다. [리뷰] 탭도 만들어지지 않은 리뷰 구획으로는
        // 이동하지 못했다). 상세 한 장이라 모두 붙잡아도 된다.
        scrollCacheExtent: const ScrollCacheExtent.pixels(100000),
        slivers: [
          SliverList.list(children: before),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabsHeader(tabs, key: _tabsKey),
          ),
          SliverList.list(children: after),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  /// 상세정보(영양·알레르기 + 상품정보 표 + 상세 이미지).
  void _openInfo(ProductDetail p) {
    final l10n = AppLocalizations.of(context);
    showDetailTextSheet(
      context,
      title: l10n.productDetailInfo,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (p.storageGuide case final String g) ...[
            Text(
              l10n.productStorageGuide,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(g),
            const SizedBox(height: 14),
          ],
          NutritionAllergenSection(
            nutrition: p.nutrition,
            allergens: p.allergens,
          ),
          if ((p.legalInfo?.isNotEmpty ?? false) || p.notices.isNotEmpty) ...[
            const SizedBox(height: 14),
            NoticeTable(
              rows: p.legalInfo ?? p.notices.map(splitNotice).toList(),
            ),
          ],
          for (final (i, url) in p.detailImageUrls.indexed)
            ContentImage(key: ValueKey('detail-image-$i'), url: url),
        ],
      ),
    );
  }
}

/// [구매하기] 시트 — 옵션(둘 이상이면 고르기)·수량·담기. 담기는 상세 응답 뒤에만(사본으로 확정하지 않는다).
/// 상품 상세와 리뷰 전체 보기(사용자 레퍼런스 2026-11-25 — 아래 막대)가 같이 쓴다.
Future<void> showProductBuySheet(BuildContext context, ProductDetail p) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => ProductBuySheet(product: p),
    );

class ProductBuySheet extends ConsumerStatefulWidget {
  const ProductBuySheet({super.key, required this.product});

  final ProductDetail product;

  @override
  ConsumerState<ProductBuySheet> createState() => _ProductBuySheetState();
}

/// 레퍼런스 7-3(사용자 2026-11-25): 옵션마다 사진 58.6 · 이름(보통 13.7) · "N개 남음"(빨강) · 할인율+가격(굵게 14.5) ·
/// 단위가격(11.8) · 오른쪽 수량 칸(98×35, 0 부터). 아래 [상품을 선택해 주세요](회색) → 고르면 [N개 담기].
/// 옵션 사진·"최대 N개 구매 가능(1회당)"은 계약에 없어(BR-101) 상품 대표 사진을 쓰고 최대 줄은 뺀다.
class _ProductBuySheetState extends ConsumerState<ProductBuySheet> {
  final Map<String, int> _qty = {};
  bool _busy = false;

  int get _total => _qty.values.fold(0, (a, b) => a + b);

  /// 고른 낱개 수 합(묶음 옵션은 묶음 수 × 개수) — 1회 최대(BR-101 `purchaseLimitUnits`)와 비교한다.
  int get _units => [
    for (final o in widget.product.options)
      (_qty[o.sku] ?? 0) * (o.unitsPerSku ?? 1),
  ].fold(0, (a, b) => a + b);

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final controller = ref.read(cartControllerProvider.notifier);
    setState(() => _busy = true);
    String? problem;
    for (final e in _qty.entries.where((e) => e.value > 0).toList()) {
      final outcome = await controller.submit(
        AddItem(sku: e.key, quantity: e.value),
      );
      if (outcome is CartChangeApplied) {
        if (mounted) setState(() => _qty.remove(e.key));
        continue;
      }
      problem = switch (outcome) {
        CartChangeRejected() => cartRejectionText(l10n, outcome),
        CartVersionConflict() => l10n.cartNoticeConflict,
        CartChangeUnknown() => l10n.cartChangeUnknown,
        CartChangeNotApplied() => l10n.cartNoticeNotApplied,
        _ => null,
      };
      break;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (problem != null) {
      messenger.notice(problem);
      return;
    }
    nav.pop();
    messenger.notice(l10n.cartAdded);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = widget.product;
    final cart = ref.watch(cartControllerProvider).value;
    final canChange = cart?.canChange ?? false;
    final total = _total;
    return SafeArea(
      child: Column(
        key: const ValueKey('buy-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 손잡이(39.6×3.8, #E5E6E8) — 시트 위 9.5.
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 9.5, bottom: 3),
              width: 39.6,
              height: 3.8,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E6E8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: p.options.length,
              separatorBuilder: (_, _) => const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.5),
                child: Divider(
                  height: 1.1,
                  thickness: 1.1,
                  color: Color(0xFFF2F3F4),
                ),
              ),
              itemBuilder: (context, i) {
                final o = p.options[i];
                final limit = p.purchaseLimitUnits;
                return _BuyOptionRow(
                  product: p,
                  option: o,
                  quantity: _qty[o.sku] ?? 0,
                  // 1회 최대를 넘게는 더하지 않는다(확정은 서버 거절 — BR-101).
                  canIncrease:
                      limit == null || _units + (o.unitsPerSku ?? 1) <= limit,
                  enabled: o.canOfferAdd && canChange && !_busy,
                  onChanged: (q) => setState(() => _qty[o.sku] = q),
                );
              },
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFF2F3F4))),
            ),
            padding: const EdgeInsets.fromLTRB(12.2, 11.8, 12.2, 10),
            child: SizedBox(
              height: 49.5,
              child: FilledButton(
                key: const ValueKey('add-to-cart'),
                style: FilledButton.styleFrom(
                  disabledBackgroundColor: const Color(0xFFD6D7D9),
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  // 앱 글꼴(Pretendard)을 잃지 않게 테마 글자에서 바꾼다.
                  textStyle: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontSize: 17.9, fontWeight: FontWeight.w700),
                ),
                onPressed: total > 0 && canChange && !_busy ? _submit : null,
                child: Text(
                  total == 0 ? l10n.buySheetPick : l10n.buySheetAdd(total),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BuyOptionRow extends StatelessWidget {
  const _BuyOptionRow({
    required this.product,
    required this.option,
    required this.quantity,
    required this.enabled,
    required this.onChanged,
    this.canIncrease = true,
  });

  final ProductDetail product;
  final SaleOption option;
  final int quantity;
  final bool enabled;
  final bool canIncrease;
  final ValueChanged<int> onChanged;

  static const _dark = Color(0xFF222222);
  static const _priceStyle = TextStyle(
    fontSize: 14.5,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: _dark,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final grey = Theme.of(context).colorScheme.onSurfaceVariant;
    final o = option;
    final notes = _optionNotes(
      l10n,
      o,
      withCapacity: o.label != null,
    ).join(' · ');
    return Padding(
      key: ValueKey('option-${o.sku}'),
      padding: const EdgeInsets.fromLTRB(20.5, 17, 20.2, 17),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: const Color(0xFFEDEEF0), width: 0.8),
            ),
            child: ProductImage(
              url: product.mainImageUrl,
              size: 58.6,
              radius: 7,
            ),
          ),
          const SizedBox(width: 13.7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  o.label ?? product.name,
                  style: const TextStyle(
                    fontSize: 13.7,
                    height: 1.35,
                    color: _dark,
                  ),
                ),
                if (o.lowStockQty case final n?) ...[
                  const SizedBox(height: 4),
                  LowStockText(n, key: ValueKey('option-low-stock-${o.sku}')),
                ],
                // "최대 N개 구매 가능(1회당)"(레퍼런스 7-3 — 보통 12, #7E807F, product-content 0.11.0
                // `purchaseLimitUnits` — 상품 단위 합).
                if (product.purchaseLimitUnits case final max?) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.buySheetMax(max),
                    key: ValueKey('option-max-${o.sku}'),
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: Color(0xFF7E807F),
                    ),
                  ),
                ],
                if (notes.isNotEmpty)
                  Text(
                    notes,
                    style: TextStyle(fontSize: 11.8, height: 1.35, color: grey),
                  ),
                const SizedBox(height: 9),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (o.discount case final d?)
                            DiscountPriceText(
                              price: d.salePrice,
                              ratePercent: d.ratePercent,
                              showBase: false,
                              rateColor: LowStockText.color,
                              style: _priceStyle,
                            )
                          else
                            Text(_priceText(l10n, o), style: _priceStyle),
                          if (o.unitPrice case final u?)
                            Text(
                              l10n.unitPriceLine(
                                '${u.basis}${u.unitLabel}',
                                formatKrw(u.price),
                              ),
                              style: TextStyle(
                                fontSize: 11.8,
                                height: 1.35,
                                color: grey,
                              ),
                            ),
                        ],
                      ),
                    ),
                    _QtyBox(
                      sku: o.sku,
                      value: quantity,
                      enabled: enabled,
                      canIncrease: canIncrease,
                      onChanged: onChanged,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 수량 칸(레퍼런스 7-3 — 98×35, 테두리 #E5E6E8, [— 0 +], 0 이면 빼기 흐림).
class _QtyBox extends StatelessWidget {
  const _QtyBox({
    required this.sku,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.canIncrease = true,
  });

  final String sku;
  final int value;
  final bool enabled;
  final bool canIncrease;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const on = Color(0xFF222222);
    const off = Color(0xFFD6D7D9);
    Widget button(String key, PmartLineIcons icon, VoidCallback? tap) =>
        InkWell(
          key: ValueKey('$key-$sku'),
          onTap: tap,
          child: SizedBox(
            width: 32,
            height: 35,
            child: Center(
              // 레퍼런스: 13dp, 선 약 1.3dp(+ 는 진하게, 0 일 때 − 는 흐리게).
              child: PmartLineIcon(
                icon,
                size: 15,
                strokeWidth: 2.2,
                color: tap == null ? off : on,
              ),
            ),
          ),
        );
    return Container(
      width: 98,
      height: 35.4,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E6E8)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          button(
            'add-dec',
            PmartLineIcons.minus,
            enabled && value > 0 ? () => onChanged(value - 1) : null,
          ),
          Expanded(
            child: Text(
              '$value',
              key: ValueKey('add-qty-$sku'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14.5, color: on),
            ),
          ),
          button(
            'add-inc',
            PmartLineIcons.plus,
            enabled && canIncrease ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

/// 담을 수 없는 까닭 안내(품절이 아닌 것): 배달 주소 없음 → 주소 정하기, 재고 조회 실패 → 다시 시도, 이 주소로 배달하지 않음.
class _CannotBuyNotice extends StatelessWidget {
  const _CannotBuyNotice({required this.reason, required this.onRetry});

  final CannotBuyReason reason;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final (text, action, onPressed) = switch (reason) {
      CannotBuyReason.noCenter => (
        l10n.productNeedAddress,
        l10n.productSetAddress,
        () => context.push('/addresses'),
      ),
      CannotBuyReason.stockUnknown => (
        l10n.productStockUnknown,
        l10n.startRetry,
        onRetry,
      ),
      _ => (l10n.productNotDelivered, null, null),
    };
    return Container(
      key: ValueKey('product-cannot-buy-${reason.name}'),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          PmartLineIcon(
            PmartLineIcons.alert,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(text, style: theme.textTheme.bodyMedium),
            ),
          ),
          if (action != null)
            TextButton(
              key: const ValueKey('product-cannot-buy-action'),
              onPressed: onPressed,
              child: Text(action),
            ),
        ],
      ),
    );
  }
}

/// 묶음·용량·재고 상태 보조 문구. [withCapacity] 가 false 면 용량은 제목에서 이미 보인 것이다.
Iterable<String> _optionNotes(
  AppLocalizations l10n,
  SaleOption o, {
  bool withCapacity = true,
}) => [
  if (o.unitType == UnitType.bundle && o.unitsPerSku != null)
    l10n.unitBundle(o.unitsPerSku!),
  if (withCapacity) ?o.capacityLabel,
  switch (o.availability) {
    _ when o.carried == false => l10n.notCarried,
    Availability.soldOut => l10n.soldOutTemporarily,
    // 남은 수량이 있으면 이름 아래 빨간 줄(레퍼런스 7-3)로 따로 그린다. 수가 없으면 "남은 수량이 적어요".
    Availability.low => o.lowStockQty == null ? l10n.availabilityLow : null,
    Availability.unknown => l10n.productStockUnknownShort,
    // 주소가 없어 모르는 것 — 화면 위 안내 줄 하나로 알린다(옵션마다 되풀이하지 않는다).
    Availability.noCenter => null,
    Availability.available => null,
  },
].nonNulls;

String _priceText(AppLocalizations l10n, SaleOption o) => switch (o) {
  SaleOption(priceNotSet: true) => l10n.priceNotSet,
  SaleOption(basePrice: final int price) => formatKrw(price),
  _ => l10n.priceUnavailable,
};

/// 옵션이 하나뿐인 상품: 선택 UI 없이 가격과 재고 상태만 보인다.
/// 상세 응답 전 카드 값으로 그리는 첫 화면(사진·이름·가격). 응답이 오면 그 값으로 바뀐다.
class _PreviewBody extends StatelessWidget {
  const _PreviewBody({required this.tile});

  final ProductTile tile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const ValueKey('product-preview'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final byHeight = MediaQuery.sizeOf(context).height * 0.5;
            return ProductImage(
              url: tile.imageUrl,
              size: c.maxWidth,
              height: c.maxWidth < byHeight ? c.maxWidth : byHeight,
              radius: 0,
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tile.name,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 17,
                  height: 1.35,
                  fontWeight: FontWeight.w400,
                ),
              ),
              if (tile.basePrice case final price?) ...[
                const SizedBox(height: 10),
                Text(
                  formatKrw(price),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const LinearProgressIndicator(),
            ],
          ),
        ),
      ],
    );
  }
}

/// 초안 14 B 영양·알레르기 구획: 분홍 테두리 알레르기 칸(함유 칩 · 같은 시설 제조 칩 · 표시사항 원문) + 영양 표(100g·100mL당 5줄).
/// 모르는 것은 숨기지 않고 회색 "정보 없음"(알레르기 "없음"·0 으로 보이지 않는다 — 고객 안전 정보).
class NutritionAllergenSection extends StatelessWidget {
  const NutritionAllergenSection({
    super.key,
    required this.nutrition,
    required this.allergens,
  });

  final ProductNutrition? nutrition;
  final ProductAllergens? allergens;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('nutrition-allergen'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.nutriAllergenTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 10),
        switch (allergens) {
          final a? when !a.unknown => _AllergenBox(allergens: a),
          _ => _UnknownBox(
            key: const ValueKey('allergen-unknown'),
            title: l10n.allergenInfoTitle,
            body: l10n.allergenUnknown,
          ),
        },
        const SizedBox(height: 10),
        switch (nutrition) {
          final n? => _NutritionTable(nutrition: n),
          null => _UnknownBox(
            key: const ValueKey('nutrition-unknown'),
            title: l10n.nutritionTitle,
            body: l10n.nutritionUnknown,
          ),
        },
      ],
    );
  }
}

/// 모름 칸: 회색 바탕 + 회색 테두리, ⓘ 제목 + 안내.
class _UnknownBox extends StatelessWidget {
  const _UnknownBox({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PmartLineIcon(
                PmartLineIcons.info,
                size: 16,
                color: scheme.onSurface,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 13,
              height: 1.45,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _AllergenBox extends StatelessWidget {
  const _AllergenBox({required this.allergens});

  final ProductAllergens allergens;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final a = allergens;
    Widget row(String label, List<String> names, String key) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ),
          ),
          Expanded(
            child: names.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      l10n.nutritionNoValue,
                      key: ValueKey('$key-none'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Wrap(
                    key: ValueKey(key),
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final n in names)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: scheme.tertiary),
                          ),
                          child: Text(
                            n,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: scheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
    return Container(
      key: const ValueKey('allergen-box'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.tertiary, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PmartLineIcon(
                PmartLineIcons.alert,
                size: 17,
                color: scheme.tertiary,
              ),
              const SizedBox(width: 6),
              Text(
                l10n.allergenTitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.tertiary,
                ),
              ),
            ],
          ),
          row(l10n.allergenContains, a.contains, 'allergen-contains'),
          row(l10n.allergenMayContain, a.mayContain, 'allergen-may-contain'),
          if (a.text case final t?)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                l10n.allergenText(t),
                key: const ValueKey('allergen-text'),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  height: 1.45,
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NutritionTable extends StatelessWidget {
  const _NutritionTable({required this.nutrition});

  final ProductNutrition nutrition;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final n = nutrition;
    // 서버 값 그대로(천 단위만 띄움) — 반올림·계산하지 않는다.
    String num0(num v) => NumberFormat('#,##0.###', 'ko').format(v);
    Widget line(String label, num? v, String Function(String) unit, int i) =>
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              const Spacer(),
              Text(
                v == null ? l10n.nutritionNoValue : unit(num0(v)),
                key: ValueKey('nutrition-row-$i'),
                style: v == null
                    ? theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      )
                    : theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
              ),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('nutrition-table'),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: scheme.surfaceContainerLow,
                padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                child: Row(
                  children: [
                    Text(
                      l10n.nutritionTitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      n.basis == NutritionBasis.milliliter
                          ? l10n.nutritionBasisMl
                          : l10n.nutritionBasisG,
                      key: const ValueKey('nutrition-basis'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              line(l10n.nutritionEnergy, n.energyKcal, l10n.nutritionKcal, 0),
              line(l10n.nutritionSodium, n.sodiumMg, l10n.nutritionMg, 1),
              line(l10n.nutritionSugars, n.sugarsG, l10n.nutritionGram, 2),
              line(l10n.nutritionProtein, n.proteinG, l10n.nutritionGram, 3),
              line(l10n.nutritionFat, n.fatG, l10n.nutritionGram, 4),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.nutritionNote,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 붙는 [상품설명 | 리뷰 N] 탭(높이 50 + 아래 선 1).
class _TabsHeader extends SliverPersistentHeaderDelegate {
  const _TabsHeader(this.tabs, {required this.key});

  final DetailTabs tabs;
  final GlobalKey key;

  static const extent = 51.0;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      SizedBox(key: key, height: extent, child: tabs);

  @override
  bool shouldRebuild(_TabsHeader old) =>
      old.tabs.reviewsSelected != tabs.reviewsSelected ||
      old.tabs.reviewCount != tabs.reviewCount;
}
