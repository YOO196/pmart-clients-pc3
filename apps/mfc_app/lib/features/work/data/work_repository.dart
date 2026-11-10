import 'package:dio/dio.dart';
import 'package:pmart_api_mfc_capacity/pmart_api_mfc_capacity.dart' as cap;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../domain/work.dart';

abstract interface class WorkRepository {
  /// 작업자 본인(권한·휴게). `GET /mfcs/{mfcId}/workers/{workerId}` — 본인 조회 허용은 BR-52.
  Future<WorkerProfile> me(String mfcId, String workerId);

  /// 다음 작업 받기. 들고 있는 작업이 있으면 그것을 돌려준다.
  /// 고른 업무로 거르는 값은 계약에 없다(BR-52) — 목만 업무로 거른다.
  Future<NextTaskOutcome> next(
    String mfcId,
    String workerId,
    WorkArea area, {
    required IdempotencyKey key,
  });

  Future<void> startBreak(
    String mfcId,
    String workerId, {
    required IdempotencyKey key,
  });

  Future<void> endBreak(
    String mfcId,
    String workerId, {
    required IdempotencyKey key,
  });
}

final class ApiWorkRepository implements WorkRepository {
  ApiWorkRepository(Dio dio)
    : _workers = cap.PmartApiMfcCapacity(dio: dio).getWorkersApi();

  final cap.WorkersApi _workers;

  @override
  Future<WorkerProfile> me(String mfcId, String workerId) async {
    final res = await pmartGuard(
      () => _workers.getWorker(mfcId: mfcId, workerId: workerId),
    );
    final w =
        res.data ?? (throw const ContractViolationFailure('WorkerDetail 없음'));
    return WorkerProfile(
      workerId: w.workerId ?? workerId,
      displayName: w.displayName,
      allowedTaskTypes: {
        for (final t in w.effectiveTaskTypes ?? const <cap.TaskType>[]) t.value,
      },
      active: w.state == null || w.state!.value == 'ACTIVE',
      onBreak: w.onBreak ?? false,
    );
  }

  @override
  Future<NextTaskOutcome> next(
    String mfcId,
    String workerId,
    WorkArea area, {
    required IdempotencyKey key,
  }) async {
    try {
      final res = await pmartGuard(
        () => _workers.pullNextTask(
          mfcId: mfcId,
          workerId: workerId,
          idempotencyKey: key.value,
          xSourceSystem: sourceSystem,
          extra: commandOptions(key).extra,
        ),
      );
      final a = res.data;
      if (a == null) return const NextUnknown();
      return NextAssigned(assignedTaskFromContract(a));
    } on PmartFailure catch (f) {
      return switch (f) {
        UnknownResultFailure() => const NextUnknown(),
        ProblemFailure(:final problem)
            when problem.code == ProblemCode.idempotencyConflict &&
                problem.retryable =>
          const NextUnknown(),
        ProblemFailure(:final problem) => NextUnavailable(problem.code),
        _ => throw f,
      };
    }
  }

  @override
  Future<void> startBreak(
    String mfcId,
    String workerId, {
    required IdempotencyKey key,
  }) => pmartGuard(
    () => _workers.startWorkerBreak(
      mfcId: mfcId,
      workerId: workerId,
      idempotencyKey: key.value,
      xSourceSystem: sourceSystem,
      extra: commandOptions(key).extra,
    ),
  );

  @override
  Future<void> endBreak(
    String mfcId,
    String workerId, {
    required IdempotencyKey key,
  }) => pmartGuard(
    () => _workers.endWorkerBreak(
      mfcId: mfcId,
      workerId: workerId,
      idempotencyKey: key.value,
      xSourceSystem: sourceSystem,
      extra: commandOptions(key).extra,
    ),
  );
}

AssignedTask assignedTaskFromContract(cap.Assignment a) {
  final d = a.detail;
  return AssignedTask(
    taskId: a.taskId ?? (throw const ContractViolationFailure('taskId 없음')),
    taskType:
        a.taskType ?? (throw const ContractViolationFailure('taskType 없음')),
    detailAvailable: d?.available ?? false,
    promisedReadyAt: d?.promisedReadyAt,
    urgent: d?.urgent ?? false,
    lines: [
      for (final l in d?.lines ?? const <cap.NextTaskDetailLinesInner>[])
        AssignedLine(
          productName: l.productName,
          sku: l.sku,
          qty: l.qty,
          fromLocation: l.fromLocation,
          toLocation: l.toLocation,
          notice: l.notice,
        ),
    ],
  );
}
