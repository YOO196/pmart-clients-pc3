import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../../address/domain/address.dart';
import '../../address/presentation/address_controller.dart';
import '../../address/presentation/address_screens.dart' show LoginRequired;
import '../domain/checkout.dart';
import 'checkout_controller.dart';

String modeLabel(AppLocalizations l10n, DeliveryMode m) => switch (m) {
  DeliveryMode.single => l10n.modeSingle,
  DeliveryMode.bundled => l10n.modeBundled,
  DeliveryMode.scheduled => l10n.modeScheduled,
};

/// 도착 구간 `오후 1:00~2:00`. 날짜·시각은 서울 기준 문자열이다.
String windowText(ArrivalWindow w) => formatSeoulWindow(
  DateTime.parse('${w.date}T${w.start}:00+09:00'),
  DateTime.parse('${w.date}T${w.end}:00+09:00'),
);

String seoulDate(DateTime instant) =>
    DateFormat('yyyy-MM-dd').format(toSeoulWallClock(instant));

/// SCR-DELIVERY-SELECT-001. 주문서 진입 전에 고른다. 주문서의 "변경"도 이 화면으로 온다.
class DeliverySelectScreen extends ConsumerWidget {
  const DeliverySelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final book = ref.watch(addressBookProvider);
    final Widget body = switch (book) {
      AsyncData(value: null) => LoginRequired(message: l10n.blockedNotMember),
      AsyncData(value: final b?) when b.shoppingAddress == null => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.needShoppingAddress),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.push('/addresses'),
              child: Text(l10n.goAddresses),
            ),
          ],
        ),
      ),
      AsyncData(value: final b?)
          when b.shoppingAddress!.serviceability !=
              Serviceability.serviceable =>
        Center(
          key: const ValueKey('address-not-serviceable'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.addressNotServiceable),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.push('/addresses'),
                child: Text(l10n.goAddresses),
              ),
            ],
          ),
        ),
      AsyncData() => const _DeliveryBody(),
      _ => UiStateView<Object?>(
        state: uiStateOf(book),
        onRetry: () => ref.invalidate(addressBookProvider),
        ready: (_, _) => const SizedBox.shrink(),
      ),
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.deliveryTitle)),
      body: body,
    );
  }
}

class _DeliveryBody extends ConsumerStatefulWidget {
  const _DeliveryBody();

  @override
  ConsumerState<_DeliveryBody> createState() => _DeliveryBodyState();
}

class _DeliveryBodyState extends ConsumerState<_DeliveryBody> {
  bool _preparing = false;

