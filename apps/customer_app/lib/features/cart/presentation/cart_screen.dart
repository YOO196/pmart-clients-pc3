import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/shopping_context.dart' show currentMfcIdProvider;
import '../../../shared/big_button_text.dart';
import '../../../shared/notice.dart';
import '../../../shared/ui_state_of.dart';
import '../../catalog/domain/catalog.dart' show SaleState;
import '../../catalog/presentation/widgets/discount_price.dart';
import '../../catalog/presentation/widgets/product_tile_card.dart'
    show ProductImage;
import '../domain/cart.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../checkout/domain/checkout.dart'
    show DeliveryMode, DeliveryOption, StockShortage, TipReason;
import '../../checkout/presentation/checkout_controller.dart';
import '../../checkout/presentation/delivery_select_screen.dart'
    show
        DeliveryOptionCard,
        checkoutPreparingProvider,
        modeLabel,
        proceedToCheckout,
        showSlotSheet;
import 'cart_controller.dart';
import 'cart_messages.dart';

/// SCR-CART-001. 화면은 서버가 확정한 장바구니만 그린다(낙관적 반영 없음).
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(cartControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainer,
      appBar: AppBar(
        title: Text(l10n.cartTitle),
        centerTitle: true,
        backgroundColor: scheme.surface,
      ),
      body: UiStateView<CartState>(
        loading: (_) => const PmartListSkeleton(thumb: true, rows: 4),
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
    final shortages = ref.watch(stockShortageProvider);
    // 지금 주소로 배달하지 않는 품목은 숨긴다. 서버 장바구니에는 남아 있어 주소를 바꾸면 다시 보인다.
    final lines = [
      for (final l in cart.lines)
        if (!hiddenAtCurrentAddress(l, shortages)) l,
    ];
    return Column(
      children: [
        if (state.sync == CartSync.unknown)
          MaterialBanner(
            key: const ValueKey('cart-change-unknown'),
            leading: const PmartLineIcon(PmartLineIcons.refresh),
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
            leading: const PmartLineIcon(PmartLineIcons.info),
            content: Text(cartNoticeText(l10n, notice)),
            actions: [
              TextButton(
                onPressed: controller.dismissNotice,
                child: Text(l10n.cartDismiss),
              ),
            ],
          ),
        Expanded(
          child: lines.isEmpty
              ? Center(
                  key: const ValueKey('cart-empty'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.cartEmpty),
                      const SizedBox(height: 12),
                      const _AddMoreButton(),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: controller.refresh,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                    children: [
                      Material(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _CartHeader(state: state),
                            for (final line in lines) ...[
                              const Divider(),
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
                            const Divider(),
                            const _AddMoreButton(),
                          ],
                        ),
                      ),
                      // 사용자 결정(2026-11-20): 수령방법·결제금액을 장바구니 안에서(레퍼런스 장바구니 캡처)
                      if (ref.watch(sessionProvider) is MemberSession) ...[
                        const _ReceiveSection(),
                        _AmountSection(cart: cart),
                      ],
                    ],
                  ),
                ),
        ),
        // 알림(스낵바)이 주문 단추를 덮지 않게 이 막대 위로 띄운다.
        NoticeClearance(
          child: _CartSummaryBar(cart: cart, state: state),
        ),
      ],
    );
  }
}

/// 목록 머리: 보관 기한(서버 `expiresAt` 날짜만 보인다) · 선택 삭제.
class _CartHeader extends ConsumerWidget {
  const _CartHeader({required this.state});

