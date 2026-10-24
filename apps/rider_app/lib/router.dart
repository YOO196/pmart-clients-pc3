import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/delivery/presentation/delivery_screen.dart';
import 'features/offers/presentation/offers_screen.dart';

/// 라우트. 라이더 로그인(BR-02) 리다이렉트·알림 딥링크는 계약 반영 뒤 붙인다.
final routerProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const OffersScreen()),
      GoRoute(
        path: '/deliveries/:deliveryId',
        builder: (_, s) =>
            DeliveryScreen(deliveryId: s.pathParameters['deliveryId']!),
      ),
    ],
  ),
);
