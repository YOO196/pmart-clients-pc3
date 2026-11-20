import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart' show PmartFailure, ProblemCode;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/order_status.dart';
import '../../../shared/ui_state_of.dart';
import '../../checkout/domain/checkout.dart';
import '../../checkout/presentation/checkout_controller.dart';
import '../../checkout/presentation/delivery_select_screen.dart'
    show seoulDate, slotDayLabel, windowText;
import '../../orders/domain/orders.dart';
import '../../orders/presentation/orders_providers.dart';
import '../domain/claims.dart';
import 'claims_controller.dart';
import 'return_fee_section.dart';
import '../../../shared/notice.dart';

/// [type] 이 반품이면 진행 중 문구를 반품용으로(회수·검수·환불 — 취소 문구를 쓰지 않는다).
String claimStateText(AppLocalizations l10n, ClaimState s, {ClaimType? type}) =>
    switch (s) {
      ClaimState.inProgress when type == ClaimType.returnItems =>
        l10n.clReturnInProgress,
      ClaimState.opened => l10n.clOpened,
      // 출고 중지 확인(STOP_PENDING)은 내부 단계라 고객에게는 "확인 중"으로만 보인다(2026-11-02 사용자 결정).
      ClaimState.underReview || ClaimState.stopPending => l10n.clUnderReview,
      ClaimState.decided => l10n.clDecided,
      ClaimState.inProgress => l10n.clInProgress,
      ClaimState.closed => l10n.clClosed,
      ClaimState.withdrawn => l10n.clWithdrawn,
      ClaimState.rejected => l10n.clRejected,
      ClaimState.feePending => l10n.clFeePending,
      ClaimState.recoveryFailed => l10n.clRecoveryFailed,
      ClaimState.cancelled => l10n.clCancelled,
      ClaimState.unknown => l10n.osUnknown,
    };

/// 주문 상세의 처리 내역 줄 제목. 모르는 종류는 일반 제목으로.
String claimTypeText(AppLocalizations l10n, ClaimType t) => switch (t) {
  ClaimType.cancel => l10n.claimTypeCancel,
  ClaimType.returnItems => l10n.claimTypeReturn,
  ClaimType.exchange => l10n.claimTypeExchange,
  ClaimType.unknown => l10n.claimTitle,
};

String cancelRejectText(AppLocalizations l10n, String code) => switch (code) {
  'ORDER_NOT_CANCELLABLE' || 'NOT_CANCELLABLE' => l10n.cancelNotCancellable,
  'QUANTITY_EXCEEDS_AVAILABLE' => l10n.cancelQtyExceeded,
  'DUPLICATE_CLAIM' => l10n.cancelDuplicate,
  ClaimProblemCode.partialCancelNotAllowed => l10n.cancelPartialNotAllowed,
  ClaimProblemCode.unsupportedAction ||
  ClaimProblemCode.notImplemented => l10n.cancelUnsupported,
  _ => l10n.checkoutRejected,
};

/// 이 거절은 주문 상태가 바뀌었다는 뜻이라 주문 상세를 다시 불러온다(handoff 2026-10-31 §3).
bool _refreshOrderOn(String code) =>
    code == 'ORDER_NOT_CANCELLABLE' ||
    code == 'QUANTITY_EXCEEDS_AVAILABLE' ||
    code == ClaimProblemCode.partialCancelNotAllowed;

/// SCR-CANCEL-001. 주문 전체 취소만(부분 취소 없음). 버튼은 접수일 뿐 취소 완료가 아니다.
class CancelScreen extends ConsumerStatefulWidget {
  const CancelScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<CancelScreen> createState() => _CancelScreenState();
}

class _CancelScreenState extends ConsumerState<CancelScreen> {
  CancelReason _reason = CancelReason.changeOfMind;
  String? _message;
  bool _unknown = false;

