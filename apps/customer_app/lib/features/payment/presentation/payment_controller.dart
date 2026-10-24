import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/order_status.dart';
import '../../../shared/providers.dart';
import '../../cart/presentation/cart_controller.dart';
import '../../checkout/data/checkout_repository.dart';
import '../../checkout/domain/checkout.dart';
import '../../checkout/presentation/checkout_controller.dart';
import '../data/payment_repository.dart';
import '../domain/payment.dart';

final paymentRepositoryProvider = Provider<PaymentRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    // 목은 초안과 같은 저장소가 결제도 흉내 낸다(BR-01).
    PmartEnv.mock => ref.watch(checkoutRepositoryProvider) as PaymentRepository,
    PmartEnv.local => const ApiPaymentRepository(),
  },
);

final pgLauncherProvider = Provider<PgLauncher>((_) => MockPgLauncher());

final pendingCommandStoreProvider = Provider<PendingCommandStore>(
  (ref) => PendingCommandStore(ref.watch(secureStoreProvider)),
);

/// 결제 결과 확인 조회 간격·횟수. 화면이 열려 있는 동안만 짧게 본다.
final paymentPollPolicyProvider = Provider<({Duration interval, int attempts})>(
  (_) => (interval: const Duration(seconds: 2), attempts: 10),
);

/// 진행 중 결제의 저장 종류. 인증 결과를 넘긴 뒤에는 결제창을 다시 열지 않는다.
abstract final class CheckoutCommandKind {
  static const started = 'checkout';
  static const authSubmitted = 'checkout-auth';
}

/// 앱을 다시 켰을 때 확인할 결제(초안 ID). 서버 조회로만 결론을 낸다.
final pendingCheckoutsProvider = FutureProvider<List<String>>((ref) async {
  final pending = await ref.watch(pendingCommandStoreProvider).list();
  return [
    for (final p in pending)
      if (p.kind.startsWith(CheckoutCommandKind.started)) p.targetId,
  ];
});

final paymentFlowProvider = NotifierProvider.autoDispose
    .family<PaymentFlowController, PaymentFlowState, String>(
      PaymentFlowController.new,
    );

/// 결제 진행. 화면 문구 단계: 준비 → 인증 → 결과 확인 → 완료/실패/복구/환불.
///
/// 결제창 복귀·인증 성공·인증 결과 접수 어느 것도 완료가 아니다. 초안 조회가 orderId 와
/// 확정 상태를 줄 때만 [PaymentPhase.done].
class PaymentFlowController extends Notifier<PaymentFlowState> {
  PaymentFlowController(this.draftId);

  final String draftId;
  bool _running = false;

  @override
  PaymentFlowState build() =>
      const PaymentFlowState(phase: PaymentPhase.preparing);

  CheckoutRepository get _drafts => ref.read(checkoutRepositoryProvider);
  PaymentRepository get _payments => ref.read(paymentRepositoryProvider);
  PendingCommandStore get _store => ref.read(pendingCommandStoreProvider);

  void _set(PaymentFlowState s) {
    if (ref.mounted) state = s;
  }

  Future<void> _remember(String kind) async {
    await _store.add(
      PendingCommand(
        requestId: 'checkout-$draftId',
        kind: kind,
        targetId: draftId,
        startedAt: DateTime.now().toUtc(),
      ),
    );
    if (ref.mounted) ref.invalidate(pendingCheckoutsProvider);
  }

  /// 결과를 서버 상태에서 읽는다. 아직 진행 중이면 null.
  PaymentFlowState? _evaluate(OrderDraft d) {
    final payment = d.resources?.payment;
    if (d.orderId != null && d.status.isConfirmedOrLater) {
      return PaymentFlowState(phase: PaymentPhase.done, orderId: d.orderId);
    }
    if ((d.status == OrderStatus.cancelled ||
            d.status == OrderStatus.expired) &&
        payment == PaymentProgress.approved) {
      return const PaymentFlowState(phase: PaymentPhase.refunding);
    }
    if (payment == PaymentProgress.mismatch) {
      return const PaymentFlowState(phase: PaymentPhase.recovering);
    }
    if (d.status == OrderStatus.paymentUnknown ||
        payment == PaymentProgress.unknown) {
      return const PaymentFlowState(phase: PaymentPhase.confirming);
    }
    if (payment == PaymentProgress.failed) {
      return PaymentFlowState(
        phase: PaymentPhase.failed,
        failureCode: 'PAYMENT_FAILED',
        entry: state.entry,
      );
    }
    return null;
  }

  bool _terminal(PaymentFlowState s) => switch (s.phase) {
    PaymentPhase.done ||
    PaymentPhase.refunding ||
    PaymentPhase.recovering => true,
    _ => false,
  };

