import 'package:dio/dio.dart';
import 'package:pmart_api_mfc_inbound/pmart_api_mfc_inbound.dart' as ib;
import 'package:pmart_api_transport_execution/pmart_api_transport_execution.dart'
    as te;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../domain/inbound.dart';

abstract interface class InboundRepository {
  /// `GET /inbound-promises/{trfId}`.
  Future<InboundPromiseView> promise(String trfId);

  /// `POST /inbound-promises/{trfId}/arrivals` — 도착 등록·하차 시작(EXPECTED→RECEIVING).
  Future<InboundCommandOutcome> recordArrival(
    String trfId, {
    required int version,
    required DateTime arrivedAt,
    required String recordedBy,
    required IdempotencyKey key,
  });

  /// `POST /inbound-promises/{trfId}/receipts` — 수령(정상/격리/미판정). 202 resultId = receiptId.
  Future<InboundCommandOutcome> recordReceipt(
    String trfId, {
    required int version,
    required List<(InboundLine, ReceiptCount)> counts,
    required Map<String, String> toLocations,
    required DateTime receivedAt,
    required String receivedBy,
    required IdempotencyKey key,
  });

  /// `GET /inbound-promises/{trfId}/receipts/{receiptId}` — 재고 반영 상태.
  Future<ReceiptView> receipt(String trfId, String receiptId);

  /// 하차 인계(DC 시뮬레이터 요청 C-01) — 그 MFC 로 오는 운행(`GET /mfcs/{mfcId}/inbound-trips`)에서 이 TRF 의 정차를 찾아
  /// `POST /trips/{tripId}/stops/{stopSeq}/handovers`(받은 박스·파손 박스). 차이가 있으면 서버가 예외로 남긴다(출발은 막지 않음).
  Future<InboundCommandOutcome> recordHandover({
    required String trfId,
    required String mfcId,
    required String tripId,
    required List<String> received,
    required List<String> damaged,
    required IdempotencyKey key,
  });
}

final class ApiInboundRepository implements InboundRepository {
  ApiInboundRepository(Dio dio)
    : _api = ib.PmartApiMfcInbound(dio: dio).getInboundPromisesApi(),
      _trips = te.PmartApiTransportExecution(dio: dio).getTripsApi(),
      _stops = te.PmartApiTransportExecution(dio: dio).getStopsApi();

  final ib.InboundPromisesApi _api;
  final te.TripsApi _trips;
  final te.StopsApi _stops;

  @override
  Future<InboundPromiseView> promise(String trfId) async {
    final res = await pmartGuard(() => _api.getInboundPromise(trfId: trfId));
    return promiseFromContract(
      res.data ?? (throw const ContractViolationFailure('InboundPromise 없음')),
    );
  }

  @override
  Future<InboundCommandOutcome> recordArrival(
    String trfId, {
    required int version,
    required DateTime arrivedAt,
    required String recordedBy,
    required IdempotencyKey key,
  }) => _command(
    () => _api.recordArrival(
      trfId: trfId,
      idempotencyKey: key.value,
      xSourceSystem: sourceSystem,
      xExpectedVersion: version,
      recordArrivalRequest: ib.RecordArrivalRequest(
        arrivedAt: arrivedAt.toUtc(),
        recordedBy: recordedBy,
      ),
      extra: commandOptions(key, expectedVersion: version).extra,
    ),
  );

  @override
  Future<InboundCommandOutcome> recordReceipt(
    String trfId, {
    required int version,
    required List<(InboundLine, ReceiptCount)> counts,
    required Map<String, String> toLocations,
    required DateTime receivedAt,
    required String receivedBy,
    required IdempotencyKey key,
  }) => _command(
    () => _api.recordReceipt(
      trfId: trfId,
      idempotencyKey: key.value,
      xSourceSystem: sourceSystem,
      xExpectedVersion: version,
      recordReceiptRequest: ib.RecordReceiptRequest(
        receivedAt: receivedAt.toUtc(),
        receivedBy: receivedBy,
        lines: [
          for (final (l, c) in counts)
            ib.RecordReceiptRequestLinesInner(
              sku: l.sku,
              lotId: l.lotId,
              normalQty: c.normal,
              quarantinedQty: c.quarantined,
              pendingQty: c.pending,
              // (0.16.0) 수령 위치(입고칸) — 서버 필수(없으면 400, 시뮬레이터 C-6)
              toLocationCode: toLocations[l.key],
              discrepancyReason: switch (c.reasonFor(l.expectedQty)) {
                null => null,
                final r =>
                  ib.RecordReceiptRequestLinesInnerDiscrepancyReasonEnum.values
                      .firstWhere((e) => e.value == r.wire),
              },
            ),
        ],
      ),
      extra: commandOptions(key, expectedVersion: version).extra,
    ),
  );

  Future<InboundCommandOutcome> _command(
    Future<Response<ib.RecordArrival202Response>> Function() call,
  ) async {
    try {
      final res = await pmartGuard(call);
      final r = res.data;
      if (r == null) return const InboundUnknown();
      return switch (r.status.value) {
        'ACCEPTED' || 'APPLIED' => InboundAccepted(resultId: r.resultId),
        'REJECTED' => const InboundRejected('REJECTED'),
        _ => const InboundUnknown(),
      };
    } on PmartFailure catch (f) {
      return switch (f) {
        UnknownResultFailure() => const InboundUnknown(),
        ProblemFailure(:final problem)
            when problem.code == ProblemCode.idempotencyConflict &&
                problem.retryable =>
          const InboundUnknown(),
        ProblemFailure(:final problem) => InboundRejected(problem.code),
        _ => throw f,
      };
    }
  }

