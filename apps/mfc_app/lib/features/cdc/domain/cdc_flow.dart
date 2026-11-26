import 'package:flutter/foundation.dart';

/// 피킹이 끝난 TRF(계약 cdc-outbound TransferSummary) — 분배·검품·상차는 TRF 를 골라 시작한다.
@immutable
final class CdcTrf {
  const CdcTrf({
    required this.trfId,
    required this.trfNumber,
    required this.mfcId,
    required this.waveId,
    required this.waveNumber,
    required this.dueAt,
    required this.pickedQty,
  });

  final String trfId;
  final String? trfNumber;
  final String mfcId;
  final String? waveId;
  final String? waveNumber;
  final DateTime dueAt;
  final int pickedQty;

  String get label => trfNumber ?? trfId;
}

/// 분배할 것 — TRF 몫으로 집은 SKU·LOT(작업 줄의 shares)와 이미 BOX 에 담은 수량.
@immutable
final class CdcSortItem {
  const CdcSortItem({
    required this.sku,
    required this.productName,
    required this.lot,
    required this.pickedQty,
    required this.sortedQty,
  });

  final String sku;
  final String? productName;
  final String lot;
  final int pickedQty;
  final int sortedQty;

  int get remaining => pickedQty - sortedQty;
  String get key => '$sku|$lot';
}

/// LPN(계약 listCenterLpns 한 줄)
@immutable
final class CdcLpn {
  const CdcLpn({
    required this.lpn,
    required this.unitType,
    required this.inspection,
    required this.failReason,
    required this.loaded,
    required this.tripId,
    required this.vehicleId,
    required this.temperatureZone,
    required this.contents,
  });

  final String lpn;

  /// BOX·PLT·RT
  final String unitType;

  /// PASSED·FAILED·null(검품 전)
  final String? inspection;
  final String? failReason;
  final bool loaded;
  final String? tripId;
  final String? vehicleId;
  final String? temperatureZone;
  final List<CdcLpnContent> contents;

  bool get passed => inspection == 'PASSED';
  int get qty => contents.fold(0, (a, c) => a + c.qty);
}

@immutable
final class CdcLpnContent {
  const CdcLpnContent({
    required this.sku,
    required this.lot,
    required this.qty,
  });

  final String sku;
  final String lot;
  final int qty;
}

/// 분배 결과로 만들 BOX 한 개
@immutable
final class CdcBoxDraft {
  const CdcBoxDraft({
    required this.lpn,
    required this.temperatureZone,
    required this.contents,
  });

  final String lpn;

  /// AMBIENT·CHILLED·FROZEN(고르지 않으면 null)
  final String? temperatureZone;
  final List<CdcLpnContent> contents;
}

/// 검품 결과 한 LPN
@immutable
final class CdcInspection {
  const CdcInspection({
    required this.lpn,
    required this.passed,
    this.failReason,
    this.temperatureC,
  });

  final String lpn;
  final bool passed;

  /// QTY_MISMATCH·SEAL_BROKEN·TEMPERATURE·DAMAGE·WRONG_TRF·OTHER
  final String? failReason;
  final num? temperatureC;
}

const cdcFailReasons = [
  'QTY_MISMATCH',
  'SEAL_BROKEN',
  'TEMPERATURE',
  'DAMAGE',
  'WRONG_TRF',
  'OTHER',
];

const cdcTemperatureZones = ['AMBIENT', 'CHILLED', 'FROZEN'];

/// 적치 지시(계약 cdc-inbound PutawayTask)
@immutable
final class CdcPutaway {
  const CdcPutaway({
    required this.taskId,
    required this.state,
    required this.version,
    required this.rows,
  });

  final String taskId;

  /// CREATED·RESERVED·DISPATCHED·IN_PROGRESS·PARTIALLY_COMPLETED·COMPLETED·FAILED·RETRY_READY·CANCELLED …
  final String state;
  final int version;
  final List<CdcPutawayRow> rows;

  bool get finished => state == 'COMPLETED' || state == 'CANCELLED';
}

/// 적치 줄 — 지시량 q = 완료 c + 미완료 u + 취소 k
@immutable
final class CdcPutawayRow {
  const CdcPutawayRow({
    required this.sku,
    required this.lot,
    required this.location,
    required this.q,
    required this.c,
    required this.u,
    required this.k,
  });

  final String sku;
  final String lot;
  final String location;
  final int q;
  final int c;
  final int u;
  final int k;

  String get key => '$sku|$lot';
}

/// 적치 실행 한 줄
@immutable
final class CdcPutawayLine {
  const CdcPutawayLine({
    required this.row,
    required this.toLocation,
    required this.completedQty,
    this.exceptionReason,
  });

  final CdcPutawayRow row;
  final String toLocation;
  final int completedQty;

  /// 지시 위치와 다르면 필수 — LOCATION_FULL·LOCATION_BLOCKED·DAMAGED·WRONG_LOT·OTHER
  final String? exceptionReason;
}

const cdcPutawayExceptions = [
  'LOCATION_FULL',
  'LOCATION_BLOCKED',
  'DAMAGED',
  'WRONG_LOT',
  'OTHER',
];
