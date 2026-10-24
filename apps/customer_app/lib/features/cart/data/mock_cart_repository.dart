import 'package:pmart_api_cart/pmart_api_cart.dart';

import '../domain/cart_summary.dart';
import 'cart_repository.dart';

/// 목 구현. 계약 스키마(`cart-service.yaml` Cart)를 따르는 JSON 을 생성 모델로 읽어서
/// 실서버 구현과 같은 변환을 거친다. 계약에 없는 필드는 넣지 않는다.
final class MockCartRepository implements CartRepository {
  MockCartRepository({this.latency = const Duration(milliseconds: 300)});

  final Duration latency;

  static const fixture = <String, Object?>{
    'cartId': 'cart-mock-1',
    'cartVersion': 3,
    'ownerType': 'GUEST',
    'accountId': null,
    'mfcId': 'MFC-MOCK-01',
    'items': [
      {
        'cartItemId': 'ci-1',
        'sku': 'E-00000001',
        'quantity': 2,
        'selected': true,
      },
      {
        'cartItemId': 'ci-2',
        'sku': 'B-00000002',
        'quantity': 1,
        'selected': true,
      },
    ],
    'selectedItemAmount': 23960,
    'lastChangedAt': '2026-10-24T06:00:00Z',
    'expiresAt': '2026-11-23T06:00:00Z',
  };

  @override
  Future<CartSummary> summary(String cartId) async {
    await Future<void>.delayed(latency);
    return cartSummaryFromContract(Cart.fromJson(fixture));
  }
}
