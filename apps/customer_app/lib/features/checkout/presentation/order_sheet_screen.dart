import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart' show ProblemFailure;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../../address/presentation/address_controller.dart';
import '../../cart/presentation/cart_controller.dart';
import '../domain/checkout.dart';
import 'checkout_controller.dart';
import 'delivery_select_screen.dart' show modeLabel, windowText;

String _money(AppLocalizations l10n, int? amount) => switch (amount) {
  final int a => formatKrw(a),
  null => l10n.amountUnavailable,
};

String tipReasonText(AppLocalizations l10n, TipReason r) => switch (r) {
  TipReason.standard => l10n.tipStandard,
  TipReason.over30000 => l10n.tipOver30000,
  TipReason.firstPurchase => l10n.tipFirstPurchase,
  TipReason.none => l10n.tipNone,
  TipReason.unknown => l10n.tipUnknown,
};

String blockerText(AppLocalizations l10n, DraftBlocker b) => switch (b) {
  DraftBlocker.minOrderAmount => l10n.blockerMinOrder,
  DraftBlocker.deliveryModeUnavailable => l10n.blockerModeUnavailable,
  DraftBlocker.slotRequired => l10n.blockerSlotRequired,
  DraftBlocker.slotUnavailable => l10n.blockerSlotUnavailable,
  DraftBlocker.unknown => l10n.blockerUnknown,
};

/// 최소주문 미달 안내. 부족액은 서버 값(minOrderShortfall)만 쓴다(BR-14).
String minOrderText(AppLocalizations l10n, Quote? q) =>
    switch (q?.minOrderShortfall) {
      final int n when n > 0 => l10n.minOrderShortfall(formatKrw(n)),
      _ => l10n.minOrderUnsatisfied,
    };

/// 결제 진입 실패 사유(초안 checkoutFailure.code·결제 흐름 실패 코드).
String checkoutFailureText(AppLocalizations l10n, String code) =>
    switch (code) {
      CheckoutProblemCode.insufficientStock => l10n.cfInsufficientStock,
      CheckoutProblemCode.skuNotHandled => l10n.cfSkuNotHandled,
      CheckoutProblemCode.capacityExceeded => l10n.cfCapacityExceeded,
      CheckoutProblemCode.slotNotSelectable => l10n.cfSlotNotSelectable,
      CheckoutProblemCode.configRequired => l10n.draftConfigRequired,
      CheckoutProblemCode.resourceExpired => l10n.cfResourceExpired,
      _ => l10n.payFailed,
    };

/// 초안 생성 거절(422·409) 사유와 고객이 갈 곳. 모르는 코드는 null(일반 오류 화면).
({String text, String? route, String? action})? draftRejection(
  AppLocalizations l10n,
  Object? error,
) {
  if (error is! ProblemFailure) return null;
  return switch (error.problem.code) {
    CheckoutProblemCode.accountNotPurchasable => (
      text: l10n.draftAccountNotPurchasable,
      route: null,
      action: null,
    ),
    CheckoutProblemCode.outOfServiceArea => (
      text: l10n.addressNotServiceable,
      route: '/addresses',
      action: l10n.goAddresses,
    ),
    // 판정 불명은 배송 불가가 아니다.
    CheckoutProblemCode.serviceabilityUnknown => (
      text: l10n.draftServiceabilityUnknown,
      route: '/addresses',
      action: l10n.goAddresses,
    ),
    CheckoutProblemCode.mfcChanged => (
      text: l10n.draftMfcChanged,
      route: '/cart',
      action: l10n.cartGoToCart,
    ),
    CheckoutProblemCode.skuNotSaleable => (
      text: l10n.draftSkuNotSaleable,
      route: '/cart',
      action: l10n.cartGoToCart,
    ),
    CheckoutProblemCode.quantityLimitExceeded => (
      text: l10n.draftQuantityLimit,
      route: '/cart',
      action: l10n.cartGoToCart,
    ),
    CheckoutProblemCode.priceNotSet => (
      text: l10n.draftPriceNotSet,
      route: '/cart',
      action: l10n.cartGoToCart,
    ),
    CheckoutProblemCode.weightUnsplittable => (
      text: l10n.draftWeightUnsplittable,
      route: '/cart',
      action: l10n.cartGoToCart,
    ),
    CheckoutProblemCode.configRequired => (
      text: l10n.draftConfigRequired,
      route: null,
      action: null,
    ),
    _ => null,
  };
}

