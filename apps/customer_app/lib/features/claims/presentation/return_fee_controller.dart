import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../checkout/presentation/checkout_controller.dart';
import '../../payment/data/payment_repository.dart' show tossUserCancelCode;
import '../../payment/domain/payment.dart';
import '../../payment/presentation/payment_controller.dart';
import '../../payment/presentation/toss_payment_page.dart' show TossPgLauncher;
import '../domain/claims.dart';
import 'claims_controller.dart';

/// 반품 회수비 결제 — 백엔드 요청 `clients/all/2026-11-17-request-return-recovery.md` §3(claim 0.2.0).
///
/// 고객센터가 고객 사유 반품을 접수하면 클레임이 FEE_PENDING 이 되고 `feePayment`(9,000원, 기한 24시간)가 생긴다.
/// 토스 결제위젯을 `orderId = feePayment.paymentAttemptId` 로 열고, 승인 요청은 기존 `POST /payment-confirmations`.
/// 결제창 복귀·승인 요청 접수는 완료가 아니다 — 클레임의 `feePayment.state` 가 PAID 가 될 때만 "결제됐어요".
/// 실패한 시도 뒤 다시 결제는 `POST /claims/{id}/fee-payment-attempts` 로 새 시도를 받는다.

/// 결제 대기 클레임을 다시 읽는 간격·횟수(결제 시도 준비 중·승인 결과 확인). 화면이 열려 있는 동안만.
final returnFeePollPolicyProvider =
    Provider<({Duration interval, int attempts})>(
      (_) => (interval: const Duration(seconds: 2), attempts: 15),
    );

/// 승인 요청을 넘긴 회수비 결제의 저장 종류. 앱을 다시 켜도 결제창을 다시 열지 않고 결과만 확인한다.
const returnFeeAuthKind = 'return-fee-auth';

/// 기한이 지나 결제창을 열지 않았다(앱 판단 — 상태는 서버가 바꾼다).
const returnFeeDeadlinePassed = 'DEADLINE_PASSED';

/// 서버가 주문명을 비워 줄 때 결제창에 쓰는 이름.
const returnFeeDefaultOrderName = '반품 회수비';

enum ReturnFeePhase {
  /// 결제할 수 있음
  ready,

  /// 결제 시도 준비 중(paymentAttemptId 대기)
  preparing,

  /// 결제창
  authenticating,

  /// 승인 결과 확인 중 — 다시 결제 없음
  confirming,

  /// 이번 결제 시도 실패 — 다시 결제할 수 있음(기한 안)
  failed,

  /// 결제 대기가 끝났다(결제됨·기한 지남·취소) — 클레임 화면이 서버 상태로 보인다
  settled,
}

@immutable
class ReturnFeeFlowState {
  const ReturnFeeFlowState({
    required this.phase,
    this.failureCode,
    this.stillChecking = false,
  });

  final ReturnFeePhase phase;
  final String? failureCode;

  /// 여러 번 확인했지만 결론이 없다. "다시 확인"만 보인다.
  final bool stillChecking;

  bool get canPay =>
      phase == ReturnFeePhase.ready || phase == ReturnFeePhase.failed;
}

final returnFeeFlowProvider = NotifierProvider.autoDispose
    .family<ReturnFeeFlowController, ReturnFeeFlowState, String>(
      ReturnFeeFlowController.new,
    );

class ReturnFeeFlowController extends Notifier<ReturnFeeFlowState> {
  ReturnFeeFlowController(this.claimId);

  final String claimId;
  bool _running = false;

  @override
  ReturnFeeFlowState build() {
    // 승인 요청을 이미 넘긴 건이면(앱을 다시 켬) 결제창을 다시 열지 않고 결과만 확인한다.
    Future.microtask(_resume);
    return const ReturnFeeFlowState(phase: ReturnFeePhase.ready);
  }

  PendingCommandStore get _store => ref.read(pendingCommandStoreProvider);
  String get _pendingId => 'return-fee-$claimId';

  void _set(ReturnFeeFlowState s) {
    if (ref.mounted) state = s;
  }

