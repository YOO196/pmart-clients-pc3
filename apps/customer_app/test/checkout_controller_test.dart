import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';

import 'package:customer_app/features/address/data/mock_address_repository.dart';
import 'package:customer_app/features/address/presentation/address_controller.dart';
import 'package:customer_app/features/auth/data/mock_auth_repository.dart';
import 'package:customer_app/features/auth/domain/auth.dart';
import 'package:customer_app/features/auth/presentation/auth_controller.dart';
import 'package:customer_app/features/cart/data/mock_cart_repository.dart';
import 'package:customer_app/features/cart/domain/cart.dart';
import 'package:customer_app/features/cart/presentation/cart_controller.dart';
import 'package:customer_app/features/checkout/data/mock_checkout_repository.dart';
import 'package:customer_app/features/checkout/domain/checkout.dart';
import 'package:customer_app/features/checkout/presentation/checkout_controller.dart';
import 'package:customer_app/shared/providers.dart';
import 'package:customer_app/shared/shopping_context.dart';

void main() {
  var now = DateTime.utc(2026, 10, 24, 3); // 서울 12:00
  late MockCheckoutRepository checkout;
  late ProviderContainer c;

  setUp(() async {
    now = DateTime.utc(2026, 10, 24, 3);
    checkout = MockCheckoutRepository(latency: Duration.zero, now: () => now);
    c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        envProvider.overrideWithValue(PmartEnv.mock),
        tokenStoreProvider.overrideWithValue(TokenStore(MemoryKeyValueStore())),
        authRepositoryProvider.overrideWithValue(
          MockAuthRepository(latency: Duration.zero),
        ),
        addressRepositoryProvider.overrideWithValue(
          MockAddressRepository(latency: Duration.zero),
        ),
        cartRepositoryProvider.overrideWithValue(
          MockCartRepository(latency: Duration.zero),
        ),
        checkoutRepositoryProvider.overrideWithValue(checkout),
        clockProvider.overrideWithValue(() => now),
        draftPollPolicyProvider.overrideWithValue((
          interval: Duration.zero,
          attempts: 5,
        )),
      ],
    );
    addTearDown(c.dispose);
    c
      ..listen(currentMfcIdProvider, (_, _) {})
      ..listen(cartControllerProvider, (_, _) {})
      ..listen(draftControllerProvider, (_, _) {});
    final login = loginFlowProvider(LoginPurpose.general);
    c.listen(login, (_, _) {});
    await c.read(login.notifier).start(SocialProvider.kakao);
    await c.read(addressBookProvider.future);
    await c.read(cartControllerProvider.future);
    c.read(checkoutSetupProvider.notifier)
      ..begin()
      ..setMode(DeliveryMode.single);
  });

  Future<void> fillCartTo(int milkQty) async {
    final cart = c.read(cartControllerProvider).requireValue.cart;
    await c
        .read(cartControllerProvider.notifier)
        .submit(
          SetQuantity(
            cartItemId: cart.lineForSku('E-00000001')!.cartItemId,
            quantity: milkQty,
          ),
        );
  }

  DraftController draft() => c.read(draftControllerProvider.notifier);
  DraftState state() => c.read(draftControllerProvider).requireValue!;

  test('최소주문 미달이면 서버가 결제로 보내지 않고 결제 버튼도 닫힌다', () async {
    await draft().enter();

    expect(state().draft.next, DraftNext.review);
    expect(state().draft.quote!.minOrderSatisfied, isFalse);
    expect(state().canPay, isFalse);
  });

  test('확인을 기다렸다가 결제 진입 전 초안(DRAFT·REVIEW)이면 결제를 연다(금액은 서버 값)', () async {
    await fillCartTo(5); // 2,980×5 + 1,980 = 16,880

    await draft().enter();

    final s = state();
    expect(s.draft.next, DraftNext.review);
    expect(s.draft.awaitingCheckout, isTrue);
    expect(s.canPay, isTrue);
    expect(s.draft.quote!.itemAmount, 16880);
    expect(s.draft.quote!.deliveryTip, 4000);
    expect(s.draft.quote!.totalAmount, 20980);
    expect(s.draft.resources!.inventory, HoldState.held);
  });

  test(
    '견적 10분이 지나 서버가 EXPIRED·RE_QUOTE 를 주면 만료로 보고, 다시 만들 때 새 주문 의도를 쓴다',
    () async {
      await fillCartTo(5);
      await draft().enter();
      final firstIntent = c.read(checkoutSetupProvider).purchaseIntentId;
      final firstDraft = state().draft.draftId;

      now = now.add(const Duration(minutes: 11));
      await draft().refresh();
      expect(state().draft.expired, isTrue);
      expect(state().canPay, isFalse);

      await draft().recreate();
      expect(
        c.read(checkoutSetupProvider).purchaseIntentId,
        isNot(firstIntent),
      );
      expect(state().draft.draftId, isNot(firstDraft));
      expect(state().draft.expired, isFalse);
    },
  );

  test('3만 원 이상이면 배달팁 0원과 사유는 서버가 준다', () async {
    await fillCartTo(10); // 29,800 + 1,980 = 31,780

    await draft().enter();

    expect(state().draft.quote!.deliveryTip, 0);
    expect(state().draft.quote!.tipReason, TipReason.over30000);
  });

  test('가격이 바뀌면 전후 금액을 비교하고 재동의 전에는 결제하지 않는다', () async {
    await fillCartTo(5);
    await draft().enter();
    checkout.priceChangesOnCheckout = true;

    final first = await draft().pay();

    expect(first, isA<CheckoutReQuote>());
    expect(state().needsReconsent, isTrue);
    expect(state().previousQuote!.totalAmount, 20980);
    expect(state().draft.quote!.totalAmount, 21480);
    expect(state().canPay, isFalse);
    expect(await draft().pay(), isNull, reason: '재동의 전 결제 요청 없음');

    draft().agreeToNewQuote();
    final second = await draft().pay();

    expect(second, isA<CheckoutAccepted>());
    expect(checkout.checkoutKeys, hasLength(2));
    expect(checkout.checkoutKeys.toSet(), hasLength(2), reason: '새 클릭은 새 키');
  });

  test('결제 진입 ACCEPTED 는 주문 완료가 아니다(주문 ID 없음, 결제 버튼 닫힘)', () async {
    await fillCartTo(5);
    await draft().enter();

    await draft().pay();

    expect(state().lastStart, isA<CheckoutAccepted>());
    expect(state().draft.orderId, isNull);
    expect(state().draft.status.isConfirmedOrLater, isFalse);
    expect(state().canPay, isFalse);
  });

  test('초안 생성 응답을 잃으면 같은 키로 다시 보내 초안을 하나만 만든다', () async {
    await fillCartTo(5);
    checkout.loseNextDraftResponse = true;

    await draft().enter();

    expect(checkout.drafts, hasLength(1));
    expect(state().draft.awaitingCheckout, isTrue);
  });

  test('주문서에 다시 들어오면 같은 초안을 다시 조회한다(타이머 재시작 없음)', () async {
    await fillCartTo(5);
    await draft().enter();
    final first = state().draft;

    now = now.add(const Duration(minutes: 3));
    await draft().enter();

    expect(checkout.drafts, hasLength(1));
    expect(state().draft.draftId, first.draftId);
    expect(state().draft.quote!.expiresAt, first.quote!.expiresAt);
  });

  test('배송 방식을 바꾸면 새 초안을 만든다', () async {
    await fillCartTo(5);
    await draft().enter();
    c.read(checkoutSetupProvider.notifier).setMode(DeliveryMode.bundled);

    await draft().enter();

    expect(checkout.drafts, hasLength(2));
    expect(state().draft.quote!.deliveryTip, 3000);
  });

  test('가격 동결이 끝나면 서버가 재견적을 요구하고 결제 버튼이 닫힌다', () async {
    await fillCartTo(5);
    await draft().enter();

    now = now.add(const Duration(minutes: 11));
    await draft().refresh();

    expect(state().draft.next, DraftNext.reQuote);
    expect(state().canPay, isFalse);
  });

  test('가격 동결과 재고 예약 만료는 따로 있고 더 이른 쪽을 안내한다', () async {
    await fillCartTo(5);
    await draft().enter();

    final d = state().draft;
    expect(d.quote!.expiresAt, isNot(d.resources!.reservationExpiresAt));
    expect(d.earliestExpiry, d.resources!.reservationExpiresAt);
  });

  test('선택한 구매 가능 품목만 초안에 담는다', () async {
    final cart = c.read(cartControllerProvider).requireValue.cart;
    await c
        .read(cartControllerProvider.notifier)
        .submit(
          SetSelected(
            cartItemId: cart.lineForSku('E-00000005')!.cartItemId,
            selected: false,
          ),
        );

    await draft().enter();

    expect(state().request.lines.map((l) => l.sku), ['E-00000001']);
  });
}
