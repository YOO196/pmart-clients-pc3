import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../features/cart/presentation/cart_controller.dart'
    show cartControllerProvider;
import '../features/catalog/domain/catalog.dart';
import '../features/catalog/presentation/widgets/product_tile_card.dart';
import '../l10n/gen/app_localizations.dart';
import 'cart_recommendations.dart';
import 'floating_cart_bar.dart' show CartBarBody;
import 'ui_state_of.dart';

/// 장바구니 막대의 ^ 를 누르면 올라오는 시트(사용자 새 UI 2026-11-24): 위 막대(⌄ — 누르면 닫힘) · 최소 주문 줄 ·
/// "회원님을 위한 추천 상품" 3칸 × 2줄 · 아래 고정 [다른 추천 상품 보기 ⟳].
/// 크기는 사용자 폰 캡처 실측(1080px = 411dp, 1dp = 2.625px).
Future<void> showCartBarSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(23)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (_) => const CartBarSheet(),
    );

class CartBarSheet extends ConsumerWidget {
  const CartBarSheet({super.key});

  // 실측: 사진 칸 115.4 · 칸 사이 9.5 · 좌우 22.9 · 한 줄 263.6.
  static const _side = 22.9;
  static const _gap = 9.5;
  static const _rowExtent = 263.6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cart = ref.watch(cartControllerProvider).value?.cart;
    final recs = ref.watch(cartRecommendationsProvider);
    // 실측: 시트 위 끝이 화면 위에서 178dp(화면의 약 80%).
    final height = MediaQuery.sizeOf(context).height * 0.8;
    return SizedBox(
      key: const ValueKey('cart-bar-sheet'),
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 손잡이(35×4.6dp, 위 4.2dp).
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 4.2),
              width: 35.4,
              height: 4.6,
              decoration: BoxDecoration(
                color: const Color(0xFF9E9E9E),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          if (cart != null && cart.lines.isNotEmpty)
            CartBarBody(
              cart: cart,
              open: true,
              onToggle: () => Navigator.of(context).pop(),
              // 실측: 금액 왼쪽 16, [장바구니] 위 끝은 시트 위에서 36.9, 오른쪽 20.4. 줄은 왼쪽 9.9·오른쪽 20.2.
              rowPadding: const EdgeInsets.fromLTRB(16, 28.1, 20.4, 8.4),
              progressPadding: const EdgeInsets.fromLTRB(9.9, 0, 20.2, 0),
            ),
          Expanded(
            child: UiStateView<List<ProductTile>>(
              state: uiStateOf(recs, isEmpty: (l) => l.isEmpty),
              onRetry: () => ref.invalidate(cartRecommendationsProvider),
              ready: (context, items) => CustomScrollView(
                key: const ValueKey('cart-reco-list'),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      // 실측: 줄 아래 → 제목 가운데 30.5, 제목 가운데 → 사진 위 22, 왼쪽 22.
                      padding: const EdgeInsets.fromLTRB(22, 16.6, 22, 10.2),
                      child: Text(
                        l10n.cartRecoTitle,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 20.2,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(_side, 0, _side, 0),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: _gap,
                            mainAxisExtent: _rowExtent,
                          ),
                      delegate: SliverChildBuilderDelegate(
                        childCount: items.length,
                        (context, i) => ProductTileCard(
                          key: ValueKey('cart-reco-${items[i].productId}'),
                          tile: items[i],
                          rail: true,
                          look: TileLook.cartSheet,
                          onTap: () {
                            Navigator.of(context).pop();
                            context.push('/products/${items[i].productId}');
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 아래 고정 버튼(실측 좌우 21 · 높이 37.7 · 모서리 9 · 검은 테두리 · 글 14.5).
          // 목록은 버튼 위 12.6dp 에서 잘린다(실측 — 그 사이 흰 여백).
          const SizedBox(height: 12.6),
          // 버튼 아래 끝은 화면 아래에서 49.5dp(실측 — 폰 아래 제스처 영역 포함). 영역이 크면 그만큼만 띄운다.
          Builder(
            builder: (context) => Padding(
              padding: EdgeInsets.fromLTRB(
                21,
                0,
                21,
                (49.5 - MediaQuery.paddingOf(context).bottom).clamp(8, 49.5),
              ),
              child: SizedBox(
                height: 37.7,
                child: OutlinedButton(
                  key: const ValueKey('cart-reco-more'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.onSurface,
                    side: BorderSide(color: scheme.onSurface, width: 1.2),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                    textStyle: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: recs.value?.isNotEmpty == true
                      ? () => ref
                            .read(cartRecommendationsProvider.notifier)
                            .next()
                      : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.cartRecoMore),
                      const SizedBox(width: 4),
                      const PmartLineIcon(
                        PmartLineIcons.refresh,
                        size: 12,
                        strokeWidth: 2.8,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
