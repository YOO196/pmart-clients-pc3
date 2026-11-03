import 'dart:async';

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
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../checkout/presentation/checkout_controller.dart';
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
                          unknown: state.sync == CartSync.unknown,
                          busy:
                              state.busyItemId == line.cartItemId &&
                              state.sync != CartSync.stable,
                          mfcKnown: cart.mfcId != null,
                          stockUnavailable: cart.inventoryUnavailable,
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

class _CartLineTile extends ConsumerStatefulWidget {
  const _CartLineTile({
    required this.line,
    required this.enabled,
    required this.unknown,
    required this.busy,
    required this.mfcKnown,
    required this.stockUnavailable,
  });

  final CartLine line;

  /// 지금 바로 변경을 보낼 수 있는지(선택·삭제용). 수량 ± 는 모아 보내므로 진행 중에도 누를 수 있다.
  final bool enabled;

  /// 직전 변경이 결과 불명 — 확인될 때까지 모든 변경을 막는다.
  final bool unknown;
  final bool busy;

  /// 장바구니에 담당 MFC 가 있는지(없으면 재고를 조회하지 않아 가용이 불명이다).
  final bool mfcKnown;

  /// 재고 원천을 못 받았다(응답 `sources`).
  final bool stockUnavailable;

  @override
  ConsumerState<_CartLineTile> createState() => _CartLineTileState();
}

class _CartLineTileState extends ConsumerState<_CartLineTile> {
  CartLine get line => widget.line;
  bool get enabled => widget.enabled;
  bool get busy => widget.busy;

  /// 아직 보내지 않은 목표 수량(연속 탭을 모은다). null 이면 서버 확정 수량 그대로.
  int? _pending;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// ± 한 번. 잠깐 기다렸다가 최종 수량 한 번만 보낸다(탭마다 왕복 2번 하지 않게). 1 아래로는 삭제 확인.
  void _bump(int delta) {
    final next = (_pending ?? line.quantity) + delta;
    if (next < 1) {
      _timer?.cancel();
      setState(() => _pending = null);
      unawaited(_confirmRemove(context, ref));
      return;
    }
    setState(() => _pending = next);
    _arm(ref.read(cartStepperDelayProvider));
  }

  void _arm(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(_flush()));
  }

  Future<void> _flush() async {
    if (!mounted) return;
    final qty = _pending;
    if (qty == null) return;
    final state = ref.read(cartControllerProvider).value;
    if (state == null) return;
    // 다른 변경이 진행 중이면 끝난 뒤 다시 시도한다(결과 불명이면 버튼이 막혀 있어 여기 오지 않는다).
    if (!state.canChange) return _arm(const Duration(milliseconds: 100));
    if (qty == line.quantity) {
      setState(() => _pending = null);
      return;
    }
    final outcome = await ref
        .read(cartControllerProvider.notifier)
        .submit(SetQuantity(cartItemId: line.cartItemId, quantity: qty));
    if (!mounted) return;
    if (outcome == null) return _arm(const Duration(milliseconds: 100));
    // 보내는 동안 또 눌렀으면(_pending 이 바뀜) 타이머가 다시 보낸다. 아니면 서버 확정본으로 돌아간다.
    if (_pending == qty) setState(() => _pending = null);
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final controller = ref.read(cartControllerProvider.notifier);
    final reason = switch ((line.saleState, line.availability)) {
      (SaleState.saleStopped, _) => l10n.cartLineSaleStopped,
      (SaleState.temporarilySoldOut, _) ||
      (_, LineAvailability.soldOut) => l10n.cartLineSoldOut,
      (_, LineAvailability.notCarried) => l10n.cartLineNotCarried,
      (SaleState.unknown, _) => l10n.cartLineUnknown,
      // 가용 불명은 "확인 중"이 아니라 왜 모르는지로 나눈다: 배송지 미정(재고 조회 안 함) / 재고 원천 장애.
      (_, LineAvailability.unknown) when !widget.mfcKnown => l10n.cartLineNoMfc,
      (_, LineAvailability.unknown) when widget.stockUnavailable =>
        l10n.cartLineStockUnavailable,
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
                  // 담은 수량만큼의 금액(단가 × 수량). 서버 합계(selectedItemAmount)와 같은 식이며 표시용이다.
                  // 주문 금액은 견적·주문서의 서버 값으로만 확정한다(사용자 요청 2026-11-03: "개당" 대신 수량 금액).
                  Text(switch (line.unitPrice) {
                    final int p => l10n.cartLineAmount(
                      formatKrw(p * line.quantity),
                    ),
                    null => l10n.priceUnavailable,
                  }, key: ValueKey('cart-amount-$id')),
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
                        onPressed: widget.unknown ? null : () => _bump(-1),
                      ),
                      // 모아 보내는 중·서버 반영 중에는 목표 수량을 흐리게 + 진행 표시. 확정되면 보통 글씨.
                      Text(
                        l10n.cartLineQuantity(_pending ?? line.quantity),
                        key: ValueKey('cart-qty-$id'),
                        style: (_pending != null || busy)
                            ? TextStyle(color: theme.colorScheme.outline)
                            : null,
                      ),
                      if (_pending != null || busy)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      IconButton(
                        key: ValueKey('cart-inc-$id'),
                        tooltip: l10n.cartIncrease,
                        icon: const Icon(Icons.add),
                        onPressed: (!widget.unknown && line.purchasable)
                            ? () => _bump(1)
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

class _CartSummaryBar extends ConsumerWidget {
  const _CartSummaryBar({required this.cart, required this.state});

  final Cart cart;
  final CartState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    // 서버 합계만 보인다. 변경 확정 뒤 다시 읽는 동안은 "확인 중", 없으면 0원이 아니라 "확인할 수 없어요".
                    switch (cart.selectedItemAmount) {
                      final int a => formatKrw(a),
                      null when state.amountStale => l10n.cartAmountChecking,
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
              const SizedBox(height: 8),
              FilledButton(
                key: const ValueKey('cart-order'),
                // "주문하기"는 PG 진입이 아니다. 배송 방식 선택 → 주문서로 간다.
                onPressed: (state.canChange && cart.hasSelectedPurchasable)
                    ? () => _order(context, ref)
                    : null,
                child: Text(l10n.cartOrder),
              ),
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
          // 버튼이 달린 SnackBar 는 Flutter 기본값으로 자동으로 닫히지 않는다(persist). 알림은 잠시 뒤 닫는다.
          persist: false,
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

/// 비회원은 주문 목적으로 로그인한 뒤 이어간다(자동 병합 없음).
Future<void> _order(BuildContext context, WidgetRef ref) async {
  if (ref.read(sessionProvider) is! MemberSession) {
    final ok = await context.push<bool>('/login?purpose=checkout');
    if (ok != true || !context.mounted) return;
  }
  ref.read(checkoutSetupProvider.notifier).begin();
  await context.push('/checkout/delivery');
}
