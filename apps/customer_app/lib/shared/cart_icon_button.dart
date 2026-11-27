import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../features/cart/presentation/cart_controller.dart';
import '../l10n/gen/app_localizations.dart';

/// 머리줄 장바구니 아이콘 + 담은 품목 수 뱃지(레퍼런스 상품 상세·주문상세·검색 머리줄).
/// 수는 서버가 확정한 장바구니 품목 수만 — 읽지 못했거나 0이면 뱃지 없이 아이콘만.
class CartIconButton extends ConsumerWidget {
  const CartIconButton({
    super.key,
    this.size = 23,
    this.width,
    this.strokeWidth = 1.8,
  });

  /// 선 굵기(24 좌표 기준).
  final double strokeWidth;

  /// 아이콘 크기(홈 머리줄은 레퍼런스대로 조금 크게).
  final double size;

  /// 누르는 칸 폭(머리줄 아이콘 간격을 레퍼런스에 맞출 때). 없으면 기본.
  final double? width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final count =
        ref.watch(cartControllerProvider).value?.cart.lines.length ?? 0;
    return IconButton(
      key: const ValueKey('appbar-cart'),
      visualDensity: VisualDensity.compact,
      constraints: width == null
          ? null
          : BoxConstraints.tightFor(width: width, height: 48),
      padding: width == null ? null : EdgeInsets.zero,
      tooltip: l10n.cartTitle,
      onPressed: () => context.push('/cart'),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        offset: const Offset(6, -6),
        child: PmartLineIcon(
          PmartLineIcons.cart,
          size: size,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}
