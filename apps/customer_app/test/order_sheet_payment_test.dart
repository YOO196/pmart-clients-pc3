import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/cart/domain/cart.dart';
import 'package:customer_app/features/catalog/domain/catalog.dart'
    show SaleState;
import 'package:customer_app/features/checkout/data/mock_checkout_repository.dart';
import 'package:customer_app/features/checkout/domain/checkout.dart';
import 'package:customer_app/features/checkout/presentation/checkout_controller.dart';
import 'package:customer_app/features/checkout/presentation/order_sheet_screen.dart'
    show orderSheetLineTitle;
import 'package:customer_app/shared/order_status.dart';
import 'package:customer_app/features/payment/data/payment_repository.dart';
import 'package:customer_app/features/payment/domain/payment.dart';
import 'package:customer_app/features/payment/presentation/payment_controller.dart';

import 'support/app_harness.dart';

/// 결제위젯 설정이 서버에 없다(422 CONFIG_REQUIRED). [fail] 을 끄면 정상 응답.
final class _NoWidgetConfig extends MockCheckoutRepository {
  _NoWidgetConfig({required super.now}) : super(latency: Duration.zero);

  bool fail = true;

  @override
  Future<PaymentWidgetConfig> widgetConfig() async {
    if (fail) {
      throw const ProblemFailure(
        Problem(status: 422, code: CheckoutProblemCode.configRequired),
      );
    }
    return super.widgetConfig();
  }
}

