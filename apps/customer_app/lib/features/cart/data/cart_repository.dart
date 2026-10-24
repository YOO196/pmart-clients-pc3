import 'package:dio/dio.dart';
import 'package:pmart_api_cart/pmart_api_cart.dart';
import 'package:pmart_core/pmart_core.dart';

import '../domain/cart_summary.dart';

abstract interface class CartRepository {
  /// 실패는 [PmartFailure] 로 던진다.
  Future<CartSummary> summary(String cartId);
}

/// 실서버 구현(`GET /carts/{cartId}`).
final class ApiCartRepository implements CartRepository {
  ApiCartRepository(Dio dio) : _carts = PmartApiCart(dio: dio).getCartsApi();

  final CartsApi _carts;

  @override
  Future<CartSummary> summary(String cartId) async {
    final res = await pmartGuard(() => _carts.getCart(cartId: cartId));
    final cart = res.data;
    if (cart == null) throw const ContractViolationFailure('Cart 본문 없음');
    return cartSummaryFromContract(cart);
  }
}

CartSummary cartSummaryFromContract(Cart cart) => CartSummary(
  cartId: cart.cartId,
  cartVersion: cart.cartVersion,
  lineCount: cart.items.length,
  selectedItemAmount: cart.selectedItemAmount,
);
