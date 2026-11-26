import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:mfc_app/app.dart';
import 'package:mfc_app/features/auth/data/auth_repository.dart';
import 'package:mfc_app/features/auth/domain/employee_auth.dart';
import 'package:mfc_app/features/auth/presentation/auth_controller.dart';
import 'package:mfc_app/features/tasks/data/mock_task_repository.dart';
import 'package:mfc_app/features/tasks/presentation/task_controllers.dart';
import 'package:mfc_app/features/work/data/mock_work_repository.dart';
import 'package:mfc_app/features/work/presentation/work_controller.dart';
import 'package:mfc_app/shared/providers.dart';

/// DC 직원은 로그인하면 DC 업무 메뉴가 뜨고 MFC 업무·도구는 없다(사용자 2026-11-26).
void main() {
  setUpAll(initPmartFormatting);

  Future<void> pump(WidgetTester t, EmployeeSession session) async {
    t.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final tasks = MockTaskRepository(latency: Duration.zero);
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          envProvider.overrideWithValue(PmartEnv.mock),
          authRepositoryProvider.overrideWithValue(
            MockAuthRepository(session: session),
          ),
          taskRepositoryProvider.overrideWithValue(tasks),
          workRepositoryProvider.overrideWithValue(
            MockWorkRepository(tasks: tasks, latency: Duration.zero),
          ),
          secureStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        ],
        child: const MfcApp(),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('DC 작업자 — DC 업무 다섯 가지, MFC 업무·도구 없음', (t) async {
    await pump(
      t,
      const EmployeeSession(
        operatorId: 'OP-cdcw-fc-01',
        roles: [EmployeeSession.cdcWorkerRole],
        centers: ['CDC01'],
      ),
    );
    expect(find.byKey(const ValueKey('cdc-home')), findsOneWidget);
    expect(find.textContaining('DC CDC01', findRichText: true), findsOneWidget);
    for (final k in ['pick', 'distribute', 'inspect', 'load']) {
      expect(find.byKey(ValueKey('cdc-area-$k')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('area-pickPack')), findsNothing);
    expect(find.byKey(const ValueKey('menu-handover')), findsNothing);
    expect(find.byKey(const ValueKey('manage-menu')), findsNothing);

    // 업무를 누르면 MFC 처럼 순서 안내 → 시작하기
    await t.tap(find.byKey(const ValueKey('cdc-area-load')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('cdc-guide')), findsOneWidget);
    expect(find.byKey(const ValueKey('cdc-guide-step-4')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('cdc-guide-ok')));
    await t.pumpAndSettle();
    // 상차는 도크부터(C-01)
    expect(find.byKey(const ValueKey('cdc-dock-scan')), findsOneWidget);
  });

  testWidgets('DC 관리자도 DC 메뉴', (t) async {
    await pump(
      t,
      const EmployeeSession(
        operatorId: 'OP-cdc-sup',
        roles: [EmployeeSession.cdcSupervisorRole],
        centers: ['CDC01'],
      ),
    );
    expect(find.byKey(const ValueKey('cdc-home')), findsOneWidget);
    expect(find.byKey(const ValueKey('manage-menu')), findsNothing);
  });

  testWidgets('MFC 작업자는 그대로 MFC 홈', (t) async {
    await pump(t, MockAuthRepository.mockSession);
    expect(find.byKey(const ValueKey('cdc-home')), findsNothing);
    expect(find.byKey(const ValueKey('area-pickPack')), findsOneWidget);
  });

  test('목 로그인 — DC 시험 계정은 DC 역할·센터', () async {
    final repo = MockPasswordAuthRepository();
    final w = await repo.loginWithPassword(
      loginId: 'cdcw-fk-03',
      password: 'x',
    );
    expect(w.roles, [EmployeeSession.cdcWorkerRole]);
    expect(w.centers, ['CDC01']);
    expect(w.isCdc, isTrue);
    final s = await repo.loginWithPassword(
      loginId: 'claude-cdc-sup',
      password: 'x',
    );
    expect(s.roles, [EmployeeSession.cdcSupervisorRole]);
    expect(
      () => repo.loginWithPassword(loginId: 'cdcw-fk-04', password: 'x'),
      throwsA(isA<LoginFailure>()),
    );
    final m = await repo.loginWithPassword(
      loginId: 'mfcw-pp-01',
      password: 'x',
    );
    expect(m.isCdc, isFalse);
  });

  testWidgets('목 앱 로그인 화면에서 cdcw-fc-01 로 들어가면 DC 홈', (t) async {
    t.view
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          envProvider.overrideWithValue(PmartEnv.mock),
          authRepositoryProvider.overrideWithValue(
            MockPasswordAuthRepository(),
          ),
          secureStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        ],
        child: const MfcApp(),
      ),
    );
    await t.pumpAndSettle();
    final start = find.byKey(const ValueKey('start-login'));
    if (start.evaluate().isNotEmpty) {
      await t.tap(start);
      await t.pumpAndSettle();
    }
    await t.tap(find.byKey(const ValueKey('employee-login')));
    await t.pumpAndSettle();
    // 폰 키보드가 첫 글자를 대문자로 바꿔도 들어간다
    await t.enterText(find.byKey(const ValueKey('login-id')), 'Cdcw-fc-01 ');
    await t.enterText(find.byKey(const ValueKey('login-password')), 'x');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('mock-signin-submit')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('cdc-home')), findsOneWidget);
  });

  testWidgets('DC·MFC 두 권한이면 작업장부터 고른다 — DC/MFC 홈, 위 바꾸기로 다시 고르기', (t) async {
    await pump(
      t,
      const EmployeeSession(
        operatorId: 'OP-both',
        roles: [EmployeeSession.mfcWorkerRole, EmployeeSession.cdcWorkerRole],
        centers: ['MFC-MOCK-01', 'CDC01'],
      ),
    );
    expect(find.byKey(const ValueKey('workplace-choice')), findsOneWidget);
    expect(find.textContaining('CDC01'), findsOneWidget);
    expect(find.textContaining('MFC-MOCK-01'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('workplace-dc')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('cdc-home')), findsOneWidget);
    // DC 홈의 센터는 DC 센터만
    expect(find.textContaining('DC CDC01', findRichText: true), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('switch-workplace')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('workplace-mfc')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('cdc-home')), findsNothing);
    expect(find.byKey(const ValueKey('menu-handover')), findsOneWidget);
    expect(find.byKey(const ValueKey('switch-workplace')), findsOneWidget);
  });

  test('목 로그인 dcmfc-all — DC·MFC 두 권한·두 센터', () async {
    final s = await MockPasswordAuthRepository().loginWithPassword(
      loginId: MockPasswordAuthRepository.bothAccount,
      password: 'x',
    );
    expect(
      [s.hasBoth, s.cdcCenters, s.mfcCenters.isNotEmpty],
      [
        true,
        ['CDC01'],
        true,
      ],
    );
  });
}
