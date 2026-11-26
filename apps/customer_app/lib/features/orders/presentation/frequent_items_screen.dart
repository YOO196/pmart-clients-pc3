import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart' show PmartFailure;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/notice.dart';
import '../../../shared/ui_state_of.dart';
import '../../auth/domain/auth.dart' show MemberSession;
import '../../auth/presentation/auth_controller.dart' show sessionProvider;
import '../../cart/domain/cart.dart';
import '../../cart/presentation/cart_controller.dart';
import '../../cart/presentation/cart_messages.dart';
import '../../../shared/shopping_context.dart' show currentMfcIdProvider;
import '../../catalog/presentation/catalog_providers.dart'
    show productDetailProvider;
import '../../checkout/presentation/checkout_controller.dart'
    show checkoutRepositoryProvider, checkoutSetupProvider;
import '../../catalog/presentation/widgets/product_tile_card.dart'
    show ProductImage;
import '../domain/orders.dart' show FrequentItem;
import 'orders_providers.dart' show ordersRepositoryProvider;
import 'orders_screens.dart' show reorderChange;

/// 홈 "내가 1번 구매한 상품 보기"(사용자 2026-11-26 레퍼런스): 사 본 상품(order 0.24.0 `GET /orders/frequent-items`,
/// 180일 안 1번 이상)을 체크해 한 번에 장바구니에 담는다. 가격은 지금 상품 옵션(서버 값)만 — 합계·배달팁은
/// 앱이 계산해 확정하지 않으므로 보이지 않는다(장바구니가 서버 값으로 보인다).
final boughtItemsProvider = FutureProvider.autoDispose<List<FrequentItem>>((
  ref,
) async {
  if (ref.watch(sessionProvider) is! MemberSession) return const [];
  final all = await ref
      .watch(ordersRepositoryProvider)
      .frequentItems(minOrders: 1, limit: 50);
  // 상품 ID·이름이 없는 줄은 뺀다(SKU 를 화면에 보이지 않는다).
  return [
    for (final f in all)
      if (f.productId != null && f.productName != null) f,
  ];
});

/// 고른 상품 합으로 서버에 묻는 배달팁(order `GET /delivery-options?itemAmount=` — 무료 사유 적용, 서버 값).
/// 장바구니에서 고른 배송 방식이 있으면 그 방식, 없으면 가능한 첫 방식. 합을 아직 모르면 상품액 없이 물어 기본 배달팁.
/// 서버가 값을 주지 않으면 null — 화면은 "배달팁 확인 중"(0원으로 바꾸지 않는다).
final _boughtTipProvider = FutureProvider.autoDispose.family<int?, int?>((
  ref,
  itemAmount,
) async {
  final mfcId = ref.watch(currentMfcIdProvider);
  if (mfcId == null) return null;
  final options = await ref
      .watch(checkoutRepositoryProvider)
      .options(mfcId, itemAmount: itemAmount);
  final mode = ref.watch(checkoutSetupProvider).mode;
  final o =
      options.where((o) => o.mode == mode && o.available).firstOrNull ??
      options.where((o) => o.available).firstOrNull;
  return o?.tip?.applied ?? o?.tip?.base;
});

class BoughtItemsScreen extends ConsumerStatefulWidget {
  const BoughtItemsScreen({super.key});

  @override
  ConsumerState<BoughtItemsScreen> createState() => _BoughtItemsScreenState();
}

class _BoughtItemsScreenState extends ConsumerState<BoughtItemsScreen> {
  /// 고르지 않은 SKU(처음에는 모두 고름).
  final _off = <String>{};
  bool _busy = false;

