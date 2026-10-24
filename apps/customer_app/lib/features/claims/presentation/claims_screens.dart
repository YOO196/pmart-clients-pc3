import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../../checkout/domain/checkout.dart';
import '../../checkout/presentation/checkout_controller.dart';
import '../../checkout/presentation/delivery_select_screen.dart'
    show seoulDate, windowText;
import '../../orders/domain/orders.dart';
import '../../orders/presentation/orders_providers.dart';
import '../domain/claims.dart';
import 'claims_controller.dart';

String claimStateText(AppLocalizations l10n, ClaimState s) => switch (s) {
  ClaimState.opened => l10n.clOpened,
  ClaimState.underReview => l10n.clUnderReview,
  ClaimState.stopPending => l10n.clStopPending,
  ClaimState.decided => l10n.clDecided,
  ClaimState.inProgress => l10n.clInProgress,
  ClaimState.closed => l10n.clClosed,
  ClaimState.withdrawn => l10n.clWithdrawn,
  ClaimState.rejected => l10n.clRejected,
  ClaimState.unknown => l10n.osUnknown,
};

String cancelRejectText(AppLocalizations l10n, String code) => switch (code) {
  'ORDER_NOT_CANCELLABLE' || 'NOT_CANCELLABLE' => l10n.cancelNotCancellable,
  'QUANTITY_EXCEEDS_AVAILABLE' => l10n.cancelQtyExceeded,
  'DUPLICATE_CLAIM' => l10n.cancelDuplicate,
  _ => l10n.checkoutRejected,
};

/// SCR-CANCEL-001. "취소 요청" 버튼은 접수일 뿐 취소 완료가 아니다.
class CancelScreen extends ConsumerStatefulWidget {
  const CancelScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<CancelScreen> createState() => _CancelScreenState();
}

class _CancelScreenState extends ConsumerState<CancelScreen> {
  final _qty = <String, int>{};
  CancelReason _reason = CancelReason.changeOfMind;
  String? _message;
  bool _unknown = false;

