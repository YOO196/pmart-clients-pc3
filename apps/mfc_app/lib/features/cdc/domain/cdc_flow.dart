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
/// 운행(transport-execution Trip) — 상차는 그 도크의 운행에 싣는다(C-01)
final class CdcTrip {
  const CdcTrip({
    required this.tripId,
    required this.state,
    required this.tempClass,
    required this.vehicleId,
    required this.plateNo,
    required this.driverName,
    required this.dockCode,
    required this.stops,
  });

  final String tripId;

  /// SCHEDULED·CHECKED_IN·LOADED·DEPARTED·COMPLETED·CANCELLED
  final String state;

  /// AMBIENT·CHILLED·FROZEN — 상차 구획 값으로 보낸다
  final String tempClass;
  final String? vehicleId;
  final String? plateNo;
  final String? driverName;
  final String? dockCode;
  final List<CdcTripStop> stops;

  List<String> get trfIds => [for (final s in stops) ...s.trfIds];

  /// 이 운행에 실을 TRF 화면 번호(사용자 2026-11-27 "무슨 TRF 상차인지 모르겠다")
  List<String> get trfNumbers => [for (final s in stops) ...s.knownNumbers];

  String? trfNumberOf(String trfId) {
    for (final s in stops) {
      if (s.numberOf(trfId) case final n?) return n;
    }
    return null;
  }

  String get vehicleLabel => plateNo ?? vehicleId ?? tripId;
  bool get checkedIn => state == 'CHECKED_IN';
  bool get loadedDone =>
      state == 'LOADED' || state == 'DEPARTED' || state == 'COMPLETED';

  /// 차량 스캔 값 — 차량 ID 나 번호판
  bool isVehicle(String code) {
    final c = code.trim().replaceAll(' ', '').toUpperCase();
    return c == (vehicleId ?? '').toUpperCase() ||
        c == (plateNo ?? '').replaceAll(' ', '').toUpperCase();
  }

  CdcTrip withState(String next) => CdcTrip(
    tripId: tripId,
    state: next,
    tempClass: tempClass,
    vehicleId: vehicleId,
    plateNo: plateNo,
    driverName: driverName,
    dockCode: dockCode,
    stops: stops,
  );
}

final class CdcTripStop {
  const CdcTripStop({
    required this.seq,
    required this.mfcId,
    required this.trfIds,
    this.trfNumbers = const [],
  });

  final int seq;
  final String mfcId;
  final List<String> trfIds;

  /// trfIds 순 TRF 화면 번호(T+6, transport-execution 0.6.0) — 모르면 빈 문자열
  final List<String> trfNumbers;

  /// 이 정차 TRF 의 화면 번호(아는 것만)
  List<String> get knownNumbers => [
    for (final n in trfNumbers)
      if (n.isNotEmpty) n,
  ];

  String? numberOf(String trfId) {
    final i = trfIds.indexOf(trfId);
    if (i < 0 || i >= trfNumbers.length || trfNumbers[i].isEmpty) return null;
    return trfNumbers[i];
  }
}
