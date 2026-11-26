import 'package:dio/dio.dart';
import 'package:pmart_api_cdc_inbound/pmart_api_cdc_inbound.dart' as ci;
import 'package:pmart_api_cdc_outbound/pmart_api_cdc_outbound.dart' as co;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../domain/cdc_flow.dart';

/// DC 분배·검품·상차(cdc-outbound 0.21.0 results·staff-views)와 지게차 적치(cdc-inbound 0.1.0 putaway-tasks).
/// 결과 등록은 202 접수 — 화면은 다시 읽은 서버 값(LPN 검품·상차, 적치 진행)만 확정으로 보인다.
abstract interface class CdcFlowRepository {
  /// 피킹이 끝난 TRF(state PICKED) — 기한 빠른 순(서버 정렬)
  Future<List<CdcTrf>> pickedTransfers(String cdcId);

  /// TRF 몫으로 집은 SKU·LOT 와 이미 BOX 에 담은 수량
  Future<List<CdcSortItem>> sortItems(String cdcId, CdcTrf trf);

  Future<List<CdcLpn>> lpns(String cdcId, String trfId);

  Future<void> reportSort({
    required CdcTrf trf,
    required String workerId,
    required CdcBoxDraft box,
    required IdempotencyKey key,
  });

  Future<void> reportInspection({
    required String trfId,
    required String inspectorId,
    required List<CdcInspection> items,
    required IdempotencyKey key,
  });

  Future<void> reportLoading({
    required String trfId,
    required String tripId,
    required String vehicleId,
    required String? dockCode,
    required String workerId,
    required List<String> lpns,
    required IdempotencyKey key,
  });

  Future<CdcPutaway> putaway(String taskId);

  Future<void> executePutaway({
    required CdcPutaway task,
    required String workerId,
    required List<CdcPutawayLine> lines,
    required IdempotencyKey key,
  });
}

final class ApiCdcFlowRepository implements CdcFlowRepository {
  ApiCdcFlowRepository(Dio dio)
    : _views = co.PmartApiCdcOutbound(dio: dio).getStaffViewsApi(),
      _tasks = co.PmartApiCdcOutbound(dio: dio).getTasksApi(),
      _results = co.PmartApiCdcOutbound(dio: dio).getResultsApi(),
      _putaway = ci.PmartApiCdcInbound(dio: dio).getPutawayTasksApi();

  final co.StaffViewsApi _views;
  final co.TasksApi _tasks;
  final co.ResultsApi _results;
  final ci.PutawayTasksApi _putaway;

  @override
  Future<List<CdcTrf>> pickedTransfers(String cdcId) async {
    final r = await pmartGuard(
      () =>
          _views.listCenterTransfers(cdcId: cdcId, state: 'PICKED', size: 200),
    );
    return [
      for (final t in r.data?.items ?? const <co.TransferSummary>[])
        CdcTrf(
          trfId: t.trfId,
          trfNumber: t.trfNumber,
          mfcId: t.mfcId,
          waveId: t.waveId,
          waveNumber: t.waveNumber,
          dueAt: t.dueAt,
          pickedQty: t.pickedQty,
        ),
    ];
  }

