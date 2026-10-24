import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../../l10n/gen/app_localizations.dart';
import '../../domain/catalog.dart';

/// 상품 이미지. 주소가 없거나 받지 못하면 자리표시를 그린다.
class ProductImage extends StatelessWidget {
  const ProductImage({super.key, this.url, this.size = 72});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(Icons.image_outlined, size: size / 2),
    );
    final u = url;
    if (u == null) return placeholder;
    return Image.network(
      u,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => placeholder,
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

class ProductTileCard extends StatelessWidget {
  const ProductTileCard({super.key, required this.tile, this.onTap});

  final ProductTile tile;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dimmed = !tile.canOfferAdd;
    final status = switch ((tile.saleState, tile.carried)) {
      (SaleState.temporarilySoldOut, _) => l10n.soldOutTemporarily,
      (_, false) => l10n.notCarried,
      (SaleState.unknown, _) => l10n.saleStateUnknown,
      _ => null,
    };
    return Card(
      key: ValueKey('tile-${tile.productId}'),
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: dimmed ? 0.55 : 1,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProductImage(url: tile.imageUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (tile.badge == DisplayBadge.isNew)
                            _Badge(l10n.badgeNew),
                          if (tile.badge == DisplayBadge.rank &&
                              tile.rank != null)
                            _Badge(l10n.badgeRank(tile.rank!)),
                          Expanded(
                            child: Text(
                              tile.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(switch (tile.basePrice) {
                        final int p => formatKrw(p),
                        null => l10n.priceUnavailable,
                      }, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        ratingText(l10n, tile.rating, tile.reviewCount),
                        style: theme.textTheme.bodySmall,
                      ),
                      if (status != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          status,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ],
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

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    ),
  );
}
