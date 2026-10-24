import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../domain/catalog.dart';
import 'catalog_providers.dart';
import '../../cart/presentation/cart_screen.dart' show AddToCartBar;
import 'widgets/product_tile_card.dart';

/// SCR-PRODUCT-001·OPTION-001. 가격·가용은 사본이다. 구매 가능 확정은 장바구니·주문서 서버 판정.
class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  String? _selectedSku;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = productDetailProvider(widget.productId);
    final value = ref.watch(provider);
    final notFound = switch (value) {
      AsyncError(error: ProblemFailure(:final problem)) =>
        problem.code == ProblemCode.notFound ||
            problem.code == 'CONTENT_NOT_PUBLISHED',
      _ => false,
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.productTitle)),
      body: notFound
          ? Center(child: Text(l10n.productNotFound))
          : UiStateView<ProductDetail>(
              state: uiStateOf(value),
              onRetry: () => ref.invalidate(provider),
              ready: (context, p) => _body(context, l10n, p),
            ),
      bottomNavigationBar: switch (value) {
        AsyncData(value: final p) => Builder(
          builder: (context) {
            final selected = _selected(p);
            return AddToCartBar(
              sku: selected?.sku,
              enabled: selected?.canOfferAdd ?? false,
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(child: ProductImage(url: p.imageUrls.firstOrNull, size: 220)),
        const SizedBox(height: 16),
        Text(p.name, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          ratingText(l10n, p.rating?.average, p.rating?.count),
          key: const ValueKey('product-rating'),
        ),
        const SizedBox(height: 16),
        Text(l10n.productOptions, style: theme.textTheme.titleMedium),
        RadioGroup<String>(
          groupValue: selected?.sku,
          onChanged: (sku) => setState(() => _selectedSku = sku),
          child: Column(
            children: [for (final o in p.options) _OptionTile(option: o)],
          ),
        ),
        Text(l10n.priceNote, style: theme.textTheme.bodySmall),
        if (p.description case final String d) ...[
          const SizedBox(height: 16),
          Text(l10n.productDescription, style: theme.textTheme.titleMedium),
          Text(d),
        ],
        if (p.storageGuide case final String g) ...[
          const SizedBox(height: 16),
          Text(l10n.productStorageGuide, style: theme.textTheme.titleMedium),
          Text(g),
        ],
        if (p.returnGuide case final String g) ...[
          const SizedBox(height: 16),
          Text(l10n.productReturnGuide, style: theme.textTheme.titleMedium),
          Text(g),
        ],
        if (p.notices.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(l10n.productNotices, style: theme.textTheme.titleMedium),
          for (final n in p.notices) Text('· $n'),
        ],
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.option});

  final SaleOption option;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final o = option;
    final notes = [
      if (o.unitType == UnitType.bundle && o.unitsPerSku != null)
        l10n.unitBundle(o.unitsPerSku!),
      ?o.capacityLabel,
      switch (o.availability) {
        _ when o.carried == false => l10n.notCarried,
        Availability.soldOut => l10n.soldOutTemporarily,
        Availability.low => l10n.availabilityLow,
        Availability.unknown => l10n.saleStateUnknown,
        Availability.available => null,
      },
    ].nonNulls;
    return RadioListTile<String>(
      key: ValueKey('option-${o.sku}'),
      value: o.sku,
      enabled: o.canOfferAdd,
      title: Text(o.label),
      subtitle: Text(notes.join(' · ')),
      secondary: Text(switch (o.basePrice) {
        final int price => formatKrw(price),
        null => l10n.priceUnavailable,
      }),
    );
  }
}