  @override
  Future<List<CdcSortItem>> sortItems(String cdcId, CdcTrf trf) async {
    final waveId = trf.waveId;
    if (waveId == null) return const [];
    // 이 TRF 몫으로 집은 수량: Wave 작업 줄의 shares(trfId) — SKU·LOT 마다 합
    final picked = <String, (String, String?, String, int)>{};
    String? cursor;
    for (var i = 0; i < 20; i++) {
      final r = await pmartGuard(
        () => _tasks.listTasks(
          cdcId: cdcId,
          waveId: waveId,
          size: 200,
          cursor: cursor,
        ),
      );
      for (final t in r.data?.items ?? const <co.Task>[]) {
        if (t.kind != co.TaskKindEnum.PICK) continue;
        for (final l in t.lines ?? const <co.TaskLinesInner>[]) {
          final sku = l.sku, lot = l.lot;
          if (sku == null || lot == null) continue;
          final shares = l.shares ?? const <co.TaskLinesInnerSharesInner>[];
          // 묶음이 아닌 작업은 shares 가 없을 수 있다 — 작업의 TRF 가 이 TRF 면 줄 실피킹 전부
          final qty = shares.isEmpty
              ? (t.trfId == trf.trfId ? l.pickedQty ?? 0 : 0)
              : shares
                    .where((s) => s.trfId == trf.trfId)
                    .fold<int>(0, (a, s) => a + (s.pickedQty ?? 0));
          if (qty <= 0) continue;
          final k = '$sku|$lot';
          final prev = picked[k];
          picked[k] = (sku, l.productName, lot, (prev?.$4 ?? 0) + qty);
        }
      }
      cursor = r.data?.page?.nextCursor;
      if (cursor == null) break;
    }
    final sorted = <String, int>{};
    for (final b in await lpns(cdcId, trf.trfId)) {
      if (b.unitType != 'BOX') continue;
      for (final c in b.contents) {
        sorted.update(
          '${c.sku}|${c.lot}',
          (v) => v + c.qty,
          ifAbsent: () => c.qty,
        );
      }
    }
    return [
      for (final e in picked.entries)
        CdcSortItem(
          sku: e.value.$1,
          productName: e.value.$2,
          lot: e.value.$3,
          pickedQty: e.value.$4,
          sortedQty: sorted[e.key] ?? 0,
        ),
    ];
  }

  @override
  Future<List<CdcLpn>> lpns(String cdcId, String trfId) async {
    final out = <CdcLpn>[];
    for (var page = 0; page < 20; page++) {
      final r = await pmartGuard(
        () => _views.listCenterLpns(
          cdcId: cdcId,
          trfId: trfId,
          page: page,
          size: 200,
        ),
      );
      final body =
          r.data ?? (throw const ContractViolationFailure('LPN 목록 없음'));
      out.addAll([
        for (final l in body.items)
          CdcLpn(
            lpn: l.lpn,
            unitType: l.unitType,
            inspection: l.inspection,
            failReason: l.failReason,
            loaded: l.loaded,
            tripId: l.tripId,
            vehicleId: l.vehicleId,
            temperatureZone: l.temperatureZone,
            contents: [
              for (final c
                  in l.contents ??
                      const <
                        co.ListCenterLpns200ResponseItemsInnerContentsInner
                      >[])
                if (c.sku != null && c.lot != null)
                  CdcLpnContent(sku: c.sku!, lot: c.lot!, qty: c.qty ?? 0),
            ],
          ),
      ]);
      if (!body.hasNext) break;
    }
    return out;
  }

  @override
  Future<void> reportSort({
    required CdcTrf trf,
    required String workerId,
    required CdcBoxDraft box,
    required IdempotencyKey key,
  }) async {
    await pmartGuard(
      () => _results.reportSortingResult(
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        reportSortingResultRequest: co.ReportSortingResultRequest(
          waveId: trf.waveId ?? '',
          trfId: trf.trfId,
          workerId: workerId,
          lpns: [
            co.LpnComposition(
              lpn: box.lpn,
              unitType: co.LpnCompositionUnitTypeEnum.BOX,
              state: co.LpnCompositionStateEnum.SEALED,
              temperatureZone: box.temperatureZone == null
                  ? null
                  : co.LpnCompositionTemperatureZoneEnum.values.firstWhere(
                      (e) => e.value == box.temperatureZone,
                    ),
              contents: [
                for (final c in box.contents)
                  co.LpnCompositionContentsInner(
                    sku: c.sku,
                    lot: c.lot,
                    qty: c.qty,
                  ),
              ],
            ),
          ],
        ),
        extra: commandOptions(key).extra,
      ),
    );
  }

  @override
  Future<void> reportInspection({
    required String trfId,
    required String inspectorId,
    required List<CdcInspection> items,
    required IdempotencyKey key,
  }) async {
    await pmartGuard(
      () => _results.reportInspectionResult(
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        reportInspectionResultRequest: co.ReportInspectionResultRequest(
          trfId: trfId,
          inspectorId: inspectorId,
          items: [
            for (final i in items)
              co.ReportInspectionResultRequestItemsInner(
                lpn: i.lpn,
                result: i.passed
                    ? co
                          .ReportInspectionResultRequestItemsInnerResultEnum
                          .PASSED
                    : co
                          .ReportInspectionResultRequestItemsInnerResultEnum
                          .FAILED,
                failReason: i.passed || i.failReason == null
                    ? null
                    : co
                          .ReportInspectionResultRequestItemsInnerFailReasonEnum
                          .values
                          .firstWhere((e) => e.value == i.failReason),
                temperatureC: i.temperatureC,
              ),
          ],
        ),
        extra: commandOptions(key).extra,
      ),
    );
  }

