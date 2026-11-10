import 'package:pmart_core/pmart_core.dart';

import '../../../shared/field_outcome.dart';
import '../../stock_move/data/mock_stock_move_repository.dart';
import '../domain/quality.dart';
import 'quality_repository.dart';

/// 목: 품질검사 작업 1건(요거트 12개). 검사하면 정상 결과마다 적치 작업을 만든다. 회수품 검수는 바로 반영.
final class MockQualityRepository implements QualityRepository {
  MockQualityRepository({
    this.latency = const Duration(milliseconds: 300),
    this.returns,
  }) {
    _tasks['TSK-INS-mock-1'] = const InboundTaskView(
      taskId: 'TSK-INS-mock-1',
      kind: InboundTaskKind.inspect,
      receiptId: 'rcp-seed-1',
      sku: 'E-00000002',
      lotId: 'LOT-Y-1110',
      locationCode: 'RCV-C-01',
      plannedQty: 12,
      doneQty: 0,
      completed: false,
      version: 1,
    );
  }

  final Duration latency;

  /// 회수품 검수가 반입 기록을 INSPECTED 로 바꾸게 잇는다.
  final MockStockMoveRepository? returns;

  /// 다음 응답을 1회 잃는다(서버는 반영함).
  bool loseNextResponse = false;
  int inspectCalls = 0;
  final inspectedReturns = <String, List<ReturnInspectionLine>>{};
  final _tasks = <String, InboundTaskView>{};
  final _done = <String, FieldOutcome<InboundTaskExecutionView>>{};
  final _returns = <String, String>{};
  int _seq = 0;

  Future<void> _wait() => Future<void>.delayed(latency);

  InboundTaskView? task(String id) => _tasks[id];

  @override
  Future<List<InboundTaskView>> inboundTasks(
    String mfcId, {
    InboundTaskKind? kind,
    bool completed = false,
  }) async {
    await _wait();
    return [
      for (final t in _tasks.values)
        if (t.completed == completed && (kind == null || t.kind == kind)) t,
    ];
  }

  InboundTaskView _advance(InboundTaskView t, int qty) => InboundTaskView(
    taskId: t.taskId,
    kind: t.kind,
    receiptId: t.receiptId,
    parentTaskId: t.parentTaskId,
    sku: t.sku,
    lotId: t.lotId,
    locationCode: t.locationCode,
    plannedQty: t.plannedQty,
    doneQty: t.doneQty + qty,
    completed: t.doneQty + qty >= t.plannedQty,
    version: t.version + 1,
  );

  @override
  Future<FieldOutcome<InboundTaskExecutionView>> inspect(
    String taskId,
    List<InspectionResult> results, {
    required IdempotencyKey key,
  }) async {
    await _wait();
    inspectCalls++;
    if (_done[key.value] case final o?) return o;
    final t = _tasks[taskId];
    if (t == null) return const FieldRejected(ProblemCode.notFound);
    final sum = results.fold(0, (s, r) => s + r.qty);
    if (t.completed || sum > t.remainingQty) {
      return const FieldRejected(ProblemCode.invalidState);
    }
    final created = <String>[];
    for (final r in results.where((r) => !r.quarantined)) {
      final id = 'TSK-PUT-mock-${++_seq}';
      created.add(id);
      _tasks[id] = InboundTaskView(
        taskId: id,
        kind: InboundTaskKind.putaway,
        receiptId: t.receiptId,
        parentTaskId: t.taskId,
        sku: t.sku,
        lotId: '${t.lotId}-${r.sourceLotRef ?? _seq}',
        locationCode: t.locationCode,
        plannedQty: r.qty,
        doneQty: 0,
        completed: false,
        version: 1,
      );
    }
    final next = _advance(t, sum);
    _tasks[taskId] = next;
    final o = FieldDone(
      InboundTaskExecutionView(
        executionId: 'exe-${++_seq}',
        task: next,
        commitId: 'commit-$_seq',
        createdTaskIds: created,
      ),
    );
    _done[key.value] = o;
    if (loseNextResponse) {
      loseNextResponse = false;
      return const FieldUnknown();
    }
    return o;
  }

  @override
  Future<FieldOutcome<InboundTaskExecutionView>> putaway(
    String taskId, {
    required String toLocationCode,
    required int qty,
    required IdempotencyKey key,
  }) async {
    await _wait();
    if (_done[key.value] case final o?) return o;
    final t = _tasks[taskId];
    if (t == null) return const FieldRejected(ProblemCode.notFound);
    if (t.completed || qty > t.remainingQty) {
      return const FieldRejected(ProblemCode.invalidState);
    }
    final next = _advance(t, qty);
    _tasks[taskId] = next;
    final o = FieldDone(
      InboundTaskExecutionView(
        executionId: 'exe-${++_seq}',
        task: next,
        commitId: 'commit-$_seq',
      ),
    );
    _done[key.value] = o;
    return o;
  }

  @override
  Future<FieldOutcome<String?>> inspectReturn({
    required String mfcId,
    required String claimId,
    required String returnReceiptId,
    required String inspectedBy,
    required List<ReturnInspectionLine> lines,
    required IdempotencyKey key,
  }) async {
    await _wait();
    if (_returns[key.value] case final id?) return FieldDone(id);
    if (lines.any(
      (l) => l.verdict == ReturnVerdict.resale && !l.resaleAllowed,
    )) {
      return const FieldRejected(QualityProblemCode.resaleNotAllowed);
    }
    final id = 'RIN-mock-${++_seq}';
    _returns[key.value] = id;
    inspectedReturns[returnReceiptId] = lines;
    returns?.markInspected(returnReceiptId);
    return FieldDone(id);
  }

  @override
  Future<({String id, String applyStatus, int resaleQty, int disposeQty})>
  returnInspection(String returnInspectionId) async {
    await _wait();
    return (
      id: returnInspectionId,
      applyStatus: 'APPLIED',
      resaleQty: 0,
      disposeQty: 0,
    );
  }
}
