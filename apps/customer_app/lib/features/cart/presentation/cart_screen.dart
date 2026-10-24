import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers.dart';
import '../../../shared/ui_state_of.dart';
import '../data/cart_repository.dart';
import '../data/mock_cart_repository.dart';
import '../domain/cart_summary.dart';

final cartRepositoryProvider = Provider<CartRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockCartRepository(),
    PmartEnv.local => ApiCartRepository(ref.watch(dioProvider)),
  },
);

/// 현재 장바구니 ID. 장바구니 단계에서 `POST /carts`(createOrGetCart) 결과로 바꾼다.
final currentCartIdProvider = Provider<String>((_) => 'cart-mock-1');

final cartSummaryProvider = FutureProvider<CartSummary>(
  (ref) => ref
      .watch(cartRepositoryProvider)
      .summary(ref.watch(currentCartIdProvider)),
);

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = uiStateOf(
      ref.watch(cartSummaryProvider),
      isEmpty: (s) => s.lineCount == 0,
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.cartSummaryTitle)),
      body: UiStateView<CartSummary>(
        state: state,
        onRetry: () => ref.invalidate(cartSummaryProvider),
        empty: (_) => Center(child: Text(l10n.cartEmpty)),
        ready: (context, cart) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                key: const ValueKey('cart-summary'),
                leading: const Icon(Icons.shopping_cart_outlined),
                title: Text(l10n.cartSummaryTitle),
                subtitle: Text(
                  [
                    l10n.cartLineCount(cart.lineCount),
                    switch (cart.selectedItemAmount) {
                      final int amount => l10n.cartSelectedAmount(
                        formatKrw(amount),
                      ),
                      null => l10n.cartAmountUnavailable,
                    },
                    l10n.cartSelectedAmountNote,
                  ].join('\n'),
                ),
                isThreeLine: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
