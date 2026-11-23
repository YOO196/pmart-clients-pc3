import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../../l10n/gen/app_localizations.dart';
import '../../../../shared/shopping_context.dart';
import '../../../cart/domain/cart.dart';
import '../../../cart/presentation/cart_controller.dart';
import '../../../cart/presentation/cart_messages.dart';
import '../../domain/catalog.dart';
import '../catalog_providers.dart';
import '../../../../shared/floating_cart_bar.dart';
import '../../../../shared/notice.dart';

/// 상품 카드의 `+` 바로 담기(Commerce §6.11). 담기 흐름은 [quickAddProduct].
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
    setState(() => _busy = true);
    try {
      await quickAddProduct(context, ref, widget.tile.productId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 30,
      child: IconButton.filledTonal(
        key: ValueKey('quick-add-${widget.tile.productId}'),
        tooltip: l10n.quickAddTooltip,
        padding: EdgeInsets.zero,
        iconSize: 20,
        style: IconButton.styleFrom(
          backgroundColor: scheme.surface,
          elevation: 2,
          shadowColor: Colors.black38,
          minimumSize: const Size.square(30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: _busy ? null : _onPressed,
        icon: _busy
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            // 레퍼런스: + 약 13dp, 굵은 선(약 1.7dp)
            : const PmartLineIcon(
                PmartLineIcons.plus,
                size: 20,
                strokeWidth: 2.4,
              ),
      ),
    );
  }
}

/// 상품 하나 바로 담기 — 카드 `+`, 찜 목록 [담기](초안 07-C)가 같이 쓴다.
///
/// 카드·찜 줄만으로는 옵션이 여럿인지 알 수 없어, 누르면 상품 옵션(`GET /product-contents/{id}`)을 먼저 확인한다.
/// 옵션이 하나이고 담을 수 있어 보일 때만 그 SKU 1개를 기존 담기 경로([CartController.submitWhenReady])로 보낸다.
/// 옵션 선택이 필요하거나 확인하지 못하면 상세(옵션 선택)로 보낸다 — 임의로 담지 않는다.
/// 이미 담긴 SKU 는 누를 때마다 1개씩 늘린다(서버 담긴 수량 + 1 로 수량 변경, 2026-11-18 사용자).
Future<void> quickAddProduct(
  BuildContext context,
  WidgetRef ref,
  String productId,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  void say(String text) => messenger.notice(text);

  final ProductDetail detail;
  try {
    detail = await ref
        .read(catalogRepositoryProvider)
        .product(productId, mfcId: ref.read(currentMfcIdProvider));
  } on PmartFailure {
    // 옵션을 확인하지 못했다. 상세 화면이 조회 상태를 직접 보인다.
    if (context.mounted) unawaited(router.push('/products/$productId'));
    return;
  }
  if (!context.mounted) return;
  final option = detail.options.length == 1 ? detail.options.single : null;
  if (option == null || !option.canOfferAdd) {
    unawaited(router.push('/products/$productId'));
    return;
  }
  final CartState cart;
  try {
    cart = await ref.read(cartControllerProvider.future);
  } on PmartFailure {
    if (context.mounted) say(l10n.cartUnavailableForAdd);
    return;
  }
  if (!context.mounted) return;
  final inCart = cart.cart.lineForSku(option.sku);
  // 누를 때마다 1개씩 더 담는다(사용자 2026-11-18). 담기(AddItem)는 절대 수량이라, 이미 담긴 상품은
  // 서버가 준 담긴 수량 + 1 로 수량 변경을 보낸다(기대 버전이 붙어 그 사이 바뀌었으면 충돌로 거절된다).
  final change = inCart == null
      ? AddItem(sku: option.sku, quantity: 1)
      : SetQuantity(
          cartItemId: inCart.cartItemId,
          quantity: inCart.quantity + 1,
        );
  final outcome = await ref
      .read(cartControllerProvider.notifier)
      .submitWhenReady(change);
  if (!context.mounted) return;
  final text = switch (outcome) {
    null => l10n.reorderBusy,
    // 서버가 반영한 뒤에만 늘어난 수량을 알린다.
    CartChangeApplied() when inCart != null => l10n.cartInCart(
      inCart.quantity + 1,
    ),
    final o => cartOutcomeText(l10n, o),
  };
  // 성공은 아래 장바구니 막대가 알린다(알림이 목록을 가려서 — 사용자 2026-11-22). 막대 자리가 없는
  // 화면(찜 목록 등)·실패·확인 중은 그대로 알림.
  if (outcome is CartChangeApplied && FloatingCartBar.hostedOnScreen()) {
    ref.read(cartBarPulseProvider.notifier).pulse(text);
  } else {
    say(text);
  }
}
