import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_api_mfc_capacity/pmart_api_mfc_capacity.dart' as cap;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart';

/// 내 업무 내역(mfc-capacity 0.17.0 `GET /mfcs/{mfcId}/workers/me/activities?date=`, F-7 R3·R4 —
/// 회신 2026-11-17 stock-check-and-work-history-impl). 피킹·포장·복귀·입고 수령·품질검사·적치·이동·회수품 반입·
/// 실사 계수·품질 판정을 네 원장에서 모은 것. 합계(totals)는 서버 값 그대로(앱이 더하지 않는다).

@immutable
class WorkActivity {
  const WorkActivity({
    required this.source,
    required this.type,
    required this.refId,
    required this.at,
    this.taskId,
    this.sku,
    this.qty,
    this.result,
  });

  final String source;

  /// PICK·PACK·RETURN·RECEIVE·INSPECT·PUTAWAY·MOVE·RETURN_RECEIPT·COUNT·RECOUNT·QUARANTINE·RELEASE·DISPOSE·RETURN_INSPECTION
  final String type;
  final String refId;
  final String? taskId;
  final String? sku;
  final int? qty;

  /// 그 원장의 상태(APPLIED·REJECTED·RECORDED·UNKNOWN_RESULT 등) 그대로.
  final String? result;
  final DateTime at;
}

@immutable
class WorkTotal {
  const WorkTotal({required this.type, required this.count, required this.qty});

  final String type;
  final int count;

  /// 거절은 수량에서 뺀 값(서버).
  final int qty;
}

@immutable
class WorkActivities {
  const WorkActivities({
    required this.date,
    required this.items,
    required this.totals,
    required this.unavailableSources,
  });

  final String date;

  /// 최근 것이 위.
  final List<WorkActivity> items;
  final List<WorkTotal> totals;

  /// 못 읽은 원장 — 비어 있지 않으면 "일부 내역을 못 불러왔어요"(빈 내역으로 보이지 않게).
  final List<String> unavailableSources;
}

abstract interface class MyWorkRepository {
  /// 오늘(서버의 Asia/Seoul) 내 업무 내역.
  Future<WorkActivities> today(String mfcId);
}

final myWorkRepositoryProvider = Provider<MyWorkRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockMyWorkRepository(),
    PmartEnv.local => ApiMyWorkRepository(ref.watch(dioProvider)),
  },
);

final class ApiMyWorkRepository implements MyWorkRepository {
  ApiMyWorkRepository(Dio dio)
    : _api = cap.PmartApiMfcCapacity(dio: dio).getWorkActivitiesApi();

  final cap.WorkActivitiesApi _api;

  @override
  Future<WorkActivities> today(String mfcId) async {
    final res = await pmartGuard(
      // 날짜를 보내지 않는다 — 오늘은 서버가 정한다(Asia/Seoul).
      () => _api.listWorkerActivities(mfcId: mfcId, workerId: 'me'),
    );
    return workActivitiesFromContract(res.data!);
  }
}

WorkActivities workActivitiesFromContract(cap.WorkerActivities a) =>
    WorkActivities(
      date: a.date,
      items: [
        for (final i in a.items)
          WorkActivity(
            source: i.source_,
            type: i.activityType,
            refId: i.refId,
            taskId: i.taskId,
            sku: i.sku,
            qty: i.qty,
            result: i.result,
            at: i.at,
          ),
      ]..sort((x, y) => y.at.compareTo(x.at)),
      totals: [
        for (final t in a.totals)
          WorkTotal(type: t.activityType, count: t.count, qty: t.qty),
      ],
      unavailableSources: [...a.unavailableSources],
    );

/// 목 — 오늘 피킹 2(1 거절)·포장 1·적치 1. [unavailable] 을 넣으면 그 원장을 못 읽은 응답.
final class MockMyWorkRepository implements MyWorkRepository {
  MockMyWorkRepository({this.latency = const Duration(milliseconds: 200)});

  final Duration latency;
  List<String> unavailable = const [];
  bool empty = false;

  @override
  Future<WorkActivities> today(String mfcId) async {
    await Future<void>.delayed(latency);
    final now = DateTime.now().toUtc();
    final items = empty
        ? const <WorkActivity>[]
        : [
            WorkActivity(
              source: 'mfc-fulfillment',
              type: 'PICK',
              refId: 'EXE-M-1',
              taskId: 'task-done-1',
              sku: 'E-00000001',
              qty: 2,
              result: 'APPLIED',
              at: now.subtract(const Duration(minutes: 50)),
            ),
            WorkActivity(
              source: 'mfc-fulfillment',
              type: 'PICK',
              refId: 'EXE-M-2',
              taskId: 'task-done-1',
              sku: 'E-00000002',
              qty: 1,
              result: 'REJECTED',
              at: now.subtract(const Duration(minutes: 45)),
            ),
            WorkActivity(
              source: 'mfc-fulfillment',
              type: 'PACK',
              refId: 'PKG-M-1',
              taskId: 'task-done-2',
              qty: 3,
              result: 'APPLIED',
              at: now.subtract(const Duration(minutes: 30)),
            ),
            WorkActivity(
              source: 'mfc-inbound',
              type: 'PUTAWAY',
              refId: 'INB-M-1',
              taskId: 'INB-T-1',
              sku: 'E-00000003',
              qty: 12,
              result: 'APPLIED',
              at: now.subtract(const Duration(minutes: 10)),
            ),
          ];
    final totals = empty
        ? const <WorkTotal>[]
        : const [
            WorkTotal(type: 'PICK', count: 2, qty: 2),
            WorkTotal(type: 'PACK', count: 1, qty: 3),
            WorkTotal(type: 'PUTAWAY', count: 1, qty: 12),
          ];
    return WorkActivities(
      date: '${now.year}-${now.month}-${now.day}',
      items: [...items]..sort((x, y) => y.at.compareTo(x.at)),
      totals: totals,
      unavailableSources: unavailable,
    );
  }
}
