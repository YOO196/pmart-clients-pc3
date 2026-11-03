import 'package:dio/dio.dart';
import 'package:pmart_api_cart/pmart_api_cart.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../../catalog/domain/catalog.dart' show SaleState;
import '../domain/cart.dart';

abstract interface class CartRepository {
  /// 현재 장바구니를 만들거나 돌려준다(`POST /carts`). 회원은 계정, 비회원은 비회원 토큰 주체 기준.
  Future<Cart> open({String? mfcId});

  /// 실패는 [PmartFailure] 로 던진다.
  Future<Cart> get(String cartId);

  /// 변경 명령 1회. 재전송은 같은 [key] 로 한다.
  ///
  /// 업무 거절·버전 충돌·결과 불명은 [CartChangeOutcome] 으로 돌려준다.
  /// 그 밖의 실패(권한·조회 불가 등)는 [PmartFailure] 로 던진다.
  Future<CartChangeOutcome> change(
    String cartId,
    CartChange change, {
    required IdempotencyKey key,
    required int expectedVersion,
  });

  /// 원결과 조회(`GET …/change-requests/{requestId}`). 변경을 다시 적용하지 않는다.
  Future<CartChangeOutcome> lookup(String cartId, IdempotencyKey key);
}

/// 실서버 구현(cart-service).
final class ApiCartRepository implements CartRepository {
  ApiCartRepository(Dio dio)
    : _carts = api.PmartApiCart(dio: dio).getCartsApi(),
      _items = api.PmartApiCart(dio: dio).getItemsApi();

  final api.CartsApi _carts;
  final api.ItemsApi _items;

  @override
  Future<Cart> open({String? mfcId}) async {
    final key = IdempotencyKey.generate();
    final res = await pmartGuard(
      () => _carts.createOrGetCart(
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        createOrGetCartRequest: api.CreateOrGetCartRequest(mfcId: mfcId),
        extra: commandOptions(key).extra,
      ),
    );
    return cartFromContract(_body(res.data));
  }

  @override
  Future<Cart> get(String cartId) async {
    final res = await pmartGuard(() => _carts.getCart(cartId: cartId));
    return cartFromContract(_body(res.data));
  }

  @override
  Future<CartChangeOutcome> change(
    String cartId,
    CartChange change, {
    required IdempotencyKey key,
    required int expectedVersion,
  }) async {
    final extra = commandOptions(key, expectedVersion: expectedVersion).extra;
    try {
      final res = await pmartGuard(
        () => switch (change) {
          AddItem(:final sku, :final quantity) => _items.addCartItem(
            cartId: cartId,
            idempotencyKey: key.value,
            xSourceSystem: sourceSystem,
            xExpectedVersion: expectedVersion,
            addCartItemRequest: api.AddCartItemRequest(
              sku: sku,
              quantity: quantity,
              expectedVersion: expectedVersion,
            ),
            extra: extra,
          ),
          SetQuantity(:final cartItemId, :final quantity) =>
            _items.changeCartItem(
              cartId: cartId,
              itemId: cartItemId,
              idempotencyKey: key.value,
              xSourceSystem: sourceSystem,
              xExpectedVersion: expectedVersion,
              changeCartItemRequest: api.ChangeCartItemRequest(
                quantity: quantity,
                expectedVersion: expectedVersion,
              ),
              extra: extra,
            ),
          SetSelected(:final cartItemId, :final selected) =>
            _items.changeCartItem(
              cartId: cartId,
              itemId: cartItemId,
              idempotencyKey: key.value,
              xSourceSystem: sourceSystem,
              xExpectedVersion: expectedVersion,
              changeCartItemRequest: api.ChangeCartItemRequest(
                selected: selected,
                expectedVersion: expectedVersion,
              ),
              extra: extra,
            ),
          RemoveItem(:final cartItemId) => _items.deleteCartItem(
            cartId: cartId,
            itemId: cartItemId,
            idempotencyKey: key.value,
            xSourceSystem: sourceSystem,
            xExpectedVersion: expectedVersion,
            extra: extra,
          ),
        },
      );
      return changeResultFromContract(res.data);
    } on PmartFailure catch (f) {
      return changeFailureToOutcome(f);
    }
  }

