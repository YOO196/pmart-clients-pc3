import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../../catalog/domain/catalog.dart' show SaleState;
import '../../catalog/presentation/widgets/product_tile_card.dart'
    show ProductImage;
import '../domain/cart.dart';
import 'cart_controller.dart';
import 'cart_messages.dart';

/// SCR-CART-001. 화면은 서버가 확정한 장바구니만 그린다(낙관적 반영 없음).
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(cartControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.cartTitle)),
      body: UiStateView<CartState>(
        state: uiStateOf(value),
        onRetry: () => ref.invalidate(cartControllerProvider),
        ready: (context, s) => _CartBody(state: s),
      ),
    );
  }
}

class _CartBody extends ConsumerWidget {
  const _CartBody({required this.state});

  final CartState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(cartControllerProvider.notifier);
    final cart = state.cart;
    final notice = state.notice;
    return Column(
      children: [
        if (state.sync == CartSync.unknown)
          MaterialBanner(
            key: const ValueKey('cart-change-unknown'),
            leading: const Icon(Icons.hourglass_top),
            content: Text(
              '${l10n.cartChangeUnknown}\n${l10n.cartChangeUnknownNote}',
            ),
            actions: [
              TextButton(
                key: const ValueKey('cart-check-again'),
                onPressed: controller.checkAgain,
                child: Text(l10n.cartCheckAgain),
              ),
            ],
          ),
        if (notice != null)
          MaterialBanner(
            key: const ValueKey('cart-notice'),
            leading: const Icon(Icons.info_outline),
            content: Text(cartNoticeText(l10n, notice)),
            actions: [
              TextButton(
                onPressed: controller.dismissNotice,
                child: Text(l10n.cartDismiss),
              ),
            ],
          ),
        Expanded(
          child: cart.lines.isEmpty
              ? Center(
                  key: const ValueKey('cart-empty'),
                  child: Text(l10n.cartEmpty),
                )
              : RefreshIndicator(
                  onRefresh: controller.refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final line in cart.lines)
                        _CartLineTile(
                          line: line,
                          enabled: state.canChange,
                          busy:
                              state.busyItemId == line.cartItemId &&
                              state.sync != CartSync.stable,
                        ),
                    ],
                  ),
                ),
        ),
        _CartSummaryBar(cart: cart, state: state),
      ],
    );
  }
}

class _CartLineTile extends ConsumerWidget {
  const _CartLineTile({
    required this.line,
    required this.enabled,
    required this.busy,
  });

  final CartLine line;
  final bool enabled;
  final bool busy;

