import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../../l10n/gen/app_localizations.dart';
import '../../../../shared/providers.dart';
import '../../domain/catalog.dart';
import 'discount_price.dart';
import '../../../wishlist/presentation/wish_heart_button.dart';
import 'quick_add_button.dart';
import '../../../../shared/network_image.dart';

/// 상품 이미지. 주소가 없거나 받지 못하면 자리표시를 그린다.
class ProductImage extends ConsumerWidget {
  const ProductImage({
    super.key,
    this.url,
    this.size = 72,
    this.radius = 12,
    this.height,
  });

  final String? url;

  /// 폭(정사각형이면 높이도). 높이를 따로 주려면 [height].
  final double size;
  final double radius;
  final double? height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final h = height ?? size;
    final placeholder = Container(
      width: size,
      height: h,
      color: scheme.surfaceContainerHigh,
      child: Icon(
        Icons.image_outlined,
        size: ((h < size ? h : size) / 3).clamp(20, 56).toDouble(),
        color: scheme.outline.withValues(alpha: 0.6),
      ),
    );
    // 서버 이미지는 상대 경로라 게이트웨이 주소를 붙여야 받을 수 있다.
    // 서버 축소본: 그릴 크기(긴 변 × 화소 비율)에 맞는 240·480·720(백엔드 요청 R3).
    final px = (size > h ? size : h) * MediaQuery.devicePixelRatioOf(context);
    final u = resolveImageUrl(
      withImageWidth(url, px),
      ref.watch(imageOriginProvider),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: u == null
          ? placeholder
          : pmartNetworkImage(
              u,
              width: size,
              height: h,
              fit: BoxFit.cover,
              // 원본(예 1080px)을 그대로 풀지 않고 그릴 크기만큼만 디코딩한다(백엔드 요청 2026-11-19 — 메모리·속도).
              // 채우기(cover)라 긴 변 기준으로 잡는다.
              cacheWidth:
                  ((size > h ? size : h) *
                          MediaQuery.devicePixelRatioOf(context))
                      .round(),
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}

/// 평점·리뷰 수. 집계가 없으면 "평점 정보 없음"(0점·0건으로 바꾸지 않는다).
String ratingText(AppLocalizations l10n, double? rating, int? count) =>
    (rating == null || count == null)
    ? l10n.ratingUnavailable
    : l10n.ratingValue(
        rating.toStringAsFixed(1),
        NumberFormat.decimalPattern('ko').format(count),
      );

/// 평점 한 줄(별 + 글자). 집계가 없으면 글자만.
class RatingLine extends StatelessWidget {
  const RatingLine({super.key, this.rating, this.count});

  final double? rating;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(fontSize: 12);
    if (rating == null || count == null) {
      return Text(
        ratingText(l10n, rating, count),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: small,
      );
    }
    // 레퍼런스: 작은 노란 별 + 굵은 검정 점수 + 회색 "(개수)"
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.star_rounded,
          size: MediaQuery.textScalerOf(context).scale(13),
          color: const Color(0xFFFFB300),
        ),
        const SizedBox(width: 1),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: rating!.toStringAsFixed(1),
                  style: small?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: ' (${NumberFormat.decimalPattern('ko').format(count)})',
                ),
              ],
            ),
            semanticsLabel: ratingText(l10n, rating, count),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: small,
          ),
        ),
      ],
    );
  }
}

class ProductTileCard extends StatelessWidget {
  const ProductTileCard({
    super.key,
    required this.tile,
    this.onTap,
    this.quickAdd = true,
    this.rail = false,
    this.highlight,
    this.look = TileLook.standard,
  });

  /// 글자·간격 모양(기본은 지금 그대로). 장바구니 추천 시트는 [TileLook.cartSheet].
  final TileLook look;

  final ProductTile tile;
  final VoidCallback? onTap;

  /// 이름에서 보라 굵게 보일 글자(검색어, 초안 16 B). 없으면 그대로.
  final String? highlight;

  /// 이미지 위 `+` 바로 담기. 담을 수 있어 보이는 카드에만 보인다([QuickAddButton.offeredFor]).
  final bool quickAdd;

