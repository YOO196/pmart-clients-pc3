import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pmart_api_transport_execution/pmart_api_transport_execution.dart'
    as te;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../../inbound/domain/inbound.dart';

/// 하차(사용자 2026-11-26 "시뮬레이션에서 도착했다고 보내면 pda 에서 하차 작업을 해야 해") — DC 운행이 이 MFC 에 도착하면
/// (transport-execution 정차 ARRIVED — 시뮬레이터·기사가 `POST /trips/{id}/stops/{seq}/arrivals`) 그 정차의 박스를 받고
/// 정차 인계 `POST /trips/{tripId}/stops/{stopSeq}/handovers`(그 정차 TRF 전부를 **한 번에** — 다른 본문으로 다시 오면 409 HANDOVER_RECORDED).
/// 인수 확정(TIN)은 이어서 입고 수령에서 한다.
@immutable
final class UnloadTrip {
  const UnloadTrip({
    required this.tripId,
    required this.vehicleLabel,
    required this.driverName,
    required this.tempClass,
    required this.stopSeq,
    required this.stopState,
    required this.trfIds,
    required this.plannedArrivalAt,
    required this.estimatedArrivalAt,
    required this.arrivedAt,
  });

  final String tripId;
  final String vehicleLabel;
  final String? driverName;

  /// AMBIENT·CHILLED·FROZEN
  final String tempClass;
  final int stopSeq;

  /// PLANNED·ARRIVED·HANDED_OVER·DEPARTED
  final String stopState;
  final List<String> trfIds;
  final DateTime? plannedArrivalAt;
  final DateTime? estimatedArrivalAt;
  final DateTime? arrivedAt;

  bool get arrived => stopState == 'ARRIVED';
  bool get handedOver => stopState == 'HANDED_OVER' || stopState == 'DEPARTED';
}

abstract interface class UnloadRepository {
  /// 이 MFC 로 오는 운행 중 이 MFC 정차가 있는 것 — 도착한 것 먼저
  Future<List<UnloadTrip>> trips(String mfcId);

  /// TRF 마다 (받은 박스, 파손 박스)
  Future<InboundCommandOutcome> handover({
    required String tripId,
    required int stopSeq,
    required Map<String, (List<String>, List<String>)> transfers,
    required IdempotencyKey key,
  });
}

List<UnloadTrip> _sorted(Iterable<UnloadTrip> all) {
  int rank(UnloadTrip t) => t.arrived ? 0 : (t.handedOver ? 2 : 1);
  return [...all]..sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    final x = a.arrivedAt ?? a.estimatedArrivalAt ?? a.plannedArrivalAt;
    final y = b.arrivedAt ?? b.estimatedArrivalAt ?? b.plannedArrivalAt;
    return (x ?? DateTime(2100)).compareTo(y ?? DateTime(2100));
  });
}

final class ApiUnloadRepository implements UnloadRepository {
  ApiUnloadRepository(Dio dio)
    : _trips = te.PmartApiTransportExecution(dio: dio).getTripsApi(),
      _stops = te.PmartApiTransportExecution(dio: dio).getStopsApi();

  final te.TripsApi _trips;
  final te.StopsApi _stops;

  @override
  Future<List<UnloadTrip>> trips(String mfcId) async {
    final r = await pmartGuard(
      () => _trips.listMfcInboundTrips(mfcId: mfcId, size: 200),
    );
    return _sorted([
      for (final t in r.data?.items ?? const <te.Trip>[])
        for (final s in t.stops)
          if (s.mfcId == mfcId && s.seq != null)
            UnloadTrip(
              tripId: t.tripId,
              vehicleLabel: t.plateNo ?? t.vehicleId ?? t.tripId,
              driverName: t.driverName,
              tempClass: t.tempClass.value,
              stopSeq: s.seq!,
              stopState: s.state?.value ?? 'PLANNED',
              trfIds: s.trfIds ?? const [],
              plannedArrivalAt: s.plannedArrivalAt,
              estimatedArrivalAt: s.estimatedArrivalAt,
              arrivedAt: s.arrivedAt,
            ),
    ]);
  }

  @override
  Future<InboundCommandOutcome> handover({
    required String tripId,
    required int stopSeq,
    required Map<String, (List<String>, List<String>)> transfers,
    required IdempotencyKey key,
  }) async {
    try {
      await pmartGuard(
        () => _stops.recordHandover(
          tripId: tripId,
          stopSeq: stopSeq,
          idempotencyKey: key.value,
          xSourceSystem: sourceSystem,
          handoverInput: te.HandoverInput(
            transfers: [
              for (final e in transfers.entries)
                te.HandoverInputAllOfTransfers(
                  trfId: e.key,
                  receivedLpns: e.value.$1,
                  damagedLpns: e.value.$2,
                ),
            ],
          ),
          extra: commandOptions(key).extra,
        ),
      );
      return const InboundAccepted();
    } on PmartFailure catch (f) {
      return switch (f) {
        UnknownResultFailure() || NetworkFailure() => const InboundUnknown(),
        ProblemFailure(:final problem) => InboundRejected(problem.code),
        _ => throw f,
      };
    }
  }
}

/// 목: 칠곡 DC 운행 둘 — 하나는 도착(TRF-MOCK-001 박스가 실림), 하나는 오는 중
final class MockUnloadRepository implements UnloadRepository {
  MockUnloadRepository({required this.mfcId});

  final String mfcId;
  final handovers = <String, Map<String, (List<String>, List<String>)>>{};
  final _done = <String>{};
  var _state = 'ARRIVED';

  @override
  Future<List<UnloadTrip>> trips(String mfcId) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final now = DateTime.now();
    return _sorted([
      UnloadTrip(
        tripId: 'TO-20261126-001',
        vehicleLabel: '경북12가3456',
        driverName: '김기사',
        tempClass: 'CHILLED',
        stopSeq: 1,
        stopState: _state,
        trfIds: const ['TRF-MOCK-001'],
        plannedArrivalAt: now.subtract(const Duration(minutes: 10)),
        estimatedArrivalAt: null,
        arrivedAt: now.subtract(const Duration(minutes: 3)),
      ),
      UnloadTrip(
        tripId: 'TO-20261126-002',
        vehicleLabel: '경북34나7890',
        driverName: '박기사',
        tempClass: 'AMBIENT',
        stopSeq: 2,
        stopState: 'PLANNED',
        trfIds: const ['TRF-MOCK-002'],
        plannedArrivalAt: now.add(const Duration(minutes: 40)),
        estimatedArrivalAt: now.add(const Duration(minutes: 45)),
        arrivedAt: null,
      ),
    ]);
  }

  @override
  Future<InboundCommandOutcome> handover({
    required String tripId,
    required int stopSeq,
    required Map<String, (List<String>, List<String>)> transfers,
    required IdempotencyKey key,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (_done.contains(key.value)) return const InboundAccepted();
    if (_state != 'ARRIVED') return const InboundRejected('INVALID_STATE');
    _done.add(key.value);
    handovers[tripId] = transfers;
    _state = 'HANDED_OVER';
    return const InboundAccepted();
  }
}
