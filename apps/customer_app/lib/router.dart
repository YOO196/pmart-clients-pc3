import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/address/presentation/address_screens.dart';
import 'features/auth/domain/auth.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/cart/presentation/cart_screen.dart';
import 'features/checkout/presentation/delivery_select_screen.dart';
import 'features/checkout/presentation/order_sheet_screen.dart';
import 'features/claims/presentation/claims_screens.dart';
import 'features/catalog/presentation/category_screen.dart';
import 'features/payment/presentation/payment_screen.dart';
import 'features/profile/presentation/phone_screen.dart';
import 'features/orders/presentation/my_screen.dart';
import 'features/orders/presentation/orders_screens.dart';
import 'features/catalog/presentation/home_screen.dart';
import 'features/catalog/presentation/product_detail_screen.dart';
import 'features/catalog/presentation/product_list_screen.dart';
import 'features/catalog/presentation/search_screen.dart';
import 'l10n/gen/app_localizations.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// 라우트. 탭은 각자 내비게이션 스택을 가진다(탭을 오가도 검색어·스크롤이 남는다).
/// 상품 상세는 탭 위로 올린다. 로그인 리다이렉트·딥링크(알림 → 화면)는 로그인 단계에서 붙인다.
final routerProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _TabShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/categories',
                builder: (_, _) => const CategoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/cart', builder: (_, _) => const CartScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/my', builder: (_, _) => const MyScreen())],
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/checkout/delivery',
        builder: (_, _) => const DeliverySelectScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/checkout',
        builder: (_, _) => const OrderSheetScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/payments/:draftId',
        builder: (_, state) =>
            PaymentScreen(draftId: state.pathParameters['draftId']!),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/orders',
        builder: (_, _) => const OrderListScreen(),
        routes: [
          GoRoute(
            parentNavigatorKey: rootNavigatorKey,
            path: ':orderId',
            builder: (_, state) =>
                OrderDetailScreen(orderId: state.pathParameters['orderId']!),
            routes: [
              GoRoute(
                parentNavigatorKey: rootNavigatorKey,
                path: 'cancel',
                builder: (_, state) =>
                    CancelScreen(orderId: state.pathParameters['orderId']!),
              ),
              GoRoute(
                parentNavigatorKey: rootNavigatorKey,
                path: 'reschedule',
                builder: (_, state) =>
                    RescheduleScreen(orderId: state.pathParameters['orderId']!),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/deliveries/:deliveryId',
        builder: (_, state) =>
            TrackingScreen(deliveryId: state.pathParameters['deliveryId']!),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/claims/:claimId',
        builder: (_, state) =>
            ClaimScreen(claimId: state.pathParameters['claimId']!),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/login',
        builder: (_, state) => LoginScreen(
          purpose: state.uri.queryParameters['purpose'] == 'checkout'
              ? LoginPurpose.checkout
              : LoginPurpose.general,
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/me/phone',
        builder: (_, state) =>
            PhoneScreen(signup: state.uri.queryParameters['from'] == 'signup'),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/addresses',
        builder: (_, _) => const AddressListScreen(),
        routes: [
          GoRoute(
            parentNavigatorKey: rootNavigatorKey,
            path: 'new',
            builder: (_, _) => const AddressFormScreen(),
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/products',
        builder: (_, state) => ProductListScreen(
          categoryId: state.uri.queryParameters['categoryId'] ?? '',
          title: state.uri.queryParameters['title'],
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/products/:productId',
        builder: (_, state) =>
            ProductDetailScreen(productId: state.pathParameters['productId']!),
      ),
    ],
  ),
);

class _TabShell extends StatelessWidget {
  const _TabShell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            label: l10n.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.category_outlined),
            label: l10n.navCategory,
          ),
          NavigationDestination(
            icon: const Icon(Icons.search),
            label: l10n.navSearch,
          ),
          NavigationDestination(
            icon: const Icon(Icons.shopping_cart_outlined),
            label: l10n.navCart,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            label: l10n.navMy,
          ),
        ],
      ),
    );
  }
}
