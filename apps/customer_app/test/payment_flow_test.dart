import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';

import 'package:customer_app/features/checkout/data/mock_checkout_repository.dart';
import 'package:customer_app/features/checkout/domain/checkout.dart';
import 'package:customer_app/features/checkout/presentation/checkout_controller.dart';
import 'package:customer_app/features/payment/data/payment_repository.dart';
import 'package:customer_app/features/payment/domain/payment.dart';
import 'package:customer_app/features/payment/presentation/payment_controller.dart';
import 'package:customer_app/features/payment/presentation/toss_payment_page.dart';
import 'package:tosspayments_widget_sdk_flutter/model/tosspayments_result.dart';

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

  test('승인 실패는 실패로 확인되고 주문서에서 새 키로 다시 결제 진입한다', () async {
    checkout.approval = MockApproval.decline;

    final s = await run();

    expect(s.phase, PaymentPhase.failed);
    expect(s.canRetryPayment, isTrue);
    expect(await c.read(pendingCheckoutsProvider.future), isEmpty);

    // 주문서로 돌아오면 초안은 결제 진입 전(DRAFT·REVIEW)이라 다시 결제할 수 있다.
    final draft = c.read(draftControllerProvider.notifier);
    await draft.refresh();
    expect(c.read(draftControllerProvider).requireValue!.canPay, isTrue);
    expect(await draft.pay(), isA<CheckoutAccepted>());
    expect(checkout.checkoutKeys.toSet(), hasLength(2), reason: '새 결제 진입은 새 키');

    c.invalidate(paymentFlowProvider(draftId));
    final again = await run();

    expect(again.phase, PaymentPhase.done);
    expect(pg.launches, 2);
  });

  test('결제창을 닫으면 승인 요청 없이 취소를 알리고 실패로 둔다', () async {
    pg.next = const PgCancelled();

    final s = await run();

    expect(s.phase, PaymentPhase.failed);
    expect(s.failureCode, 'USER_CANCELLED');
    expect(checkout.authKeys, isEmpty);
    expect(checkout.authFailures.single.$2, tossUserCancelCode);
  });

  test('재고 확보에 실패하면 결제창을 열지 않고 사유를 보인다', () async {
    c.invalidate(paymentFlowProvider(draftId));
    // 새 결제 진입이 재고 부족으로 끝난 초안을 만든다.
    checkout.drafts[draftId]!.json
      ..['status'] = 'DRAFT'
      ..['nextAction'] = 'REVIEW'
      ..remove('payment')
      ..['checkoutFailure'] = {
        'step': 'RESERVE_INVENTORY',
        'code': CheckoutProblemCode.insufficientStock,
      };

    final s = await run();

    expect(s.phase, PaymentPhase.failed);
    expect(s.failureCode, CheckoutProblemCode.insufficientStock);
    expect(pg.launches, 0);
  });

  test('결제 가능 시간이 지난 결제창 정보로는 결제창을 열지 않는다', () async {
    final payment =
        checkout.drafts[draftId]!.json['payment']! as Map<String, Object?>;
    payment['expiresAt'] = now
        .subtract(const Duration(seconds: 1))
        .toIso8601String();

    final s = await run();

    expect(s.phase, PaymentPhase.failed);
    expect(s.failureCode, CheckoutProblemCode.resourceExpired);
    expect(pg.launches, 0);
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

  test('승인 요청 응답을 잃어도 다시 보내지 않고 조회로 완료를 확인한다', () async {
    checkout.loseNextAuthResponse = true;

    final s = await run();

    expect(s.phase, PaymentPhase.done);
    expect(checkout.authKeys, hasLength(1));
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

  group('토스 결제위젯 결과', () {
    const entry = PaymentEntry(
      clientKey: 'k',
      pgOrderId: 'pay-1',
      amount: 16880,
      orderName: 'x',
    );

    test('성공은 인증일 뿐이고 결과의 주문번호·금액이 서버 값과 같을 때만 승인 요청으로 간다', () {
      final ok = pgReturnFromToss(
        Result(success: Success('pk-1', 'pay-1', 16880, null)),
        entry,
      );
      expect(ok, isA<PgAuthenticated>());
      expect((ok as PgAuthenticated).paymentKey, 'pk-1');

      expect(
        pgReturnFromToss(
          Result(success: Success('pk-1', 'pay-1', 100, null)),
          entry,
        ),
        isA<PgFailed>(),
      );
      expect(
        pgReturnFromToss(
          Result(success: Success('pk-1', 'pay-OTHER', 16880, null)),
          entry,
        ),
        isA<PgFailed>(),
      );
    });

    test('사용자 취소는 취소, 그 밖 실패는 실패, 승인 대기는 서버 조회', () {
      expect(
        pgReturnFromToss(
          Result(fail: Fail(tossUserCancelCode, '취소', '')),
          entry,
        ),
        isA<PgCancelled>(),
      );
      expect(
        pgReturnFromToss(
          Result(fail: Fail('REJECT_CARD', 'x', 'pay-1')),
          entry,
        ),
        isA<PgFailed>(),
      );
      expect(
        pgReturnFromToss(Result(pending: Pending('pk', 'pay-1', 16880)), entry),
        isA<PgNoReturn>(),
      );
    });
  });

  test('결제창 결과가 주문과 맞지 않으면 승인 요청을 보내지 않는다', () async {
    pg.next = const PgFailed(TossPgLauncher.resultMismatch);

    final s = await run();

    expect(s.phase, PaymentPhase.failed);
    expect(checkout.authKeys, isEmpty);
  });
}