String _left(Duration d) {
  final s = d.inSeconds.clamp(0, 359999);
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

String blockedText(AppLocalizations l10n, CheckoutBlockReason r) => switch (r) {
  CheckoutBlockReason.notMember => l10n.blockedNotMember,
  CheckoutBlockReason.noShoppingAddress => l10n.blockedNoAddress,
  CheckoutBlockReason.noSelectedItems => l10n.blockedNoItems,
  CheckoutBlockReason.setupIncomplete => l10n.blockedSetup,
};

/// SCR-CHECKOUT-001. 금액·기한·자격은 서버 값만 보인다. 결제 버튼은 서버가 PAY 를 줬을 때만 열린다.
class OrderSheetScreen extends ConsumerStatefulWidget {
  const OrderSheetScreen({super.key});

  @override
  ConsumerState<OrderSheetScreen> createState() => _OrderSheetScreenState();
}

class _OrderSheetScreenState extends ConsumerState<OrderSheetScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(draftControllerProvider.notifier).enter());
    // 남은 시간 표시만 갱신한다. 앱 타이머로 확보를 풀거나 상태를 바꾸지 않는다.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(draftControllerProvider);
    final blocked = switch (value) {
      AsyncError(error: final CheckoutBlocked b) => b.reason,
      _ => null,
    };
    final rejection = switch (value) {
      AsyncError(:final error) => draftRejection(l10n, error),
      _ => null,
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.checkoutTitle)),
      body: blocked != null
          ? Center(child: Text(blockedText(l10n, blocked)))
          : rejection != null
          ? Center(
              key: const ValueKey('draft-rejected'),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(rejection.text, textAlign: TextAlign.center),
                    if (rejection case (
                      route: final String route,
                      action: final String action,
                      text: _,
                    )) ...[
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => context.go(route),
                        child: Text(action),
                      ),
                    ],
                  ],
                ),
              ),
            )
          : switch (value) {
              AsyncData(value: null) => const Center(
                child: CircularProgressIndicator(),
              ),
              _ => UiStateView<DraftState?>(
                state: uiStateOf(value),
                onRetry: () =>
                    ref.read(draftControllerProvider.notifier).recreate(),
                ready: (context, s) => _Sheet(state: s!),
              ),
            },
    );
  }
}

class _Sheet extends ConsumerWidget {
  const _Sheet({required this.state});

  final DraftState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ctl = ref.read(draftControllerProvider.notifier);
    final draft = state.draft;
    final quote = state.agreedQuote ?? draft.quote;
    final now = ref.watch(clockProvider)();
    final cart = ref.watch(cartControllerProvider).value?.cart;
    final address = ref.watch(addressBookProvider).value?.shoppingAddress;
    final req = state.request;