  Future<void> _addSelected(List<FrequentItem> items) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final picked = [
      for (final f in items)
        if (!_off.contains(f.sku)) f,
    ];
    if (picked.isEmpty) return;
    setState(() => _busy = true);
    var added = 0;
    String? stop;
    String? rejected;
    try {
      for (final f in picked) {
        final cart = await ref.read(cartControllerProvider.future);
        final outcome = await ref
            .read(cartControllerProvider.notifier)
            .submitWhenReady(reorderChange(cart.cart, f.sku, 1));
        switch (outcome) {
          case null:
            stop = l10n.reorderBusy;
          case CartChangeApplied():
            added++;
          case CartChangeRejected():
            rejected ??= cartOutcomeText(l10n, outcome);
          default:
            stop = cartOutcomeText(l10n, outcome);
        }
        if (stop != null) break;
      }
    } on PmartFailure {
      stop = l10n.cartUnavailableForAdd;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.notice(
      stop ??
          rejected ??
          (added > 0 ? l10n.reorderAllAdded(added) : l10n.reorderAllInCart),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = ref.watch(boughtItemsProvider);
    final items = value.value ?? const <FrequentItem>[];
    final picked = [
      for (final f in items)
        if (!_off.contains(f.sku)) f,
    ];
    final count = picked.length;
    // 고른 상품의 지금 가격(서버 상품 조회 값) 합 — 하나라도 모르면 보이지 않는다(0원·일부 합으로 바꾸지 않는다).
    // 청구 금액이 아니다: 담은 뒤 장바구니·주문서가 서버 금액으로 다시 보인다.
    int? sum = 0;
    for (final f in picked) {
      final o = ref
          .watch(productDetailProvider(f.productId!))
          .value
          ?.options
          .where((o) => o.sku == f.sku)
          .firstOrNull;
      final p = o?.discount?.salePrice ?? o?.basePrice;
      if (p == null) {
        sum = null;
        break;
      }
      sum = sum! + p;
    }
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        automaticallyImplyLeading: false,
        leading: IconButton(
          key: const ValueKey('bought-close'),
          onPressed: () => context.pop(),
          icon: const PmartLineIcon(PmartLineIcons.close, size: 25.7),
        ),
      ),
      body: UiStateView<List<FrequentItem>>(
        state: uiStateOf(value, isEmpty: (l) => l.isEmpty),
        onRetry: () => ref.invalidate(boughtItemsProvider),
        empty: (_) => Center(child: Text(l10n.boughtItemsEmpty)),
        ready: (context, items) => ListView(
          key: const ValueKey('bought-list'),
          padding: const EdgeInsets.fromLTRB(0, 18.9, 0, 17.1),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16.6, 0, 16.6, 11.4),
              child: Text(
                l10n.boughtItemsTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 20.1,
                  height: 1.52,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            for (final f in items)
              _BoughtRow(
                key: ValueKey('bought-${f.sku}'),
                item: f,
                on: !_off.contains(f.sku),
                onChanged: (v) =>
                    setState(() => v ? _off.remove(f.sku) : _off.add(f.sku)),
              ),
          ],
        ),
      ),
      bottomNavigationBar: items.isEmpty
          ? null
          : SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(15.5, 12.3, 16.6, 13.4),
                    child: Row(
                      children: [
                        Text(
                          l10n.boughtItemsCount(count),
                          key: const ValueKey('bought-count'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 13.3,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (sum != null && count > 0) ...[
                          Container(
                            width: 1,
                            height: 12.9,
                            margin: const EdgeInsets.symmetric(horizontal: 8.6),
                            color: scheme.outlineVariant,
                          ),
                          Text(
                            formatKrw(sum),
                            key: const ValueKey('bought-sum'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 13.3,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const Spacer(),
                        // 배달팁은 늘 보인다 — 서버 값, 받는 중·실패면 "배달팁 확인 중"(실패는 눌러 다시 묻기).
                        if (count > 0)
                          Builder(
                            builder: (context) {
                              final tipValue = ref.watch(
                                _boughtTipProvider(sum),
                              );
                              final style = theme.textTheme.titleMedium
                                  ?.copyWith(
                                    fontSize: 13.3,
                                    fontWeight: FontWeight.w800,
                                    color: scheme.primary,
                                  );
                              return switch (tipValue) {
                                AsyncData(value: final int tip) => Text(
                                  l10n.optionTip(formatKrw(tip)),
                                  key: const ValueKey('bought-tip'),
                                  style: style,
                                ),
                                AsyncError() || AsyncData() => GestureDetector(
                                  key: const ValueKey('bought-tip-retry'),
                                  onTap: () =>
                                      ref.invalidate(_boughtTipProvider(sum)),
                                  child: Text(l10n.tipUnknown, style: style),
                                ),
                                _ => Text(
                                  l10n.tipUnknown,
                                  key: const ValueKey('bought-tip-loading'),
                                  style: style,
                                ),
                              };
                            },
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(13.7, 0, 13.7, 12.9),
                    child: SizedBox(
                      height: 49.3,
                      child: FilledButton(
                        key: const ValueKey('bought-add'),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          textStyle: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        onPressed: (_busy || count == 0)
                            ? null
                            : () => _addSelected(items),
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(l10n.boughtItemsAdd),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// 한 줄(레퍼런스 실측 ÷2.8125): 체크 20 (왼쪽 21.7) · 사진 55.8(모서리 8, 왼쪽 54.5) · 글(왼쪽 120) — 이름 한 줄,
/// 할인율 빨강 + 가격 굵게(지금 옵션 값), "N회 구매". 줄 간격 76.5. 글자: 이름 13.5 · 가격 13.6 굵게 · "N회 구매" 11 파랑(#2B7AE1, 레퍼런스 색).
class _BoughtRow extends ConsumerWidget {
  const _BoughtRow({
    super.key,
    required this.item,
    required this.on,
    required this.onChanged,
  });

  final FrequentItem item;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final detail = ref.watch(productDetailProvider(item.productId!)).value;
    final option = detail?.options.where((o) => o.sku == item.sku).firstOrNull;
    final priceStyle = theme.textTheme.titleMedium?.copyWith(
      fontSize: 14.6,
      height: 1.25,
      fontWeight: FontWeight.w800,
    );
    return InkWell(
      onTap: () => onChanged(!on),
      child: SizedBox(
        height: 82,
        child: Row(
          children: [
            const SizedBox(width: 9.9),
            Transform.scale(
              scale: 1.19,
              child: Checkbox(
                key: ValueKey('bought-check-${item.sku}'),
                value: on,
                onChanged: (v) => onChanged(v ?? false),
                fillColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.selected)
                      ? const Color(0xFF1B1B1D)
                      : null,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            // 체크 칸(누르는 자리 40) 바로 옆 — 실측 사진 왼쪽 54.
            Transform.translate(
              offset: const Offset(2.1, 0),
              child: GestureDetector(
                onTap: () => context.push('/products/${item.productId}'),
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: scheme.outlineVariant,
                      width: 0.8,
                    ),
                  ),
                  child: ProductImage(
                    url: item.imageUrl,
                    size: 59.8,
                    radius: 8,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8.6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.optionLabel == null
                        ? item.productName!
                        : '${item.productName!} · ${item.optionLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 14.5,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 1),
                  if (option?.discount case final d?)
                    // 할인율과 가격 사이는 공백보다 좁다(레퍼런스 실측 4.3px).
                    Text.rich(
                      TextSpan(
                        style: priceStyle,
                        children: [
                          if (d.ratePercent case final r?) ...[
                            TextSpan(
                              text: '$r%',
                              style: const TextStyle(color: Color(0xFFFF3E3E)),
                            ),
                            const WidgetSpan(child: SizedBox(width: 2.2)),
                          ],
                          TextSpan(text: formatKrw(d.salePrice)),
                        ],
                      ),
                    )
                  else if (option?.basePrice case final p?)
                    Text(formatKrw(p), style: priceStyle)
                  else
                    // 가격을 아직 모르거나 조회하지 못했다 — 0원으로 보이지 않는다.
                    Text(
                      detail == null ? ' ' : l10n.priceUnavailable,
                      style: priceStyle?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 3.2),
                  Text(
                    l10n.boughtItemsTimes(item.orderCount),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 11.8,
                      color: const Color(0xFF2B7AE1),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 17.1),
          ],
        ),
      ),
    );
  }
}
