import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pmart_api_cdc_outbound/pmart_api_cdc_outbound.dart' as co;
import 'package:pmart_api_transport_execution/pmart_api_transport_execution.dart'
    as te;
import 'package:pmart_core/pmart_core.dart';

/// DC 홈 현황(사용자 2026-11-27 "pda 에 dc 작업 대기랑 작업 내역이 안 뜨네") — 서버 값만 센다.
///
/// - 피킹 대기 = 다음 작업 받기(cdc-outbound `next-tasks`)가 내줄 수 있는 것과 같은 기준:
///   시작한 Wave(RELEASED·IN_PROGRESS)의 **담당 없는 CREATED 피킹 작업**(`GET /cdcs/{cdcId}/waves?state=`, `GET /cdcs/{cdcId}/tasks?state=CREATED`).
/// - 분배 대기 = 피킹 끝난 TRF(PICKED), 검품 대기 = 분배 끝난 TRF(SORTED), 상차 대기 = 입차한 운행(transport-execution CHECKED_IN).
/// - 오늘 내역 = 내가 끝낸 작업(`tasks?assigneeId=나&state=DONE`, 끝난 시각이 오늘(서울)) + 지금 들고 있는 작업(ACCEPTED·IN_PROGRESS).
/// 못 읽은 칸은 null(0 으로 꾸미지 않는다).
@immutable
class CdcBoard {
  const CdcBoard({
    required this.pick,
    required this.distribute,
    required this.inspect,
    required this.load,
    required this.done,
    required this.holding,
  });

  final int? pick;
  final int? distribute;
  final int? inspect;
  final int? load;

  /// 오늘 끝낸 작업(최근 순) — null 이면 못 읽음
  final List<CdcWorkItem>? done;

  /// 지금 들고 있는 작업
  final List<CdcWorkItem>? holding;
}

@immutable
class CdcWorkItem {
  const CdcWorkItem({
    required this.taskId,
    required this.kind,
    required this.state,
    this.taskNumber,
    this.trfNumbers = const [],
    this.waveNumber,
    this.completedAt,
    this.qty,
  });

  final String taskId;

  /// PICK·SORT·INSPECT·LOAD
  final String kind;
  final String state;
  final String? taskNumber;
  final List<String> trfNumbers;
  final String? waveNumber;
  final DateTime? completedAt;

  /// 줄 실피킹 합(있을 때)
  final int? qty;
}

abstract interface class CdcBoardRepository {
  Future<CdcBoard> board({required String cdcId, required String workerId});
}

/// 서울 날짜(yyyy-MM-dd)
String _seoulDay(DateTime t) =>
    t.toUtc().add(const Duration(hours: 9)).toIso8601String().substring(0, 10);

final class ApiCdcBoardRepository implements CdcBoardRepository {
  ApiCdcBoardRepository(Dio dio, {DateTime Function()? now})
    : _views = co.PmartApiCdcOutbound(dio: dio).getStaffViewsApi(),
      _tasks = co.PmartApiCdcOutbound(dio: dio).getTasksApi(),
      _trips = te.PmartApiTransportExecution(dio: dio).getTripsApi(),
      _now = now ?? DateTime.now;

  final co.StaffViewsApi _views;
  final co.TasksApi _tasks;
  final te.TripsApi _trips;
  final DateTime Function() _now;

