import 'package:pmart_api_mfc_fulfillment/pmart_api_mfc_fulfillment.dart';

import '../domain/task_list.dart';
import 'task_repository.dart';

/// 목 구현. 계약(`mfc-fulfillment-service.yaml` listTasks) 모양 JSON 을 생성 모델로 읽는다.
final class MockTaskRepository implements TaskRepository {
  MockTaskRepository({this.latency = const Duration(milliseconds: 300)});

  final Duration latency;

  static const fixture = <String, Object?>{
    'items': [
      {
        'taskId': 'task-mock-1',
        'taskType': 'PICK',
        'state': 'ASSIGNED',
        'version': 1,
        'mfcId': 'MFC-MOCK-01',
        'fulfillmentId': 'ful-1',
        'shipmentId': 'shp-1',
        'assignment': {'workerId': 'worker-mock-1', 'assignmentVersion': 2},
        'lineCount': 4,
        'plannedQty': 7,
        'completedQty': 2,
        'remainingQty': 5,
        'promisedReadyAt': '2026-10-24T06:20:00Z',
        'createdAt': '2026-10-24T06:00:00Z',
      },
      {
        'taskId': 'task-mock-2',
        'taskType': 'PACK',
        'state': 'IN_PROGRESS',
        'remainingQty': 1,
      },
    ],
    'page': {'nextCursor': null, 'size': 50},
    'asOf': {'asOf': '2026-10-24T06:05:00Z', 'freshness': 'CURRENT'},
  };

  @override
  Future<TaskList> myTasks(String mfcId) async {
    await Future<void>.delayed(latency);
    return taskListFromContract(ListTasks200Response.fromJson(fixture));
  }
}
