import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../features/cart/presentation/cart_controller.dart'
    show cartControllerProvider;
import '../features/cart/domain/cart.dart' show Cart;
import '../l10n/gen/app_localizations.dart';
import 'notice.dart';

/// 홈·검색 결과·카테고리 목록 아래 떠 있는 장바구니 막대(사용자 캡처 2026-11-20 "24,138원 주문 가능 [2 장바구니]").
/// 서버가 확정한 장바구니에 품목이 있을 때만. 금액은 서버 선택 합계 그대로(없으면 금액 없이).
class FloatingCartBar extends ConsumerWidget {
  const FloatingCartBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cart = ref.watch(cartControllerProvider).value?.cart;
    if (cart == null || cart.lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      // 알림(스낵바)이 이 막대를 덮지 않게 위로 띄운다.
      child: NoticeClearance(child: _bar(context, l10n, cart)),
    );
  }

  Widget _bar(BuildContext context, AppLocalizations l10n, Cart cart) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final short = cart.minOrderShortfall;
    return Material(
      key: const ValueKey('home-cart-bar'),
      color: scheme.surface,
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (cart.selectedItemAmount case final a?)
                    Text(
                      formatKrw(a),
                      key: const ValueKey('home-cart-amount'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  Text(
                    switch (short) {
                      final int s when s > 0 => l10n.cartMinOrderShortfall(
                        formatKrw(s),
                      ),
                      _ => l10n.homeCartOrderable,
                    },
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 13,
                      color: short != null && short > 0
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(
              key: const ValueKey('home-cart-go'),
              onPressed: () => context.go('/cart'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 46),
                padding: const EdgeInsets.fromLTRB(10, 0, 18, 0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${cart.lines.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.cartTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
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
