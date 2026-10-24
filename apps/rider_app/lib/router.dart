import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/offers/presentation/offers_screen.dart';

/// 라우트. 로그인 리다이렉트·딥링크(알림 → 화면)는 C1 에서 붙인다.
final routerProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    initialLocation: '/',
    routes: [GoRoute(path: '/', builder: (_, _) => const OffersScreen())],
  ),
);
