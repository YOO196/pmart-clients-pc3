import 'package:flutter/foundation.dart';

enum TaskKind { pick, pack, dispatch }

/// `GET /tasks` 결과(화면용).
@immutable
class TaskList {
  const TaskList({required this.tasks, required this.assignmentFresh});

  final List<TaskItem> tasks;

  /// 담당자 정보 사본이 CURRENT 인지. 아니면 "최신이 아닐 수 있음"을 표시한다.
  /// 시작 가능 여부는 목록이 아니라 `POST /tasks/{id}/starts` 판정만 믿는다(BR-05 회신).
  final bool assignmentFresh;
}

@immutable
class TaskItem {
  const TaskItem({
    required this.taskId,
    required this.kind,
    required this.state,
    required this.remainingQty,
  });

  final String taskId;
  final TaskKind kind;

  /// 계약 TaskState 코드 그대로(표시 문구 매핑은 C2).
  final String state;
  final int? remainingQty;
}