  Future<void> _decrease(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(cartControllerProvider.notifier);
    if (line.quantity > 1) {
      await controller.submit(
        SetQuantity(cartItemId: line.cartItemId, quantity: line.quantity - 1),
      );
      return;
    }
    // 1에서 "-" 는 삭제 확인을 거친다.
    await _confirmRemove(context, ref);
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.cartRemoveConfirmTitle),
        content: Text(l10n.cartRemoveConfirmBody(line.name ?? line.sku)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cartRemoveConfirmCancel),
          ),
          FilledButton(
            key: const ValueKey('cart-remove-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.cartRemoveConfirmOk),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await ref
          .read(cartControllerProvider.notifier)
          .submit(RemoveItem(cartItemId: line.cartItemId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final controller = ref.read(cartControllerProvider.notifier);
    final reason = switch ((line.saleState, line.availability)) {
      (SaleState.saleStopped, _) => l10n.cartLineSaleStopped,
      (SaleState.temporarilySoldOut, _) ||
      (_, LineAvailability.soldOut) => l10n.cartLineSoldOut,
      (_, LineAvailability.notCarried) => l10n.cartLineNotCarried,
      (SaleState.unknown, _) ||
      (_, LineAvailability.unknown) => l10n.cartLineUnknown,
      (_, LineAvailability.low) => switch (line.availableQty) {
        final int n => l10n.cartLineAvailableQty(n),
        null => l10n.cartLineLowStock,
      },
      _ => null,
    };
    final id = line.cartItemId;
    return Card(
      key: ValueKey('cart-line-$id'),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              key: ValueKey('cart-select-$id'),
              value: line.selected,
              // 구매 불가 품목은 선택만 막는다(삭제는 가능).
              onChanged: (enabled && line.purchasable)
                  ? (v) => controller.submit(
                      SetSelected(cartItemId: id, selected: v ?? false),
                    )
                  : null,
            ),
            ProductImage(url: line.imageUrl, size: 56),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.name ?? line.sku, style: theme.textTheme.bodyLarge),
                  if (line.optionLabel case final String label)
                    Text(label, style: theme.textTheme.bodySmall),
                  Text(switch (line.unitPrice) {
                    final int p => l10n.cartUnitPrice(formatKrw(p)),
                    null => l10n.priceUnavailable,
                  }),
                  if (reason != null)
                    Text(
                      reason,
                      key: ValueKey('cart-reason-$id'),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  Row(
                    children: [
                      IconButton(
                        key: ValueKey('cart-dec-$id'),
                        tooltip: l10n.cartDecrease,
                        icon: const Icon(Icons.remove),
                        onPressed: enabled
                            ? () => _decrease(context, ref)
                            : null,
                      ),
                      busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              l10n.cartLineQuantity(line.quantity),
                              key: ValueKey('cart-qty-$id'),
                            ),
                      IconButton(
                        key: ValueKey('cart-inc-$id'),
                        tooltip: l10n.cartIncrease,
                        icon: const Icon(Icons.add),
                        onPressed: (enabled && line.purchasable)
                            ? () => controller.submit(
                                SetQuantity(
                                  cartItemId: id,
                                  quantity: line.quantity + 1,
                                ),
                              )
                            : null,
                      ),
                      const Spacer(),
                      TextButton(
                        key: ValueKey('cart-remove-$id'),
                        onPressed: enabled
                            ? () => _confirmRemove(context, ref)
                            : null,
                        child: Text(l10n.cartRemove),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartSummaryBar extends StatelessWidget {
  const _CartSummaryBar({required this.cart, required this.state});

  final Cart cart;
  final CartState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(l10n.cartSelectedTotal),
                  const Spacer(),
                  Text(
                    // 서버 합계만 보인다. 없으면 0원이 아니라 "확인할 수 없어요".
                    switch (cart.selectedItemAmount) {
                      final int a => formatKrw(a),
                      null => l10n.cartAmountUnavailable,
                    },
                    key: const ValueKey('cart-total'),
                    style: theme.textTheme.titleLarge,
                  ),
                ],
              ),
              Text(
                l10n.cartSelectedAmountNote,
                style: theme.textTheme.bodySmall,
              ),
              if (state.sync == CartSync.pending)
                Text(l10n.cartChangePending, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// 상품 상세 하단의 담기 막대. 수량은 절대값이다(이미 담겼으면 그 수량에서 시작).
class AddToCartBar extends ConsumerStatefulWidget {
  const AddToCartBar({super.key, required this.sku, required this.enabled});

  final String? sku;

  /// 옵션이 담기를 권해도 되는지(판매 상태·가용 사본).
  final bool enabled;

  @override
  ConsumerState<AddToCartBar> createState() => _AddToCartBarState();
}

class _AddToCartBarState extends ConsumerState<AddToCartBar> {
  int? _quantity;
  String? _skuForQuantity;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(cartControllerProvider);
    final cartState = value.value;
    final sku = widget.sku;
    final inCart = (sku == null) ? null : cartState?.cart.lineForSku(sku);
    if (_skuForQuantity != sku) {
      _skuForQuantity = sku;
      _quantity = null;
    }
    final quantity = _quantity ?? inCart?.quantity ?? 1;
    final canSubmit =
        sku != null &&
        widget.enabled &&
        cartState != null &&
        cartState.canChange;
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (value.hasError && cartState == null)
                Text(l10n.cartUnavailableForAdd),
              if (inCart != null)
                Text(
                  l10n.cartInCart(inCart.quantity),
                  key: const ValueKey('in-cart'),
                ),
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('add-dec'),
                    tooltip: l10n.cartDecrease,
                    onPressed: quantity > 1
                        ? () => setState(() => _quantity = quantity - 1)
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Text(
                    l10n.cartLineQuantity(quantity),
                    key: const ValueKey('add-qty'),
                  ),
                  IconButton(
                    key: const ValueKey('add-inc'),
                    tooltip: l10n.cartIncrease,
                    onPressed: () => setState(() => _quantity = quantity + 1),
                    icon: const Icon(Icons.add),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: CommandButton(
                      key: const ValueKey('add-to-cart'),
                      label: inCart == null
                          ? l10n.cartAdd
                          : l10n.cartUpdateQuantity,
                      onPressed: canSubmit
                          ? () => _submit(sku, quantity, inCart)
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit(String sku, int quantity, CartLine? inCart) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(cartControllerProvider.notifier);
    final outcome = await controller.submit(
      inCart == null
          ? AddItem(sku: sku, quantity: quantity)
          : SetQuantity(cartItemId: inCart.cartItemId, quantity: quantity),
    );
    if (!mounted) return;
    final text = switch (outcome) {
      CartChangeApplied() => l10n.cartAdded,
      CartChangeRejected() => cartRejectionText(l10n, outcome),
      CartVersionConflict() => l10n.cartNoticeConflict,
      CartChangeUnknown() => l10n.cartChangeUnknown,
      CartChangeNotApplied() => l10n.cartNoticeNotApplied,
      null => null,
    };
    if (outcome is CartChangeApplied) setState(() => _quantity = null);
    if (text == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          action: outcome is CartChangeApplied
              ? SnackBarAction(
                  label: l10n.cartGoToCart,
                  onPressed: () => context.go('/cart'),
                )
              : null,
        ),
      );
  }
}