  final CartState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final shortages = ref.watch(stockShortageProvider);
    final selected = state.cart.lines
        .where((l) => l.selected && !hiddenAtCurrentAddress(l, shortages))
        .length;
    final visible = state.cart.lines
        .where((l) => !hiddenAtCurrentAddress(l, shortages))
        .toList();
    final selectable = visible.where((l) => l.purchasable || l.selected);
    final allSelected =
        selectable.isNotEmpty && selectable.every((l) => l.selected);
    final controller = ref.read(cartControllerProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 14, 8),
      child: Row(
        children: [
          // 레퍼런스 5: "☐ 전체 선택" — 품목별 선택을 하나씩 서버에 보낸다(일괄 경로 없음)
          Checkbox(
            key: const ValueKey('cart-select-all'),
            value: allSelected,
            onChanged: (state.canChange && selectable.isNotEmpty)
                ? (_) => controller.setAllSelected(!allSelected)
                : null,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.cartSelectAll,
                  style: theme.textTheme.bodyLarge?.copyWith(fontSize: 14),
                ),
                if (state.cart.expiresAt case final at?)
                  Text(
                    l10n.cartExpiresAt(seoulDate(at)),
                    key: const ValueKey('cart-expires'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            key: const ValueKey('cart-remove-selected'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurface,
              side: BorderSide(color: theme.colorScheme.outlineVariant),
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              textStyle: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
            onPressed: (state.canChange && selected > 0)
                ? () => _confirmRemoveSelected(context, ref, selected)
                : null,
            child: Text(l10n.cartRemoveSelected),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemoveSelected(
    BuildContext context,
    WidgetRef ref,
    int count,
  ) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.cartRemoveSelectedConfirmTitle(count)),
        content: Text(l10n.cartRemoveSelectedConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cartRemoveConfirmCancel),
          ),
          FilledButton(
            key: const ValueKey('cart-remove-selected-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.cartRemoveConfirmOk),
          ),
        ],
      ),
    );
    // 결과 안내(거절·충돌·불명)는 컨트롤러가 장바구니 안내 띠로 올린다.
    if (ok ?? false) {
      await ref.read(cartControllerProvider.notifier).removeSelected();
    }
  }
}

