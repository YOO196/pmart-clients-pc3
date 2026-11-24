import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:pmart_core/pmart_core.dart' show PmartFailure, ProblemCode;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/order_status.dart';
import '../../../shared/ui_state_of.dart';
import '../../checkout/domain/checkout.dart';
import '../../checkout/presentation/checkout_controller.dart';
import '../../catalog/presentation/widgets/product_tile_card.dart'
    show ProductImage;
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
                      fontSize: 18,
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
                          // 테마 글꼴을 잃지 않게 테마 글자 모양에서(그냥 TextStyle 이면 글꼴이 빠져 □ 로 그려졌다).
                          textStyle: theme.textTheme.bodyLarge?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                          ),
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

/// 종류 칩(초안 08): 취소 회색 / 반품 연보라 / 그 밖 회색.
class ClaimTypeChip extends StatelessWidget {
  const ClaimTypeChip({super.key, required this.type});

  final ClaimType type;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ret = type == ClaimType.returnItems;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ret ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        switch (type) {
          ClaimType.cancel => l10n.claimChipCancel,
          ClaimType.returnItems => l10n.claimChipReturn,
          ClaimType.exchange => l10n.claimChipExchange,
          ClaimType.unknown => l10n.claimTitle,
        },
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: ret ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 단계 막대(초안 08 상세 B) — 상태값으로만 칠한다(서버에 단계별 시각이 없어 시각은 넣지 않는다).
/// 철회·거절·반품 취소·회수 실패·모르는 상태·교환은 막대 없음(null).
({List<String> steps, int current})? claimSteps(
  AppLocalizations l10n,
  ClaimView c,
) {
  final s = c.state;
  switch (c.type) {
    case ClaimType.cancel:
      final i = switch (s) {
        ClaimState.opened => 0,
        ClaimState.underReview ||
        ClaimState.stopPending ||
        ClaimState.decided => 1,
        ClaimState.inProgress => 2,
        ClaimState.closed => 3,
        _ => null,
      };
      if (i == null) return null;
      return (
        steps: [
          l10n.claimStepOpened,
          l10n.claimStepReview,
          l10n.claimStepRefunding,
          l10n.claimStepDone,
        ],
        current: i,
      );
    case ClaimType.returnItems:
      // 고객 사유(회수비 있음): 접수 → 회수비 결제 → 회수·검수 → 환불 / 회사 잘못: 접수 → 확인 → 회수·검수 → 환불.
      final customer = c.feePayment != null;
      final i = switch (s) {
        ClaimState.opened => 0,
        ClaimState.feePending when customer => 1,
        ClaimState.underReview when !customer => 1,
        ClaimState.inProgress || ClaimState.decided => 2,
        ClaimState.closed => 3,
        _ => null,
      };
      if (i == null) return null;
      return (
        steps: [
          l10n.claimStepOpened,
          customer ? l10n.claimStepFee : l10n.claimStepReview,
          l10n.claimStepRecovery,
          l10n.claimStepRefund,
        ],
        current: i,
      );
    case ClaimType.exchange || ClaimType.unknown:
      return null;
  }
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.steps, required this.current});

  final List<String> steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = scheme.primary;
    final off = scheme.outlineVariant;
    return Column(
      key: const ValueKey('claim-steps'),
      children: [
        SizedBox(
          height: 18,
          child: Row(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 2,
                          color: i == 0
                              ? Colors.transparent
                              : (i <= current ? on : off),
                        ),
                      ),
                      Container(
                        key: ValueKey('claim-step-$i'),
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < current
                              ? on
                              : (i == current ? scheme.surface : off),
                          border: i == current
                              ? Border.all(color: on, width: 3.5)
                              : null,
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 2,
                          color: i == steps.length - 1
                              ? Colors.transparent
                              : (i < current ? on : off),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < steps.length; i++)
              Expanded(
                child: Text(
                  steps[i],
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    fontWeight: i == current
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: i == current
                        ? on
                        : (i < current
                              ? scheme.onSurfaceVariant
                              : scheme.outline),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 상세의 흰 카드(회색 바탕 위, 모서리 16).
class _ClaimBox extends StatelessWidget {
  const _ClaimBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
}

/// 작은 칩(승인·확인 중·거절·요청 수, 환불 상태).
Widget _chip(
  BuildContext context,
  String text, {
  required Color bg,
  required Color fg,
  bool bold = true,
  Key? key,
}) => Container(
  key: key,
  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
  child: Text(
    text,
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      fontSize: 12,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: fg,
    ),
  ),
);

/// SCR-CLAIM-DETAIL-001 — 초안 08 상세 B(상태 카드 + 단계 막대 · 상품 카드 · 환불 카드), C(회수비 대기 분홍 카드 +
/// 아래 고정 결제), D(끝남·일부 거절). 품목별 승인·거절, 환불은 PG 성공 전 "완료" 없음.
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

  Future<void> _withdraw(ClaimView c) async {
    setState(() => _withdrawing = true);
    final s = await ref.read(withdrawClaimProvider)(c);
    if (!mounted) return;
    setState(() {
      _withdrawing = false;
      _withdrawal = s;
    });
    if (s == RequestState.confirmed) {
      ref.invalidate(claimProvider(widget.claimId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
    final value = ref.watch(provider);
    final claim = value.value;
    // 아래 고정: 회수비 결제(초안 C) 또는 [요청 철회](접수 상태).
    final Widget? bottom = switch (claim) {
      final c? when c.awaitingFee => ReturnFeePayBar(claim: c),
      final c? when c.canWithdraw && _withdrawal == null => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: OutlinedButton(
            key: const ValueKey('withdraw'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              foregroundColor: scheme.primary,
              side: BorderSide(color: scheme.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _withdrawing ? null : () => _withdraw(c),
            child: Text(l10n.withdraw),
          ),
        ),
      ),
      _ => null,
    };
    return Scaffold(
      backgroundColor: scheme.surfaceContainer,
      appBar: AppBar(title: Text(l10n.claimTitle)),
      bottomNavigationBar: bottom,
      body: UiStateView<ClaimView>(
        state: uiStateOf(value),
        onRetry: () => ref.invalidate(provider),
        ready: (context, c) {
          final orderValue = ref.watch(orderDetailProvider(c.orderId));
          final order = orderValue.value;
          // 품목 이름·사진은 주문 상세에서 붙인다(ClaimLine 에 이름이 없다 — BR 요청). 읽는 중·실패를 구분한다.
          final orderLoading = order == null && orderValue.isLoading;
          final orderFailed = order == null && orderValue.hasError;
          final steps = claimSteps(l10n, c);
          final ended =
              c.state == ClaimState.withdrawn ||
              c.state == ClaimState.rejected ||
              c.state == ClaimState.cancelled;
          String? note;
          if (c.autoCancelled) {
            // 주문 취소가 확정되기 전에는 "취소되었어요"라고 하지 않는다
            note =
                c.state == ClaimState.closed ||
                    order?.status == OrderStatus.cancelled
                ? l10n.claimAutoCancelled
                : l10n.claimAutoCancelling;
          } else if (c.state == ClaimState.opened) {
            note = l10n.claimAcceptedNote;
          }
          final productRefunds = [
            for (final r in c.refunds)
              if (!r.returnFee) r,
          ];
          final feeRefunds = [
            for (final r in c.refunds)
              if (r.returnFee) r,
          ];
          return RefreshIndicator(
            onRefresh: () => ref.refresh(provider.future),
            child: ListView(
              padding: const EdgeInsets.only(top: 12, bottom: 16),
              children: [
                // ① 상태 카드
                _ClaimBox(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          ClaimTypeChip(type: c.type),
                          const SizedBox(width: 8),
                          if (c.openedAt case final t?)
                            Text(
                              l10n.claimOpenedOn(
                                DateFormat(
                                  'M.d(E)',
                                  'ko',
                                ).format(toSeoulWallClock(t)),
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          const Spacer(),
                          if (order?.orderNumber case final no?)
                            InkWell(
                              key: const ValueKey('claim-order-link'),
                              onTap: () => context.push(
                                '/orders/${Uri.encodeComponent(c.orderId)}',
                              ),
                              child: Text(
                                l10n.claimOrderNumber(no),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 13,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        claimStateText(l10n, c.state, type: c.type),
                        key: const ValueKey('claim-state'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: ended
                              ? scheme.onSurfaceVariant
                              : scheme.onSurface,
                        ),
                      ),
                      if (note != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            note,
                            key: c.autoCancelled
                                ? const ValueKey('claim-auto-cancelled')
                                : null,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 13.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (c.state == ClaimState.recoveryFailed)
                        Container(
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            l10n.clRecoveryFailed,
                            style: TextStyle(color: scheme.onTertiaryContainer),
                          ),
                        ),
                      if (steps != null) ...[
                        const SizedBox(height: 18),
                        _StepBar(steps: steps.steps, current: steps.current),
                      ],
                    ],
                  ),
                ),
                // 반품 회수비(고객 사유 반품). 대기면 분홍 카드, 아니면 결과 한 줄.
                ReturnFeeSection(claim: c),
                // ② 상품 카드
                if (c.lines.isNotEmpty)
                  _ClaimBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(
                              c.type == ClaimType.returnItems
                                  ? l10n.claimSectionReturnLines
                                  : l10n.claimSectionCancelLines,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              l10n.claimLineCount(c.lines.length),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        for (final (i, l) in c.lines.indexed) ...[
                          if (i > 0)
                            Divider(height: 1, color: scheme.outlineVariant),
                          _ClaimLineRow(
                            line: l,
                            orderLine: order?.lines
                                .where((o) => o.orderLineId == l.orderLineId)
                                .firstOrNull,
                            orderLoading: orderLoading,
                            onRetryOrder: orderFailed
                                ? () => ref.invalidate(
                                    orderDetailProvider(c.orderId),
                                  )
                                : null,
                          ),
                        ],
                      ],
                    ),
                  ),
                // ③ 환불 카드
                if (c.refunds.isNotEmpty)
                  _ClaimBox(
                    child: Column(
                      key: const ValueKey('refund'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.claimSectionRefund,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        for (final r in productRefunds) _RefundBlock(refund: r),
                        for (final r in feeRefunds) _RefundBlock(refund: r),
                      ],
                    ),
                  ),
                if (_withdrawal == RequestState.pending ||
                    _withdrawal == RequestState.unknown)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      l10n.withdrawChecking,
                      key: const ValueKey('withdraw-checking'),
                    ),
                  ),
                if (_withdrawal == RequestState.rejected)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(l10n.withdrawRejected),
                  ),
                Center(
                  child: TextButton(
                    key: const ValueKey('claim-help'),
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onSurfaceVariant,
                    ),
                    onPressed: () => context.push(
                      '/orders/${Uri.encodeComponent(c.orderId)}/help',
                    ),
                    child: Text(l10n.claimHelp),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 상품 한 줄: 사진 52 · 이름 · 판정 칩(승인 N개 연보라 / 확인 중 회색 / 거절 회색) + "요청 N개" · 품목 환불액,
/// 거절이면 서버 거절 사유를 분홍 띠로. 이름·사진은 클레임 품목 사본(claim 0.14.0, BR-92)을 먼저, 없으면(옛 클레임)
/// 주문 상세 품목(orderLineId)에서. 고객에게 SKU 를 보이지 않는다(사용자 2026-11-24): 주문을 읽는 중이면 회색 막대,
/// 이름을 못 찾으면 안내 문구(주문 조회 실패면 옆에 "다시 시도").
class _ClaimLineRow extends StatelessWidget {
  const _ClaimLineRow({
    required this.line,
    this.orderLine,
    this.orderLoading = false,
    this.onRetryOrder,
  });

  final ClaimLineView line;
  final OrderLineView? orderLine;

  /// 이름을 붙일 주문 상세를 아직 읽는 중.
  final bool orderLoading;

  /// 주문 상세를 못 읽었을 때 다시 읽기. null 이면 버튼 없음.
  final VoidCallback? onRetryOrder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l = line;
    return Padding(
      key: ValueKey('claim-line-${l.orderLineId}'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 사진·이름을 누르면 상품 상세(사용자 2026-11-24, 주문 상세 품목과 같게). 상품 ID 는 주문 상세 품목에서 —
          // 주문을 아직 못 읽었거나 상품 ID 가 없는 옛 주문 줄이면 누를 수 없다.
          InkWell(
            key: ValueKey('claim-line-open-${l.orderLineId}'),
            borderRadius: BorderRadius.circular(8),
            onTap: switch (orderLine?.productId) {
              final id? => () => context.push(
                '/products/${Uri.encodeComponent(id)}',
              ),
              null => null,
            },
            child: Row(
              children: [
                ProductImage(
                  url: l.imageUrl ?? orderLine?.imageUrl,
                  size: 52,
                  radius: 8,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      switch ((l.productName, orderLine)) {
                        (final name?, _) => Text(
                          [name, ?l.optionLabel].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 14.5,
                          ),
                        ),
                        (_, final o?) when o.productName != null => Text(
                          o.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 14.5,
                          ),
                        ),
                        _ when orderLoading => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 2),
                          child: PmartBone(
                            key: ValueKey('claim-line-name-loading'),
                            width: 140,
                            height: 15,
                          ),
                        ),
                        _ => Row(
                          children: [
                            Flexible(
                              child: Text(
                                l10n.claimLineNameUnavailable,
                                key: const ValueKey(
                                  'claim-line-name-unavailable',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 14,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (onRetryOrder case final retry?)
                              TextButton(
                                key: const ValueKey('claim-line-name-retry'),
                                onPressed: retry,
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                ),
                                child: Text(l10n.claimLineNameRetry),
                              ),
                          ],
                        ),
                      },
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        children: [
                          switch (l.decision) {
                            LineDecision.approved => _chip(
                              context,
                              l10n.claimLineApproved(l.approvedQty ?? 0),
                              bg: scheme.primaryContainer,
                              fg: scheme.primary,
                            ),
                            LineDecision.pending => _chip(
                              context,
                              l10n.decisionPending,
                              bg: scheme.surfaceContainerHigh,
                              fg: scheme.onSurfaceVariant,
                            ),
                            LineDecision.rejected => _chip(
                              context,
                              l10n.decisionRejected,
                              bg: scheme.surfaceContainerHigh,
                              fg: scheme.onSurfaceVariant,
                            ),
                          },
                          if (l.requestedQty case final q?)
                            Text(
                              l10n.claimRequested(q),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 12.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (l.refundAmount case final a?)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      formatKrw(a),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (l.decision == LineDecision.rejected && l.rejectReason != null)
            Container(
              margin: const EdgeInsets.only(top: 8, left: 64),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                l.rejectReason!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 환불 한 건: 상태 칩(진행 중 연보라 / 완료 회색 / 실패 분홍 / 확인 중 회색) + 큰 금액(서버 값), 완료면 완료 시각.
/// 회수비를 돌려받는 환불은 "반품 회수비 환불" 줄로 따로.
class _RefundBlock extends StatelessWidget {
  const _RefundBlock({required this.refund});

  final RefundView refund;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = refund;
    final amount = switch (r.amount) {
      final int a => formatKrw(a),
      null => l10n.amountUnavailable,
    };
    if (r.returnFee) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            Text(
              r.done ? l10n.refundFeeDone : l10n.refundFeeInProgress,
              style: theme.textTheme.bodyMedium,
            ),
            const Spacer(),
            Text(amount, style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }
    final (String chip, Color bg, Color fg) = switch (r) {
      _ when r.done => (
        l10n.claimRefundChipDone,
        scheme.surfaceContainerHigh,
        scheme.onSurfaceVariant,
      ),
      RefundView(state: RefundState.failed) => (
        l10n.claimRefundChipFailed,
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      RefundView(state: RefundState.unknown) => (
        l10n.claimRefundChipChecking,
        scheme.surfaceContainerHigh,
        scheme.onSurfaceVariant,
      ),
      _ => (
        l10n.claimRefundChipInProgress,
        scheme.primaryContainer,
        scheme.primary,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _chip(context, chip, bg: bg, fg: fg),
              const Spacer(),
              Text(
                amount,
                key: const ValueKey('refund-amount'),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: r.done ? scheme.onSurface : scheme.primary,
                ),
              ),
            ],
          ),
          // 초안 08-B(사용자 2026-11-23 "응 넣어줘"): 원결제를 PG 에서 취소해 돌려준다(cs-scripts/03, Commerce 환불).
          // "반영까지 며칠" 같은 기간 안내는 정해지지 않아 넣지 않는다.
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.claimRefundToOriginal,
              key: const ValueKey('refund-to-original'),
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (r.done && r.completedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Text(
                    l10n.claimRefundCompletedAt,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    DateFormat(
                      'M.d(E) HH:mm',
                      'ko',
                    ).format(toSeoulWallClock(r.completedAt!)),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
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
                    fontSize: 12,
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
