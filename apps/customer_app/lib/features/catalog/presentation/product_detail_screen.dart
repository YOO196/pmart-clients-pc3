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
        // 옵션이 하나뿐이면 고를 것이 없으니 가격·재고만 보이고, 둘 이상일 때만 옵션 선택을 연다.
        if (p.options case [final only])
          _SingleOptionSummary(option: only)
        else ...[
          Text(l10n.productOptions, style: theme.textTheme.titleMedium),
          RadioGroup<String>(
            groupValue: selected?.sku,
            onChanged: (sku) => setState(() => _selectedSku = sku),
            child: Column(
              children: [for (final o in p.options) _OptionTile(option: o)],
            ),
          ),
        ],
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
    Availability.unknown => l10n.saleStateUnknown,
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
        Text(
          _priceText(l10n, option),
          key: const ValueKey('product-price'),
          style: theme.textTheme.titleLarge,
        ),
        if (notes.isNotEmpty) Text(notes, style: theme.textTheme.bodyMedium),
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
    // 라벨이 없으면 용량, 그것도 없으면 "기본". SKU 코드는 보이지 않는다.
    final title = o.label ?? o.capacityLabel ?? l10n.optionDefault;
    final notes = _optionNotes(
      l10n,
      o,
      withCapacity: o.label != null,
    ).join(' · ');
    return RadioListTile<String>(
      key: ValueKey('option-${o.sku}'),
      value: o.sku,
      enabled: o.canOfferAdd,
      title: Text(title),
      subtitle: notes.isEmpty ? null : Text(notes),
      secondary: Text(_priceText(l10n, o)),
    );
  }
}