  @override
  Future<void> reportLoading({
    required String trfId,
    required String tripId,
    required String vehicleId,
    required String? dockCode,
    required String workerId,
    required List<String> lpns,
    required IdempotencyKey key,
  }) async {
    await pmartGuard(
      () => _results.reportLoadingResult(
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        reportLoadingResultRequest: co.ReportLoadingResultRequest(
          trfId: trfId,
          tripId: tripId,
          vehicleId: vehicleId,
          dockCode: dockCode,
          workerId: workerId,
          action: co.ReportLoadingResultRequestActionEnum.LOADED,
          lpns: [
            for (final l in lpns)
              co.ReportLoadingResultRequestLpnsInner(lpn: l),
          ],
        ),
        extra: commandOptions(key).extra,
      ),
    );
  }

  @override
  Future<CdcPutaway> putaway(String taskId) async {
    final r = await pmartGuard(() => _putaway.getPutawayTask(taskId: taskId));
    final t =
        r.data ?? (throw const ContractViolationFailure('PutawayTask 없음'));
    return CdcPutaway(
      taskId: t.taskId ?? taskId,
      state: t.state?.value ?? 'CREATED',
      version: t.version ?? 0,
      rows: [
        for (final p in t.progress ?? const <ci.PutawayTaskAllOfProgress>[])
          if (p.sku != null && p.lot != null)
            CdcPutawayRow(
              sku: p.sku!,
              lot: p.lot!,
              location: p.assignedLocationCode ?? '',
              q: p.q ?? 0,
              c: p.c ?? 0,
              u: p.u ?? 0,
              k: p.k ?? 0,
            ),
      ],
    );
  }

  @override
  Future<void> executePutaway({
    required CdcPutaway task,
    required String workerId,
    required List<CdcPutawayLine> lines,
    required IdempotencyKey key,
  }) async {
    await pmartGuard(
      () => _putaway.recordPutawayExecution(
        taskId: task.taskId,
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        xExpectedVersion: task.version,
        recordPutawayExecutionRequest: ci.RecordPutawayExecutionRequest(
          workerId: workerId,
          lines: [
            for (final l in lines)
              ci.RecordPutawayExecutionRequestLinesInner(
                sku: l.row.sku,
                lot: l.row.lot,
                toLocationCode: l.toLocation,
                completedQty: l.completedQty,
                exceptionReason: l.exceptionReason == null
                    ? null
                    : ci
                          .RecordPutawayExecutionRequestLinesInnerExceptionReasonEnum
                          .values
                          .firstWhere((e) => e.value == l.exceptionReason),
              ),
          ],
        ),
        extra: commandOptions(key, expectedVersion: task.version).extra,
      ),
    );
  }
}

/// 목: 칠곡 DC — 피킹 끝난 TRF 둘, 분배·검품·상차가 서로 이어지고, 적치 지시 둘(`PA-mock-1`·`PA-mock-2`).
final class MockCdcFlowRepository implements CdcFlowRepository {
  MockCdcFlowRepository({this.latency = const Duration(milliseconds: 300)}) {
    reset();
  }

  final Duration latency;
  late Map<String, List<CdcSortItem>> _picked;
  late Map<String, List<_MockLpn>> _lpns;
  late Map<String, CdcPutaway> _putaways;
  final _done = <String>{};

