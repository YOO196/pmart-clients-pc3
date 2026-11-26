import 'package:dio/dio.dart';
import 'package:pmart_api_cdc_outbound/pmart_api_cdc_outbound.dart' as co;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../domain/cdc_task.dart';

/// DC 피킹(계약 cdc-outbound 0.21.0 — 작업자 PDA):
/// 다음 작업 받기(`pullNextTask`) → 착수(`startTask`) → 실피킹 결과(`reportPickResult`, 202) → 작업 조회(`getTask`)로 끝났는지 확인.
abstract interface class CdcTaskRepository {
  /// 다음 피킹 작업 받기. 이미 들고 있는 작업이 있으면 그 작업(서버 규칙). 없으면 [CdcNoTask](409 NO_TASK_AVAILABLE).
  Future<CdcNextTask> nextPick({
    required String cdcId,
    required String workerId,
    required IdempotencyKey key,
  });

  /// 착수(ACCEPTED → IN_PROGRESS)
  Future<CdcTask> start({
    required String cdcId,
    required CdcTask task,
    required IdempotencyKey key,
  });

  Future<CdcTask> get({required String cdcId, required String taskId});

  /// 실피킹 결과(202 접수 — 끝났는지는 [get] 으로 확인한다)
  Future<void> reportPick({
    required String cdcId,
    required CdcTask task,
    required String workerId,
    required List<CdcPickLine> lines,
    required IdempotencyKey key,
  });
}

/// 받을 작업 없음(계약 409 code)
const noTaskAvailable = 'NO_TASK_AVAILABLE';

final class ApiCdcTaskRepository implements CdcTaskRepository {
  ApiCdcTaskRepository(Dio dio)
    : _api = co.PmartApiCdcOutbound(dio: dio).getTasksApi();

  final co.TasksApi _api;

  CdcTask _task(co.Task? t) => cdcTaskFromContract(
    t ?? (throw const ContractViolationFailure('Task 없음')),
  );

  @override
  Future<CdcNextTask> nextPick({
    required String cdcId,
    required String workerId,
    required IdempotencyKey key,
  }) async {
    try {
      final r = await pmartGuard(
        () => _api.pullNextTask(
          cdcId: cdcId,
          workerId: workerId,
          idempotencyKey: key.value,
          xSourceSystem: sourceSystem,
          pullNextTaskRequest: co.PullNextTaskRequest(
            kind: co.PullNextTaskRequestKindEnum.PICK,
          ),
          extra: commandOptions(key).extra,
        ),
      );
      return CdcGotTask(_task(r.data));
    } on ProblemFailure catch (f) {
      if (f.problem.code == noTaskAvailable) return const CdcNoTask();
      rethrow;
    }
  }

  @override
  Future<CdcTask> start({
    required String cdcId,
    required CdcTask task,
    required IdempotencyKey key,
  }) async {
    final r = await pmartGuard(
      () => _api.startTask(
        cdcId: cdcId,
        taskId: task.taskId,
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        xExpectedVersion: task.version,
        extra: commandOptions(key, expectedVersion: task.version).extra,
      ),
    );
    return _task(r.data);
  }

  @override
  Future<CdcTask> get({required String cdcId, required String taskId}) async {
    final r = await pmartGuard(
      () => _api.getTask(cdcId: cdcId, taskId: taskId),
    );
    return _task(r.data);
  }

  @override
  Future<void> reportPick({
    required String cdcId,
    required CdcTask task,
    required String workerId,
    required List<CdcPickLine> lines,
    required IdempotencyKey key,
  }) async {
    await pmartGuard(
      () => _api.reportPickResult(
        cdcId: cdcId,
        taskId: task.taskId,
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        xExpectedVersion: task.version,
        reportPickResultRequest: co.ReportPickResultRequest(
          workerId: workerId,
          lines: [
            for (final p in lines)
              co.ReportPickResultRequestLinesInner(
                sku: p.line.sku,
                lot: p.line.lot,
                locationCode: p.line.locationCode,
                pickedQty: p.pickedQty,
                shortQty: p.shortQty > 0 ? p.shortQty : null,
                shortReason: p.shortQty > 0
                    ? co.ReportPickResultRequestLinesInnerShortReasonEnum.values
                          .firstWhere((e) => e.value == p.shortReason)
                    : null,
              ),
          ],
        ),
        extra: commandOptions(key, expectedVersion: task.version).extra,
      ),
    );
  }
}

/// 목: 칠곡 DC 피킹 작업 셋. 같은 키 재전송은 같은 결과.
final class MockCdcTaskRepository implements CdcTaskRepository {
  MockCdcTaskRepository({this.latency = const Duration(milliseconds: 300)}) {
    reset();
  }

  final Duration latency;
  late List<_MockTask> _tasks;
  final _done = <String, Object>{};