  Future<T?> _try<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on PmartFailure {
      return null;
    }
  }

  Future<List<co.Task>> _allTasks(
    String cdcId, {
    co.TaskState? state,
    String? assigneeId,
  }) async {
    final out = <co.Task>[];
    String? cursor;
    for (var i = 0; i < 10; i++) {
      final r = await pmartGuard(
        () => _tasks.listTasks(
          cdcId: cdcId,
          state: state,
          assigneeId: assigneeId,
          size: 200,
          cursor: cursor,
        ),
      );
      out.addAll(r.data?.items ?? const <co.Task>[]);
      cursor = r.data?.page?.nextCursor;
      if (cursor == null) break;
    }
    return out;
  }

  Future<int> _transfers(String cdcId, String state) async {
    final r = await pmartGuard(
      () => _views.listCenterTransfers(cdcId: cdcId, state: state, size: 200),
    );
    return r.data?.items.length ?? 0;
  }

  Future<int> _pickWaiting(String cdcId) async {
    final waves = <String>{};
    for (final st in [co.WaveState.RELEASED, co.WaveState.IN_PROGRESS]) {
      final r = await pmartGuard(
        () => _views.listCenterWaves(cdcId: cdcId, state: st, size: 200),
      );
      for (final w in r.data?.items ?? const <co.Wave>[]) {
        if (w.waveId case final id?) waves.add(id);
      }
    }
    if (waves.isEmpty) return 0;
    final created = await _allTasks(cdcId, state: co.TaskState.CREATED);
    return created
        .where(
          (t) =>
              t.kind == co.TaskKindEnum.PICK &&
              (t.assigneeId ?? '').isEmpty &&
              waves.contains(t.waveId),
        )
        .length;
  }

  Future<int> _loadWaiting(String cdcId) async {
    final r = await pmartGuard(
      () => _trips.listCenterTrips(
        cdcId: cdcId,
        state: te.TripState.CHECKED_IN,
        size: 200,
      ),
    );
    return r.data?.items.length ?? 0;
  }

  static CdcWorkItem _item(co.Task t) => CdcWorkItem(
    taskId: t.taskId ?? '',
    kind: t.kind?.value ?? '',
    state: t.state?.value ?? '',
    taskNumber: t.taskNumber,
    trfNumbers: [
      ...?t.trfNumbers,
      if ((t.trfNumbers ?? const []).isEmpty) ?t.trfNumber,
    ],
    waveNumber: t.waveNumber,
    completedAt: t.completedAt,
    qty: (t.lines ?? const <co.TaskLinesInner>[]).isEmpty
        ? null
        : (t.lines ?? const <co.TaskLinesInner>[]).fold<int>(
            0,
            (a, l) => a + (l.pickedQty ?? 0),
          ),
  );

  @override
  Future<CdcBoard> board({
    required String cdcId,
    required String workerId,
  }) async {
    final today = _seoulDay(_now());
    final results = await Future.wait<Object?>([
      _try(() => _pickWaiting(cdcId)),
      _try(() => _transfers(cdcId, 'PICKED')),
      _try(() => _transfers(cdcId, 'SORTED')),
      _try(() => _loadWaiting(cdcId)),
      _try(
        () => _allTasks(cdcId, state: co.TaskState.DONE, assigneeId: workerId),
      ),
      _try(
        () async => [
          ...await _allTasks(
            cdcId,
            state: co.TaskState.ACCEPTED,
            assigneeId: workerId,
          ),
          ...await _allTasks(
            cdcId,
            state: co.TaskState.IN_PROGRESS,
            assigneeId: workerId,
          ),
        ],
      ),
    ]);
    final done = results[4] as List<co.Task>?;
    final holding = results[5] as List<co.Task>?;
    return CdcBoard(
      pick: results[0] as int?,
      distribute: results[1] as int?,
      inspect: results[2] as int?,
      load: results[3] as int?,
      done: done == null
          ? null
          : ([
              for (final t in done)
                if (t.completedAt case final at? when _seoulDay(at) == today)
                  _item(t),
            ]..sort((a, b) => b.completedAt!.compareTo(a.completedAt!))),
      holding: holding == null ? null : [for (final t in holding) _item(t)],
    );
  }
}

/// 목: 피킹 대기 2·분배 1·검품 1·상차 1, 오늘 끝낸 작업 2(피킹·분배)
final class MockCdcBoardRepository implements CdcBoardRepository {
  MockCdcBoardRepository({this.latency = const Duration(milliseconds: 200)});

  final Duration latency;

  @override
  Future<CdcBoard> board({
    required String cdcId,
    required String workerId,
  }) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final now = DateTime.now().toUtc();
    return CdcBoard(
      pick: 2,
      distribute: 1,
      inspect: 1,
      load: 1,
      holding: const [],
      done: [
        CdcWorkItem(
          taskId: 'TSK-mock-done-2',
          kind: 'SORT',
          state: 'DONE',
          taskNumber: 'K20482',
          trfNumbers: const ['T482913'],
          waveNumber: 'W2611260001',
          completedAt: now.subtract(const Duration(minutes: 12)),
          qty: 36,
        ),
        CdcWorkItem(
          taskId: 'TSK-mock-done-1',
          kind: 'PICK',
          state: 'DONE',
          taskNumber: 'K20481',
          trfNumbers: const ['T482913', 'T482914'],
          waveNumber: 'W2611260001',
          completedAt: now.subtract(const Duration(minutes: 40)),
          qty: 52,
        ),
      ],
    );
  }
}
