import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:pmart_core/pmart_core.dart' show ProblemCode;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../checkout/presentation/checkout_controller.dart'
    show clockProvider;
import '../../payment/presentation/pg_widget_session.dart'
    show pgAmountMismatchCode;
import '../../payment/presentation/toss_payment_page.dart' show TossPgLauncher;
import '../domain/claims.dart';
import 'return_fee_controller.dart';

/// 반품 회수비 결제 구역(클레임 상세). 회수비를 결제해야 하는 반품에만 결제 버튼이 있다.
/// 결제했거나 기한이 지났으면 서버 상태(클레임 상태 문구)로만 보인다.
class ReturnFeeSection extends ConsumerWidget {
  const ReturnFeeSection({super.key, required this.claim});

  final ClaimView claim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final fee = claim.feePayment;
    if (fee == null) return const SizedBox.shrink();
    final s = ref.watch(returnFeeFlowProvider(claim.claimId));
    final ctl = ref.read(returnFeeFlowProvider(claim.claimId).notifier);
    final amount = fee.amount;
    final amountText = amount == null
        ? l10n.amountUnavailable
        : formatKrw(amount);

    // 결제 대기가 아니면 결과 한 줄만(결제함·기한 지남·돌려줌).
    if (!claim.awaitingFee) {
      final text = switch (fee.state) {
        ReturnFeeState.paid when fee.refunded => l10n.retFeeRefunded(
          amountText,
        ),
        ReturnFeeState.paid => l10n.retFeePaid(amountText),
        ReturnFeeState.unpaid => l10n.retFeeUnpaid,
        _ => null,
      };
      if (text == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Text(
          text,
          key: const ValueKey('ret-fee-result'),
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    final working = switch (s.phase) {
      ReturnFeePhase.preparing ||
      ReturnFeePhase.authenticating ||
      ReturnFeePhase.confirming => !s.stillChecking,
      _ => false,
    };
    final phaseText = switch (s.phase) {
      ReturnFeePhase.preparing => l10n.rdpPreparing,
      ReturnFeePhase.authenticating => l10n.payAuthenticating,
      ReturnFeePhase.confirming => l10n.payConfirming,
      _ => _failureText(l10n, s.failureCode),
    };

    // 초안 08 상세 C: 상태 카드 바로 아래 연분홍 카드(제목·설명·흰 금액 줄·기한). 결제 버튼은 아래 고정([ReturnFeePayBar]).
    final scheme = theme.colorScheme;
    return Container(
      key: const ValueKey('ret-fee'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.retFeeTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: scheme.onTertiaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.retFeeBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13.5,
              color: scheme.onTertiaryContainer,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Text(l10n.retFeeLabel, style: theme.textTheme.bodyMedium),
                const Spacer(),
                Text(
                  amountText,
                  key: const ValueKey('ret-fee-amount'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (fee.deadlineAt case final d?) ...[
            const SizedBox(height: 10),
            _Deadline(deadlineAt: d),
          ],
          if (working) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
          if (phaseText != null) ...[
            const SizedBox(height: 12),
            Text(
              phaseText,
              key: const ValueKey('ret-fee-phase'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
            ),
          ],
          if (s.phase == ReturnFeePhase.confirming) ...[
            const SizedBox(height: 8),
            Text(l10n.payDoNotRetry, textAlign: TextAlign.center),
          ],
          if (s.stillChecking) ...[
            const SizedBox(height: 8),
            Text(l10n.payStillChecking, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('ret-fee-check-again'),
              onPressed: ctl.checkAgain,
              child: Text(l10n.checkoutCheckAgain),
            ),
          ],
        ],
      ),
    );
  }
}

/// 초안 08 상세 C 아래 고정: 안내 한 줄 + [9,000원 결제하기](결제 흐름은 [ReturnFeeFlowController] 그대로).
class ReturnFeePayBar extends ConsumerWidget {
  const ReturnFeePayBar({super.key, required this.claim});

  final ClaimView claim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final fee = claim.feePayment;
    if (fee == null || !claim.awaitingFee) return const SizedBox.shrink();
    final s = ref.watch(returnFeeFlowProvider(claim.claimId));
    final ctl = ref.read(returnFeeFlowProvider(claim.claimId).notifier);
    final amount = fee.amount;
    final amountText = amount == null
        ? l10n.amountUnavailable
        : formatKrw(amount);
    return SafeArea(
      child: Container(
        color: theme.colorScheme.surface,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.retFeeAfter,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            // 결과를 모르는 동안·진행 중에는 결제 버튼 자체를 두지 않는다(다시 결제 막기 — CLAUDE.md).
            if (s.canPay && amount != null) ...[
              const SizedBox(height: 10),
              FilledButton(
                key: const ValueKey('ret-fee-pay'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: ctl.pay,
                child: Text(
                  s.phase == ReturnFeePhase.failed
                      ? l10n.rdpPayAgain
                      : l10n.rdpPay(amountText),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Deadline extends ConsumerWidget {
  const _Deadline({required this.deadlineAt});

  final DateTime deadlineAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final left = deadlineAt.difference(ref.watch(clockProvider)());
    final over = left <= Duration.zero;
    return Text(
      over
          ? l10n.retFeeDeadlineOver
          : l10n.retFeeDeadline(
              // 초안 08-C: "11.23(일) 18:05까지 결제".
              DateFormat(
                'M.d(E) HH:mm',
                'ko',
              ).format(toSeoulWallClock(deadlineAt)),
              // 남은 시간은 올림(분 단위) — 0분으로 보이지 않게.
              (left.inSeconds + 59) ~/ 60 ~/ 60,
              (left.inSeconds + 59) ~/ 60 % 60,
            ),
      key: const ValueKey('ret-fee-deadline'),
      style: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.tertiary,
      ),
    );
  }
}

String? _failureText(AppLocalizations l10n, String? code) => switch (code) {
  null => null,
  'USER_CANCELLED' => l10n.rdpCancelled,
  returnFeeDeadlinePassed => l10n.retFeeDeadlineOver,
  TossPgLauncher.configMissing => l10n.payConfigRequired,
  TossPgLauncher.resultMismatch => l10n.payResultMismatch,
  pgAmountMismatchCode => l10n.payAmountMismatch,
  // 409 — 기한이 지났거나 결제 대기가 아니다. 클레임을 다시 읽어 서버 상태를 보인다.
  ProblemCode.invalidState => l10n.retFeeNotWaiting,
  _ => l10n.rdpFailed,
};
