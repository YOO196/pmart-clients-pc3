import 'package:dio/dio.dart';
import 'package:pmart_api_mfc_fulfillment/pmart_api_mfc_fulfillment.dart';
import 'package:pmart_core/pmart_core.dart';

import '../domain/task_list.dart';

abstract interface class TaskRepository {
  /// 내 작업(state 생략 = ASSIGNED, IN_PROGRESS). 실패는 [PmartFailure].
  Future<TaskList> myTasks(String mfcId);
}

/// 실서버 구현(`GET /tasks?mfcId=&assignee=me`). `assignee=me` 는 BR-02(점원 로그인) 전에는 동작하지 않는다.
final class ApiTaskRepository implements TaskRepository {
  ApiTaskRepository(Dio dio)
    : _tasks = PmartApiMfcFulfillment(dio: dio).getTasksApi();

  final TasksApi _tasks;

  @override
  Future<TaskList> myTasks(String mfcId) async {
    final res = await pmartGuard(
      () => _tasks.listTasks(mfcId: mfcId, assignee: 'me'),
    );
    final body = res.data;
    if (body == null) throw const ContractViolationFailure('listTasks 본문 없음');
    return taskListFromContract(body);
  }
}

TaskList taskListFromContract(ListTasks200Response body) {
  final items = body.items;
  if (items == null) {
    throw const ContractViolationFailure('listTasks.items 없음');
  }
  return TaskList(
    assignmentFresh:
        body.asOf?.freshness == ListTasks200ResponseAsOfFreshnessEnum.CURRENT,
    tasks: [
      for (final t in items)
        TaskItem(
          taskId:
              t.taskId ??
              (throw const ContractViolationFailure('TaskSummary.taskId 없음')),
          kind: switch (t.taskType) {
            TaskType.PICK => TaskKind.pick,
            TaskType.PACK => TaskKind.pack,
            TaskType.DISPATCH => TaskKind.dispatch,
            null => throw const ContractViolationFailure(
              'TaskSummary.taskType 없음',
            ),
          },
          state:
              t.state?.value ??
              (throw const ContractViolationFailure('TaskSummary.state 없음')),
          remainingQty: t.remainingQty,
        ),
    ],
  );
}
