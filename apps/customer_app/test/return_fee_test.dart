import 'package:dio/dio.dart' show Dio;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_api_claim/pmart_api_claim.dart' as api;
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/checkout/data/mock_checkout_repository.dart';
import 'package:customer_app/features/checkout/presentation/checkout_controller.dart';
import 'package:customer_app/features/claims/data/claims_repository.dart';
import 'package:customer_app/features/claims/data/mock_claims_repository.dart';
import 'package:customer_app/features/claims/domain/claims.dart';
import 'package:customer_app/features/claims/presentation/return_fee_controller.dart';
import 'package:customer_app/features/orders/data/mock_orders_repository.dart';
import 'package:customer_app/features/payment/data/payment_repository.dart';
import 'package:customer_app/features/payment/domain/payment.dart';
import 'package:customer_app/features/payment/presentation/payment_controller.dart';
import 'package:customer_app/shared/providers.dart' show sourceSystem;

import 'support/app_harness.dart';

/// 반품 회수비 결제(claim 0.2.0, 백엔드 요청 2026-11-17 return-recovery §3). 목 모드.
void main() {
  setUpAll(initPmartFormatting);
  final now = DateTime.utc(2026, 10, 24, 3); // 서울 12:00

  late MockOrdersRepository orders;
  late MockClaimsRepository claims;
  late MockCheckoutRepository checkout;
  late MockPgLauncher pg;
  late String claimId;

  setUp(() {
    orders = MockOrdersRepository(latency: Duration.zero, now: () => now);
    claims = MockClaimsRepository(
      orders: orders,
      latency: Duration.zero,
      now: () => now,
    );
    checkout = MockCheckoutRepository(latency: Duration.zero, now: () => now)
      ..externals.add(claims);
    pg = MockPgLauncher();
    // 고객센터가 접수한 고객 사유 반품(order-seed-1) — 회수비 9,000원, 기한 24시간.
    claimId = claims.seedReturnFee('order-seed-1');
  });

  Future<void> openClaim(WidgetTester t) async {
    t.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp(orders: orders, claims: claims, checkout: checkout, [
        clockProvider.overrideWithValue(() => now),
        pgLauncherProvider.overrideWithValue(pg),
        returnFeePollPolicyProvider.overrideWithValue((
          interval: Duration.zero,
          attempts: 3,
        )),
      ]),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-login')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('my-orders')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('order-order-seed-1')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(ValueKey('order-claim-$claimId')));
    await t.tap(find.byKey(ValueKey('order-claim-$claimId')));
    await t.pumpAndSettle();
  }

  String phase(WidgetTester t) =>
      t.widget<Text>(find.byKey(const ValueKey('ret-fee-phase'))).data!;

  String claimState(WidgetTester t) =>
      t.widget<Text>(find.byKey(const ValueKey('claim-state'))).data!;

  testWidgets('회수비 결제 대기: 서버 금액·기한(남은 시간)·안내, 결제 버튼', (t) async {
    await openClaim(t);
    expect(claimState(t), '회수비 결제를 기다리고 있어요');
    expect(find.text('반품 회수비 결제가 필요해요'), findsOneWidget);
    expect(find.text('결제하시면 라이더가 상품을 가지러 가요'), findsOneWidget);
    expect(
      t.widget<Text>(find.byKey(const ValueKey('ret-fee-amount'))).data,
      '9,000원',
    );
    expect(
      t.widget<Text>(find.byKey(const ValueKey('ret-fee-deadline'))).data,
      contains('24시간 0분 남음'),
    );
    expect(find.text('9,000원 결제하기'), findsOneWidget);
  });

  testWidgets('결제 → 승인 요청 → 서버가 PAID 를 준 뒤에만 결제됨, 반품이 진행으로', (t) async {
    await openClaim(t);
    await t.tap(find.byKey(const ValueKey('ret-fee-pay')));
    await t.pumpAndSettle();

    expect(pg.launches, 1);
    expect(checkout.authKeys, hasLength(1));
    expect(find.byKey(const ValueKey('ret-fee-pay')), findsNothing);
    expect(claimState(t), '반품을 진행하고 있어요');
    expect(
      t.widget<Text>(find.byKey(const ValueKey('ret-fee-result'))).data,
      '반품 회수비 9,000원을 결제했어요',
    );
  });

  testWidgets('결제창을 닫으면 실패 보고 뒤 "다시 결제하기" — 새 결제 시도로 다시 연다', (t) async {
    pg.next = const PgCancelled();
    await openClaim(t);
    await t.tap(find.byKey(const ValueKey('ret-fee-pay')));
    await t.pumpAndSettle();

    expect(phase(t), '결제를 취소했어요. 기한 안에 다시 결제할 수 있어요');
    expect(checkout.authFailures.single.$2, tossUserCancelCode);
    expect(find.text('다시 결제하기'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('ret-fee-pay')));
    await t.pumpAndSettle();
    expect(claims.feeRetries.map((r) => r.$1), [claimId]);
    expect(pg.launches, 2);
    expect(claimState(t), '반품을 진행하고 있어요');
  });

  testWidgets('승인 결과가 아직 없으면 "확인 중" — 다시 결제 없음', (t) async {
    claims.feeApproval = null;
    await openClaim(t);
    await t.tap(find.byKey(const ValueKey('ret-fee-pay')));
    await t.pumpAndSettle();

    expect(phase(t), isNot(contains('결제했어요')));
    expect(find.byKey(const ValueKey('ret-fee-pay')), findsNothing);
    expect(find.byKey(const ValueKey('ret-fee-check-again')), findsOneWidget);
    expect(claimState(t), '회수비 결제를 기다리고 있어요');
  });

  testWidgets('결제 시도가 아직 준비 중이면 기다렸다가 연다', (t) async {
    claims.feeAttemptReadyAfter = 2;
    await openClaim(t);
    await t.tap(find.byKey(const ValueKey('ret-fee-pay')));
    await t.pumpAndSettle();
    expect(pg.launches, 1);
    expect(claimState(t), '반품을 진행하고 있어요');
  });

  testWidgets('기한이 지났으면 결제창을 열지 않는다', (t) async {
    claimId = claims.seedReturnFee('order-seed-1', left: Duration.zero);
    await openClaim(t);
    await t.tap(find.byKey(const ValueKey('ret-fee-pay')));
    await t.pumpAndSettle();
    expect(pg.launches, 0);
    expect(phase(t), '결제 기한이 지났어요. 곧 반품이 취소돼요');
  });

  testWidgets('기한 안에 결제하지 않아 취소된 반품은 결제 버튼 없이 안내만', (t) async {
    claims.setReturnState(claimId, 'CANCELLED', feeState: 'UNPAID');
    await openClaim(t);
    expect(claimState(t), '반품이 취소됐어요');
    expect(find.byKey(const ValueKey('ret-fee-pay')), findsNothing);
    expect(
      t.widget<Text>(find.byKey(const ValueKey('ret-fee-result'))).data,
      '기한 안에 회수비를 결제하지 않아 반품이 취소됐어요',
    );
  });

  test('계약 → 앱: 회사 잘못 반품은 회수비 없음, 회수비 돌려주기 환불은 따로 표시', () {
    final free = claimFromContract(
      api.Claim.fromJson({
        'claimId': 'c-1',
        'type': 'RETURN',
        'state': 'IN_PROGRESS',
        'faultCode': 'MISDELIVERY',
        'fees': {'returnPickupFee': 0},
      }),
    );
    expect(free.feePayment, isNull);
    expect(free.awaitingFee, isFalse);

    final cancelled = claimFromContract(
      api.Claim.fromJson({
        'claimId': 'c-2',
        'type': 'RETURN',
        'state': 'CANCELLED',
        'feePayment': {
          'amount': 9000,
          'state': 'PAID',
          'refundDecision': 'REFUND',
        },
        'refunds': [
          {
            'kind': 'RETURN_FEE',
            'state': 'COMPLETED',
            'pgResult': 'SUCCESS',
            'amount': 9000,
          },
        ],
      }),
    );
    expect(cancelled.state, ClaimState.cancelled);
    expect(cancelled.feePayment!.refunded, isTrue);
    expect(cancelled.refunds.single.returnFee, isTrue);
    expect(isClaimSettled(cancelled.state), isTrue);
  });

  test(
    'API: POST /claims/{id}/fee-payment-attempts — 본문 없음, 멱등 키·출처 헤더',
    () async {
      final adapter = FakeAdapter(
        (o, _) async => FakeReply(
          200,
          body: {
            'claimId': 'c-1',
            'type': 'RETURN',
            'state': 'FEE_PENDING',
            'feePayment': {
              'amount': 9000,
              'state': 'WAITING',
              'paymentAttemptId': 'PAY-2',
              'deadlineAt': now.add(const Duration(hours: 3)).toIso8601String(),
            },
          },
        ),
      );
      final Dio dio = createPmartDio(
        baseUrl: 'http://test.invalid/api/v1',
        sourceSystem: sourceSystem,
        tokens: TokenStore(MemoryKeyValueStore()),
        refresher: (_) async => null,
        adapter: adapter,
        delay: (_) async {},
      );
      final key = IdempotencyKey.generate();
      final c = await ApiClaimsRepository(dio).retryFeePayment('c-1', key: key);

      final sent = adapter.requests.single;
      expect(sent.method, 'POST');
      expect(sent.path, endsWith('/claims/c-1/fee-payment-attempts'));
      expect(sent.headers['Idempotency-Key'], key.value);
      expect(sent.headers['X-Source-System'], sourceSystem);
      expect(c.feePayment!.paymentAttemptId, 'PAY-2');
      expect(c.awaitingFee, isTrue);
    },
  );
}