  /// 가로 진열용(사진 위, 글자 아래). false 면 세로 목록용(사진 왼쪽).
  final bool rail;

  /// 가로 진열 카드 폭(레퍼런스: 360dp 에 세 장 반, 한 장 약 97dp). 사진은 칸 폭을 채운 정사각형이다.
  static double railWidthOf(BuildContext context) =>
      ((MediaQuery.sizeOf(context).width - 14 - 8 * 3) / 3.3)
          .clamp(94, 132)
          .toDouble();

  /// 2칸 격자의 한 칸 폭(좌우 여백 16, 칸 사이 12).
  static double gridWidthOf(BuildContext context) =>
      (MediaQuery.sizeOf(context).width - 16 * 2 - 12) / 2;

  /// 칸 폭 [width] 인 카드 한 장의 높이. 사진 + 이름 2줄·가격·평점·상태 문구가 들어가는 높이에
  /// 기기 글자 크기 설정을 반영한다.
  /// [rank] 면 사진 위 순위 숫자 줄만큼 더한다.
  static double heightFor(
    BuildContext context,
    double width, {
    bool rank = false,
  }) =>
      width +
      8 +
      (rank ? 22 : 0) +
      MediaQuery.textScalerOf(context).scale(122).clamp(122, 270).toDouble();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dimmed = !tile.canOfferAdd;
    final status = switch ((tile.saleState, tile.carried)) {
      (SaleState.temporarilySoldOut, _) => l10n.soldOutTemporarily,
      _ when tile.soldOut => l10n.listSoldOut,
      (_, false) => l10n.notCarried,
      (SaleState.unknown, _) => l10n.saleStateUnknown,
      _ => null,
    };
    final badge = switch (tile.badge) {
      DisplayBadge.isNew => _CornerBadge(l10n.badgeNew),
      // 가로 진열은 순위를 사진 위 숫자로 그린다. 세로 목록만 모서리 꼬리표.
      DisplayBadge.rank when tile.rank != null && !rail => _CornerBadge(
        l10n.badgeRank(tile.rank!),
      ),
      _ => null,
    };
    // 담기 버튼은 카드(상세 이동)와 따로 눌린다 — 상세 이동이 담기로 실행되지 않는다.
    Widget imageOf(double size) => Stack(
      children: [
        DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
              width: 0.8,
            ),
          ),
          child: ProductImage(url: tile.imageUrl, size: size, radius: 8),
        ),
        // 품절·미취급은 사진을 어둡게 덮고 가운데에 상태를 적는다(레퍼런스 "다 팔렸어요").
        // 칸 카드는 높이가 고정이라 상태 문구를 아래 줄에 더하지 않는다 — 더하면 아래가 넘친다(BOTTOM OVERFLOWED).
        if (rail && status != null)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.38),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  // 사진에 박힌 "일시품절"은 글꼴이 달라 가장자리가 비친다 — 아래를 흐린 덮개로 가리고 흰 글자
                  // (사용자 2026-11-26). 크기는 사진 폭 비율(그려진 글자 높이와 같게).
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 사진 속 글자 자리(폭 0.345·높이 0.084)를 덮개 색으로 흐리게 덮는다 — 가장자리는 번져
                      // 테두리처럼 보이지 않는다(사용자 2026-11-26 "그라데이션으로 자연스럽게").
                      IgnorePointer(
                        child: ImageFiltered(
                          imageFilter: ui.ImageFilter.blur(
                            sigmaX: size * 0.03,
                            sigmaY: size * 0.03,
                          ),
                          child: Container(
                            width: size * 0.38,
                            height: size * 0.105,
                            decoration: BoxDecoration(
                              color: const Color(0xFF403C3A),
                              borderRadius: BorderRadius.circular(size * 0.05),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        status,
                        key: ValueKey('tile-status-${tile.productId}'),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontSize: size * _soldTextRatio,
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (badge != null) Positioned(left: 0, top: 0, child: badge),
        // 찜 하트(customer 0.13.0) — 카드(상세 이동)와 따로 눌린다.
        if (look.showWish)
          Positioned(
            right: 5,
            top: 5,
            child: WishHeartButton(
              key: ValueKey('tile-wish-${tile.productId}'),
              productId: tile.productId,
              size: 16,
              onImage: true,
            ),
          ),
        // 상품 사진(서버 그림)에 + 동그라미가 그려져 있다 — 같은 자리·같은 크기로 덮어 겹쳐 보이지 않게(사용자
        // 2026-11-26, 폰 캡처 실측: 지름 = 사진 폭 × 0.242, 오른쪽·아래 여백 × 0.038, + 길이 = 지름 × 0.47).
        if (quickAdd && QuickAddButton.offeredFor(tile))
          Positioned(
            right: size * _addInsetRatio,
            bottom: size * _addInsetRatio,
            child: QuickAddButton(
              tile: tile,
              size: size * _addSizeRatio,
              iconSize: size * _addSizeRatio * 0.47,
              strokeWidth: size * _addSizeRatio * 0.035,
            ),
          ),
      ],
    );
    // 레퍼런스(3-2 TOP 30·신상품 카드): 이름 14sp 2줄 → 가격 14sp 굵게 → 회색 "100g당 999원" → 별점
    final info = <Widget>[
      HighlightedName(
        // 단어 중간에서 줄을 바꾸지 않게(장바구니 추천 시트 — 레퍼런스는 띄어쓰기에서만 줄바꿈).
        name: look.keepWords ? keepWordsTogether(tile.name) : tile.name,
        highlight: highlight,
        maxLines: 2,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: look.nameSize,
          height: look.nameLineHeight,
          color: look.dark ? theme.colorScheme.onSurface : null,
          fontWeight: look.nameWeight,
        ),
      ),
      SizedBox(height: look.priceGap),
      // 기간 할인(ADR-0082 4단계): 레퍼런스 TOP 30 카드처럼 빨간 할인율 + 할인가(정가 취소선 없음). 서버 값만.
      if (tile.discount case final d?)
        DiscountPriceText(
          key: ValueKey('tile-discount-${tile.productId}'),
          price: d.salePrice,
          ratePercent: d.ratePercent,
          showBase: false,
          rateColor: look.rateColor ?? discountRateColor,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: look.priceSize,
            fontWeight: look.priceWeight,
          ),
        )
      else
        Text(
          switch (tile.basePrice) {
            final int p => formatKrw(p),
            null => l10n.priceUnavailable,
          },
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: look.priceSize,
            fontWeight: look.priceWeight,
          ),
        ),
      if (tile.unitPrice case final u? when !look.compact)
        Text(
          l10n.unitPriceLine('${u.basis}${u.unitLabel}', formatKrw(u.price)),
          key: ValueKey('tile-unit-price-${tile.productId}'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: look.unitSize,
            fontWeight: look.unitWeight,
            color: look.dark
                ? theme.colorScheme.onSurface.withValues(alpha: 0.72)
                : null,
          ),
        ),
      if (!look.compact) SizedBox(height: look.ratingGap),
      // 장바구니 추천 시트는 평점이 없으면 줄을 비운다(레퍼런스).
      if (!look.compact && !(look.hideNoRating && tile.rating == null))
        RatingLine(rating: tile.rating, count: tile.reviewCount),
      // "N개 남음"(BR-100 R7 — 서버가 10개 이하일 때만). 레퍼런스 7-1: 평점 아래 빨간 한 줄
      // (Pretendard 보통 12, #FA4240). 안내일 뿐 확보가 아니다.
      if (tile.lowStockQty case final left? when status == null) ...[
        // 평점 글자 아래 끝 → 빨간 글자 위 끝 18px/1080(레퍼런스 7-1 실측).
        const SizedBox(height: 2.5),
        LowStockText(left, key: ValueKey('tile-low-stock-${tile.productId}')),
      ],
      // 세로 목록(높이 고정 아님)만 아래 줄에 상태를 적는다. 칸 카드는 사진 위에 적었다.
      if (status != null && !rail) ...[
        const SizedBox(height: 4),
        Text(
          status,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ],
    ];
    // 레퍼런스: 품절은 사진만 어둡게 덮고(위 imageOf) 이름·가격 글자는 그대로 진하다. 세로 목록만 살짝 흐리게.
    return InkWell(
      key: ValueKey('tile-${tile.productId}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: dimmed && !rail ? 0.55 : 1,
        child: rail
            ? LayoutBuilder(
                builder: (context, c) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 순위 진열은 사진 위에 굵은 숫자(레퍼런스 TOP 30)
                    if (tile.badge == DisplayBadge.rank &&
                        tile.rank != null &&
                        !look.compact)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${tile.rank}',
                          key: ValueKey('tile-rank-${tile.productId}'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                      ),
                    imageOf(c.maxWidth),
                    SizedBox(height: look.imageGap),
                    ...info,
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    imageOf(96),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: info,
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

/// 사진 왼쪽 위 모서리에 붙는 꼬리표(NEW·순위).
class _CornerBadge extends StatelessWidget {
  const _CornerBadge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          bottomRight: Radius.circular(6),
        ),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
}

/// 상품 이름 — [highlight] 와 같은 글자(공백 무시 없이 그대로, 대소문자 같게)를 보라 굵게(초안 16 B 검색어 강조).
class HighlightedName extends StatelessWidget {
  const HighlightedName({
    super.key,
    required this.name,
    this.highlight,
    this.maxLines,
    this.style,
  });

  final String name;
  final String? highlight;
  final int? maxLines;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base =
        style ??
        theme.textTheme.bodyMedium?.copyWith(fontSize: 14, height: 1.25);
    final h = highlight?.trim();
    if (h == null || h.isEmpty) {
      return Text(
        name,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: base,
      );
    }
    final lower = name.toLowerCase();
    final needle = h.toLowerCase();
    final spans = <TextSpan>[];
    var i = 0;
    while (true) {
      final j = lower.indexOf(needle, i);
      if (j < 0) {
        spans.add(TextSpan(text: name.substring(i)));
        break;
      }
      if (j > i) spans.add(TextSpan(text: name.substring(i, j)));
      spans.add(
        TextSpan(
          text: name.substring(j, j + needle.length),
          style: TextStyle(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      i = j + needle.length;
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: base,
    );
  }
}

/// 사진에 그려진 + 동그라미·"일시품절" 글자와 같은 크기·자리(사진 폭에 대한 비율, 폰 캡처 2026-11-26 실측:
/// 서버 사진 475px 에 지름 115px·여백 18px·+ 54px·선 4px, 글자 높이 40px·가운데).
const _addSizeRatio = 0.242;
const _addInsetRatio = 0.038;
const _soldTextRatio = 0.107;

/// 상품 칸 카드의 글자·간격 모양. [standard] 는 지금까지의 모양 그대로(홈·검색·카테고리).
@immutable
class TileLook {
  const TileLook({
    this.showWish = true,
    this.nameLineHeight = 1.25,
    this.priceSize = 14,
    this.imageGap = 8,
    this.ratingGap = 2,
    this.addSize = 30,
    this.addIconSize = 20,
    this.dark = false,
    this.unitSize = 10,
    this.keepWords = false,
    this.rateColor,
    this.hideNoRating = false,
    this.nameWeight,
    this.priceWeight = FontWeight.w700,
    this.unitWeight,
    this.nameSize = 14,
    this.compact = false,
    this.priceGap = 4,
  });

  /// 이름 → 가격 사이.
  final double priceGap;

  /// 이름·가격·"N개 남음"만(단위가격·평점·순위 숫자 없음) — 빈 장바구니 추천(레퍼런스 2026-11-26).
  final bool compact;

  static const standard = TileLook();

  /// 장바구니 막대 펼친 시트(사용자 새 UI 2026-11-24, 폰 캡처 px ÷ 2.625 실측): 하트 없음, 사진 → 이름 7.2,
  /// 이름 줄 21dp, 가격 13, 단위가격 → 평점 4.7, + 동그라미 32.4(+ 22), 이름·단위가격 진한 글자.
  static const cartSheet = TileLook(
    showWish: false,
    nameLineHeight: 1.5,
    priceSize: 13,
    imageGap: 7.2,
    ratingGap: 4.7,
    addSize: 32.4,
    addIconSize: 22,
    dark: true,
    unitSize: 10,
    keepWords: true,
    rateColor: Color(0xFFFF3E3E),
    hideNoRating: true,
    // 폰 캡처 3배 확대 비교(획 굵기): 이름은 SemiBold, 가격은 ExtraBold, 단위가격은 SemiBold.
    nameWeight: FontWeight.w600,
    priceWeight: FontWeight.w800,
    unitWeight: FontWeight.w600,
  );

  /// 빈 장바구니 아래 추천(레퍼런스 2026-11-26, 1080px = 411dp(S23) 실측): 하트 없음, 이름 11.6 보통·줄 1.43,
  /// 가격 11.4 아주 굵게, + 동그라미 30.3.
  static const emptyCart = TileLook(
    showWish: false,
    nameLineHeight: 1.43,
    nameSize: 12.4,
    priceSize: 12.2,
    imageGap: 5.5,
    priceGap: 0,
    ratingGap: 2,
    addSize: 32.5,
    addIconSize: 22.1,
    dark: true,
    keepWords: true,
    rateColor: Color(0xFFFF3E3E),
    hideNoRating: true,
    nameWeight: FontWeight.w400,
    priceWeight: FontWeight.w800,
    compact: true,
  );

  /// 상품 상세 "다른 사람들이 함께 본 상품" 가로 진열(레퍼런스 2026-11-25 실측): 이름 15.8 보통·줄 1.25,
  /// 가격 13.7 굵게, 단위가격 11.3, 하트 없음.
  static const detailRail = TileLook(
    showWish: false,
    nameLineHeight: 1.25,
    priceSize: 13.7,
    imageGap: 7,
    ratingGap: 2,
    addSize: 32.4,
    addIconSize: 22,
    dark: true,
    unitSize: 11.3,
    keepWords: true,
    rateColor: Color(0xFFFF3E3E),
    hideNoRating: true,
    nameSize: 15.8,
    nameWeight: FontWeight.w400,
    priceWeight: FontWeight.w800,
    unitWeight: FontWeight.w500,
  );

  final bool showWish;
  final double nameLineHeight;
  final double priceSize;
  final double imageGap;
  final double ratingGap;
  final double addSize;
  final double addIconSize;

  /// 이름·단위가격을 진한 글자로.
  final bool dark;
  final double unitSize;

  /// 띄어쓰기에서만 줄을 바꾼다.
  final bool keepWords;

  /// 할인율 색(null 이면 기본 [discountRateColor]).
  final Color? rateColor;

  /// 평점이 없으면 "평점 정보 없음" 대신 줄을 비운다.
  final bool hideNoRating;
  final FontWeight? nameWeight;
  final FontWeight priceWeight;
  final FontWeight? unitWeight;
  final double nameSize;
}

/// 글자 사이에 줄바꿈 금지 문자(U+2060)를 넣어 띄어쓰기에서만 줄이 바뀌게 한다(한글은 글자마다 줄이 바뀐다).
String keepWordsTogether(String s) =>
    s.split(' ').map((w) => w.characters.join('⁠')).join(' ');

/// "N개 남음" 빨간 한 줄(레퍼런스 7-1 카드·7-3 구매 시트 — Pretendard 보통 12dp — 폭 103px/1080 실측, #FA4240).
class LowStockText extends StatelessWidget {
  const LowStockText(this.count, {super.key});

  final int count;

  static const color = Color(0xFFFA4240);

  @override
  Widget build(BuildContext context) => Text(
    AppLocalizations.of(context).stockLeft(count),
    maxLines: 1,
    style: const TextStyle(
      fontSize: 12,
      height: 1.25,
      fontWeight: FontWeight.w400,
      color: color,
    ),
  );
}