  Future<void> _submit(OrderDetail order) async {
    final l10n = AppLocalizations.of(context);
    final lines = [
      for (final e in _qty.entries)
        if (e.value > 0) CancelLine(orderLineId: e.key, qty: e.value),
    ];
    final outcome = await ref
        .read(cancelRequesterProvider(widget.orderId))
        .submit(order.orderId, lines, _reason);
    if (!mounted) return;
    switch (outcome) {
      case CommandDone(:final value):
        ref.invalidate(orderDetailProvider(widget.orderId));
        context.pushReplacement('/claims/${value.claimId}');
      case CommandRejected(:final code):
        setState(() {
          _unknown = false;
          _message = cancelRejectText(l10n, code);
        });
      case CommandUnknown():
        setState(() {
          _unknown = true;
          _message = l10n.cancelUnknown;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = orderDetailProvider(widget.orderId);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.cancelTitle)),
      body: UiStateView<OrderDetail>(
        state: uiStateOf(ref.watch(provider)),
        onRetry: () => ref.invalidate(provider),
        ready: (context, order) {
          final any = _qty.values.any((q) => q > 0);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(l10n.cancelPickItems),
              for (final l in order.lines)
                Builder(
                  builder: (context) {
                    final max = cancellableHint(l);
                    final q = _qty[l.orderLineId] ?? 0;
                    return ListTile(
                      key: ValueKey('cancel-line-${l.orderLineId}'),
                      contentPadding: EdgeInsets.zero,
                      enabled: max > 0,
                      title: Text(l.productName ?? l.sku),
                      subtitle: Text(
                        max > 0
                            ? l10n.cancelUpTo(max)
                            : l10n.cancelLineUnavailable,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: ValueKey('cancel-dec-${l.orderLineId}'),
                            onPressed: q > 0
                                ? () => setState(
                                    () => _qty[l.orderLineId] = q - 1,
                                  )
                                : null,
                            icon: const Icon(Icons.remove),
                          ),
                          Text('$q'),
                          IconButton(
                            key: ValueKey('cancel-inc-${l.orderLineId}'),
                            onPressed: q < max
                                ? () => setState(
                                    () => _qty[l.orderLineId] = q + 1,
                                  )
                                : null,
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              const SizedBox(height: 12),
              Text(l10n.cancelReason),
              RadioGroup<CancelReason>(
                groupValue: _reason,
                onChanged: (r) => setState(() => _reason = r ?? _reason),
                child: Column(
                  children: [
                    for (final r in CancelReason.values)
                      RadioListTile<CancelReason>(
                        value: r,
                        title: Text(switch (r) {
                          CancelReason.changeOfMind => l10n.reasonChangeOfMind,
                          CancelReason.addressError => l10n.reasonAddressError,
                          CancelReason.lateDelivery => l10n.reasonLateDelivery,
                          CancelReason.other => l10n.reasonOther,
                        }),
                      ),
                  ],
                ),
              ),
              Text(
                l10n.cancelNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_message case final m?)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    m,
                    key: const ValueKey('cancel-message'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              CommandButton(
                key: const ValueKey('cancel-submit'),
                // 결과를 모르면 같은 키로 다시 확인한다(새 취소 요청이 아니다).
                label: _unknown ? l10n.checkoutCheckAgain : l10n.cancelSubmit,
                onPressed: any ? () => _submit(order) : null,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// SCR-CLAIM-DETAIL-001. 품목별 승인·거절, 환불은 PG 성공 전 "완료" 없음.
class ClaimScreen extends ConsumerStatefulWidget {
  const ClaimScreen({super.key, required this.claimId});

  final String claimId;

  @override
  ConsumerState<ClaimScreen> createState() => _ClaimScreenState();
}

class _ClaimScreenState extends ConsumerState<ClaimScreen> {
  RequestState? _withdrawal;
  bool _withdrawing = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = claimProvider(widget.claimId);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.claimTitle)),
      body: UiStateView<ClaimView>(
        state: uiStateOf(ref.watch(provider)),
        onRetry: () => ref.invalidate(provider),
        ready: (context, c) => RefreshIndicator(
          onRefresh: () => ref.refresh(provider.future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                claimStateText(l10n, c.state),
                key: const ValueKey('claim-state'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (c.state == ClaimState.opened) Text(l10n.claimAcceptedNote),
              const SizedBox(height: 12),
              for (final l in c.lines)
                ListTile(
                  key: ValueKey('claim-line-${l.orderLineId}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.sku ?? l.orderLineId),
                  subtitle: Text(
                    [
                      if (l.requestedQty case final q?) l10n.claimRequested(q),
                      switch (l.decision) {
                        LineDecision.pending => l10n.decisionPending,
                        LineDecision.approved => l10n.decisionApproved(
                          l.approvedQty ?? 0,
                        ),
                        LineDecision.rejected => l10n.decisionRejected,
                      },
                      ?l.rejectReason,
                    ].join(' · '),
                  ),
                ),
              for (final r in c.refunds)
                ListTile(
                  key: const ValueKey('refund'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    r.done ? Icons.check_circle_outline : Icons.hourglass_top,
                  ),
                  title: Text(
                    r.done
                        ? l10n.refundDone
                        : r.state == RefundState.failed
                        ? l10n.refundFailed
                        : l10n.refundInProgress,
                  ),
                  trailing: Text(switch (r.amount) {
                    final int a => formatKrw(a),
                    null => l10n.amountUnavailable,
                  }),
                ),
              if (_withdrawal == RequestState.pending ||
                  _withdrawal == RequestState.unknown)
                Text(
                  l10n.withdrawChecking,
                  key: const ValueKey('withdraw-checking'),
                ),
              if (_withdrawal == RequestState.rejected)
                Text(l10n.withdrawRejected),
              if (c.canWithdraw && _withdrawal == null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: OutlinedButton(
                    key: const ValueKey('withdraw'),
                    onPressed: _withdrawing
                        ? null
                        : () async {
                            setState(() => _withdrawing = true);
                            final s = await ref.read(withdrawClaimProvider)(c);
                            if (!mounted) return;
                            setState(() {
                              _withdrawing = false;
                              _withdrawal = s;
                            });
                            if (s == RequestState.confirmed) {
                              ref.invalidate(provider);
                            }
                          },
                    child: Text(l10n.withdraw),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// SCR-RESCHEDULE-001. 상품 준비 전만. 확인 중에는 지금 시간과 요청한 시간을 구분해 보인다.
class RescheduleScreen extends ConsumerStatefulWidget {
  const RescheduleScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<RescheduleScreen> createState() => _RescheduleScreenState();
}

class _RescheduleScreenState extends ConsumerState<RescheduleScreen> {
  ArrivalWindow? _picked;
  ArrivalWindow? _requested;
  RequestState? _state;
  String? _rejectCode;

  Future<void> _submit(OrderDetail order) async {
    final w = _picked;
    if (w == null) return;
    setState(() {
      _requested = w;
      _state = RequestState.pending;
      _rejectCode = null;
    });
    final outcome = await ref.read(requestTimeChangeProvider)(order, w);
    if (!mounted) return;
    setState(() {
      switch (outcome) {
        case CommandDone(:final value):
          _state = value;
        case CommandRejected(:final code):
          _state = RequestState.rejected;
          _rejectCode = code;
        case CommandUnknown():
          _state = RequestState.unknown;
      }
    });
    if (_state == RequestState.confirmed) {
      ref.invalidate(orderDetailProvider(widget.orderId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = orderDetailProvider(widget.orderId);
    final now = ref.watch(clockProvider)();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.rescheduleTitle)),
      body: UiStateView<OrderDetail>(
        state: uiStateOf(ref.watch(provider)),
        onRetry: () => ref.invalidate(provider),
        ready: (context, order) {
          final slots = ref.watch(slotsProvider(seoulDate(now)));
          final busy = _state == RequestState.pending;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                l10n.rescheduleCurrent(
                  order.window == null ? '-' : windowText(order.window!),
                ),
                key: const ValueKey('reschedule-current'),
              ),
              if (_requested != null && _state != RequestState.confirmed)
                Text(switch (_state) {
                  RequestState.rejected => l10n.rescheduleRejected(
                    _rejectCode == 'INVALID_STATE'
                        ? l10n.rescheduleTooLate
                        : l10n.rescheduleNotAvailable,
                  ),
                  _ => l10n.rescheduleChecking(windowText(_requested!)),
                }, key: const ValueKey('reschedule-status')),
              if (_state == RequestState.confirmed)
                Text(
                  l10n.rescheduleDone,
                  key: const ValueKey('reschedule-done'),
                ),
              const SizedBox(height: 12),
              UiStateView<List<Slot>>(
                state: uiStateOf(slots),
                onRetry: () => ref.invalidate(slotsProvider(seoulDate(now))),
                ready: (context, list) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in list)
                      ChoiceChip(
                        key: ValueKey('rs-slot-${s.window.start}'),
                        selected: _picked == s.window,
                        label: Text(windowText(s.window)),
                        onSelected:
                            (s.selectable && !busy && s.window != order.window)
                            ? (_) => setState(() => _picked = s.window)
                            : null,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              CommandButton(
                key: const ValueKey('reschedule-submit'),
                label: l10n.rescheduleSubmit,
                onPressed: (_picked != null && !busy)
                    ? () => _submit(order)
                    : null,
              ),
            ],
          );
        },
      ),
    );
  }
}
