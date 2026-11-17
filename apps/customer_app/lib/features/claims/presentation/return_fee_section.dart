import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        padding: const EdgeInsets.only(top: 8, bottom: 4),
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

    return Card(
      key: const ValueKey('ret-fee'),
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.retFeeTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(l10n.retFeeBody, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(l10n.retFeeLabel, style: theme.textTheme.bodyMedium),
                const Spacer(),
                Text(
                  amountText,
                  key: const ValueKey('ret-fee-amount'),
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            if (fee.deadlineAt case final d?) ...[
              const SizedBox(height: 6),
              _Deadline(deadlineAt: d),
            ],
            const SizedBox(height: 8),
            Text(l10n.retFeeAfter, style: theme.textTheme.bodySmall),
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
            if (s.canPay && amount != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('ret-fee-pay'),
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
              formatSeoulDateTime(deadlineAt),
              // 남은 시간은 올림(분 단위) — 0분으로 보이지 않게.
              (left.inSeconds + 59) ~/ 60 ~/ 60,
              (left.inSeconds + 59) ~/ 60 % 60,
            ),
      key: const ValueKey('ret-fee-deadline'),
      style: theme.textTheme.labelLarge?.copyWith(
        color: over ? theme.colorScheme.error : theme.colorScheme.primary,
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
