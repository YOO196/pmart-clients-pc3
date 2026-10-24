import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers.dart';
import '../../../shared/ui_state_of.dart';
import '../data/mock_task_repository.dart';
import '../data/task_repository.dart';
import '../domain/task_list.dart';

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockTaskRepository(),
    PmartEnv.local => ApiTaskRepository(ref.watch(dioProvider)),
  },
);

/// 근무 센터. 점원 로그인(BR-02) 뒤 세션의 centerScope 로 바꾼다.
final currentMfcIdProvider = Provider<String>((_) => 'MFC-MOCK-01');

final myTasksProvider = FutureProvider<TaskList>(
  (ref) => ref
      .watch(taskRepositoryProvider)
      .myTasks(ref.watch(currentMfcIdProvider)),
);

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mock = ref.watch(envProvider) == PmartEnv.mock;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tasksTitle),
        actions: [
          if (mock)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(label: Text(l10n.mockModeBadge)),
            ),
        ],
      ),
      body: UiStateView<TaskList>(
        state: uiStateOf(
          ref.watch(myTasksProvider),
          isEmpty: (l) => l.tasks.isEmpty,
        ),
        onRetry: () => ref.invalidate(myTasksProvider),
        empty: (_) => Center(child: Text(l10n.tasksEmpty)),
        ready: (context, list) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!list.assignmentFresh)
              ListTile(
                key: const ValueKey('assignment-stale'),
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.assignmentStale),
              ),
            for (final task in list.tasks)
              Card(
                key: ValueKey('task-${task.taskId}'),
                child: ListTile(
                  title: Text(switch (task.kind) {
                    TaskKind.pick => l10n.taskTypePick,
                    TaskKind.pack => l10n.taskTypePack,
                    TaskKind.dispatch => l10n.taskTypeDispatch,
                  }),
                  subtitle: Text(
                    [
                      switch (task.remainingQty) {
                        final int q => l10n.taskRemaining(q),
                        null => l10n.taskRemainingUnknown,
                      },
                      l10n.taskStateLabel(task.state),
                    ].join('\n'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
