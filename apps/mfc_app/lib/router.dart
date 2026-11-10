import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/handover/presentation/handover_screens.dart';
import 'features/packing/presentation/packing_screen.dart';
import 'features/tasks/presentation/tasks_screen.dart';
import 'shared/printer/printer_ui.dart';

/// 라우트. 점원 로그인(BR-02) 리다이렉트는 계약 반영 뒤 붙인다.
final routerProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const TasksScreen()),
      GoRoute(
        path: '/settings/printer',
        builder: (_, _) => const PrinterSettingsScreen(),
      ),
      GoRoute(
        path: '/handover-checks',
        builder: (_, _) => const HandoverChecksScreen(),
      ),
      GoRoute(
        path: '/packages/:packageId/handover',
        builder: (_, s) => PackageHandoverScreen(
          packageId: s.pathParameters['packageId']!,
          scannedVersion: int.tryParse(s.uri.queryParameters['scanned'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/tasks/:taskId',
        builder: (_, s) =>
            TaskDetailScreen(taskId: s.pathParameters['taskId']!),
        routes: [
          GoRoute(
            path: 'pick',
            builder: (_, s) =>
                PickingScreen(taskId: s.pathParameters['taskId']!),
          ),
          GoRoute(
            path: 'pack',
            builder: (_, s) =>
                PackingScreen(taskId: s.pathParameters['taskId']!),
          ),
        ],
      ),
    ],
  ),
);