  Future<void> _guarded(Future<void> Function() body) async {
    if (_running) return;
    _running = true;
    try {
      await body();
    } finally {
      _running = false;
    }
  }

  Future<ClaimView> _read() => ref.read(claimsRepositoryProvider).get(claimId);

  Future<void> _forget() => _store.remove(_pendingId);

  Future<void> _resume() => _guarded(() async {
    if (!ref.mounted) return;
    if (!(await _store.list()).any((c) => c.requestId == _pendingId)) return;
    _set(const ReturnFeeFlowState(phase: ReturnFeePhase.confirming));
    await _confirm();
  });

  /// "다시 확인" — 서버 상태만 다시 읽는다(결제창을 다시 열지 않는다).
  Future<void> checkAgain() => _guarded(() async {
    if (state.phase == ReturnFeePhase.confirming) return _confirm(attempts: 1);
    if (state.phase == ReturnFeePhase.preparing) {
      try {
        final c = await _read();
        if (!c.awaitingFee) return _settled();
        if (c.feePayment?.paymentAttemptId != null) {
          return _set(const ReturnFeeFlowState(phase: ReturnFeePhase.ready));
        }
      } on PmartFailure {
        // 그대로 준비 중
      }
      _set(
        const ReturnFeeFlowState(
          phase: ReturnFeePhase.preparing,
          stillChecking: true,
        ),
      );
    }
  });

  /// "결제하기". 실패한 시도 뒤면 새 결제 시도를 받고 결제창을 연다.
  Future<void> pay() => _guarded(() async {
    if (!state.canPay) return;
    try {
      var c = await _read();
      if (!c.awaitingFee) return _settled();
      if (state.phase == ReturnFeePhase.failed) {
        _set(const ReturnFeeFlowState(phase: ReturnFeePhase.preparing));
        c = await ref
            .read(claimsRepositoryProvider)
            .retryFeePayment(claimId, key: IdempotencyKey.generate());
        if (!c.awaitingFee) return _settled();
      }
      final ready = await _waitAttempt(c);
      if (ready == null) return;
      await _open(ready);
    } on PmartFailure catch (f) {
      // 409(결제 대기 아님·기한 지남)·결과 불명·조회 실패 — 결제창을 열지 않고 서버 상태를 다시 읽게 한다.
      _set(
        ReturnFeeFlowState(
          phase: ReturnFeePhase.failed,
          failureCode: f is ProblemFailure ? f.problem.code : 'PAY_FAILED',
        ),
      );
      ref.invalidate(claimProvider(claimId));
    }
  });

  /// 결제 시도(paymentAttemptId)가 생길 때까지 클레임을 다시 읽는다.
  Future<ClaimView?> _waitAttempt(ClaimView c) async {
    if (c.feePayment?.paymentAttemptId != null) return c;
    _set(const ReturnFeeFlowState(phase: ReturnFeePhase.preparing));
    final policy = ref.read(returnFeePollPolicyProvider);
    for (var i = 0; i < policy.attempts; i++) {
      await Future<void>.delayed(policy.interval);
      if (!ref.mounted) return null;
      final now = await _read();
      if (!now.awaitingFee) {
        _settled();
        return null;
      }
      if (now.feePayment?.paymentAttemptId != null) return now;
    }
    _set(
      const ReturnFeeFlowState(
        phase: ReturnFeePhase.preparing,
        stillChecking: true,
      ),
    );
    return null;
  }

