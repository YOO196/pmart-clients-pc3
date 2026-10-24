import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:pmart_core/pmart_core.dart';

import 'package:customer_app/app.dart';
import 'package:customer_app/features/address/data/mock_address_repository.dart';
import 'package:customer_app/features/address/presentation/address_controller.dart';
import 'package:customer_app/features/auth/data/mock_auth_repository.dart';
import 'package:customer_app/features/auth/presentation/auth_controller.dart';
import 'package:customer_app/features/cart/data/cart_repository.dart';
import 'package:customer_app/features/cart/data/mock_cart_repository.dart';
import 'package:customer_app/features/cart/presentation/cart_controller.dart';
import 'package:customer_app/features/catalog/data/catalog_repository.dart';
import 'package:customer_app/features/catalog/data/mock_catalog_repository.dart';
import 'package:customer_app/features/catalog/presentation/catalog_providers.dart';
import 'package:customer_app/shared/providers.dart';

/// 목 모드 앱. 둘러보기는 [catalog](기본: 지연 없는 목)를 쓰고 [overrides] 를 더한다.
Widget testApp(
  List<Override> overrides, {
  CatalogRepository? catalog,
  CartRepository? cart,
}) => ProviderScope(
  retry: (_, _) => null,
  overrides: [
    envProvider.overrideWithValue(PmartEnv.mock),
    catalogRepositoryProvider.overrideWithValue(
      catalog ?? MockCatalogRepository(latency: Duration.zero),
    ),
    cartRepositoryProvider.overrideWithValue(
      cart ?? MockCartRepository(latency: Duration.zero),
    ),
    authRepositoryProvider.overrideWithValue(
      MockAuthRepository(latency: Duration.zero),
    ),
    addressRepositoryProvider.overrideWithValue(
      MockAddressRepository(latency: Duration.zero),
    ),
    // 보안 저장소 대신 메모리 저장소(플랫폼 채널 없음).
    tokenStoreProvider.overrideWithValue(TokenStore(MemoryKeyValueStore())),
    ...overrides,
  ],
  child: const CustomerApp(),
);

/// 가로 진열 안의 상품을 화면에 보이게 한 뒤 누른다.
Future<void> tapTile(WidgetTester t, String productId) async {
  final tile = find.byKey(ValueKey('tile-$productId')).first;
  await t.ensureVisible(tile);
  await t.pumpAndSettle();
  await t.tap(tile);
  await t.pumpAndSettle();
}
