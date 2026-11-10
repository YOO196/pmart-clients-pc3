import 'package:flutter/foundation.dart';

/// 입고 예정(TRF) 상태. EXPECTED → RECEIVING(도착 등록) → TIN_POSTED(수령 반영).
enum PromiseState { expected, receiving, tinPosted, cancelled, unknown }

/// 재고 반영 상태. APPLIED 만 반영 완료다.
enum ApplyStatus {
  captured,
  submitted,
  processing,
  applied,
  rejected,
  unknownResult,
  unknown;

  bool get finished => this == applied || this == rejected;
}

/// 예정과 다른 이유(계약 값).
enum DiscrepancyReason {
  notReceived('NOT_RECEIVED'),
  short('SHORT'),
  over('OVER'),
  damaged('DAMAGED'),
  temperature('TEMPERATURE');

  const DiscrepancyReason(this.wire);

  final String wire;
}

@immutable
class InboundLine {
  const InboundLine({
    required this.sku,
    required this.expectedQty,
    this.lotId,
    this.productName,
    this.barcode,
    this.unitsPerBox,
    this.boxCount,
    this.receivedQty = 0,
    this.quarantinedQty = 0,
    this.pendingQty = 0,
  });

  final String sku;
  final String? lotId;

  /// 표시용 상품명·스캔 대조값 — 계약 입고 예정 행에 없다(BR-53). 목만 채운다.
  final String? productName;
  final String? barcode;

  /// 박스 입수·예정 박스 수 — 계약에 없다(BR-53 R17). 목만. 수량(expectedQty)은 판매 단위.
  final int? unitsPerBox;
  final int? boxCount;
  final int expectedQty;
  final int receivedQty;
  final int quarantinedQty;
  final int pendingQty;

  /// 같은 SKU 라도 LOT 가 다르면 다른 행이다.
  String get key => '$sku|${lotId ?? ''}';
}

@immutable
class ReceiptView {
  const ReceiptView({
    required this.receiptId,
    required this.applyStatus,
    this.commitId,
    this.receivedAt,
  });

  final String receiptId;
  final ApplyStatus applyStatus;
  final String? commitId;
  final DateTime? receivedAt;
}

@immutable
class InboundPromiseView {
  const InboundPromiseView({
    required this.trfId,
    required this.version,
    required this.state,
    required this.lines,
    this.plannedArrivalAt,
    this.eta,
    this.arrivedAt,
    this.receipts = const [],
    this.rollContainers,
    this.boxes,
    this.temperatureZone,
    this.boxList = const [],
  });

  /// 차량 적재 단위(롤테이너 R/T)·박스 수·온도대 — 계약 입고 예정에 없다(BR-53 R17). 목만.
  final int? rollContainers;
  final int? boxes;
  final String? temperatureZone;

  /// 이 송장의 박스 하나하나(박스 바코드 = 번호 자체, 채번 지침 G-05). 계약에 없다(BR-53 R17) — 목만.
  /// 비어 있으면 박스 검수 없이 상품별 계수로 한다.
  final List<InboundBox> boxList;

  List<InboundBox> boxesOf(InboundLine l) => [
    for (final b in boxList)
      if (b.lineKey == l.key) b,
  ];

  final String trfId;
  final int version;
  final PromiseState state;
  final DateTime? plannedArrivalAt;
  final DateTime? eta;
  final DateTime? arrivedAt;
  final List<InboundLine> lines;
  final List<ReceiptView> receipts;

  int get expectedTotal => lines.fold(0, (s, l) => s + l.expectedQty);
}

/// 송장의 박스 하나. 한 박스엔 한 상품(행)만 — 입수만큼 들어 있어야 한다.
@immutable
class InboundBox {
  const InboundBox({
    required this.boxId,
    required this.lineKey,
    required this.unitsPerBox,
  });

  /// `BOX-{8자리}` — 스캔값도 이 번호.
  final String boxId;

  /// 어느 행(SKU·LOT)의 박스인지([InboundLine.key]).
  final String lineKey;
  final int unitsPerBox;
}

/// 한 행의 현장 계수. 인수 = 정상 + 격리 + 미판정(IV-02).
@immutable
class ReceiptCount {
  const ReceiptCount({
    this.normal = 0,
    this.quarantined = 0,
    this.pending = 0,
    this.quarantineReason,
  });

  final int normal;
  final int quarantined;
  final int pending;

  /// 격리 사유(파손·온도). 격리가 있으면 고른다.
  final DiscrepancyReason? quarantineReason;

  int get total => normal + quarantined + pending;

  ReceiptCount copyWith({
    int? normal,
    int? quarantined,
    int? pending,
    DiscrepancyReason? Function()? quarantineReason,
  }) => ReceiptCount(
    normal: normal ?? this.normal,
    quarantined: quarantined ?? this.quarantined,
    pending: pending ?? this.pending,
    quarantineReason: quarantineReason != null
        ? quarantineReason()
        : this.quarantineReason,
  );

  /// 보낼 차이 사유. 수량이 다르면 수량 사유(0 = 미도착), 같고 격리가 있으면 격리 사유. 가정 — 행당 하나라서.
  DiscrepancyReason? reasonFor(int expected) {
    if (total == 0 && expected > 0) return DiscrepancyReason.notReceived;
    if (total < expected) return DiscrepancyReason.short;
    if (total > expected) return DiscrepancyReason.over;
    if (quarantined > 0) return quarantineReason;
    return null;
  }

  /// 격리가 있는데 사유를 안 골랐으면 아직 못 넘어간다.
  bool get complete => quarantined == 0 || quarantineReason != null;
}

/// 도착 등록·수령 등록 결과.
@immutable
sealed class InboundCommandOutcome {
  const InboundCommandOutcome();
}

/// 접수됨(202). 수령이면 resultId = receiptId. 접수 ≠ 반영 — 반영은 조회로 확인한다.
final class InboundAccepted extends InboundCommandOutcome {
  const InboundAccepted({this.resultId});

  final String? resultId;
}

final class InboundRejected extends InboundCommandOutcome {
  const InboundRejected(this.code);

  final String code;
}

/// 응답을 못 받았다. 같은 키로 다시 보내 확정한다.
final class InboundUnknown extends InboundCommandOutcome {
  const InboundUnknown();
}

abstract final class InboundProblemCode {
  static const invalidState = 'INVALID_STATE';
  static const versionConflict = 'VERSION_CONFLICT';
}