  static final trfs = [
    CdcTrf(
      trfId: 'TRF-mock-1',
      trfNumber: 'T482913',
      mfcId: 'MFC-BJG-01',
      waveId: 'WAV-mock-1',
      waveNumber: 'W2611260001',
      dueAt: DateTime.utc(2026, 11, 26, 9),
      pickedQty: 36,
    ),
    CdcTrf(
      trfId: 'TRF-mock-2',
      trfNumber: 'T482914',
      mfcId: 'MFC-MOKPO-01',
      waveId: 'WAV-mock-1',
      waveNumber: 'W2611260001',
      dueAt: DateTime.utc(2026, 11, 26, 11),
      pickedQty: 16,
    ),
  ];

  void reset() {
    _done.clear();
    CdcSortItem item(String sku, String name, String lot, int qty) =>
        CdcSortItem(
          sku: sku,
          productName: name,
          lot: lot,
          pickedQty: qty,
          sortedQty: 0,
        );
    _picked = {
      'TRF-mock-1': [
        item('SKU-1001', '서울우유 1L', 'L261120011', 24),
        item('SKU-1002', '맛있는 두부 300g', 'L261121021', 12),
      ],
      'TRF-mock-2': [
        item('SKU-2001', '양파 3kg', 'L261122011', 6),
        item('SKU-1003', '생수 2L 6입', 'L261119031', 10),
      ],
    };
    // TRF-mock-2 는 BOX 하나가 이미 분배·검품 합격 — 상차 시험용
    _lpns = {
      'TRF-mock-1': [],
      'TRF-mock-2': [
        _MockLpn('BOX-26112600001', 'AMBIENT', const [
          CdcLpnContent(sku: 'SKU-1003', lot: 'L261119031', qty: 10),
        ])..inspection = 'PASSED',
      ],
    };
    CdcPutawayRow row(String sku, String lot, String loc, int q) =>
        CdcPutawayRow(
          sku: sku,
          lot: lot,
          location: loc,
          q: q,
          c: 0,
          u: q,
          k: 0,
        );
    _putaways = {
      'PA-mock-1': CdcPutaway(
        taskId: 'PA-mock-1',
        state: 'DISPATCHED',
        version: 1,
        rows: [row('SKU-1001', 'L261124011', 'CDC01-C-5-02-24-3-1', 120)],
      ),
      'PA-mock-2': CdcPutaway(
        taskId: 'PA-mock-2',
        state: 'DISPATCHED',
        version: 1,
        rows: [
          row('SKU-2001', 'L261125021', 'CDC01-B-6-05-12-2-1', 40),
          row('SKU-1002', 'L261125022', 'CDC01-F-5-01-07-1-2', 30),
        ],
      ),
    };
  }