/// 주문서형 결제위젯(BR-34)·배송지 사본(BR-37)·결제 진입 계정 재확인(BR-37 회신 4).
void main() {
  setUpAll(initPmartFormatting);
  final now = DateTime.utc(2026, 10, 24, 3);

  Future<void> toOrderSheet(
    WidgetTester t,
    MockCheckoutRepository checkout, {
    List<Override> overrides = const [],
  }) async {
    t.view
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      testApp(checkout: checkout, [
        clockProvider.overrideWithValue(() => now),
        draftPollPolicyProvider.overrideWithValue((
          interval: Duration.zero,
          attempts: 3,
        )),
        ...overrides,
      ]),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('장바구니').last);
    await t.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await t.tap(find.byKey(const ValueKey('cart-inc-ci-1')));
      await t.pumpAndSettle();
    }
    await t.tap(find.byKey(const ValueKey('cart-order')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('login-kakao')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('mode-single')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('delivery-next')));
    await t.pumpAndSettle();
    expect(find.text('주문서'), findsOneWidget);
  }

  VoidCallback? payOnPressed(WidgetTester t) => t
      .widget<FilledButton>(
        find.descendant(
          of: find.byKey(const ValueKey('pay')),
          matching: find.byType(FilledButton),
        ),
      )
      .onPressed;

  test('주문서 품목 제목은 초안의 상품명 사본 → 장바구니 이름 → sku 순이다(BR-35)', () {
    const line = DraftLine(cartItemId: 'ci-1', sku: 'E-00000001', quantity: 2);
    OrderDraft draft(List<DraftLineView> lines) => OrderDraft(
      draftId: 'd',
      version: 1,
      status: OrderStatus.draft,
      next: DraftNext.review,
      lines: lines,
    );
    const cart = Cart(
      cartId: 'c',
      version: 1,
      isMember: true,
      lines: [
        CartLine(
          cartItemId: 'ci-1',
          sku: 'E-00000001',
          quantity: 2,
          selected: true,
          saleState: SaleState.onSale,
          availability: LineAvailability.available,
          name: '장바구니 이름',
        ),
      ],
    );

    expect(
      orderSheetLineTitle(
        draft(const [
          DraftLineView(
            sku: 'E-00000001',
            cartItemId: 'ci-1',
            productName: '서울우유 1L',
            optionLabel: '1L',
          ),
        ]),
        cart,
        line,
      ),
      '서울우유 1L · 1L',
    );
    // cartItemId 가 없는 사본은 sku 로 맞춘다. 옵션 라벨이 없으면 이름만.
    expect(
      orderSheetLineTitle(
        draft(const [DraftLineView(sku: 'E-00000001', productName: '서울우유 1L')]),
        cart,
        line,
      ),
      '서울우유 1L',
    );
    // 사본이 비어 오면(조회 실패) 장바구니 이름, 그것도 없으면 sku.
    expect(
      orderSheetLineTitle(
        draft(const [DraftLineView(sku: 'E-00000001', cartItemId: 'ci-1')]),
        cart,
        line,
      ),
      '장바구니 이름',
    );
    expect(orderSheetLineTitle(draft(const []), null, line), 'E-00000001');
  });

  testWidgets('주문서 품목은 초안에 고정된 상품명 사본으로 보인다(BR-35)', (t) async {
    final checkout = MockCheckoutRepository(
      latency: Duration.zero,
      now: () => now,
    );
    await toOrderSheet(t, checkout);

    final draft = checkout.drafts.values.single;
    expect(
      (draft.json['lines'] as List).cast<Map<String, Object?>>().first,
      containsPair('productName', '서울우유 1L'),
    );
    expect(find.text('서울우유 1L · 5개'), findsOneWidget);
    expect(find.text('감자칩 오리지널 110g · 1개'), findsOneWidget);
    expect(find.textContaining('E-0000'), findsNothing);
  });

  testWidgets('주문서 "받는 곳"은 초안에 고정된 배송지 사본이다(BR-37)', (t) async {
    final checkout = MockCheckoutRepository(
      latency: Duration.zero,
      now: () => now,
    );
    await toOrderSheet(t, checkout);

    expect(find.byKey(const ValueKey('shipping-address')), findsOneWidget);
    expect(find.textContaining('전포대로 210'), findsOneWidget);
    // 받는 곳은 이름만, 번호는 "내 연락처" 칸에 한 번(BR-60).
    expect(find.text('김피마'), findsOneWidget);
    expect(find.textContaining('010-0000-0000'), findsOneWidget);
    expect(find.textContaining('비밀번호 필요'), findsOneWidget);
    // 결제수단·약관 영역이 주문서 안에 있다(목은 안내 문구).
    expect(find.byKey(const ValueKey('pg-widget-mock')), findsOneWidget);
    expect(payOnPressed(t), isNotNull);
  });

  testWidgets('결제위젯 설정이 없으면(CONFIG_REQUIRED) 결제를 열지 않고, 다시 받으면 연다', (t) async {
    final checkout = _NoWidgetConfig(now: () => now);
    await toOrderSheet(t, checkout);

    expect(find.byKey(const ValueKey('pg-config-failed')), findsOneWidget);
    expect(find.text('결제를 준비하지 못했어요. 잠시 뒤 다시 시도해 주세요'), findsOneWidget);
    expect(payOnPressed(t), isNull);

    checkout.fail = false;
    await t.tap(find.text('다시 시도'));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('pg-config-failed')), findsNothing);
    expect(payOnPressed(t), isNotNull);
  });

  testWidgets('결제창을 닫으면 주문서에 남아 취소 안내를 보이고, 새로 결제 진입할 수 있다', (t) async {
    final checkout = MockCheckoutRepository(
      latency: Duration.zero,
      now: () => now,
    );
    final pg = MockPgLauncher(next: const PgCancelled());
    await toOrderSheet(
      t,
      checkout,
      overrides: [pgLauncherProvider.overrideWithValue(pg)],
    );

    await t.tap(find.byKey(const ValueKey('pay')));
    await t.pumpAndSettle();

    // 결제 화면으로 가지 않고 주문서에 남는다.
    expect(find.text('주문서'), findsOneWidget);
    expect(find.byKey(const ValueKey('pg-failed')), findsOneWidget);
    expect(find.text('결제를 취소했어요'), findsOneWidget);
    expect(find.byKey(const ValueKey('order-id')), findsNothing);
    expect(pg.launches, 1);
    // 이번 시도는 끝났다. 다시 결제는 새 키로 결제 진입한다.
    expect(payOnPressed(t), isNotNull);
    await t.tap(find.byKey(const ValueKey('pay')));
    await t.pumpAndSettle();
    expect(pg.launches, 2);
    expect(checkout.checkoutKeys.toSet().length, 2);
    expect(find.text('주문이 완료됐어요'), findsOneWidget);
  });

  testWidgets('결제 진입이 ACCOUNT_NOT_PURCHASABLE 로 거절되면 사유를 보이고 결제창을 열지 않는다', (
    t,
  ) async {
    final checkout = MockCheckoutRepository(
      latency: Duration.zero,
      now: () => now,
    )..rejectNextCheckout = CheckoutProblemCode.accountNotPurchasable;
    final pg = MockPgLauncher();
    await toOrderSheet(
      t,
      checkout,
      overrides: [pgLauncherProvider.overrideWithValue(pg)],
    );

    await t.tap(find.byKey(const ValueKey('pay')));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('checkout-rejected')), findsOneWidget);
    expect(find.text('지금은 이 계정으로 주문할 수 없어요. 고객센터로 문의해 주세요'), findsOneWidget);
    expect(pg.launches, 0);
    expect(find.text('주문서'), findsOneWidget);
  });

  testWidgets('결제 진행 중에는 주문서 위에 진행 상태를 보이고 결제 버튼을 잠근다', (t) async {
    final checkout = MockCheckoutRepository(
      latency: Duration.zero,
      now: () => now,
    );
    final pg = _HoldingLauncher();
    await toOrderSheet(
      t,
      checkout,
      overrides: [pgLauncherProvider.overrideWithValue(pg)],
    );

    await t.tap(find.byKey(const ValueKey('pay')));
    // 결제창이 열린 채 멈춰 있으므로 settle 하지 않는다. 결제 진입·PAY 대기 조회가 끝날 만큼만 돌린다.
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }

    expect(find.byKey(const ValueKey('pay-progress')), findsOneWidget);
    expect(find.text('결제 인증 중'), findsOneWidget);
    expect(payOnPressed(t), isNull);

    pg.finish(const PgCancelled());
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('pay-progress')), findsNothing);
    expect(find.byKey(const ValueKey('pg-failed')), findsOneWidget);
  });
}

/// 결제창이 열린 채로 멈춰 있는 결제창. [finish] 로 결과를 돌려준다.
final class _HoldingLauncher implements PgLauncher {
  Completer<PgReturn>? _pending;

  @override
  Future<PgReturn> launch(PaymentEntry entry) =>
      (_pending = Completer<PgReturn>()).future;

  void finish(PgReturn ret) => _pending?.complete(ret);
}
