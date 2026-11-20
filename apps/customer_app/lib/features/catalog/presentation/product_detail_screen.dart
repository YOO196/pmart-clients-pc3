import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/cart_icon_button.dart';
import '../../../shared/ui_state_of.dart';
import '../../wishlist/presentation/wish_heart_button.dart';
import '../domain/catalog.dart';
import 'catalog_providers.dart';
import '../../reviews/presentation/reviews_screens.dart'
    show ProductReviewsPreview;
import '../../cart/presentation/cart_screen.dart' show AddToCartBar;
import 'widgets/content_image.dart';
import 'widgets/product_tile_card.dart';

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

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  String? _selectedSku;

  @override
  void initState() {
    super.initState();
    // 몇 분 붙잡아 둔 상세가 있으면 그것을 바로 보이고, 가격·재고는 뒤에서 다시 읽는다(R2).
    final provider = productDetailProvider(widget.productId);
    if (ref.read(provider).hasValue) ref.invalidate(provider);
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
            onPressed: () => context.go('/search'),
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
                ready: (context, p) => _body(context, l10n, p),
              ),
            },
      bottomNavigationBar: switch (value) {
        AsyncData(value: final p) => Builder(
          builder: (context) {
            final selected = _selected(p);
            return AddToCartBar(
              sku: selected?.sku,
              enabled: selected?.canOfferAdd ?? false,
              // 찜 하트(customer 0.13.0 — 레퍼런스 4-1 아래 막대 왼쪽)
              leading: WishHeartButton(
                key: const ValueKey('detail-wish'),
                productId: p.productId,
                size: 26,
              ),
            );
          },
        ),
        _ => null,
      },
    );
  }

  SaleOption? _selected(ProductDetail p) =>
      p.options.where((o) => o.sku == _selectedSku).firstOrNull ??
      p.options.where((o) => o.canOfferAdd).firstOrNull;

  Widget _body(BuildContext context, AppLocalizations l10n, ProductDetail p) {
    final theme = Theme.of(context);
    final selected = _selected(p);
    final bodyTone = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final scheme = theme.colorScheme;
    // 평점: 상세 응답 rating(product-content 0.3.0 — BR-63, 집계와 같은 값). 비어 오면 그때만 평점 집계를 부른다.
    final rating =
        p.rating ?? ref.watch(productRatingProvider(p.productId)).value;

    final hasRating = rating != null;
    // 사진 아래 내용(좌우 여백 16). 구획 띠([PmartSectionGap])만 화면 폭을 채운다.
    final reason = p.cannotBuyReason;
    final rest = <Widget>[
      if (reason != null && reason != CannotBuyReason.soldOut) ...[
        const SizedBox(height: 14),
        _CannotBuyNotice(
          reason: reason,
          onRetry: () =>
              ref.invalidate(productDetailProvider(widget.productId)),
        ),
      ],
      const SizedBox(height: 14),
      Text(
        p.name,
        style: theme.textTheme.titleLarge?.copyWith(
          fontSize: 15,
          height: 1.35,
          fontWeight: FontWeight.w400,
        ),
      ),
      const SizedBox(height: 10),
      // 평점 알약(레퍼런스 4-1): "★ 4.9 리뷰 12,569개 >" — 누르면 리뷰 전체
      Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: scheme.surface,
          shape: StadiumBorder(
            side: BorderSide(color: scheme.outlineVariant, width: 1.2),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('product-rating-pill'),
            onTap: hasRating
                ? () => context.push('/products/${p.productId}/reviews')
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 5, 8, 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasRating) ...[
                    const Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: Color(0xFFFFB300),
                    ),
                    const SizedBox(width: 3),
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
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                    ),
                  ),
                  if (hasRating)
                    const PmartLineIcon(PmartLineIcons.chevronRight, size: 16),
                ],
              ),
            ),
          ),
        ),
      ),
      // 큰 가격 + 단위 가격(레퍼런스 4-1) — 고른 옵션의 서버 값
      if (selected != null) ...[
        const SizedBox(height: 12),
        Text(
          _priceText(l10n, selected),
          key: const ValueKey('product-price'),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (selected.unitPrice case final u?)
          Text(
            l10n.unitPriceLine('${u.basis}${u.unitLabel}', formatKrw(u.price)),
            key: const ValueKey('product-unit-price'),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 11.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
      const SizedBox(height: 16),
      // 옵션이 하나뿐이면 고를 것이 없으니 가격·재고만 보이고, 둘 이상일 때만 옵션 선택을 연다.
      if (p.options case [final only])
        _SingleOptionSummary(option: only)
      else ...[
        Text(l10n.productOptions, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        RadioGroup<String>(
          groupValue: selected?.sku,
          onChanged: (sku) => setState(() => _selectedSku = sku),
          child: Column(
            children: [
              for (final o in p.options)
                _OptionTile(option: o, selected: o.sku == selected?.sku),
            ],
          ),
        ),
      ],
      const SizedBox(height: 6),
      Text(l10n.priceNote, style: theme.textTheme.bodySmall),
      const SizedBox(height: 20),
      const PmartSectionGap(),
      const SizedBox(height: 20),
      // 리뷰 미리보기(GET /products/{id}/reviews). 실패는 "리뷰 없음"이 아니라 실패로 보인다.
      ProductReviewsPreview(productId: p.productId),
      if (p.description != null || p.descriptionImageUrls.isNotEmpty) ...[
        const _DetailDivider(),
        Text(l10n.productDescription, style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        if (p.description case final String d) Text(d, style: bodyTone),
        if (p.descriptionImageUrls.isNotEmpty) ...[
          const SizedBox(height: 8),
          // 롱이미지 조각은 sortOrder 순서로 간격 없이 이어 붙인다.
          for (final (i, url) in p.descriptionImageUrls.indexed)
            ContentImage(key: ValueKey('description-image-$i'), url: url),
        ],
      ],
      if (p.storageGuide case final String g) ...[
        const _DetailDivider(),
        Text(l10n.productStorageGuide, style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(g, style: bodyTone),
      ],
      if (p.returnGuide case final String g) ...[
        const _DetailDivider(),
        Text(l10n.productReturnGuide, style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(g, style: bodyTone),
      ],
      if (p.notices.isNotEmpty) ...[
        const _DetailDivider(),
        Text(l10n.productNotices, style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        for (final n in p.notices) Text('· $n', style: bodyTone),
      ],
      if (p.detailImageUrls.isNotEmpty) ...[
        const _DetailDivider(),
        Text(l10n.productDetailInfo, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final (i, url) in p.detailImageUrls.indexed)
          ContentImage(key: ValueKey('detail-image-$i'), url: url),
      ],
    ];
    // 위 사진 + 나머지 줄. 화면에 들어올 때 만든다(설명 이미지 여러 장을 처음에 다 만들지 않게 — 백엔드 요청 2026-11-19).
    // 정말 다 팔렸을 때만 사진을 어둡게 덮고 "다 팔렸어요"(레퍼런스 4-1). 주소 없음·재고 조회 실패·배달 안 함은
    // 품절이 아니라 위 안내 줄로 알린다(백엔드 요청 2026-11-20 availability-display).
    final soldOut = reason == CannotBuyReason.soldOut;
    Widget item(int i) {
      if (i == 0) {
        return LayoutBuilder(
          // 레퍼런스: 화면 폭 정사각형(360dp)
          builder: (context, c) => Stack(
            children: [
              ProductImage(
                url: p.mainImageUrl,
                size: c.maxWidth,
                // 넓은 화면에서 사진이 내용을 다 밀어내지 않게 화면 높이 절반까지만
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
        );
      }
      final w = rest[i - 1];
      return w is PmartSectionGap
          ? w
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: w,
            );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: rest.length + 1,
      itemBuilder: (context, i) => item(i),
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
    Availability.low => l10n.availabilityLow,
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
class _SingleOptionSummary extends StatelessWidget {
  const _SingleOptionSummary({required this.option});

  final SaleOption option;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final notes = _optionNotes(l10n, option).join(' · ');
    return Column(
      key: ValueKey('option-${option.sku}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 가격은 위 큰 가격 줄에 있다(레퍼런스 4-1). 여기는 재고·용량 보조 문구만.
        if (notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              notes,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// 상세 구획 사이 선(위아래 여백 포함).
class _DetailDivider extends StatelessWidget {
  const _DetailDivider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 20),
    child: Divider(),
  );
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.option, required this.selected});

  final SaleOption option;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final o = option;
    // 라벨이 없으면 용량, 그것도 없으면 "기본". SKU 코드는 보이지 않는다.
    final title = o.label ?? o.capacityLabel ?? l10n.optionDefault;
    final notes = _optionNotes(
      l10n,
      o,
      withCapacity: o.label != null,
    ).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        clipBehavior: Clip.antiAlias,
        color: selected ? scheme.surfaceContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: RadioListTile<String>(
          key: ValueKey('option-${o.sku}'),
          value: o.sku,
          enabled: o.canOfferAdd,
          contentPadding: const EdgeInsets.only(left: 4, right: 16),
          title: Text(title),
          subtitle: notes.isEmpty ? null : Text(notes),
          secondary: Text(
            _priceText(l10n, o),
            style: theme.textTheme.titleMedium,
          ),
        ),
      ),
    );
  }
}

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
