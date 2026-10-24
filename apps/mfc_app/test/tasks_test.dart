import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:mfc_app/app.dart';
import 'package:mfc_app/features/tasks/data/mock_task_repository.dart';
import 'package:mfc_app/features/tasks/data/task_repository.dart';
import 'package:mfc_app/features/tasks/presentation/tasks_screen.dart';
import 'package:mfc_app/shared/providers.dart';

Widget _app(List<Override> overrides) => ProviderScope(
  retry: (_, _) => null,
  overrides: [envProvider.overrideWithValue(PmartEnv.mock), ...overrides],
  child: const MfcApp(),
);

TaskRepository _repoWith(FakeAdapter adapter) => ApiTaskRepository(
  createPmartDio(
    baseUrl: 'http://test.invalid/api/v1',
    sourceSystem: sourceSystem,
    tokens: TokenStore(MemoryKeyValueStore()),
    refresher: (_) async => null,
    adapter: adapter,
    delay: (_) async {},
  ),
);

void main() {
  setUpAll(initPmartFormatting);

  testWidgets('목 모드로 기동하면 내 작업 목록이 보인다', (t) async {
    await t.pumpWidget(
      _app([
        taskRepositoryProvider.overrideWithValue(
          MockTaskRepository(latency: Duration.zero),
        ),
      ]),
    );
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('task-task-mock-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-task-mock-2')), findsOneWidget);
    expect(find.textContaining('남은 수량 5'), findsOneWidget);
    expect(find.byKey(const ValueKey('assignment-stale')), findsNothing);
  });

  test('GET /tasks 에 mfcId·assignee=me 를 보내고 응답을 domain 으로 바꾼다', () async {
    final adapter = FakeAdapter(
      (_, _) async => const FakeReply(200, body: MockTaskRepository.fixture),
    );
    final list = await _repoWith(adapter).myTasks('MFC-MOCK-01');

    expect(list.tasks.map((t) => t.taskId), ['task-mock-1', 'task-mock-2']);
    expect(list.assignmentFresh, isTrue);
    final uri = adapter.requests.single.uri;
    expect(uri.path, '/api/v1/tasks');
    expect(uri.queryParameters, {
      'mfcId': 'MFC-MOCK-01',
      'assignee': 'me',
      'size': '50',
    });
    expect(adapter.requests.single.headers['X-Source-System'], 'mfc-app');
  });

  test('담당자 사본이 STALE 이면 최신 아님으로 표시한다', () async {
    final adapter = FakeAdapter(
      (_, _) async => FakeReply(
        200,
        body: {
          ...MockTaskRepository.fixture,
          'asOf': {'asOf': '2026-10-24T06:05:00Z', 'freshness': 'STALE'},
        },
      ),
    );
    final list = await _repoWith(adapter).myTasks('MFC-MOCK-01');
    expect(list.assignmentFresh, isFalse);
  });

  test('계약에 없는 작업 유형은 조용히 넘기지 않는다', () async {
    final adapter = FakeAdapter(
      (_, _) async => const FakeReply(
        200,
        body: {
          'items': [
            {'taskId': 't', 'taskType': 'LOAD', 'state': 'READY'},
          ],
        },
      ),
    );
    await expectLater(
      _repoWith(adapter).myTasks('MFC-MOCK-01'),
      throwsA(isA<ContractViolationFailure>()),
    );
  });
}
