import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../domain/orders.dart';
import 'orders_providers.dart';

/// "받았어요"(고객 수령 확인) — 백엔드 요청 `clients/customer-app/2026-11-17-request-receipt-confirmation.md`,
/// execution 0.20.0 `POST /deliveries/{id}/receipt-confirmations`.
///
/// 도착 예정 + 20분이 지나면 서버가 알림함에 "상품을 받으셨나요?"(목적지 ORDER)를 보낸다 — 그 알림을 누르면 주문 상세로 와서 이 버튼을 쓴다.
/// 버튼은 배송이 픽업 뒤·전달 전(도착 예상 단계 TO_CUSTOMER·AT_CUSTOMER)일 때만. 가능 여부는 서버가 최종 판정한다.
sealed class ReceiptState {
  const ReceiptState();
}

final class ReceiptIdle extends ReceiptState {
  const ReceiptIdle();
}

final class ReceiptSending extends ReceiptState {
  const ReceiptSending();
}

/// 서버가 전달 완료로 바꿨다(APPLIED, 또는 다시 읽어 완료를 확인).
final class ReceiptDone extends ReceiptState {
  const ReceiptDone();
}

/// 접수됐거나(ACCEPTED) 결과를 모른다 — 완료로 보이지 않는다. "다시 확인"은 같은 키로만.
final class ReceiptPending extends ReceiptState {
  const ReceiptPending({required this.unknown});

  /// 결과 불명(응답 유실·5xx·UNKNOWN_RESULT). false 면 접수(ACCEPTED).
  final bool unknown;
}

/// 이미 처리된 배송(409 — 이미 완료·전달 실패 처리 중).
final class ReceiptAlreadyHandled extends ReceiptState {
  const ReceiptAlreadyHandled();
}

/// 서버가 거절했거나 보내지 못했다. 다시 누르면 새 요청.
final class ReceiptFailed extends ReceiptState {
  const ReceiptFailed();
}

final receiptConfirmationProvider = NotifierProvider.autoDispose
    .family<
      ReceiptController,
      ReceiptState,
      ({String orderId, String deliveryId})
    >(ReceiptController.new);

/// 버튼을 보일지 정하는 배송 단계. 배송 조회 화면의 [deliveryEtaProvider] 와 따로 둔다 —
/// 주문 상세가 그것을 붙잡으면 배송 조회 화면을 다시 열 때 새로 읽지 않는다.
final receiptStageProvider = FutureProvider.autoDispose
    .family<DeliveryStage, String>(
      (ref, deliveryId) async =>
          (await ref.watch(ordersRepositoryProvider).eta(deliveryId)).stage,
    );

class ReceiptController extends Notifier<ReceiptState> {
  ReceiptController(this.target);

  final ({String orderId, String deliveryId}) target;

  /// 이번 "받았어요"의 키. 결과를 모르는 동안 다시 확인할 때도 같은 키.
  IdempotencyKey? _key;

  @override
  ReceiptState build() => const ReceiptIdle();

  /// 고객이 확인 대화에서 "받았어요"를 골랐다.
  Future<void> confirm() async {
    if (state is ReceiptSending) return;
    _key = IdempotencyKey.generate();
    await _send();
  }

  /// 접수·결과 불명 뒤 다시 확인. 배송을 다시 읽어 완료면 끝, 결과 불명이면 같은 키로 다시 보낸다(같은 결과가 온다).
  Future<void> check() async {
    final current = state;
    if (current is! ReceiptPending) return;
    state = const ReceiptSending();
    try {
      final eta = await ref
          .read(ordersRepositoryProvider)
          .eta(target.deliveryId);
      if (!ref.mounted) return;
      if (eta.stage == DeliveryStage.done) return _finish(const ReceiptDone());
    } on PmartFailure {
      // 배송을 못 읽었다 — 아래로(결과 불명이면 같은 키로 묻는다).
    }
    if (!ref.mounted) return;
    if (current.unknown) return _send();
    state = current;
  }