  /// 서버가 최소 주문 미달이라고 하면 주문서로 넘어가지 않고 장바구니로 안내한다.
  Future<void> _next() async {
    setState(() => _preparing = true);
    final gate = await ref.read(draftControllerProvider.notifier).prepare();
    if (!mounted) return;
    setState(() => _preparing = false);
    switch (gate) {
      case CheckoutGate.proceed:
        await context.push('/checkout');
      case CheckoutGate.minOrderUnmet:
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              key: const ValueKey('delivery-min-order'),
              // BR-14: 부족액은 계약에 없어 금액 없이 안내한다(앱에서 계산하지 않는다).
              content: Text(l10n.minOrderUnsatisfied),
              action: SnackBarAction(
                label: l10n.cartGoToCart,
                onPressed: () => context.go('/cart'),
              ),
            ),
          );
    }
  }

  bool _tomorrow = false;
  late final _note = TextEditingController(
    text: ref.read(checkoutSetupProvider).deliveryNote,
  );

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final setup = ref.watch(checkoutSetupProvider);
    final setupCtl = ref.read(checkoutSetupProvider.notifier);
    final options = ref.watch(deliveryOptionsProvider);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              UiStateView<List<DeliveryOption>>(
                state: uiStateOf(options, isEmpty: (o) => o.isEmpty),
                onRetry: () => ref.invalidate(deliveryOptionsProvider),
                ready: (context, list) => RadioGroup<DeliveryMode>(
                  groupValue: setup.mode,
                  onChanged: (m) {
                    if (m != null) setupCtl.setMode(m);
                  },
                  child: Column(
                    children: [
                      for (final o in list)
                        RadioListTile<DeliveryMode>(
                          key: ValueKey('mode-${o.mode.name}'),
                          value: o.mode,
                          enabled: o.available,
                          title: Text(modeLabel(l10n, o.mode)),
                          subtitle: Text(
                            o.unavailableReason ??
                                switch (o.mode) {
                                  DeliveryMode.single => l10n.modeSingleNote,
                                  DeliveryMode.bundled => l10n.modeBundledNote,
                                  DeliveryMode.scheduled =>
                                    l10n.modeScheduledNote,
                                },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (setup.mode == DeliveryMode.scheduled) ...[
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(l10n.slotToday)),
                    ButtonSegment(value: true, label: Text(l10n.slotTomorrow)),
                  ],
                  selected: {_tomorrow},
                  onSelectionChanged: (v) =>
                      setState(() => _tomorrow = v.first),
                ),
                const SizedBox(height: 8),
                _SlotPicker(tomorrow: _tomorrow),
              ],
              const Divider(height: 32),
              Text(
                l10n.orderOptionsTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              RadioGroup<OutOfStockPreference>(
                groupValue: setup.outOfStock,
                onChanged: (p) {
                  if (p != null) setupCtl.setOutOfStock(p);
                },
                child: Column(
                  children: [
                    RadioListTile(
                      value: OutOfStockPreference.cancelOutOfStockOnly,
                      title: Text(l10n.oosOnly),
                    ),
                    RadioListTile(
                      value: OutOfStockPreference.cancelAll,
                      title: Text(l10n.oosAll),
                    ),
                  ],
                ),
              ),
              TextField(
                key: const ValueKey('delivery-note'),
                controller: _note,
                maxLength: 200,
                decoration: InputDecoration(labelText: l10n.deliveryNote),
                onChanged: setupCtl.setNote,
              ),
              SwitchListTile(
                value: setup.bagOptOut,
                title: Text(l10n.bagOptOut),
                subtitle: Text(l10n.bagOptOutNote),
                onChanged: setupCtl.setBagOptOut,
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
              child: FilledButton(
                key: const ValueKey('delivery-next'),
                onPressed: setup.complete && !_preparing ? _next : null,
                child: _preparing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.deliveryNext),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SlotPicker extends ConsumerWidget {
  const _SlotPicker({required this.tomorrow});

  final bool tomorrow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final now = ref.watch(clockProvider)();
    final date = seoulDate(tomorrow ? now.add(const Duration(days: 1)) : now);
    final provider = slotsProvider(date);
    final setup = ref.watch(checkoutSetupProvider);
    final slots = ref.watch(provider);
    return UiStateView<List<Slot>>(
      state: uiStateOf(slots),
      // 슬롯 조회 실패는 자동 재시도하지 않는다. 고객이 "다시 조회"를 누른다.
      onRetry: () => ref.invalidate(provider),
      ready: (context, list) {
        if (!list.any((s) => s.selectable)) {
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Text(l10n.slotEmpty),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in list)
                  ChoiceChip(
                    key: ValueKey('slot-${s.window.date}-${s.window.start}'),
                    selected: setup.window == s.window,
                    onSelected: s.selectable
                        ? (_) => ref
                              .read(checkoutSetupProvider.notifier)
                              .setWindow(s.window)
                        : null,
                    label: Text(
                      [
                        windowText(s.window),
                        switch (s.availability) {
                          SlotAvailability.available => switch (s.remaining) {
                            final int n => l10n.slotRemaining(n),
                            null => null,
                          },
                          SlotAvailability.full => l10n.slotFull,
                          SlotAvailability.closed => l10n.slotClosed,
                          SlotAvailability.configRequired =>
                            l10n.slotConfigRequired,
                          SlotAvailability.unavailable => l10n.slotUnavailable,
                        },
                      ].nonNulls.join(' · '),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(l10n.slotNote, style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      },
    );
  }
}
