import 'package:pmart_core/pmart_core.dart';

import '../domain/inbound.dart';
import 'inbound_repository.dart';

/// 목 입고 예정 2건. 도착 등록 → RECEIVING, 수령 → 접수(202) 뒤 조회 [applyPolls] 번째에 반영(TIN_POSTED).
/// 상품명·바코드는 계약에 없어 목만 준다(BR-53).
final class MockInboundRepository implements InboundRepository {
  MockInboundRepository({this.latency = const Duration(milliseconds: 300)}) {
    _add('TRF-MOCK-001', const [
      InboundLine(
        sku: 'E-00000001',
        lotId: 'LOT-M-1110',
        productName: '서울우유 1L',
        barcode: '8801115114154',
        expectedQty: 24,
      ),
      InboundLine(
        sku: 'E-00000002',
        lotId: 'LOT-Y-1110',
        productName: '그릭요거트 플레인 400g',
        barcode: '8801115220015',
        expectedQty: 12,
      ),
      InboundLine(
        sku: 'E-00000005',
        lotId: 'LOT-C-1101',
        productName: '감자칩 오리지널 110g',
        barcode: '8801019606557',
        expectedQty: 30,
      ),
    ]);
    _add('TRF-MOCK-002', const [
      InboundLine(
        sku: 'E-00000005',
        lotId: 'LOT-C-1102',
        productName: '감자칩 오리지널 110g',
        barcode: '8801019606557',
        expectedQty: 20,
      ),
    ]);
  }

  final Duration latency;

  /// 수령 뒤 몇 번째 조회에서 반영되는지.
  int applyPolls = 1;

  /// 다음 수령 응답을 1회 잃는다(서버는 접수함).
  bool loseNextReceiptResponse = false;

  /// 재고 반영을 거절한다.
  bool rejectApply = false;

  final _promises = <String, InboundPromiseView>{};
  final _receiptKeys = <String, String>{};
  final _receipts = <String, (String trfId, int polls, ReceiptView view)>{};
  final _arrivalKeys = <String>{};
  int _seq = 0;
  int receiptCalls = 0;

  /// 목 입고 예정 ID(다음 작업 받기 목이 고른다).
  Iterable<String> get trfIds => _promises.keys;
  InboundPromiseView peek(String trfId) => _promises[trfId]!;

  void _add(String id, List<InboundLine> lines) =>
      _promises[id] = InboundPromiseView(
        trfId: id,
        version: 1,
        state: PromiseState.expected,
        plannedArrivalAt: DateTime.utc(2026, 11, 10, 6),
        lines: lines,
      );

  Future<void> _wait() => Future<void>.delayed(latency);

  InboundPromiseView _copy(
    InboundPromiseView p, {
    PromiseState? state,
    DateTime? arrivedAt,
    List<InboundLine>? lines,
    List<ReceiptView>? receipts,
  }) => InboundPromiseView(
    trfId: p.trfId,
    version: p.version + 1,
    state: state ?? p.state,
    plannedArrivalAt: p.plannedArrivalAt,
    eta: p.eta,
    arrivedAt: arrivedAt ?? p.arrivedAt,
    lines: lines ?? p.lines,
    receipts: receipts ?? p.receipts,
  );

  @override
  Future<InboundPromiseView> promise(String trfId) async {
    await _wait();
    return _promises[trfId] ??
        (throw const ProblemFailure(
          Problem(status: 404, code: ProblemCode.notFound),
        ));
  }

  @override
  Future<InboundCommandOutcome> recordArrival(
    String trfId, {
    required int version,
    required DateTime arrivedAt,
    required String recordedBy,
    required IdempotencyKey key,
  }) async {
    await _wait();
    final p = _promises[trfId]!;
    if (_arrivalKeys.contains(key.value)) return const InboundAccepted();
    if (p.state != PromiseState.expected) {
      return const InboundRejected(InboundProblemCode.invalidState);
    }
    if (p.version != version) {
      return const InboundRejected(InboundProblemCode.versionConflict);
    }
    _arrivalKeys.add(key.value);
    _promises[trfId] = _copy(
      p,
      state: PromiseState.receiving,
      arrivedAt: arrivedAt.toUtc(),
    );
    return const InboundAccepted();
  }

  @override
  Future<InboundCommandOutcome> recordReceipt(
    String trfId, {
    required int version,
    required List<(InboundLine, ReceiptCount)> counts,
    required DateTime receivedAt,
    required String receivedBy,
    required IdempotencyKey key,
  }) async {
    await _wait();
    receiptCalls++;
    final existing = _receiptKeys[key.value];
    if (existing != null) return InboundAccepted(resultId: existing);
    final p = _promises[trfId]!;
    if (p.state != PromiseState.receiving) {
      return const InboundRejected(InboundProblemCode.invalidState);
    }
    if (p.version != version) {
      return const InboundRejected(InboundProblemCode.versionConflict);
    }
    final id = 'rcp-${++_seq}';
    _receiptKeys[key.value] = id;
    final view = ReceiptView(
      receiptId: id,
      applyStatus: ApplyStatus.submitted,
      receivedAt: receivedAt.toUtc(),
    );
    _receipts[id] = (trfId, 0, view);
    _promises[trfId] = _copy(
      p,
      lines: [
        for (final l in p.lines)
          switch (counts.where((c) => c.$1.key == l.key).firstOrNull) {
            null => l,
            (_, final c) => InboundLine(
              sku: l.sku,
              lotId: l.lotId,
              productName: l.productName,
              barcode: l.barcode,
              expectedQty: l.expectedQty,
              receivedQty: c.total,
              quarantinedQty: c.quarantined,
              pendingQty: c.pending,
            ),
          },
      ],
      receipts: [...p.receipts, view],
    );
    if (loseNextReceiptResponse) {
      loseNextReceiptResponse = false;
      return const InboundUnknown();
    }
    return InboundAccepted(resultId: id);
  }

  @override
  Future<ReceiptView> receipt(String trfId, String receiptId) async {
    await _wait();
    final r = _receipts[receiptId]!;
    final polls = r.$2 + 1;
    var view = r.$3;
    if (!view.applyStatus.finished && polls >= applyPolls) {
      view = ReceiptView(
        receiptId: view.receiptId,
        applyStatus: rejectApply ? ApplyStatus.rejected : ApplyStatus.applied,
        commitId: rejectApply ? null : 'commit-$receiptId',
        receivedAt: view.receivedAt,
      );
      if (!rejectApply) {
        final p = _promises[trfId]!;
        _promises[trfId] = _copy(
          p,
          state: PromiseState.tinPosted,
          receipts: [
            for (final x in p.receipts) x.receiptId == receiptId ? view : x,
          ],
        );
      }
    }
    _receipts[receiptId] = (trfId, polls, view);
    return view;
  }
}