    final banners = <Widget>[
      if (draft.next == DraftNext.wait)
        _Banner(
          key: const ValueKey('draft-waiting'),
          icon: Icons.hourglass_top,
          text: l10n.checkoutPreparing,
          action: TextButton(
            onPressed: ctl.refresh,
            child: Text(l10n.checkoutCheckAgain),
          ),
        ),
      if (draft.expired)
        _Banner(
          key: const ValueKey('draft-expired'),
          icon: Icons.timer_off_outlined,
          text: l10n.draftExpired,
          action: TextButton(
            onPressed: ctl.recreate,
            child: Text(l10n.draftRecreate),
          ),
        ),
      if (draft.quote?.minOrderSatisfied == false ||
          draft.blockers.contains(DraftBlocker.minOrderAmount))
        _Banner(
          key: const ValueKey('min-order'),
          icon: Icons.info_outline,
          text: minOrderText(l10n, draft.quote),
          action: TextButton(
            onPressed: () => context.go('/cart'),
            child: Text(l10n.cartGoToCart),
          ),
        ),
      // 최소주문 밖의 막는 사유도 모두 보인다(서버 순서).
      for (final b in draft.blockers)
        if (b != DraftBlocker.minOrderAmount)
          _Banner(
            key: ValueKey('blocker-${b.name}'),
            icon: Icons.block,
            text: blockerText(l10n, b),
            action: TextButton(
              onPressed: () => context.push('/checkout/delivery'),
              child: Text(l10n.checkoutChange),
            ),
          ),
      if (state.checkoutUnknown)
        _Banner(
          key: const ValueKey('checkout-unknown'),
          icon: Icons.hourglass_top,
          text: l10n.checkoutUnknown,
          action: TextButton(
            onPressed: ctl.refresh,
            child: Text(l10n.checkoutCheckAgain),
          ),
        ),
      if (state.lastStart is CheckoutAccepted)
        _Banner(
          key: const ValueKey('checkout-accepted'),
          icon: Icons.payment,
          text: l10n.checkoutAccepted,
        ),
      // 지난 결제 진입이 자원 확보·결제에서 실패했다. 서버가 확보분을 풀었고, 견적이 유효하면 다시 결제할 수 있다.
      if (draft.checkoutFailure case final f?
          when state.lastStart is! CheckoutAccepted)
        _Banner(
          key: const ValueKey('checkout-failure'),
          icon: Icons.error_outline,
          text: checkoutFailureText(l10n, f.code),
        ),
      if (state.lastStart case CheckoutRejected(:final code))
        _Banner(
          key: const ValueKey('checkout-rejected'),
          icon: Icons.error_outline,
          text: switch (code) {
            CheckoutProblemCode.unsupported => l10n.checkoutNotYetSupported,
            CheckoutProblemCode.checkoutBlocked => l10n.checkoutBlocked,
            _ => l10n.checkoutRejected,
          },
        ),
      if (state.needsReconsent) _ReQuoteCard(state: state),
    ];