  /// 화면 진입·재진입. 이미 인증 결과를 넘긴 결제면 결제창을 다시 열지 않고 결과만 확인한다.
  Future<void> run() async {
    if (_running) return;
    _running = true;
    try {
      final pending = (await _store.list())
          .where((p) => p.targetId == draftId)
          .firstOrNull;
      if (pending?.kind == CheckoutCommandKind.authSubmitted) {
        _set(const PaymentFlowState(phase: PaymentPhase.confirming));
        return await _confirm();
      }
      final current = await _drafts.getDraft(draftId);
      final evaluated = _evaluate(current);
      if (evaluated != null) {
        // 실패였으면 실패를 보이고 고객이 "다시 결제"를 고르게 한다(자동으로 다시 열지 않는다).
        _set(evaluated);
        if (evaluated.phase == PaymentPhase.confirming) return await _confirm();
        if (_terminal(evaluated)) return await _finish(evaluated);
        return;
      }
      await _remember(CheckoutCommandKind.started);
      await _pay();
    } on PmartFailure {
      // 조회 실패는 결과가 아니다. 확인 중으로 두고 "다시 확인"을 보인다.
      _set(
        PaymentFlowState(
          phase: PaymentPhase.confirming,
          stillChecking: true,
          entry: state.entry,
        ),
      );
    } finally {
      _running = false;
    }
  }

  /// 실패 확인 뒤에만 "다시 결제". 결과 불명·복구·환불 중에는 아무것도 하지 않는다.
  Future<void> retry() async {
    if (!state.canRetryPayment || _running) return;
    _running = true;
    try {
      await _pay();
    } on PmartFailure {
      _set(
        const PaymentFlowState(
          phase: PaymentPhase.confirming,
          stillChecking: true,
        ),
      );
    } finally {
      _running = false;
    }
  }

  /// "다시 확인". 서버 상태만 다시 조회한다.
  Future<void> checkAgain() async {
    if (_running) return;
    _running = true;
    try {
      await _confirm(attempts: 1);
    } finally {
      _running = false;
    }
  }

  Future<void> _pay() async {
    _set(PaymentFlowState(phase: PaymentPhase.preparing, entry: state.entry));
    final entry = state.entry ?? await _waitEntry();
    if (entry == null) {
      _set(
        const PaymentFlowState(
          phase: PaymentPhase.preparing,
          stillChecking: true,
        ),
      );
      return;
    }
    _set(PaymentFlowState(phase: PaymentPhase.authenticating, entry: entry));
    final ret = await ref.read(pgLauncherProvider).launch(entry);
    if (!ref.mounted) return;
    switch (ret) {
      case PgAuthenticated():
        _set(PaymentFlowState(phase: PaymentPhase.confirming, entry: entry));
        await _submit(ret);
        await _confirm();
      case PgCancelled():
        _set(
          PaymentFlowState(
            phase: PaymentPhase.failed,
            failureCode: 'USER_CANCELLED',
            entry: entry,
          ),
        );
      case PgFailed(:final code):
        _set(
          PaymentFlowState(
            phase: PaymentPhase.failed,
            failureCode: code,
            entry: entry,
          ),
        );
      case PgNoReturn():
        // 결과를 못 받았다. 서버(웹훅 등)가 처리했을 수 있으니 조회로만 판단한다.
        _set(PaymentFlowState(phase: PaymentPhase.confirming, entry: entry));
        await _confirm();
    }
  }

  Future<PaymentEntry?> _waitEntry() async {
    final policy = ref.read(paymentPollPolicyProvider);
    for (var i = 0; i < policy.attempts; i++) {
      if (i > 0) await Future<void>.delayed(policy.interval);
      if (!ref.mounted) return null;
      final entry = await _payments.entry(draftId);
      if (entry != null) return entry;
    }
    return null;
  }

  Future<void> _submit(PgAuthenticated auth) async {
    final key = IdempotencyKey.generate();
    // 넘긴 뒤에는 결제창을 다시 열지 않는다(앱이 꺼져도 결과 조회로 복구).
    await _remember(CheckoutCommandKind.authSubmitted);
    for (var i = 0; i < 3; i++) {
      try {
        final r = await _payments.submitAuth(auth, key: key);
        if (r != AuthSubmitResult.unknown) return;
      } on UnknownResultFailure {
        // 같은 키로 다시 보낸다.
      }
    }
  }

  Future<void> _confirm({int? attempts}) async {
    final policy = ref.read(paymentPollPolicyProvider);
    final n = attempts ?? policy.attempts;
    for (var i = 0; i < n; i++) {
      if (i > 0) await Future<void>.delayed(policy.interval);
      if (!ref.mounted) return;
      try {
        final d = await _drafts.getDraft(draftId);
        if (!ref.mounted) return;
        final evaluated = _evaluate(d);
        if (evaluated != null && evaluated.phase != PaymentPhase.confirming) {
          _set(evaluated);
          if (_terminal(evaluated)) await _finish(evaluated);
          return;
        }
      } on PmartFailure {
        // 조회 실패는 계속 "확인 중"이다.
      }
    }
    _set(
      PaymentFlowState(
        phase: PaymentPhase.confirming,
        stillChecking: true,
        entry: state.entry,
      ),
    );
  }

  Future<void> _finish(PaymentFlowState s) async {
    await _store.remove('checkout-$draftId');
    ref.invalidate(pendingCheckoutsProvider);
    if (s.phase == PaymentPhase.done) {
      ref.read(checkoutSetupProvider.notifier).finish();
      ref.invalidate(draftControllerProvider);
      // 주문된 품목은 서버가 장바구니에서 뺀다. 최신 장바구니를 다시 받는다.
      ref.invalidate(cartControllerProvider);
    }
  }
}