  Future<void> _wait() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);

  static Never _problem(int status, String code) =>
      throw ProblemFailure(Problem(status: status, code: code));

  @override
  Future<List<CdcTrf>> pickedTransfers(String cdcId) async {
    await _wait();
    return trfs;
  }

  @override
  Future<List<CdcSortItem>> sortItems(String cdcId, CdcTrf trf) async {
    await _wait();
    final sorted = <String, int>{};
    for (final b in _lpns[trf.trfId] ?? const <_MockLpn>[]) {
      for (final c in b.contents) {
        sorted.update(
          '${c.sku}|${c.lot}',
          (v) => v + c.qty,
          ifAbsent: () => c.qty,
        );
      }
    }
    return [
      for (final i in _picked[trf.trfId] ?? const <CdcSortItem>[])
        CdcSortItem(
          sku: i.sku,
          productName: i.productName,
          lot: i.lot,
          pickedQty: i.pickedQty,
          sortedQty: sorted[i.key] ?? 0,
        ),
    ];
  }

  @override
  Future<List<CdcLpn>> lpns(String cdcId, String trfId) async {
    await _wait();
    return [for (final l in _lpns[trfId] ?? const <_MockLpn>[]) l.view];
  }

  @override
  Future<void> reportSort({
    required CdcTrf trf,
    required String workerId,
    required CdcBoxDraft box,
    required IdempotencyKey key,
  }) async {
    await _wait();
    if (!_done.add(key.value)) return;
    final all = _lpns.values.expand((l) => l);
    if (all.any((l) => l.lpn == box.lpn)) {
      _done.remove(key.value);
      _problem(409, 'LPN_ALREADY_SEALED');
    }
    final items = await sortItems('', trf);
    for (final c in box.contents) {
      final i = items.firstWhere((i) => i.sku == c.sku && i.lot == c.lot);
      if (c.qty > i.remaining) {
        _done.remove(key.value);
        _problem(409, 'SORT_EXCEEDS_PICKED');
      }
    }
    _lpns[trf.trfId]!.add(_MockLpn(box.lpn, box.temperatureZone, box.contents));
  }

  @override
  Future<void> reportInspection({
    required String trfId,
    required String inspectorId,
    required List<CdcInspection> items,
    required IdempotencyKey key,
  }) async {
    await _wait();
    if (!_done.add(key.value)) return;
    for (final i in items) {
      final l = (_lpns[trfId] ?? const <_MockLpn>[])
          .where((l) => l.lpn == i.lpn)
          .firstOrNull;
      if (l == null) {
        _done.remove(key.value);
        _problem(404, 'NOT_FOUND');
      }
      if (l.loaded) {
        _done.remove(key.value);
        _problem(409, 'INVALID_STATE');
      }
      l
        ..inspection = i.passed ? 'PASSED' : 'FAILED'
        ..failReason = i.passed ? null : i.failReason;
    }
  }

  @override
  Future<void> reportLoading({
    required String trfId,
    required String tripId,
    required String vehicleId,
    required String? dockCode,
    required String workerId,
    required List<String> lpns,
    required IdempotencyKey key,
  }) async {
    await _wait();
    if (!_done.add(key.value)) return;
    for (final id in lpns) {
      final l = (_lpns[trfId] ?? const <_MockLpn>[]).firstWhere(
        (l) => l.lpn == id,
      );
      if (l.inspection != 'PASSED') {
        _done.remove(key.value);
        _problem(409, 'LPN_NOT_PASSED');
      }
      if (l.loaded && l.tripId != tripId) {
        _done.remove(key.value);
        _problem(409, 'TRIP_MISMATCH');
      }
    }
    for (final id in lpns) {
      (_lpns[trfId] ?? const <_MockLpn>[]).firstWhere((l) => l.lpn == id)
        ..loaded = true
        ..tripId = tripId
        ..vehicleId = vehicleId;
    }
  }

  @override
  Future<CdcPutaway> putaway(String taskId) async {
    await _wait();
    return _putaways[taskId] ?? _problem(404, 'NOT_FOUND');
  }

  @override
  Future<void> executePutaway({
    required CdcPutaway task,
    required String workerId,
    required List<CdcPutawayLine> lines,
    required IdempotencyKey key,
  }) async {
    await _wait();
    if (_done.contains(key.value)) return;
    final t = _putaways[task.taskId] ?? _problem(404, 'NOT_FOUND');
    if (t.finished) _problem(409, 'INVALID_STATE');
    if (t.version != task.version) _problem(409, 'VERSION_CONFLICT');
    final rows = [
      for (final r in t.rows)
        switch (lines.where((l) => l.row.key == r.key).firstOrNull) {
          null => r,
          final l when l.completedQty > r.u => _problem(
            409,
            'EXECUTION_EXCEEDS_REMAINING',
          ),
          final l => CdcPutawayRow(
            sku: r.sku,
            lot: r.lot,
            location: r.location,
            q: r.q,
            c: r.c + l.completedQty,
            u: r.u - l.completedQty,
            k: r.k,
          ),
        },
    ];
    _done.add(key.value);
    _putaways[t.taskId] = CdcPutaway(
      taskId: t.taskId,
      state: rows.every((r) => r.u == 0) ? 'COMPLETED' : 'PARTIALLY_COMPLETED',
      version: t.version + 1,
      rows: rows,
    );
  }
}

final class _MockLpn {
  _MockLpn(this.lpn, this.temperatureZone, this.contents);

  final String lpn;
  final String? temperatureZone;
  final List<CdcLpnContent> contents;
  String? inspection;
  String? failReason;
  bool loaded = false;
  String? tripId;
  String? vehicleId;

  CdcLpn get view => CdcLpn(
    lpn: lpn,
    unitType: 'BOX',
    inspection: inspection,
    failReason: failReason,
    loaded: loaded,
    tripId: tripId,
    vehicleId: vehicleId,
    temperatureZone: temperatureZone,
    contents: contents,
  );
}