  Future<void> _open(ClaimView c) async {
    final fee = c.feePayment!;
    final deadline = fee.deadlineAt;
    final amount = fee.amount;
    // 기한이 지났으면 결제창을 열지 않는다(그 뒤 승인은 서버가 취소한다).
    if (deadline != null && !ref.read(clockProvider)().isBefore(deadline)) {
      return _set(
        const ReturnFeeFlowState(
          phase: ReturnFeePhase.ready,
          failureCode: returnFeeDeadlinePassed,
        ),
      );
    }
    if (amount == null) {
      // 금액을 모르면 결제창을 열지 않는다(앱이 금액을 정하지 않는다).
      return _set(
        const ReturnFeeFlowState(
          phase: ReturnFeePhase.failed,
          failureCode: 'AMOUNT_MISSING',
        ),
      );
    }
    final config = await ref.read(paymentWidgetConfigProvider.future);
    if (!ref.mounted) return;
    if (config == null) {
      return _set(
        const ReturnFeeFlowState(
          phase: ReturnFeePhase.failed,
          failureCode: TossPgLauncher.configMissing,
        ),
      );
    }
    final entry = PaymentEntry(
      clientKey: config.clientKey,
      pgOrderId: fee.paymentAttemptId!,
      paymentAttemptId: fee.paymentAttemptId,
      amount: amount,
      orderName: fee.orderName ?? returnFeeDefaultOrderName,
      expiresAt: deadline,
    );
    _set(const ReturnFeeFlowState(phase: ReturnFeePhase.authenticating));
    final ret = await ref.read(pgLauncherProvider).launch(entry);
    if (!ref.mounted) return;
    switch (ret) {
      case PgAuthenticated():
        _set(const ReturnFeeFlowState(phase: ReturnFeePhase.confirming));
        // 넘긴 뒤에는 결제창을 다시 열지 않는다(앱이 꺼져도 결과 조회로 복구).
        await _store.add(
          PendingCommand(
            requestId: _pendingId,
            kind: returnFeeAuthKind,
            targetId: claimId,
            startedAt: DateTime.now().toUtc(),
          ),
        );
        final AuthSubmitResult result;
        try {
          // 응답을 놓쳐도 다시 보내지 않는다. 결과는 클레임 조회로 본다.
          result = await ref
              .read(paymentRepositoryProvider)
              .submitAuth(ret, key: IdempotencyKey.generate());
        } on PmartFailure {
          return _confirm();
        }
        if (result == AuthSubmitResult.rejected) {
          await _forget();
          return _set(
            const ReturnFeeFlowState(
              phase: ReturnFeePhase.failed,
              failureCode: 'PAYMENT_FAILED',
            ),
          );
        }
        await _confirm();
      case PgCancelled():
        await _reportFailure(entry, tossUserCancelCode);
        _set(
          const ReturnFeeFlowState(
            phase: ReturnFeePhase.failed,
            failureCode: 'USER_CANCELLED',
          ),
        );
      case PgFailed(:final code):
        await _reportFailure(entry, code);
        _set(
          ReturnFeeFlowState(phase: ReturnFeePhase.failed, failureCode: code),
        );
      case PgNoReturn():
        _set(const ReturnFeeFlowState(phase: ReturnFeePhase.confirming));
        await _confirm();
    }
  }

  Future<void> _reportFailure(PaymentEntry entry, String code) async {
    try {
      await ref
          .read(paymentRepositoryProvider)
          .reportAuthFailure(entry, code, key: IdempotencyKey.generate());
    } on PmartFailure {
      // 알리지 못해도 결제 시도가 만료로 끝난다. 다시 결제는 새 시도를 받는다.
    }
  }

  /// 클레임이 회수비 결제 대기에서 벗어날 때까지 본다. 그대로면 "확인 중"(다시 결제 없음).
  Future<void> _confirm({int? attempts}) async {
    final policy = ref.read(returnFeePollPolicyProvider);
    final n = attempts ?? policy.attempts;
    for (var i = 0; i < n; i++) {
      if (i > 0) await Future<void>.delayed(policy.interval);
      if (!ref.mounted) return;
      try {
        final c = await _read();
        if (!ref.mounted) return;
        if (!c.awaitingFee) {
          await _forget();
          return _settled();
        }
      } on PmartFailure {
        // 조회 실패는 계속 "확인 중"이다.
      }
    }
    _set(
      const ReturnFeeFlowState(
        phase: ReturnFeePhase.confirming,
        stillChecking: true,
      ),
    );
  }

  void _settled() {
    _set(const ReturnFeeFlowState(phase: ReturnFeePhase.settled));
    if (ref.mounted) ref.invalidate(claimProvider(claimId));
  }
}