  @override
  Future<CartChangeOutcome> lookup(String cartId, IdempotencyKey key) async {
    try {
      final res = await pmartGuard(
        () => _items.getCartChangeRequest(cartId: cartId, requestId: key.value),
      );
      return changeResultFromContract(res.data);
    } on ProblemFailure catch (f) {
      // 그 키로 접수된 변경이 없다 → 미적용(계약 getCartChangeRequest 404).
      if (f.problem.code == ProblemCode.notFound) {
        return const CartChangeNotApplied();
      }
      return const CartChangeUnknown();
    } on PmartFailure {
      // 조회 실패는 "아직 모름"이다.
      return const CartChangeUnknown();
    }
  }
}

api.Cart _body(api.Cart? data) =>
    data ?? (throw const ContractViolationFailure('Cart 본문 없음'));

Cart cartFromContract(api.Cart c) => Cart(
  cartId: c.cartId,
  version: c.cartVersion,
  isMember: c.ownerType == api.CartOwnerTypeEnum.MEMBER,
  mfcId: c.mfcId,
  selectedItemAmount: c.selectedItemAmount,
  expiresAt: c.expiresAt,
  sources: [
    for (final s in c.sources ?? const <api.CartSourcesInner>[])
      if (s.system case final system?)
        CartSource(
          system: system,
          unavailable:
              s.asOf?.freshness ==
              api.CartSourcesInnerAsOfFreshnessEnum.UNAVAILABLE,
        ),
  ],
  lines: [
    for (final i in c.items)
      CartLine(
        cartItemId: i.cartItemId,
        sku: i.sku,
        productId: i.productId,
        quantity: i.quantity,
        selected: i.selected,
        name: i.display?.name,
        optionLabel: i.display?.optionLabel,
        imageUrl: i.display?.imageUrl,
        unitPrice: i.display?.unitPrice,
        saleState: switch (i.display?.saleState) {
          api.CartItemDisplaySaleStateEnum.ON_SALE => SaleState.onSale,
          api.CartItemDisplaySaleStateEnum.TEMPORARILY_SOLD_OUT =>
            SaleState.temporarilySoldOut,
          api.CartItemDisplaySaleStateEnum.SALE_STOPPED =>
            SaleState.saleStopped,
          _ => SaleState.unknown,
        },
        availability: switch (i.display?.availability) {
          api.CartItemDisplayAvailabilityEnum.AVAILABLE =>
            LineAvailability.available,
          api.CartItemDisplayAvailabilityEnum.LOW => LineAvailability.low,
          api.CartItemDisplayAvailabilityEnum.SOLD_OUT =>
            LineAvailability.soldOut,
          api.CartItemDisplayAvailabilityEnum.NOT_CARRIED =>
            LineAvailability.notCarried,
          _ => LineAvailability.unknown,
        },
        availableQty: i.display?.availableQty,
      ),
  ],
);

CartChangeOutcome changeResultFromContract(api.CartChangeResult? r) {
  if (r == null) {
    // 2xx 인데 본문이 없으면 반영 여부를 모른다.
    return const CartChangeUnknown();
  }
  return switch (r.status) {
    api.CartChangeResultStatusEnum.APPLIED => CartChangeApplied(
      cartVersion: r.cartVersion ?? r.version,
    ),
    api.CartChangeResultStatusEnum.REJECTED => CartChangeRejected(
      r.nextAction ?? ProblemCode.domainRejected,
    ),
    _ => const CartChangeUnknown(),
  };
}

/// 변경 명령의 실패를 결과로 바꾼다. 권한·인증 등 화면 전체 문제는 그대로 던진다.
CartChangeOutcome changeFailureToOutcome(PmartFailure f) => switch (f) {
  UnknownResultFailure() => const CartChangeUnknown(),
  ProblemFailure(:final problem)
      when problem.code == CartProblemCode.versionConflict ||
          problem.code == ProblemCode.versionConflict =>
    const CartVersionConflict(),
  ProblemFailure(:final problem) when problem.status == 422 =>
    CartChangeRejected(
      problem.code,
      limit: switch (problem.raw['limit']) {
        final Map<String, dynamic> l => QuantityLimit(
          totalUnits: l['totalUnits'] as int?,
          limitUnits: l['limitUnits'] as int?,
          suggestedQuantity: l['suggestedQuantity'] as int?,
        ),
        _ => null,
      },
      availableQty: problem.raw['availableQty'] as int?,
    ),
  _ => throw f,
};