    final expiry = draft.earliestExpiry;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...banners,
              if (expiry != null && draft.awaitingCheckout)
                Text(
                  expiry.isAfter(now)
                      ? l10n.payWithin(_left(expiry.difference(now)))
                      : l10n.holdExpired,
                  key: const ValueKey('pay-within'),
                  style: theme.textTheme.titleMedium,
                ),
              _Section(
                title: l10n.checkoutItems,
                children: [
                  for (final l in req.lines)
                    Text(
                      '${cart?.lines.where((c) => c.cartItemId == l.cartItemId).firstOrNull?.name ?? l.sku} · ${l10n.cartLineQuantity(l.quantity)}',
                    ),
                ],
              ),
              _Section(
                title: l10n.checkoutDelivery,
                trailing: TextButton(
                  key: const ValueKey('change-delivery'),
                  onPressed: () => context.pop(),
                  child: Text(l10n.checkoutChange),
                ),
                children: [
                  Text(
                    [
                      modeLabel(l10n, req.mode),
                      if (req.window case final w?) windowText(w),
                    ].join(' · '),
                  ),
                  if ((quote?.plannedShipments ?? 1) > 1)
                    Text(l10n.splitShipment(quote!.plannedShipments!)),
                ],
              ),
              _Section(
                title: l10n.checkoutAddress,
                children: [
                  if (address != null) ...[
                    Text(address.label ?? address.roadAddress),
                    Text('${address.roadAddress} ${address.detailAddress}'),
                  ],
                ],
              ),
              _Section(
                title: l10n.checkoutOptions,
                children: [
                  Text(switch (req.outOfStock) {
                    OutOfStockPreference.cancelOutOfStockOnly => l10n.oosOnly,
                    OutOfStockPreference.cancelAll => l10n.oosAll,
                  }),
                  if (req.deliveryNote case final n?) Text(n),
                  if (req.bagOptOut) Text(l10n.bagOptOut),
                ],
              ),
              _Section(
                title: l10n.checkoutAmounts,
                children: [
                  _AmountRow(l10n.amountItems, _money(l10n, quote?.itemAmount)),
                  _AmountRow(
                    '${l10n.amountTip} (${tipReasonText(l10n, quote?.tipReason ?? TipReason.unknown)})',
                    _money(l10n, quote?.deliveryTip),
                  ),
                  if (quote?.firstPurchase case final f
                      when f == FirstPurchaseBenefit.expected ||
                          f == FirstPurchaseBenefit.checkingOtherOrder)
                    Text(
                      f == FirstPurchaseBenefit.expected
                          ? l10n.firstPurchaseExpected
                          : l10n.firstPurchaseChecking,
                      key: const ValueKey('first-purchase'),
                      style: theme.textTheme.bodySmall,
                    ),
                  _AmountRow(l10n.amountBag, _money(l10n, quote?.bagFee)),
                  const Divider(),
                  _AmountRow(
                    l10n.amountTotal,
                    _money(l10n, quote?.totalAmount),
                    key: const ValueKey('amount-total'),
                    strong: true,
                  ),
                  if (quote?.expiresAt case final e?)
                    Text(
                      e.isAfter(now)
                          ? l10n.priceHoldLeft(_left(e.difference(now)))
                          : l10n.holdExpired,
                      key: const ValueKey('price-hold'),
                      style: theme.textTheme.bodySmall,
                    ),
                  if (draft.resources?.reservationExpiresAt case final e?)
                    Text(
                      e.isAfter(now)
                          ? l10n.stockHoldLeft(_left(e.difference(now)))
                          : l10n.holdExpired,
                      key: const ValueKey('stock-hold'),
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: CommandButton(
                key: const ValueKey('pay'),
                busy: state.paying,
                // 막는 사유가 있으면 주버튼에 첫 사유를 쓴다(DraftBlocker 설명의 순서).
                label: switch ((
                  draft.blockers.firstOrNull,
                  quote?.totalAmount,
                )) {
                  (final DraftBlocker b, _) => blockerText(l10n, b),
                  (null, final int t) => l10n.payButton(formatKrw(t)),
                  (null, null) => l10n.payButtonNoAmount,
                },
                onPressed: state.canPay
                    ? () async {
                        final start = await ctl.pay();
                        // 사가가 시작됐을 뿐이다. 결제 화면이 결과를 서버에서 확인한다.
                        if (start is CheckoutAccepted && context.mounted) {
                          await context.push('/payments/${draft.draftId}');
                        }
                      }
                    : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReQuoteCard extends ConsumerWidget {
  const _ReQuoteCard({required this.state});

  final DraftState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final before = state.previousQuote!;
    final after = state.draft.quote;
    return Card(
      key: const ValueKey('re-quote'),
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.reQuoteTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(l10n.reQuoteBefore(_money(l10n, before.totalAmount))),
            Text(
              l10n.reQuoteAfter(_money(l10n, after?.totalAmount)),
              key: const ValueKey('re-quote-after'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey('re-quote-agree'),
              onPressed: () =>
                  ref.read(draftControllerProvider.notifier).agreeToNewQuote(),
              child: Text(l10n.reQuoteAgree),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.icon,
    required this.text,
    this.action,
  });

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(leading: Icon(icon), title: Text(text), trailing: action),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.trailing});

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ?trailing,
          ],
        ),
        ...children,
      ],
    ),
  );
}

class _AmountRow extends StatelessWidget {
  const _AmountRow(this.label, this.value, {super.key, this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final style = strong ? Theme.of(context).textTheme.titleLarge : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
