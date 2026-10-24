import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';

import 'package:customer_app/features/checkout/data/mock_checkout_repository.dart';
import 'package:customer_app/features/payment/data/payment_repository.dart';
import 'package:customer_app/features/payment/domain/payment.dart';
import 'package:customer_app/features/payment/presentation/payment_controller.dart';

import 'support/member_checkout.dart';

void main() {
  final now = DateTime.utc(2026, 10, 24, 3);
  late MockCheckoutRepository checkout;
  late MockPgLauncher pg;
  late MemoryKeyValueStore secure;
  late ProviderContainer c;
  late String draftId;

  setUp(() async {
    checkout = MockCheckoutRepository(latency: Duration.zero, now: () => now);
    pg = MockPgLauncher();
    secure = MemoryKeyValueStore();
    c = await memberContainer(
      checkout: checkout,
      now: () => now,
      secure: secure,
      extra: [
        pgLauncherProvider.overrideWithValue(pg),
        paymentPollPolicyProvider.overrideWithValue((
          interval: Duration.zero,
          attempts: 3,
        )),
      ],
    );
    draftId = await checkoutAccepted(c);
  });

  Future<PaymentFlowState> run() async {
    final p = paymentFlowProvider(draftId);
    c.listen(p, (_, _) {});
    await c.read(p.notifier).run();
    return c.read(p);
  }

  PaymentFlowController flow() => c.read(paymentFlowProvider(draftId).notifier);
  PaymentFlowState state() => c.read(paymentFlowProvider(draftId));

  test('서버가 orderId 와 확정 상태를 줄 때만 주문 완료다', () async {
    final s = await run();

    expect(s.phase, PaymentPhase.done);
    expect(s.orderId, isNotNull);
    expect(checkout.confirmedOrders.keys, [s.orderId]);
    expect(await c.read(pendingCheckoutsProvider.future), isEmpty);
  });

  test('결제창 인증 성공으로 돌아와도 승인 결과를 모르면 확인 중이고 다시 결제는 없다', () async {
    checkout.approval = MockApproval.unknown;

    final s = await run();

    expect(s.phase, PaymentPhase.confirming);
    expect(s.stillChecking, isTrue);
    expect(s.canRetryPayment, isFalse);
    expect(s.orderId, isNull);
    expect(await c.read(pendingCheckoutsProvider.future), [draftId]);

    checkout.resolveUnknownAsApproved();
    await flow().checkAgain();

    expect(state().phase, PaymentPhase.done);
    expect(pg.launches, 1, reason: '다시 확인은 결제창을 다시 열지 않는다');
  });

  test('승인 실패는 실패로 확인되고 고객이 다시 결제할 수 있다', () async {
    checkout.approval = MockApproval.decline;

    final s = await run();

    expect(s.phase, PaymentPhase.failed);
    expect(s.canRetryPayment, isTrue);

    await flow().retry();

    expect(state().phase, PaymentPhase.done);
    expect(pg.launches, 2);
  });

  test('결제창을 닫으면 서버에 인증 결과를 보내지 않는다', () async {
    pg.next = const PgCancelled();

    final s = await run();

    expect(s.phase, PaymentPhase.failed);
    expect(s.failureCode, 'USER_CANCELLED');
    expect(checkout.authKeys, isEmpty);
  });

  test('승인·주문 불일치는 복구 중이고 다시 결제는 없다', () async {
    checkout.approval = MockApproval.mismatch;

    final s = await run();

    expect(s.phase, PaymentPhase.recovering);
    expect(s.canRetryPayment, isFalse);
  });

  test('승인 뒤 주문이 취소되면 취소·환불 확인 중이다', () async {
    checkout.approval = MockApproval.approveThenCancel;

    final s = await run();

    expect(s.phase, PaymentPhase.refunding);
    expect(s.canRetryPayment, isFalse);
  });

  test('결제창 결과를 못 받아도 서버가 승인했으면 조회로 완료를 확인한다', () async {
    pg.next = const PgNoReturn();
    checkout.approvesWithoutReturn = true;

    final s = await run();

    expect(s.phase, PaymentPhase.done);
    expect(checkout.authKeys, isEmpty);
  });

  test('인증 결과 전달 응답을 잃으면 같은 키로 다시 보낸다', () async {
    checkout.loseNextAuthResponse = true;

    final s = await run();

    expect(s.phase, PaymentPhase.done);
    expect(checkout.authKeys, hasLength(2));
    expect(checkout.authKeys.toSet(), hasLength(1));
  });

  test('인증 결과를 넘긴 뒤 다시 들어오면 결제창을 열지 않고 결과만 조회한다', () async {
    checkout.approval = MockApproval.unknown;
    await run();
    expect(pg.launches, 1);

    // 앱을 다시 켠 것처럼 흐름 상태를 버린다(저장된 진행 명령은 남아 있다).
    c.invalidate(paymentFlowProvider(draftId));
    checkout.resolveUnknownAsApproved();
    final s = await run();

    expect(s.phase, PaymentPhase.done);
    expect(pg.launches, 1);
  });

  test('실패로 끝난 결제에 다시 들어오면 실패를 보이고 결제창을 자동으로 열지 않는다', () async {
    checkout.approval = MockApproval.decline;
    await run();
    c.invalidate(paymentFlowProvider(draftId));

    final s = await run();

    expect(s.phase, PaymentPhase.failed);
    expect(pg.launches, 1);
  });

  test('실서버 결제 경로는 BR-01 회신 전이라 계약 위반으로 막힌다', () async {
    await expectLater(
      const ApiPaymentRepository().entry('d'),
      throwsA(isA<ContractViolationFailure>()),
    );
  });
}