  void reset() {
    _done.clear();
    CdcTaskLine line(
      String sku,
      String name,
      String lot,
      String loc,
      int qty,
    ) => CdcTaskLine(
      sku: sku,
      productName: name,
      lot: lot,
      locationCode: loc,
      plannedQty: qty,
      pickedQty: 0,
      shortQty: 0,
    );
    _MockTask task(
      String n,
      String method,
      List<CdcTaskLine> lines, {
      String mode = 'DISCRETE',
      String? region,
    }) => _MockTask(
      CdcTask(
        taskId: 'CTK-mock-$n',
        taskNumber: 'T26112600$n',
        waveNumber: 'W2611260001',
        trfNumbers: ['TRF2611260$n'],
        kind: 'PICK',
        pickMethod: method,
        pickMode: mode,
        regionCode: region,
        zone: 'C',
        floor: '5',
        dueAt: DateTime.utc(2026, 11, 26, 9),
        state: 'CREATED',
        version: 1,
        lines: lines,
      ),
    );
    _tasks = [
      task('1', 'DPS', [
        line('SKU-1001', '서울우유 1L', 'L261120011', 'CDC01-C-5-61-03-2-1', 24),
        line(
          'SKU-1002',
          '맛있는 두부 300g',
          'L261121021',
          'CDC01-C-5-61-04-1-2',
          12,
        ),
      ]),
      task('2', 'LINE', mode: 'SKU_BATCH', [
        line('SKU-2001', '양파 3kg', 'L261122011', 'CDC01-G-5-63-01-3-1', 6),
      ]),
      task('3', 'BOX_PICK', mode: 'REGION_BATCH', region: 'JEONNAM', [
        line('SKU-1003', '생수 2L 6입', 'L261119031', 'CDC01-A-6-12-02-1-1', 10),
      ]),
    ];
  }

  Future<void> _wait() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  _MockTask _find(String id) => _tasks.firstWhere(
    (t) => t.task.taskId == id,
    orElse: () =>
        throw const ProblemFailure(Problem(status: 404, code: 'NOT_FOUND')),
  );

  static Never _conflict(String code) =>
      throw ProblemFailure(Problem(status: 409, code: code));

  @override
  Future<CdcNextTask> nextPick({
    required String cdcId,
    required String workerId,
    required IdempotencyKey key,
  }) async {
    await _wait();
    if (_done[key.value] case final CdcNextTask r) return r;
    final held = _tasks.where(
      (t) => t.assignee == workerId && (t.task.accepted || t.task.inProgress),
    );
    final CdcNextTask r;
    if (held.isNotEmpty) {
      r = CdcGotTask(held.first.task);
    } else {
      final free = _tasks.where((t) => t.task.state == 'CREATED');
      if (free.isEmpty) {
        r = const CdcNoTask();
      } else {
        final t = free.first
          ..assignee = workerId
          ..update(state: 'ACCEPTED');
        r = CdcGotTask(t.task);
      }
    }
    _done[key.value] = r;
    return r;
  }

  @override
  Future<CdcTask> start({
    required String cdcId,
    required CdcTask task,
    required IdempotencyKey key,
  }) async {
    await _wait();
    if (_done[key.value] case final CdcTask r) return r;
    final t = _find(task.taskId);
    if (t.task.accepted) {
      if (t.task.version != task.version) _conflict('VERSION_CONFLICT');
      t.update(state: 'IN_PROGRESS');
    } else if (!t.task.inProgress) {
      _conflict('INVALID_STATE');
    }
    _done[key.value] = t.task;
    return t.task;
  }

  @override
  Future<CdcTask> get({required String cdcId, required String taskId}) async {
    await _wait();
    return _find(taskId).task;
  }

  @override
  Future<void> reportPick({
    required String cdcId,
    required CdcTask task,
    required String workerId,
    required List<CdcPickLine> lines,
    required IdempotencyKey key,
  }) async {
    await _wait();
    if (_done.containsKey(key.value)) return;
    final t = _find(task.taskId);
    if (t.assignee != workerId) _conflict('NOT_ASSIGNEE');
    if (!t.task.inProgress) _conflict('INVALID_STATE');
    if (t.task.version != task.version) _conflict('VERSION_CONFLICT');
    final next = [
      for (final row in t.task.lines)
        switch (lines.where((p) => p.line.key == row.key).firstOrNull) {
          null => row,
          final p when p.pickedQty + p.shortQty > row.remaining => _conflict(
            'PICK_EXCEEDS_ALLOCATION',
          ),
          final p => CdcTaskLine(
            sku: row.sku,
            productName: row.productName,
            lot: row.lot,
            locationCode: row.locationCode,
            plannedQty: row.plannedQty,
            pickedQty: row.pickedQty + p.pickedQty,
            shortQty: row.shortQty + p.shortQty,
          ),
        },
    ];
    final allDone = next.every((r) => r.remaining == 0);
    t.update(
      lines: next,
      state: allDone
          ? (next.any((r) => r.shortQty > 0) ? 'PARTIAL' : 'DONE')
          : null,
    );
    _done[key.value] = true;
  }
}

final class _MockTask {
  _MockTask(this.task);

  CdcTask task;
  String? assignee;

  void update({String? state, List<CdcTaskLine>? lines}) {
    final t = task;
    task = CdcTask(
      taskId: t.taskId,
      taskNumber: t.taskNumber,
      waveNumber: t.waveNumber,
      trfNumbers: t.trfNumbers,
      kind: t.kind,
      pickMethod: t.pickMethod,
      zone: t.zone,
      floor: t.floor,
      dueAt: t.dueAt,
      state: state ?? t.state,
      version: t.version + 1,
      lines: lines ?? t.lines,
      pickMode: t.pickMode,
      regionCode: t.regionCode,
    );
  }
}