/// 서버 시각 → 서울 날짜 `YYYY-MM-DD`(표시 전용. 기한 판정에 쓰지 않는다).
String seoulDate(DateTime instant) {
  final d = toSeoulWallClock(instant);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// "+ 더 담으러 가기"(레퍼런스 — 가운데 브랜드색) — 쇼핑(홈)으로 돌아간다. 장바구니는 그대로.
class _AddMoreButton extends StatelessWidget {
  const _AddMoreButton();

  @override
  Widget build(BuildContext context) => TextButton.icon(
    key: const ValueKey('cart-add-more'),
    style: TextButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      foregroundColor: Theme.of(context).colorScheme.primary,
      textStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 15),
      shape: const RoundedRectangleBorder(),
    ),
    icon: const PmartLineIcon(PmartLineIcons.plus, size: 20),
    label: Text(AppLocalizations.of(context).cartAddMore),
    onPressed: () => context.go('/'),
  );
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
    // 주문하기가 422 INSUFFICIENT_STOCK 으로 막혔을 때 서버가 짚은 상품(order 0.8.0). 수량을 맞추면 사라진다.
    final shortage = switch (ref.watch(stockShortageProvider)[line.sku]) {
      final s? when s.stillShortAt(line.quantity) => s,
      _ => null,
    };
    final reason = switch ((line.saleState, line.availability)) {
      (SaleState.saleStopped, _) => l10n.cartLineSaleStopped,
      (SaleState.temporarilySoldOut, _) ||
      (_, LineAvailability.soldOut) => l10n.cartLineSoldOut,
      // 취급 안 함(NOT_HANDLED)은 목록에서 숨기므로 여기 오지 않는다.
      _ when shortage != null => switch (shortage) {
        StockShortage(availableQty: 0) => l10n.cartLineSoldOut,
        StockShortage(availableQty: final int a) => l10n.cartLineAvailableQty(
          a,
        ),
        _ => l10n.cartLineLowStock,
      },
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
    final shown = _pending ?? line.quantity;
    final scheme = theme.colorScheme;
    // 레퍼런스 5: [☐ 굵은 이름] / [사진 | 회색 이름·옵션, 빨간 재고 문구, 굵은 금액] / 오른쪽 [− N +] 상자 하나
    final stepIcon = scheme.onSurface;
    final VoidCallback? openProduct = switch (line.productId) {
      final p? => () => context.push('/products/${Uri.encodeComponent(p)}'),
      null => null,
    };
    return Padding(
      key: ValueKey('cart-line-$id'),
      padding: const EdgeInsets.fromLTRB(4, 10, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                key: ValueKey('cart-select-$id'),
                value: line.selected,
                // 구매 불가 품목은 새로 고르는 것만 막는다. 이미 선택된 채 품절·미취급이 됐으면
                // 해제는 할 수 있어야 한다(선택 합계에서 빼려면). 삭제는 언제나 가능.
                onChanged: (enabled && (line.purchasable || line.selected))
                    ? (v) => controller.submit(
                        SetSelected(cartItemId: id, selected: v ?? false),
                      )
                    : null,
              ),
              Expanded(
                // 이름·사진을 누르면 그 상품 상세(사용자 2026-11-21). 상품 ID 가 없으면 누를 수 없다.
                child: GestureDetector(
                  key: ValueKey('cart-open-product-$id'),
                  behavior: HitTestBehavior.opaque,
                  onTap: openProduct,
                  child: Text(
                    line.name ?? line.sku,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  key: ValueKey('cart-open-product-image-$id'),
                  onTap: openProduct,
                  child: ProductImage(url: line.imageUrl, size: 62, radius: 8),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.optionLabel ?? line.name ?? line.sku,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (reason != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              PmartLineIcon(
                                PmartLineIcons.alert,
                                size: 14,
                                color: scheme.error,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  reason,
                                  key: ValueKey('cart-reason-$id'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 13,
                                    color: scheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 3),
                      // 담은 수량만큼의 금액(단가 × 수량). 서버 합계(selectedItemAmount)와 같은 식이며 표시용이다.
                      // 주문 금액은 견적·주문서의 서버 값으로만 확정한다(사용자 요청 2026-11-03: "개당" 대신 수량 금액).
                      // 기간 할인(cart 0.4.0, 레퍼런스 5-1 "33% 5,990원 8,990원"): 할인가·정가 모두 수량만큼.
                      if (line.discount case final d?)
                        DiscountPriceText(
                          key: ValueKey('cart-amount-$id'),
                          price: d.salePrice * line.quantity,
                          ratePercent: d.ratePercent,
                          base: switch (line.unitPrice) {
                            final int p => p * line.quantity,
                            null => null,
                          },
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      else
                        Text(
                          switch (line.unitPrice) {
                            final int p => l10n.cartLineAmount(
                              formatKrw(p * line.quantity),
                            ),
                            null => l10n.priceUnavailable,
                          },
                          key: ValueKey('cart-amount-$id'),
                          style: theme.textTheme.titleSmall?.copyWith(
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
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1개에서는 − 대신 휴지통(누르면 같은 삭제 확인).
                  IconButton(
                    key: ValueKey('cart-dec-$id'),
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    padding: EdgeInsets.zero,
                    tooltip: shown <= 1 ? l10n.cartRemove : l10n.cartDecrease,
                    icon: PmartLineIcon(
                      shown <= 1 ? PmartLineIcons.trash : PmartLineIcons.minus,
                      key: ValueKey(
                        shown <= 1
                            ? 'cart-dec-trash-$id'
                            : 'cart-dec-minus-$id',
                      ),
                      size: 18,
                      color: stepIcon,
                    ),
                    onPressed: widget.unknown ? null : () => _bump(-1),
                  ),
                  // 누른 수량은 바로 보통 글씨로 보인다(사용자 2026-11-21 "바로 반영이 아니라 로딩시간이 있어" — 흐린
                  // 글씨가 로딩처럼 보였다). 수량은 고객이 고른 입력값이고, 금액·합계는 서버가 확정한 값만 바뀐다.
                  SizedBox(
                    width: 28,
                    child: Center(
                      child: Text(
                        l10n.cartStepperQuantity(_pending ?? line.quantity),
                        key: ValueKey('cart-qty-$id'),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('cart-inc-$id'),
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    padding: EdgeInsets.zero,
                    tooltip: l10n.cartIncrease,
                    icon: PmartLineIcon(
                      PmartLineIcons.plus,
                      size: 18,
                      color: (!widget.unknown && line.purchasable)
                          ? stepIcon
                          : scheme.outlineVariant,
                    ),
                    onPressed: (!widget.unknown && line.purchasable)
                        ? () => _bump(1)
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ],
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
    final shortages = ref.watch(stockShortageProvider);
    final member = ref.watch(sessionProvider) is MemberSession;
    final setup = ref.watch(checkoutSetupProvider);
    final preparing = ref.watch(checkoutPreparingProvider);
    final purchasable = cart.lines
        .where(
          (l) =>
              l.selected &&
              l.purchasable &&
              !hiddenAtCurrentAddress(l, shortages),
        )
        .length;
    // 서버가 부족액(>0)을 주면 주문 버튼을 막는다(레퍼런스 5-1 "최소주문금액을 채워주세요", 사용자 2026-11-21).
    // 부족액을 모르면(null) 막지 않는다 — 최종 판정은 주문서 견적.
    final minOrderShort =
        cart.hasSelectedPurchasable && (cart.minOrderShortfall ?? 0) > 0;
    return Material(
      color: theme.colorScheme.surface,
      elevation: 12,
      shadowColor: Colors.black26,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 최소 주문 금액 안내(cart 0.2.0, 레퍼런스 5-1). 서버 부족액이 있을 때만 — 없으면(null) 바를 숨긴다.
              // 안내용이라 주문 버튼을 막지 않는다(최종 판정은 주문서 견적).
              if (cart.hasSelectedPurchasable)
                if ((cart.minOrderAmount, cart.minOrderShortfall)
                    case (final int min, final int short) when short > 0)
                  _MinOrderBar(min: min, shortfall: short),
              if (cart.hasSelectedPurchasable) const _FirstPurchaseHint(),
              // 결제금액·배달팁/봉투값 안내 문구는 두지 않는다(사용자 2026-11-21). 변경 반영 중 안내만 남긴다.
              if (!member && state.sync == CartSync.pending)
                Text(
                  l10n.cartChangePending,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              // 레퍼런스 5: 큰 단추 = [개수 동그라미] 문구 [금액]. 금액은 서버 합계 그대로(앱에서 더하지 않는다).
              FilledButton(
                key: const ValueKey('cart-order'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  // 레퍼런스 5-1 아래 버튼 글자 18(2026-11-21 측정).
                  textStyle: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                // "주문하기"는 PG 진입이 아니다. 배송 방식 선택 → 주문서로 간다.
                onPressed:
                    (state.canChange &&
                        cart.hasSelectedPurchasable &&
                        !preparing &&
                        !minOrderShort &&
                        (!member || setup.complete))
                    ? () => _order(context, ref)
                    : null,
                child: Row(
                  children: [
                    // 막혔을 때는 문구만 가운데(양옆 자리 없이 — 글자가 줄어들지 않게).
                    if (!minOrderShort)
                      SizedBox(
                        width: 72,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          // 막혔을 때는 레퍼런스 5-1 처럼 문구만(개수·금액 없음).
                          child: purchasable > 0 && !minOrderShort
                              ? Container(
                                  key: const ValueKey('cart-order-count'),
                                  width: 26,
                                  height: 26,
                                  alignment: Alignment.center,
                                  decoration: const BoxDecoration(
                                    color: Colors.black,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '$purchasable',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          // 회원: 수령방법을 고르기 전엔 "수령방법을 선택해주세요", 고르면 "예약배달 주문하기"처럼
                          switch ((member, setup.mode)) {
                            _ when minOrderShort => l10n.cartMinOrderFill,
                            (true, null) => l10n.deliveryPickTitle,
                            (true, final m?) => l10n.cartOrderWithMode(
                              modeLabel(l10n, m),
                            ),
                            _ => l10n.cartOrder,
                          },
                          key: const ValueKey('cart-order-label'),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                        ),
                      ),
                    ),
                    // 막혔을 때는 문구만 가운데(양옆 자리 없이 — 글자가 줄어들지 않게).
                    if (!minOrderShort)
                      SizedBox(
                        width: 72,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            // 변경 확정 뒤 다시 읽는 동안은 "확인 중", 없으면 0원이 아니라 "확인할 수 없어요".
                            switch (cart.selectedItemAmount) {
                              _ when minOrderShort => '',
                              final int a => formatKrw(a),
                              null when state.amountStale =>
                                l10n.cartAmountChecking,
                              null => l10n.cartAmountUnavailable,
                            },
                            key: const ValueKey('cart-total'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "15,000원부터 배달 가능해요 / N원 더 담으면 주문할 수 있어요" + 진행 바(레퍼런스 5-1). 금액은 서버 값 그대로.
class _MinOrderBar extends StatelessWidget {
  const _MinOrderBar({required this.min, required this.shortfall});

  final int min;
  final int shortfall;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('cart-min-order'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.cartMinOrderTitle(formatKrw(min)),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.cartMinOrderShortfall(formatKrw(shortfall)),
            key: const ValueKey('cart-min-order-shortfall'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              key: const ValueKey('cart-min-order-bar'),
              value: ((min - shortfall) / min).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 첫 구매 무료배달 "적용 예상" 한 줄. 서버 `GET /delivery-options?itemAmount=` 의 `deliveryTip.reason=FIRST_PURCHASE`
/// (회원만)가 있을 때만 보인다. 확정은 주문서·결제 때 서버가 한다. 조회 실패·미정이면 줄을 두지 않는다(무료 아님으로 단정하지 않음).
class _FirstPurchaseHint extends ConsumerWidget {
  const _FirstPurchaseHint();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(sessionProvider) is! MemberSession) {
      return const SizedBox.shrink();
    }
    final options = ref.watch(deliveryOptionsProvider).value;
    final expected = (options ?? const <DeliveryOption>[]).any(
      (o) => o.available && o.tip?.reason == TipReason.firstPurchase,
    );
    if (!expected) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Text(
      AppLocalizations.of(context).firstPurchaseExpected,
      key: const ValueKey('cart-first-purchase'),
      textAlign: TextAlign.center,
      style: theme.textTheme.titleSmall?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.primary,
      ),
    );
  }
}

/// 배달팁·봉투값 안내(정적 문구. 업무 문서 Commerce §8.3 기준. 금액은 서버 견적으로만 보인다).
/// 레퍼런스 5-3: 가운데 창 — 굵은 제목 + 글머리 줄 + 오른쪽 아래 [확인].
Future<void> _showFeeInfo(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      Widget bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('• '),
            Expanded(child: Text(text)),
          ],
        ),
      );
      return Dialog(
        key: const ValueKey('cart-fee-sheet'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
          child: DefaultTextStyle.merge(
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.cartFeeTipTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                bullet(l10n.cartFeeTipBody),
                bullet(l10n.cartFeeMinOrderNote),
                const SizedBox(height: 6),
                Text(
                  l10n.cartFeeBagTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                bullet(l10n.cartFeeBagBody),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    key: const ValueKey('cart-fee-ok'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(64, 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.actionConfirm),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// 상품 상세 하단의 담기 막대. 수량은 절대값이다(이미 담겼으면 그 수량에서 시작).
class AddToCartBar extends ConsumerStatefulWidget {
  const AddToCartBar({
    super.key,
    required this.sku,
    required this.enabled,
    this.leading,
  });

  /// 수량 칸 앞에 두는 것(상품 상세의 찜 하트 — 레퍼런스 4-1 아래 막대 왼쪽).
  final Widget? leading;

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
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (value.hasError && cartState == null)
                Text(l10n.cartUnavailableForAdd),
              if (inCart != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    l10n.cartInCart(inCart.quantity),
                    key: const ValueKey('in-cart'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              Row(
                children: [
                  ?widget.leading,
                  IconButton(
                    key: const ValueKey('add-dec'),
                    tooltip: l10n.cartDecrease,
                    onPressed: quantity > 1
                        ? () => setState(() => _quantity = quantity - 1)
                        : null,
                    icon: const PmartLineIcon(PmartLineIcons.minus),
                  ),
                  Text(
                    l10n.cartLineQuantity(quantity),
                    key: const ValueKey('add-qty'),
                  ),
                  IconButton(
                    key: const ValueKey('add-inc'),
                    tooltip: l10n.cartIncrease,
                    onPressed: () => setState(() => _quantity = quantity + 1),
                    icon: const PmartLineIcon(PmartLineIcons.plus),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: BigButtonText(
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
    messenger.notice(
      text,
      action: outcome is CartChangeApplied
          ? SnackBarAction(
              label: l10n.cartGoToCart,
              onPressed: () => context.push('/cart'),
            )
          : null,
    );
  }
}

/// 비회원은 주문 목적으로 로그인한 뒤 이어간다. 서버는 병합 신호를 주지 않으므로(BR-50 회신) 로그인 전
/// 비회원 장바구니를 기억해 두었다가 병합 확인 화면이 읽는다 — 품목이 없으면 바로 주문서로, 있으면 고객이 고른 것만.
Future<void> _order(BuildContext context, WidgetRef ref) async {
  if (ref.read(sessionProvider) is! MemberSession) {
    final guestCartId = ref.read(cartControllerProvider).value?.cart.cartId;
    // 로그인하면 회원 장바구니를 다시 읽느라 이 버튼(context)이 새로 그려진다 — 라우터·컨테이너를 붙잡아 이어 간다.
    final router = GoRouter.of(context);
    final container = ProviderScope.containerOf(context);
    final ok = await router.push<bool>('/login?purpose=checkout');
    if (ok != true) return;
    if (guestCartId != null) {
      final go = await router.push<bool>('/cart/merge', extra: guestCartId);
      if (go != true) return;
    }
    // 로그인 뒤에는 장바구니로 돌아와 수령방법을 고른다(사용자 결정 2026-11-20).
    container.read(checkoutSetupProvider.notifier).begin();
    return;
  }
  ref.read(checkoutSetupProvider.notifier).begin();
  await proceedToCheckout(context, ref);
}

/// 장바구니 안 "수령방법"(사용자 캡처 2026-11-20): 방식 카드(서버 판정 그대로), 예약은 도착 시간 시트.
/// 수량을 바꾸면 상품액이 바뀌어 배달팁을 서버에 다시 묻는다 — 그동안 이전 카드를 그대로 두고 위에 얇은 진행 줄만
/// (전에는 칸 전체가 자리 표시로 바뀌어 깜빡였다, 사용자 2026-11-21). 그동안은 누를 수 없다.
/// 배송지(센터)가 바뀐 재조회는 다른 센터 값을 남기지 않게 자리 표시를 보인다.
class _ReceiveSection extends ConsumerStatefulWidget {
  const _ReceiveSection();

  @override
  ConsumerState<_ReceiveSection> createState() => _ReceiveSectionState();
}

class _ReceiveSectionState extends ConsumerState<_ReceiveSection> {
  /// 마지막으로 그린 수령방법이 어느 센터 것인지.
  String? _shownMfc;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final setup = ref.watch(checkoutSetupProvider);
    final options = ref.watch(deliveryOptionsProvider);
    final mfc = ref.watch(currentMfcIdProvider);
    final previous = options.value;
    final reloadingSameCenter =
        options.isLoading && previous != null && _shownMfc == mfc;
    if (options case AsyncData()) _shownMfc = mfc;
    Widget cards(List<DeliveryOption> list) => Column(
      children: [
        for (final o in list)
          DeliveryOptionCard(
            option: o,
            selected: o.mode == setup.mode,
            window: o.mode == DeliveryMode.scheduled ? setup.window : null,
            onTap: () async {
              ref.read(checkoutSetupProvider.notifier).setMode(o.mode);
              if (o.mode == DeliveryMode.scheduled) {
                await showSlotSheet(context);
              }
            },
          ),
      ],
    );
    return Padding(
      key: const ValueKey('cart-receive'),
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              l10n.cartReceiveTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (reloadingSameCenter)
            Stack(
              key: const ValueKey('cart-receive-reloading'),
              children: [
                IgnorePointer(child: cards(previous)),
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              ],
            )
          else
            UiStateView<List<DeliveryOption>>(
              state: uiStateOf(options, isEmpty: (o) => o.isEmpty),
              onRetry: () => ref.invalidate(deliveryOptionsProvider),
              ready: (context, list) => cards(list),
            ),
        ],
      ),
    );
  }
}

/// 봉투값 확정 정책(주문 1건 100원 — 봉투를 안 받아도 청구, order 계약 `bagOptOut`). 장바구니 계약에는 값이 없어 표시만 이 값으로 한다.
/// 실제 청구액은 주문서 견적 `bagFee`(서버)다.
const cartBagFeePolicy = 100;

/// 장바구니 안 "결제금액": 서버 값만(상품금액 = 선택 합계, 배달팁 = 고른 방식의 서버 팁).
/// 봉투값·결제예정금액은 주문서 견적에서 확정된다 — 앱이 더해 만들지 않는다.
class _AmountSection extends ConsumerWidget {
  const _AmountSection({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final setup = ref.watch(checkoutSetupProvider);
    final option = ref
        .watch(deliveryOptionsProvider)
        .value
        ?.where((o) => o.mode == setup.mode)
        .firstOrNull;
    final tip = option?.tip?.applied ?? option?.tip?.base;
    Widget row(String label, String value, {Key? key, Widget? extra}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
              ),
              ?extra,
              const Spacer(),
              Text(
                value,
                key: key,
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
              ),
            ],
          ),
        );
    Widget detail() => Padding(
      padding: const EdgeInsets.only(left: 6),
      child: ActionChip(
        key: const ValueKey('cart-fee-detail'),
        label: Text(l10n.cartFeeDetail),
        labelStyle: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
        backgroundColor: scheme.surfaceContainer,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onPressed: () => _showFeeInfo(context),
      ),
    );
    return Padding(
      key: const ValueKey('cart-amounts'),
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              l10n.cartAmountsTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                row(l10n.amountItems, switch (cart.selectedItemAmount) {
                  final int a => formatKrw(a),
                  null => l10n.cartAmountUnavailable,
                }),
                // 기간 할인(cart 0.4.0 — 상품금액은 이미 할인 뒤). 서버 할인 합계가 있을 때만.
                if (cart.selectedDiscountAmount case final d? when d > 0)
                  row(
                    l10n.cartPromotionIncluded,
                    formatKrw(d, negative: true),
                    key: const ValueKey('cart-amount-promotion'),
                  ),
                row(
                  l10n.amountTip,
                  switch (tip) {
                    final int v => formatKrw(v),
                    null => l10n.cartAmountAfterPick,
                  },
                  key: const ValueKey('cart-amount-tip'),
                  extra: detail(),
                ),
                // 봉투값은 확정 정책 고정값(100원)을 보인다(사용자 2026-11-21 — 장바구니 계약에 값이 없다). 청구액은 주문서 견적.
                row(
                  l10n.amountBag,
                  formatKrw(cartBagFeePolicy),
                  key: const ValueKey('cart-amount-bag'),
                  extra: detail(),
                ),
                const SizedBox(height: 8),
                Divider(height: 2, thickness: 1.6, color: scheme.onSurface),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      l10n.cartAmountExpected,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      l10n.cartAmountInSheet,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
