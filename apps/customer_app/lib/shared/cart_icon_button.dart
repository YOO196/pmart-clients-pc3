import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../features/cart/presentation/cart_controller.dart';
import '../l10n/gen/app_localizations.dart';

/// 머리줄 장바구니 아이콘 + 담은 품목 수 뱃지(레퍼런스 상품 상세·주문상세·검색 머리줄).
/// 수는 서버가 확정한 장바구니 품목 수만 — 읽지 못했거나 0이면 뱃지 없이 아이콘만.
class CartIconButton extends ConsumerWidget {
  const CartIconButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final count =
        ref.watch(cartControllerProvider).value?.cart.lines.length ?? 0;
    return IconButton(
      key: const ValueKey('appbar-cart'),
      visualDensity: VisualDensity.compact,
      tooltip: l10n.cartTitle,
      onPressed: () => context.go('/cart'),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        offset: const Offset(6, -6),
        child: const PmartLineIcon(PmartLineIcons.cart, size: 23),
      ),
    );
  }
}
