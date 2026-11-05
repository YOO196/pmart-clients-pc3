import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../../l10n/gen/app_localizations.dart';
import '../../../../shared/shopping_context.dart';
import '../../../cart/domain/cart.dart';
import '../../../cart/presentation/cart_controller.dart';
import '../../../cart/presentation/cart_messages.dart';
import '../../domain/catalog.dart';
import '../catalog_providers.dart';

/// 상품 카드의 `+` 바로 담기(Commerce §6.11).
///
/// 카드만으로는 옵션이 여럿인지 알 수 없어, 누르면 상품 옵션(`GET /product-contents/{id}`)을 먼저 확인한다.
/// 옵션이 하나이고 담을 수 있어 보일 때만 그 SKU 1개를 기존 담기 경로([CartController.submitWhenReady])로 보낸다.
/// 옵션 선택이 필요하거나 확인하지 못하면 상세(옵션 선택)로 보낸다 — 임의로 담지 않는다.
/// 이미 담긴 SKU 는 담기가 절대 수량 설정이라 보내지 않고 담긴 수량만 알린다.
class QuickAddButton extends ConsumerStatefulWidget {
  const QuickAddButton({super.key, required this.tile});

  final ProductTile tile;

  /// `+` 를 보여도 되는지(안내용). 확정은 장바구니 서버 판정.
  static bool offeredFor(ProductTile t) =>
      t.canOfferAdd && t.representativeSku != null;

  @override
  ConsumerState<QuickAddButton> createState() => _QuickAddButtonState();
}

class _QuickAddButtonState extends ConsumerState<QuickAddButton> {
  bool _busy = false;

  Future<void> _onPressed() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final productId = widget.tile.productId;
    void say(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));

    setState(() => _busy = true);
    try {
      final ProductDetail detail;
      try {
        detail = await ref
            .read(catalogRepositoryProvider)
            .product(productId, mfcId: ref.read(currentMfcIdProvider));
      } on PmartFailure {
        // 옵션을 확인하지 못했다. 상세 화면이 조회 상태를 직접 보인다.
        if (mounted) unawaited(router.push('/products/$productId'));
        return;
      }
      if (!mounted) return;
      final option = detail.options.length == 1 ? detail.options.single : null;
      if (option == null || !option.canOfferAdd) {
        unawaited(router.push('/products/$productId'));
        return;
      }
      final CartState cart;
      try {
        cart = await ref.read(cartControllerProvider.future);
      } on PmartFailure {
        if (mounted) say(l10n.cartUnavailableForAdd);
        return;
      }
      if (!mounted) return;
      final inCart = cart.cart.lineForSku(option.sku);
      if (inCart != null) {
        say(l10n.cartInCart(inCart.quantity));
        return;
      }
      final outcome = await ref
          .read(cartControllerProvider.notifier)
          .submitWhenReady(AddItem(sku: option.sku, quantity: 1));
      if (!mounted) return;
      say(outcome == null ? l10n.reorderBusy : cartOutcomeText(l10n, outcome));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 36,
      child: IconButton.filledTonal(
        key: ValueKey('quick-add-${widget.tile.productId}'),
        tooltip: l10n.quickAddTooltip,
        padding: EdgeInsets.zero,
        iconSize: 20,
        style: IconButton.styleFrom(backgroundColor: scheme.surface),
        onPressed: _busy ? null : _onPressed,
        icon: _busy
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
      ),
    );
  }
}