  Future<void> _submit(OrderDetail order, List<CancelLine> lines) async {
    final l10n = AppLocalizations.of(context);
    final outcome = await ref
        .read(cancelRequesterProvider(widget.orderId))
        .submit(order.orderId, lines, _reason);
    if (!mounted) return;
    switch (outcome) {
      case CommandDone(:final value):
        ref.invalidate(orderDetailProvider(widget.orderId));
        context.pushReplacement('/claims/${value.claimId}');
      case CommandRejected(:final code)
          when code == ClaimProblemCode.duplicateClaim:
        // 이미 취소가 진행 중이다(자동 취소 포함) — 안내하고 그 처리 내역으로 보낸다(백엔드 공지 2026-11-07 C4)
        final messenger = ScaffoldMessenger.of(context);
        ClaimView? found;
        try {
          found = await ref
              .read(claimsRepositoryProvider)
              .findActiveCancel(widget.orderId);
        } on PmartFailure {
          found = null; // 찾지 못하면 이 화면에 안내만 남긴다
        }
        if (!mounted) return;
        ref.invalidate(orderDetailProvider(widget.orderId));
        if (found != null) {
          messenger.notice(l10n.cancelDuplicate);
          context.pushReplacement('/claims/${found.claimId}');
          return;
        }
        setState(() {
          _unknown = false;
          _message = l10n.cancelDuplicate;
        });
      case CommandRejected(:final code):
        setState(() {
          _unknown = false;
          _message = cancelRejectText(l10n, code);
        });
        if (_refreshOrderOn(code)) {
          ref.invalidate(orderDetailProvider(widget.orderId));
        }
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
    final theme = Theme.of(context);
    final provider = orderDetailProvider(widget.orderId);
    // 레퍼런스 9-1 4: 가운데 작은 창 — 제목 "주문을 취소할까요?", 사유(계약 필수), 오른쪽 아래 [아니요][주문취소]
    return Dialog(
      key: const ValueKey('cancel-dialog'),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: UiStateView<OrderDetail>(
          state: uiStateOf(ref.watch(provider)),
          onRetry: () => ref.invalidate(provider),
          ready: (context, order) {
            final lines = cancelLinesOf(order);
            final qtyByLine = {
              for (final c in lines ?? const <CancelLine>[])
                c.orderLineId: c.qty,
            };
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 24, 18, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.cancelConfirmTitle,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    switch (lines) {
                      null => l10n.cancelQtyUnavailable,
                      [] => l10n.cancelNothingLeft,
                      _ => l10n.cancelWholeOrderNote,
                    },
                    key: const ValueKey('cancel-scope'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  for (final l in order.lines)
                    if (qtyByLine[l.orderLineId] case final q?)
                      Padding(
                        key: ValueKey('cancel-line-${l.orderLineId}'),
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                l.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                            Text(
                              l10n.cancelLineQty(q),
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.cancelReason,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  RadioGroup<CancelReason>(
                    groupValue: _reason,
                    onChanged: (r) => setState(() => _reason = r ?? _reason),
                    child: Column(
                      children: [
                        for (final r in CancelReason.values)
                          RadioListTile<CancelReason>(
                            value: r,
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            contentPadding: EdgeInsets.zero,
                            title: Text(switch (r) {
                              CancelReason.changeOfMind =>
                                l10n.reasonChangeOfMind,
                              CancelReason.addressError =>
                                l10n.reasonAddressError,
                              CancelReason.lateDelivery =>
                                l10n.reasonLateDelivery,
                              CancelReason.other => l10n.reasonOther,
                            }, style: theme.textTheme.bodyMedium),
                          ),
                      ],
                    ),
                  ),
                  Text(l10n.cancelNote, style: theme.textTheme.bodySmall),
                  if (_message case final m?)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        m,
                        key: const ValueKey('cancel-message'),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        key: const ValueKey('cancel-dismiss'),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.onSurface,
                          minimumSize: const Size(72, 44),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(l10n.cancelConfirmNo),
                      ),
                      const SizedBox(width: 8),
                      CommandButton(
                        key: const ValueKey('cancel-submit'),
                        // 결과를 모르면 같은 키로 다시 확인한다(새 취소 요청이 아니다).
                        label: _unknown
                            ? l10n.checkoutCheckAgain
                            : l10n.cancelSubmit,
                        onPressed: switch (lines) {
                          final l? when l.isNotEmpty => () => _submit(order, l),
                          _ => null,
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
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
  Timer? _refresh;

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  /// 끝 상태가 될 때까지 잠깐씩 다시 조회한다. 조회 실패면 멈추고 화면의 다시 시도에 맡긴다.
  void _scheduleRefresh(ClaimView? claim) {
    _refresh?.cancel();
    _refresh = null;
    if (claim == null || isClaimSettled(claim.state)) return;
    _refresh = Timer(ref.read(claimRefreshIntervalProvider), () {
      if (mounted) ref.invalidate(claimProvider(widget.claimId));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = claimProvider(widget.claimId);
    ref.listen(provider, (prev, next) {
      if (next.isLoading) return;
      final claim = next.hasError ? null : next.value;
      _scheduleRefresh(claim);
      // 클레임이 나아가면 주문 상태도 바뀐다(출고 중지·취소·환불). 아래에 열려 있는 주문 상세·목록이
      // 돌아갔을 때 옛 상태를 보이지 않도록 다시 읽게 한다.
      if (claim != null && claim.state != prev?.value?.state) {
        ref.invalidate(orderDetailProvider(claim.orderId));
        ref.invalidate(orderClaimsProvider(claim.orderId));
        ref.invalidate(orderListProvider);
      }
    });
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
                claimStateText(l10n, c.state, type: c.type),
                key: const ValueKey('claim-state'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (c.autoCancelled)
                Text(
                  // 주문 취소가 확정되기 전에는 "취소되었어요"라고 하지 않는다
                  c.state == ClaimState.closed ||
                          ref
                                  .watch(orderDetailProvider(c.orderId))
                                  .value
                                  ?.status ==
                              OrderStatus.cancelled
                      ? l10n.claimAutoCancelled
                      : l10n.claimAutoCancelling,
                  key: const ValueKey('claim-auto-cancelled'),
                )
              else if (c.state == ClaimState.opened)
                Text(l10n.claimAcceptedNote),
              // 반품 회수비(고객 사유 반품 — 고객센터 접수). 결제해야 회수가 시작된다.
              ReturnFeeSection(claim: c),
              const SizedBox(height: 12),
              for (final l in c.lines)
                ListTile(
                  key: ValueKey('claim-line-${l.orderLineId}'),
                  contentPadding: EdgeInsets.zero,
                  // 클레임 응답에는 이름이 없다(BR-35 회신 §3). 주문 상세의 품목 사본과 orderLineId 로 맞춘다.
                  title: Text(
                    ref
                            .watch(orderDetailProvider(c.orderId))
                            .value
                            ?.lines
                            .where((o) => o.orderLineId == l.orderLineId)
                            .firstOrNull
                            ?.title ??
                        l.sku ??
                        l.orderLineId,
                  ),
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
                  leading: PmartLineIcon(
                    r.done ? PmartLineIcons.checkCircle : PmartLineIcons.clock,
                  ),
                  title: Text(switch (r) {
                    _ when r.returnFee && r.done => l10n.refundFeeDone,
                    _ when r.returnFee => l10n.refundFeeInProgress,
                    _ when r.done => l10n.refundDone,
                    RefundView(state: RefundState.failed) => l10n.refundFailed,
                    RefundView(state: RefundState.unknown) =>
                      l10n.refundChecking,
                    _ => l10n.refundInProgress,
                  }),
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

/// 시간 변경에서 고를 슬롯 — 주문의 담당 센터(`Order.mfcId`) 기준(지금 쇼핑 주소의 센터가 아니다).
final orderSlotsProvider = FutureProvider.autoDispose
    .family<List<Slot>, ({String mfcId, String date})>(
      (ref, a) => ref.watch(checkoutRepositoryProvider).slots(a.mfcId, a.date),
    );

/// 시간 변경 거절 사유(요청 단계 코드 또는 결과의 reason). 모르는 코드는 "다른 시간을 골라 주세요".
String rescheduleReasonText(AppLocalizations l10n, String? code) =>
    switch (code) {
      ProblemCode.invalidState ||
      TimeChangeCode.preparationStarted => l10n.rescheduleTooLate,
      TimeChangeCode.notScheduled => l10n.rescheduleNotScheduled,
      TimeChangeCode.sameSlot => l10n.rescheduleSameSlot,
      TimeChangeCode.inProgress => l10n.rescheduleInProgress,
      ProblemCode.versionConflict => l10n.rescheduleVersionConflict,
      TimeChangeCode.capacityExceeded ||
      TimeChangeCode.slotNotSelectable => l10n.rescheduleSlotClosed,
      TimeChangeCode.operationRestricted => l10n.rescheduleCenterLimited,
      TimeChangeCode.lotExpiryNotMet => l10n.rescheduleLotExpiry,
      _ => l10n.rescheduleNotAvailable,
    };

class _RescheduleScreenState extends ConsumerState<RescheduleScreen> {
  ArrivalWindow? _picked;
  ArrivalWindow? _requested;
  RequestState? _state;
  String? _rejectCode;
  bool _tomorrow = false;

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
          _state = value.state;
          _rejectCode = value.reason;
        case CommandRejected(:final code):
          _state = RequestState.rejected;
          _rejectCode = code;
        case CommandUnknown():
          _state = RequestState.unknown;
      }
    });
    // 바뀌었으면 새 시간, 주문이 그사이 바뀌었으면(VERSION_CONFLICT) 최신 주문을 다시 읽는다.
    if (_state == RequestState.confirmed ||
        _rejectCode == ProblemCode.versionConflict) {
      ref.invalidate(orderDetailProvider(widget.orderId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = orderDetailProvider(widget.orderId);
    final now = ref.watch(clockProvider)();
    return SafeArea(
      child: UiStateView<OrderDetail>(
        state: uiStateOf(ref.watch(provider)),
        onRetry: () => ref.invalidate(provider),
        ready: (context, order) {
          // 오늘·내일(서울) 중 고른 날의 슬롯. 주문의 센터를 모르면(예전 주문) 지금 주소의 센터로.
          final date = seoulDate(
            _tomorrow ? now.add(const Duration(days: 1)) : now,
          );
          final slotsArg = switch (order.mfcId) {
            final m? => (mfcId: m, date: date),
            null => null,
          };
          final slots = slotsArg == null
              ? ref.watch(slotsProvider(date))
              : ref.watch(orderSlotsProvider(slotsArg));
          void retrySlots() => slotsArg == null
              ? ref.invalidate(slotsProvider(date))
              : ref.invalidate(orderSlotsProvider(slotsArg));
          final busy = _state == RequestState.pending;
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          Widget dayPill(bool t) {
            final on = _tomorrow == t;
            final d = seoulDate(t ? now.add(const Duration(days: 1)) : now);
            return Expanded(
              child: OutlinedButton(
                key: ValueKey(t ? 'rs-day-tomorrow' : 'rs-day-today'),
                onPressed: busy
                    ? null
                    : () => setState(() {
                        _tomorrow = t;
                        _picked = null;
                      }),
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
                child: Text(slotDayLabel(l10n, d, now: now)),
              ),
            );
          }

          // 레퍼런스 9-1 4: 아래 시트 — 제목 + ✕, 날짜 알약, 시간 목록, 글머리, [시간 변경]
          return Column(
            key: const ValueKey('reschedule-sheet'),
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
                      key: const ValueKey('reschedule-close'),
                      tooltip: l10n.actionClose,
                      icon: const PmartLineIcon(PmartLineIcons.close, size: 22),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                child: DefaultTextStyle.merge(
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.rescheduleCurrent(
                          order.window == null
                              ? '-'
                              : windowText(order.window!),
                        ),
                        key: const ValueKey('reschedule-current'),
                      ),
                      if (_requested != null &&
                          _state != RequestState.confirmed)
                        Text(
                          switch (_state) {
                            // 거절이면 기존 시간 그대로다(서버가 약속을 바꾸지 않았다).
                            RequestState.rejected =>
                              '${l10n.rescheduleRejected(rescheduleReasonText(l10n, _rejectCode))}\n${l10n.rescheduleKept}',
                            _ => l10n.rescheduleChecking(
                              windowText(_requested!),
                            ),
                          },
                          key: const ValueKey('reschedule-status'),
                          style: _state == RequestState.rejected
                              ? TextStyle(color: scheme.error)
                              : null,
                        ),
                      if (_state == RequestState.confirmed)
                        Text(
                          l10n.rescheduleDone,
                          key: const ValueKey('reschedule-done'),
                          style: TextStyle(color: scheme.primary),
                        ),
                    ],
                  ),
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
              // 레퍼런스: 시트는 화면 아래쪽 절반쯤 — 시간 목록은 높이를 묶고 안에서 스크롤
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.3,
                ),
                child: UiStateView<List<Slot>>(
                  state: uiStateOf(slots),
                  onRetry: retrySlots,
                  ready: (context, list) => ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final s in list)
                        Builder(
                          builder: (context) {
                            final on =
                                s.selectable &&
                                !busy &&
                                s.window != order.window;
                            final picked = _picked == s.window;
                            return Material(
                              color: picked
                                  ? scheme.surfaceContainer
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                key: ValueKey('rs-slot-${s.window.start}'),
                                borderRadius: BorderRadius.circular(12),
                                onTap: on
                                    ? () => setState(() => _picked = s.window)
                                    : null,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  child: Text(
                                    windowText(s.window),
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          fontSize: picked ? 19 : 17,
                                          fontWeight: picked
                                              ? FontWeight.w700
                                              : FontWeight.w400,
                                          color: on
                                              ? null
                                              : scheme.outlineVariant,
                                        ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Text(
                  '• ${l10n.slotNote}\n• ${l10n.slotChangeNote}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                child: CommandButton(
                  key: const ValueKey('reschedule-submit'),
                  label: l10n.rescheduleSubmit,
                  onPressed: (_picked != null && !busy)
                      ? () => _submit(order)
                      : null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
