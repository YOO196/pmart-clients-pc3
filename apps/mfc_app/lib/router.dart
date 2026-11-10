import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/handover/presentation/handover_screens.dart';
import 'features/inbound/presentation/inbound_screen.dart';
import 'features/quality/presentation/quality_screens.dart';
import 'features/packing/presentation/packing_screen.dart';
import 'features/tasks/presentation/tasks_screen.dart';
import 'features/work/domain/work.dart';
import 'features/work/presentation/work_screens.dart';
import 'shared/printer/printer_ui.dart';

/// 라우트. 점원 로그인(BR-02) 리다이렉트는 계약 반영 뒤 붙인다.
/// 크루는 작업 목록을 보지 않는다(2026-11-10) — 메인 → 업무 안내 → 서버가 준 작업 하나.
final routerProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: '/work/:area',
        redirect: (_, s) =>
            WorkArea.fromName(s.pathParameters['area']) == null ? '/' : null,
        builder: (_, s) => WorkSessionScreen(
          area: WorkArea.fromName(s.pathParameters['area'])!,
        ),
        routes: [
          GoRoute(
            path: 'guide',
            builder: (_, s) => WorkGuideScreen(
              area: WorkArea.fromName(s.pathParameters['area'])!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/inbound/:trfId',
        builder: (_, s) =>
            InboundReceiveScreen(trfId: s.pathParameters['trfId']!),
      ),
      GoRoute(
        path: '/quality/inspect/:taskId',
        builder: (_, s) => InspectScreen(taskId: s.pathParameters['taskId']!),
      ),
      GoRoute(
        path: '/quality/return/:id',
        builder: (_, s) =>
            ReturnInspectScreen(returnReceiptId: s.pathParameters['id']!),
      ),
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
