import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
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

/// 회원 로그인·주소·장바구니까지 준비된 목 컨테이너.
Future<ProviderContainer> memberContainer({
  required MockCheckoutRepository checkout,
  required DateTime Function() now,
  List<Override> extra = const [],
  SecureKeyValueStore? secure,
}) async {
  final c = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      envProvider.overrideWithValue(PmartEnv.mock),
      secureStoreProvider.overrideWithValue(secure ?? MemoryKeyValueStore()),
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
      clockProvider.overrideWithValue(now),
      draftPollPolicyProvider.overrideWithValue((
        interval: Duration.zero,
        attempts: 5,
      )),
      ...extra,
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
  return c;
}

/// 서울우유 수량을 바꿔 최소주문을 채운다.
Future<void> setMilk(ProviderContainer c, int qty) async {
  final cart = c.read(cartControllerProvider).requireValue.cart;
  await c
      .read(cartControllerProvider.notifier)
      .submit(
        SetQuantity(
          cartItemId: cart.lineForSku('E-00000001')!.cartItemId,
          quantity: qty,
        ),
      );
}

/// 주문서를 만들고 결제 진입(ACCEPTED)까지 간다. 초안 ID 를 돌려준다.
Future<String> checkoutAccepted(ProviderContainer c) async {
  await setMilk(c, 5);
  final draft = c.read(draftControllerProvider.notifier);
  await draft.enter();
  final start = await draft.pay();
  expect(start, isA<CheckoutAccepted>());
  return c.read(draftControllerProvider).requireValue!.draft.draftId;
}