  Future<void> _send() async {
    final key = _key;
    if (key == null) return;
    state = const ReceiptSending();
    try {
      final status = await ref
          .read(ordersRepositoryProvider)
          .confirmReceipt(target.deliveryId, key: key);
      if (!ref.mounted) return;
      _finish(switch (status) {
        CommandStatus.applied => const ReceiptDone(),
        CommandStatus.accepted => const ReceiptPending(unknown: false),
        CommandStatus.unknownResult => const ReceiptPending(unknown: true),
        CommandStatus.rejected => const ReceiptFailed(),
      });
    } on UnknownResultFailure {
      _finish(const ReceiptPending(unknown: true));
    } on ProblemFailure catch (f) {
      // 계약 409(Conflict)에는 정해진 code 가 없다 — 이미 끝났거나 전달 실패 처리 중.
      _finish(
        f.problem.status == 409
            ? const ReceiptAlreadyHandled()
            : const ReceiptFailed(),
      );
    } on PmartFailure {
      _finish(const ReceiptFailed());
    }
  }

  void _finish(ReceiptState next) {
    if (!ref.mounted) return;
    state = next;
    if (next is ReceiptFailed) _key = null;
    // 완료·접수·이미 처리됨이면 배송·주문을 다시 읽는다(버튼이 사라지고 상태가 바뀐다).
    if (next is ReceiptDone ||
        next is ReceiptAlreadyHandled ||
        next is ReceiptPending) {
      ref.invalidate(receiptStageProvider(target.deliveryId));
      ref.invalidate(deliveryEtaProvider(target.deliveryId));
      ref.invalidate(orderDetailProvider(target.orderId));
    }
  }
}

/// 배송 하나의 "받았어요" 버튼·결과. 도착 예상을 못 읽거나 픽업 전·완료 뒤면 버튼을 두지 않는다.
class ReceiptConfirmation extends ConsumerWidget {
  const ReceiptConfirmation({
    super.key,
    required this.orderId,
    required this.deliveryId,
  });

  final String orderId;
  final String deliveryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final target = (orderId: orderId, deliveryId: deliveryId);
    final provider = receiptConfirmationProvider(target);
    final state = ref.watch(provider);
    final stage = ref.watch(receiptStageProvider(deliveryId)).value;
    final canAsk =
        stage == DeliveryStage.toCustomer || stage == DeliveryStage.atCustomer;

    Widget message(String text, {bool error = false}) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        key: ValueKey('receipt-message-$deliveryId'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: error ? theme.colorScheme.error : null,
        ),
      ),
    );

    return switch (state) {
      ReceiptIdle() when !canAsk => const SizedBox.shrink(),
      ReceiptIdle() || ReceiptFailed() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state is ReceiptFailed) message(l10n.receiptFailed, error: true),
          if (canAsk)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton(
                key: ValueKey('receipt-$deliveryId'),
                onPressed: () => _ask(context, ref),
                child: Text(l10n.receiptButton),
              ),
            ),
        ],
      ),
      ReceiptSending() => const Padding(
        padding: EdgeInsets.only(top: 8),
        child: LinearProgressIndicator(),
      ),
      ReceiptDone() => message(l10n.receiptDone),
      ReceiptAlreadyHandled() => message(l10n.receiptAlreadyHandled),
      ReceiptPending(:final unknown) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          message(unknown ? l10n.receiptUnknown : l10n.receiptAccepted),
          TextButton(
            key: ValueKey('receipt-check-$deliveryId'),
            onPressed: () => ref.read(provider.notifier).check(),
            child: Text(l10n.receiptCheck),
          ),
        ],
      ),
    };
  }

  Future<void> _ask(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.receiptConfirmTitle),
        content: Text(l10n.receiptConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.receiptConfirmCancel),
          ),
          FilledButton(
            key: const ValueKey('receipt-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.receiptButton),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await ref
          .read(
            receiptConfirmationProvider((
              orderId: orderId,
              deliveryId: deliveryId,
            )).notifier,
          )
          .confirm();
    }
  }
}