  @override
  Future<InboundCommandOutcome> recordHandover({
    required String trfId,
    required String mfcId,
    required String tripId,
    required List<String> received,
    required List<String> damaged,
    required IdempotencyKey key,
  }) async {
    try {
      final trips = await pmartGuard(
        () => _trips.listMfcInboundTrips(mfcId: mfcId, size: 200),
      );
      final trip = (trips.data?.items ?? const <te.Trip>[])
          .where((t) => t.tripId == tripId)
          .firstOrNull;
      final seq = trip?.stops
          .where(
            (s) => s.mfcId == mfcId && (s.trfIds ?? const []).contains(trfId),
          )
          .firstOrNull
          ?.seq;
      if (seq == null) return const InboundRejected('STOP_NOT_FOUND');
      await pmartGuard(
        () => _stops.recordHandover(
          tripId: tripId,
          stopSeq: seq,
          idempotencyKey: key.value,
          xSourceSystem: sourceSystem,
          handoverInput: te.HandoverInput(
            transfers: [
              te.HandoverInputAllOfTransfers(
                trfId: trfId,
                receivedLpns: received,
                damagedLpns: damaged,
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
        ProblemFailure(:final problem) => InboundRejected(
          problem.code,
          problem.detail,
        ),
        _ => throw f,
      };
    }
  }

  @override
  Future<ReceiptView> receipt(String trfId, String receiptId) async {
    final res = await pmartGuard(
      () => _api.getReceipt(trfId: trfId, receiptId: receiptId),
    );
    return receiptFromContract(
      res.data ?? (throw const ContractViolationFailure('Receipt 없음')),
    );
  }
}

ReceiptView receiptFromContract(ib.Receipt r) => ReceiptView(
  receiptId:
      r.receiptId ?? (throw const ContractViolationFailure('receiptId 없음')),
  applyStatus: switch (r.inventoryApplyStatus?.value) {
    'CAPTURED' => ApplyStatus.captured,
    'SUBMITTED' => ApplyStatus.submitted,
    'PROCESSING' => ApplyStatus.processing,
    'APPLIED' => ApplyStatus.applied,
    'REJECTED' => ApplyStatus.rejected,
    'UNKNOWN_RESULT' => ApplyStatus.unknownResult,
    _ => ApplyStatus.unknown,
  },
  commitId: r.inventoryCommitId,
  receivedAt: r.receivedAt,
);

InboundPromiseView promiseFromContract(ib.InboundPromise p) =>
    InboundPromiseView(
      trfId: p.trfId ?? (throw const ContractViolationFailure('trfId 없음')),
      version: p.version ?? 0,
      state: switch (p.state?.value) {
        'EXPECTED' => PromiseState.expected,
        'RECEIVING' => PromiseState.receiving,
        'TIN_POSTED' => PromiseState.tinPosted,
        'CANCELLED' => PromiseState.cancelled,
        _ => PromiseState.unknown,
      },
      plannedArrivalAt: p.plannedArrivalAt,
      eta: p.eta,
      arrivedAt: p.arrivedAt,
      mfcId: p.mfcId,
      tripId: switch (p.tripId?.trim()) {
        final t? when t.isNotEmpty => t,
        _ => null,
      },
      boxList: [
        for (final b in p.packages ?? const <ib.InboundPromisePackagesInner>[])
          if (b.lpn case final lpn? when lpn.trim().isNotEmpty)
            InboundBox(
              boxId: lpn.trim(),
              lineKey: _lineKeyOf(p, b.sku, b.lotId),
              unitsPerBox: b.qty ?? 0,
            ),
      ],
      lines: [
        for (final l in p.lines ?? const <ib.InboundPromiseLinesInner>[])
          InboundLine(
            sku: l.sku ?? (throw const ContractViolationFailure('sku 없음')),
            lotId: l.lotId,
            expectedQty:
                l.expectedQty ??
                (throw const ContractViolationFailure('expectedQty 없음')),
            receivedQty: l.receivedQty ?? 0,
            temperatureZone: l.temperatureZone,
            quarantinedQty: l.quarantinedQty ?? 0,
            pendingQty: l.pendingQty ?? 0,
            productName: switch (l.productName?.trim()) {
              final n? when n.isNotEmpty => n,
              _ => null,
            },
            barcodes: [
              for (final b in l.barcodes ?? const <String>[])
                if (b.trim().isNotEmpty) b.trim(),
            ],
          ),
      ],
      receipts: [
        for (final r in p.receipts ?? const <ib.Receipt>[])
          receiptFromContract(r),
      ],
    );

/// 포장(LPN)이 어느 줄인지 — 같은 SKU 에 LOT 이 같거나 줄 LOT 이 비면 그 줄
String _lineKeyOf(ib.InboundPromise p, String? sku, String? lotId) {
  final lines = p.lines ?? const <ib.InboundPromiseLinesInner>[];
  final hit =
      lines.where((l) => l.sku == sku && l.lotId == lotId).firstOrNull ??
      lines.where((l) => l.sku == sku).firstOrNull;
  return '${hit?.sku ?? sku ?? ''}|${hit?.lotId ?? ''}';
}
