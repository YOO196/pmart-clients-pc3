import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.checkoutTitle)),
      body: blocked != null
          ? Center(child: Text(blockedText(l10n, blocked)))
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
      if (draft.next == DraftNext.expired)
        _Banner(
          key: const ValueKey('draft-expired'),
          icon: Icons.timer_off_outlined,
          text: l10n.draftExpired,
          action: TextButton(
            onPressed: ctl.recreate,
            child: Text(l10n.draftRecreate),
          ),
        ),
      if (draft.quote?.minOrderSatisfied == false)
        _Banner(
          key: const ValueKey('min-order'),
          icon: Icons.info_outline,
          // BR-14: 부족액은 계약에 없어서 금액 없이 안내한다(앱에서 계산하지 않는다).
          text: l10n.minOrderUnsatisfied,
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
      if (state.lastStart is CheckoutRejected)
        _Banner(
          key: const ValueKey('checkout-rejected'),
          icon: Icons.error_outline,
          text: l10n.checkoutRejected,
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
              if (expiry != null && draft.next == DraftNext.pay)
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
                label: switch (quote?.totalAmount) {
                  final int t => l10n.payButton(formatKrw(t)),
                  null => l10n.payButtonNoAmount,
                },
                onPressed: state.canPay ? () async => ctl.pay() : null,
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
