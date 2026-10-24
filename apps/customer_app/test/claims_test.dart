import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/checkout/domain/checkout.dart';
import 'package:customer_app/features/checkout/presentation/checkout_controller.dart';
import 'package:customer_app/features/claims/data/mock_claims_repository.dart';
import 'package:customer_app/features/claims/domain/claims.dart';
import 'package:customer_app/features/claims/presentation/claims_controller.dart';
import 'package:customer_app/features/orders/data/mock_orders_repository.dart';

import 'support/app_harness.dart';

void main() {
  setUpAll(initPmartFormatting);

  late MockOrdersRepository orders;
  late MockClaimsRepository claims;
  setUp(() {
    orders = MockOrdersRepository(latency: Duration.zero);
    claims = MockClaimsRepository(orders: orders, latency: Duration.zero);
  });

  Future<ClaimView> cancelSeed4(int qty) async {
    final outcome = await CancelRequester(claims).submit('order-seed-4', [
      CancelLine(orderLineId: 'ol-5', qty: qty),
    ], CancelReason.changeOfMind);
    return (outcome as CommandDone<ClaimView>).value;
  }

  group('취소 요청', () {
    test('접수는 완료가 아니고, 조회하며 출고 중지 → 환불 진행 → 종결로 간다', () async {
      final claim = await cancelSeed4(3);
      expect(claim.state, ClaimState.opened);
      expect(claim.refunds, isEmpty);

      expect((await claims.get(claim.claimId)).state, ClaimState.opened);
      expect((await claims.get(claim.claimId)).state, ClaimState.stopPending);
      final inProgress = await claims.get(claim.claimId);
      expect(inProgress.state, ClaimState.inProgress);
      expect(inProgress.refunds.single.done, isFalse, reason: 'PG 성공 전');
      final closed = await claims.get(claim.claimId);
      expect(closed.state, ClaimState.closed);
      expect(closed.refunds.single.done, isTrue);
      expect(orders.orderJson('order-seed-4')!['status'], 'CANCELLED');
    });

    test('접수 응답을 잃으면 같은 키로 다시 보내 클레임을 하나만 만든다', () async {
      claims.loseNextCreateResponse = true;

      await cancelSeed4(1);

      expect(claims.claims, hasLength(1));
    });

    test('배송이 시작된 주문은 서버가 취소를 받지 않는다', () async {
      final outcome = await CancelRequester(claims).submit(
        'order-seed-1',
        const [CancelLine(orderLineId: 'ol-2', qty: 1)],
        CancelReason.changeOfMind,
      );
      expect(
        (outcome as CommandRejected<ClaimView>).code,
        ClaimProblemCode.orderNotCancellable,
      );
    });

    test('철회는 확인 중을 거쳐 서버가 확정한다', () async {
      claims.holdAtOpened = true;
      final claim = await cancelSeed4(1);
      final key = IdempotencyKey.generate();

      await claims.withdraw(
        claim.claimId,
        expectedVersion: claim.version,
        key: key,
      );

      expect(await claims.withdrawal(claim.claimId, key), RequestState.pending);
      expect(
        await claims.withdrawal(claim.claimId, key),
        RequestState.confirmed,
      );
      expect((await claims.get(claim.claimId)).state, ClaimState.withdrawn);
    });
  });

  group('예약시간 변경', () {
    const window = ArrivalWindow(
      date: '2026-10-24',
      start: '20:00',
      end: '21:00',
    );

    test('상품 준비 전에는 확인 중을 거쳐 바뀐 시간이 주문에 반영된다', () async {
      final order = await orders.get('order-seed-4');
      final key = IdempotencyKey.generate();

      await orders.requestTimeChange(
        order.orderId,
        window,
        expectedVersion: order.version,
        key: key,
      );

      expect(await orders.timeChange(order.orderId, key), RequestState.pending);
      // 확인 중에는 주문의 시간이 아직 그대로다.
      expect((await orders.get(order.orderId)).window!.start, '18:00');
      expect(
        await orders.timeChange(order.orderId, key),
        RequestState.confirmed,
      );
      expect((await orders.get(order.orderId)).window, window);
    });

    test('상품 준비에 들어간 주문은 INVALID_STATE 로 거절된다', () async {
      final order = await orders.get('order-seed-1');
      await expectLater(
        orders.requestTimeChange(
          order.orderId,
          window,
          expectedVersion: order.version,
          key: IdempotencyKey.generate(),
        ),
        throwsA(
          isA<ProblemFailure>().having(
            (f) => f.problem.code,
            'code',
            'INVALID_STATE',
          ),
        ),
      );
    });
  });

  group('화면', () {
    final now = DateTime.utc(2026, 10, 24, 3);

    Future<void> openOrder(WidgetTester t, String orderId) async {
      t.view
        ..physicalSize = const Size(800, 2200)
        ..devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        testApp(orders: orders, [
          claimsRepositoryProvider.overrideWithValue(claims),
          clockProvider.overrideWithValue(() => now),
          requestPollPolicyProvider.overrideWithValue((
            interval: Duration.zero,
            attempts: 3,
          )),
        ]),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('마이').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('my-login')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('login-kakao')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('my-orders')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(ValueKey('order-$orderId')));
      await t.pumpAndSettle();
    }

    testWidgets('배송이 시작된 주문에는 취소 버튼이 없다', (t) async {
      await openOrder(t, 'order-seed-1');
      expect(find.byKey(const ValueKey('cancel-order')), findsNothing);
    });

    testWidgets('취소 요청 → 처리 내역은 "접수"로 시작하고 완료로 보이지 않는다', (t) async {
      await openOrder(t, 'order-seed-4');
      await t.tap(find.byKey(const ValueKey('cancel-order')));
      await t.pumpAndSettle();

      final submit = find.byKey(const ValueKey('cancel-submit'));
      FilledButton button() => t.widget<FilledButton>(
        find.descendant(of: submit, matching: find.byType(FilledButton)),
      );
      expect(button().onPressed, isNull, reason: '수량을 고르기 전');
      await t.tap(find.byKey(const ValueKey('cancel-inc-ol-5')));
      await t.pump();
      await t.tap(submit);
      await t.pumpAndSettle();

      expect(find.text('요청을 접수했어요'), findsOneWidget);
      expect(find.textContaining('접수는 취소 완료가 아니에요'), findsOneWidget);
      expect(find.text('환불 완료'), findsNothing);
    });

    testWidgets('도착 시간 변경은 확인 중 → 확정 뒤에만 바뀐 시간으로 보인다', (t) async {
      await openOrder(t, 'order-seed-4');
      await t.tap(find.byKey(const ValueKey('reschedule')));
      await t.pumpAndSettle();

      expect(
        t.widget<Text>(find.byKey(const ValueKey('reschedule-current'))).data,
        contains('오후 6:00'),
      );
      await t.tap(find.byKey(const ValueKey('rs-slot-20:00')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('reschedule-submit')));
      await t.pumpAndSettle();

      expect(find.byKey(const ValueKey('reschedule-done')), findsOneWidget);
      expect(
        t.widget<Text>(find.byKey(const ValueKey('reschedule-current'))).data,
        contains('오후 8:00'),
      );
    });
  });
}
