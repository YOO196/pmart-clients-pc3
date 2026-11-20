import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pmart_core/pmart_core.dart'
    show IdempotencyKey, PmartFailure, ProblemFailure, UnknownResultFailure;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../../address/domain/address.dart';
import '../../address/presentation/address_controller.dart';
import '../../address/presentation/address_screens.dart' show LoginRequired;
import '../domain/checkout.dart';
import 'checkout_controller.dart';
import '../../payment/presentation/payment_controller.dart'
    show paymentWidgetConfigProvider;
import 'order_sheet_screen.dart' show draftRejection;
import '../../profile/presentation/consents_screens.dart'
    show ensureCurrentConsents;

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

/// 방식 한 줄 설명: 불가면 사유, 가능하면 방식 설명 + 예상시간·배달팁·가장 빠른 시간(서버 값만).
String optionSubtitle(AppLocalizations l10n, DeliveryOption o) {
  if (!o.available) {
    return switch (o.availability) {
      OptionAvailability.unknown => l10n.optionUnknown,
      OptionAvailability.configRequired => l10n.optionConfigRequired,
      _ => switch (o.reason) {
        UnavailableReason.nightTime => l10n.optionNightTime,
        UnavailableReason.centerClosed => l10n.optionCenterClosed,
        UnavailableReason.noSlot => l10n.optionNoSlot,
        UnavailableReason.configRequired => l10n.optionConfigRequired,
        // 조회 실패를 "배달 불가"로 보이지 않는다.
        UnavailableReason.lookupFailed => l10n.optionLookupFailed,
        UnavailableReason.unknown || null => l10n.optionUnavailable,
      },
    };
  }
  final eta = o.eta;
  final tip = o.tip?.applied ?? o.tip?.base;
  return [
    switch (o.mode) {
      DeliveryMode.single => l10n.modeSingleNote,
      DeliveryMode.bundled => l10n.modeBundledNote,
      DeliveryMode.scheduled => l10n.modeScheduledNote,
    },
    // ETA 미설정(NOT_SET)은 표시하지 않는다(0분·"곧"으로 그리지 않음, ⑤ 안내 §1).
    if (eta != null && !eta.notSet)
      switch ((eta.minMinutes, eta.maxMinutes)) {
        (final int a, final int b) => l10n.optionEta(a, b),
        _ => null,
      },
    if (tip != null) l10n.optionTip(formatKrw(tip)),
    if (o.earliestSlot case final w?) l10n.optionEarliestSlot(windowText(w)),
  ].nonNulls.join(' · ');
}

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
      appBar: AppBar(title: Text(l10n.deliveryTitle), centerTitle: true),
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
  @override
  void initState() {
    super.initState();
    _loadSavedOutOfStock();
  }

  /// 저장된 "다음에도 적용"(customer 0.4.0)을 기본으로. 못 읽으면 앱 기본(품절만 취소) 그대로 — 저장값으로 단정하지 않는다.
  Future<void> _loadSavedOutOfStock() async {
    try {
      final saved = await ref.read(orderPreferencesRepositoryProvider).get();
      if (!mounted) return;
      if (saved.outOfStock case final p?) {
        ref.read(checkoutSetupProvider.notifier).applySavedOutOfStock(p);
      }
    } on PmartFailure {
      // 기본값만 못 읽었다. 주문은 막지 않는다.
    }
  }

  Future<void> _next() => proceedToCheckout(context, ref);

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
              // 레퍼런스 5-2: 굵은 제목 + (고르기 전) 빨간 안내, 방식마다 카드 하나(카드 전체가 단추)
              Text(
                l10n.deliveryPickTitle,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontSize: 19, fontWeight: FontWeight.w700),
              ),
              if (setup.mode == null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l10n.deliveryPickRequired,
                    key: const ValueKey('delivery-pick-required'),
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              const SizedBox(height: 14),
              UiStateView<List<DeliveryOption>>(
                state: uiStateOf(options, isEmpty: (o) => o.isEmpty),
                onRetry: () => ref.invalidate(deliveryOptionsProvider),
                ready: (context, list) => Column(
                  children: [
                    for (final o in list)
                      DeliveryOptionCard(
                        option: o,
                        selected: o.mode == setup.mode,
                        window: o.mode == DeliveryMode.scheduled
                            ? setup.window
                            : null,
                        onTap: () async {
                          setupCtl.setMode(o.mode);
                          // 예약배달은 고르면 바로 도착 시간 시트(레퍼런스 5 "예약배달 도착 시간")
                          if (o.mode == DeliveryMode.scheduled) {
                            await showSlotSheet(context);
                          }
                        },
                      ),
                  ],
                ),
              ),
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
              // 레퍼런스 6-4 "다음에도 적용" — 다음 주문서의 기본값으로 서버에 저장한다(customer 0.4.0).
              CheckboxListTile(
                key: const ValueKey('oos-remember'),
                value: setup.rememberOutOfStock,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsets.only(left: 4),
                title: Text(l10n.oosRemember),
                onChanged: (v) => setupCtl.setRememberOutOfStock(v ?? false),
              ),
              TextField(
                key: const ValueKey('delivery-note'),
                controller: _note,
                maxLength: 200,
                decoration: InputDecoration(labelText: l10n.deliveryNote),
                onChanged: setupCtl.setNote,
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
                onPressed:
                    setup.complete && !ref.watch(checkoutPreparingProvider)
                    ? _next
                    : null,
                child: ref.watch(checkoutPreparingProvider)
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

/// 방식 카드(레퍼런스 5-2): 왼쪽 굵은 이름(+아이콘)·도착 안내, 오른쪽 배달팁(서버 값). 고르면 테두리 진하게.
/// 지금 안 되면 회색 + 서버 사유, 누를 수 없다.
class DeliveryOptionCard extends ConsumerWidget {
  const DeliveryOptionCard({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
    this.window,
  });

  final DeliveryOption option;
  final bool selected;
  final VoidCallback onTap;
  final ArrivalWindow? window;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = ref.watch(clockProvider)();
    final o = option;
    final on = o.available;
    final fg = on ? scheme.onSurface : scheme.outline;
    final eta = o.eta;
    final line = !on
        ? optionSubtitle(l10n, o)
        : switch (o.mode) {
            DeliveryMode.scheduled => switch (window) {
              final w? => l10n.slotPicked(
                slotDayLabel(l10n, w.date, now: now),
                windowText(w),
              ),
              null => l10n.modeScheduledArrive,
            },
            _ when eta != null && !eta.notSet => switch ((
              eta.minMinutes,
              eta.maxMinutes,
            )) {
              (final int a, final int b) => l10n.optionEtaArrive(a, b),
              _ => null,
            },
            _ => null,
          };
    final tip = o.tip;
    final shown = tip?.applied ?? tip?.base;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: scheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? scheme.onSurface : scheme.outlineVariant,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          key: ValueKey('mode-${o.mode.name}'),
          onTap: on ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            modeLabel(l10n, o.mode),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: fg,
                            ),
                          ),
                          if (o.mode == DeliveryMode.single) ...[
                            const SizedBox(width: 3),
                            PmartLineIcon(
                              PmartLineIcons.home,
                              size: 17,
                              strokeWidth: 2.4,
                              color: on ? scheme.primary : fg,
                            ),
                          ],
                        ],
                      ),
                      if (line != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            line,
                            key: ValueKey('mode-line-${o.mode.name}'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              color: on ? scheme.onSurface : scheme.outline,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (on && shown != null) ...[
                  if (tip?.base case final int base when base > shown) ...[
                    Text(
                      formatKrw(base),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.outline,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    formatKrw(shown),
                    key: ValueKey('mode-tip-${o.mode.name}'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "11.20 (오늘)" — 날짜 알약·예약 줄 표시. [date] 는 서울 `YYYY-MM-DD`.
String slotDayLabel(AppLocalizations l10n, String date, {DateTime? now}) {
  final p = date.split('-');
  final md = '${p[1]}.${p[2]}';
  final today = seoulDate(now ?? DateTime.now());
  final tomorrow = seoulDate(
    (now ?? DateTime.now()).add(const Duration(days: 1)),
  );
  return switch (date) {
    _ when date == today => l10n.slotDayToday(md),
    _ when date == tomorrow => l10n.slotDayTomorrow(md),
    _ => md,
  };
}

/// 예약배달 도착 시간 시트(레퍼런스 5 "4. 예약배달 도착 시간"): 제목 + ✕, 날짜 알약 둘, 시간 목록, 글머리, [시간 선택].
/// [시간 선택]을 눌러야 고른 시간이 들어간다(닫기는 그대로).
Future<void> showSlotSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  builder: (_) => const _SlotSheet(),
);

class _SlotSheet extends ConsumerStatefulWidget {
  const _SlotSheet();

  @override
  ConsumerState<_SlotSheet> createState() => _SlotSheetState();
}

class _SlotSheetState extends ConsumerState<_SlotSheet> {
  late bool _tomorrow =
      ref.read(checkoutSetupProvider).window?.date ==
      seoulDate(ref.read(clockProvider)().add(const Duration(days: 1)));
  late ArrivalWindow? _picked = ref.read(checkoutSetupProvider).window;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = ref.watch(clockProvider)();
    String dateOf(bool t) =>
        seoulDate(t ? now.add(const Duration(days: 1)) : now);
    final provider = slotsProvider(dateOf(_tomorrow));
    final slots = ref.watch(provider);
    Widget dayPill(bool t) {
      final on = _tomorrow == t;
      return Expanded(
        child: OutlinedButton(
          key: ValueKey(t ? 'slot-day-tomorrow' : 'slot-day-today'),
          onPressed: () => setState(() => _tomorrow = t),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(42),
            shape: const StadiumBorder(),
            backgroundColor: on ? scheme.onSurface : scheme.surface,
            foregroundColor: on ? scheme.surface : scheme.outline,
            side: BorderSide(
              color: on ? scheme.onSurface : scheme.outlineVariant,
            ),
            textStyle: theme.textTheme.titleSmall?.copyWith(
              fontSize: 16,
              fontWeight: on ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          child: Text(slotDayLabel(l10n, dateOf(t), now: now)),
        ),
      );
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          key: const ValueKey('slot-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.slotSheetTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('slot-sheet-close'),
                    tooltip: l10n.actionClose,
                    icon: const PmartLineIcon(PmartLineIcons.close, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Row(
                children: [
                  dayPill(false),
                  const SizedBox(width: 8),
                  dayPill(true),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.3,
              ),
              child: UiStateView<List<Slot>>(
                state: uiStateOf(slots),
                // 슬롯 조회 실패는 자동 재시도하지 않는다. 고객이 "다시 조회"를 누른다.
                onRetry: () => ref.invalidate(provider),
                ready: (context, list) {
                  if (!list.any((s) => s.selectable)) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(l10n.slotEmpty, textAlign: TextAlign.center),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final s in list)
                        _SlotRow(
                          slot: s,
                          picked: _picked == s.window,
                          onTap: s.selectable
                              ? () => setState(() => _picked = s.window)
                              : null,
                        ),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: DefaultTextStyle.merge(
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ${l10n.slotNote}'),
                    Text('• ${l10n.slotChangeNote}'),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
              child: FilledButton(
                key: const ValueKey('slot-confirm'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _picked == null
                    ? null
                    : () {
                        ref
                            .read(checkoutSetupProvider.notifier)
                            .setWindow(_picked!);
                        Navigator.of(context).pop();
                      },
                child: Text(l10n.slotConfirm),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 시간 한 줄. 고른 줄은 회색 채움 + 굵게, 고를 수 없으면 흐리게 + 사유.
class _SlotRow extends StatelessWidget {
  const _SlotRow({required this.slot, required this.picked, this.onTap});

  final Slot slot;
  final bool picked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = slot;
    final note = switch (s.availability) {
      SlotAvailability.available => switch (s.remaining) {
        final int n => l10n.slotRemaining(n),
        null => null,
      },
      SlotAvailability.full => l10n.slotFull,
      SlotAvailability.closed => l10n.slotClosed,
      SlotAvailability.configRequired => l10n.slotConfigRequired,
      SlotAvailability.unavailable => l10n.slotUnavailable,
    };
    return Material(
      color: picked ? scheme.surfaceContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('slot-${s.window.date}-${s.window.start}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Column(
            children: [
              Text(
                windowText(s.window),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: picked ? 19 : 17,
                  fontWeight: picked ? FontWeight.w700 : FontWeight.w400,
                  color: onTap == null ? scheme.outlineVariant : null,
                ),
              ),
              if (note != null)
                Text(
                  note,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: onTap == null
                        ? scheme.outlineVariant
                        : scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 주문서로 넘어가는 중(약관 확인 뒤 초안 만들기). 장바구니·배송 방식 화면이 같은 값을 본다.
final checkoutPreparingProvider = NotifierProvider<_Preparing, bool>(
  _Preparing.new,
);

class _Preparing extends Notifier<bool> {
  @override
  bool build() => false;

  // ignore: use_setters_to_change_properties
  void set(bool v) => state = v;
}

/// "다음에도 적용"(품절 시 요청)을 저장한다. 결과를 모르면 같은 키로 한 번 더. 실패해도 주문은 막지 않고 알린다.
Future<void> saveOutOfStockPreference(
  BuildContext context,
  WidgetRef ref,
  OutOfStockPreference p,
) async {
  final repo = ref.read(orderPreferencesRepositoryProvider);
  final key = IdempotencyKey.generate();
  try {
    try {
      await repo.save(p, key: key);
    } on UnknownResultFailure {
      await repo.save(p, key: key);
    }
  } on PmartFailure {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const ValueKey('oos-remember-failed'),
        content: Text(AppLocalizations.of(context).oosRememberFailed),
      ),
    );
  }
}

/// 주문서로: 약관 다시 동의(필요하면) → "다음에도 적용" 저장 → 초안 만들기 → 주문서. 막히면 사유를 알린다.
/// 서버가 최소 주문 미달이라고 하면 주문서로 넘어가지 않고 장바구니로 안내한다.
/// 장바구니(사용자 결정 2026-11-20 — 수령방법을 장바구니에서 고른다)와 배송 방식 화면이 같이 쓴다.
Future<void> proceedToCheckout(BuildContext context, WidgetRef ref) async {
  final busy = ref.read(checkoutPreparingProvider.notifier);
  if (ref.read(checkoutPreparingProvider)) return;
  // 주문 전 확인(CU-1 §3): 필수 약관이 바뀌었으면 다시 동의를 받는다(아래 시트). 동의하지 않으면 넘어가지 않는다.
  // 시트가 떠 있는 동안 뒤 단추가 "진행 중"으로 돌지 않게 동의를 먼저 묻는다.
  if (!await ensureCurrentConsents(context, ref)) return;
  if (!context.mounted) return;
  busy.set(true);
  try {
    // 저장된 "다음에도 적용"(customer 0.4.0)을 기본으로 — 고객이 이번에 고르기 전에만. 못 읽으면 앱 기본 그대로.
    try {
      final saved = await ref.read(orderPreferencesRepositoryProvider).get();
      if (saved.outOfStock case final p?) {
        ref.read(checkoutSetupProvider.notifier).applySavedOutOfStock(p);
      }
    } on PmartFailure {
      // 기본값만 못 읽었다. 주문은 막지 않는다.
    }
    if (!context.mounted) return;
    final setup = ref.read(checkoutSetupProvider);
    if (setup.rememberOutOfStock) {
      await saveOutOfStockPreference(context, ref, setup.outOfStock);
    }
    if (!context.mounted) return;
    // 결제창 설정을 초안과 동시에 받아 둔다(주문서에 들어간 뒤 차례로 받으면 결제수단이 늦게 뜬다).
    // 실패는 주문서가 결제수단 자리에 "다시 시도"로 보인다.
    ref.read(paymentWidgetConfigProvider.future).ignore();
    final gate = await ref.read(draftControllerProvider.notifier).prepare();
    if (!context.mounted) return;
    busy.set(false);
    switch (gate) {
      case CheckoutGate.proceed:
        await context.push('/checkout');
      case CheckoutGate.rejected:
        final l10n = AppLocalizations.of(context);
        final error = ref.read(draftControllerProvider).error;
        final rejection = draftRejection(l10n, error);
        // 재고 부족(order 0.8.0)은 장바구니에서 고칠 일이라 장바구니로 돌아가 줄마다 보인다.
        final stock =
            error is ProblemFailure &&
            error.problem.code == CheckoutProblemCode.insufficientStock;
        if (stock) context.go('/cart');
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              // 버튼이 달린 SnackBar 는 Flutter 기본값으로 자동으로 닫히지 않는다(persist). 알림은 잠시 뒤 닫는다.
              persist: false,
              key: const ValueKey('delivery-rejected'),
              content: Text(rejection?.text ?? l10n.checkoutRejected),
              action: switch (rejection) {
                _ when stock => null,
                (
                  route: final String route,
                  action: final String label,
                  text: _,
                ) =>
                  SnackBarAction(
                    label: label,
                    onPressed: () => context.go(route),
                  ),
                _ => null,
              },
            ),
          );
      case CheckoutGate.minOrderUnmet:
        final l10n = AppLocalizations.of(context);
        final shortfall = ref
            .read(draftControllerProvider)
            .value
            ?.draft
            .quote
            ?.minOrderShortfall;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              // 버튼이 달린 SnackBar 는 Flutter 기본값으로 자동으로 닫히지 않는다(persist). 알림은 잠시 뒤 닫는다.
              persist: false,
              key: const ValueKey('delivery-min-order'),
              // BR-14: 부족액은 서버 값(minOrderShortfall)만 쓴다. 없으면 금액 없이 안내한다.
              content: Text(switch (shortfall) {
                final int n when n > 0 => l10n.minOrderShortfall(formatKrw(n)),
                _ => l10n.minOrderUnsatisfied,
              }),
              action: SnackBarAction(
                label: l10n.cartGoToCart,
                onPressed: () => context.go('/cart'),
              ),
            ),
          );
    }
  } finally {
    if (ref.context.mounted) busy.set(false);
  }
}
