import 'package:flutter/foundation.dart';
import 'package:pmart_api_cdc_outbound/pmart_api_cdc_outbound.dart' as co;
import 'package:pmart_core/pmart_core.dart';

/// DC 작업(계약 cdc-outbound `Task`) — PDA 피킹에 쓰는 필드만 읽는다.
@immutable
final class CdcTask {
  const CdcTask({
    required this.taskId,
    required this.taskNumber,
    required this.waveNumber,
    required this.trfNumbers,
    required this.kind,
    required this.pickMethod,
    required this.zone,
    required this.floor,
    required this.dueAt,
    required this.state,
    required this.version,
    required this.lines,
    this.pickMode,
    this.regionCode,
  });

  final String taskId;

  /// 화면 번호(없으면 옛 기록 — taskId 를 보인다)
  final String? taskNumber;
  final String? waveNumber;
  final List<String> trfNumbers;

  /// PICK·SORT·INSPECT·LOAD
  final String kind;

  /// DPS·BOX_PICK·FC·DISTRIBUTION·LINE(없을 수 있다)
  final String? pickMethod;

  /// (0.9.0) DISCRETE·REGION_BATCH·SKU_BATCH — 문구가 다르다(C-01)
  final String? pickMode;

  /// REGION_BATCH 의 지역 = 지역 카트 바코드 값
  final String? regionCode;
  final String? zone;
  final String? floor;
  final DateTime? dueAt;

  /// CREATED·ASSIGNED·ACCEPTED·HELD·IN_PROGRESS·PARTIAL·DONE·EXCEPTION·CANCELLED
  final String state;
  final int version;
  final List<CdcTaskLine> lines;

  String get label => taskNumber ?? taskId;
  bool get accepted => state == 'ACCEPTED';
  bool get inProgress => state == 'IN_PROGRESS';

  /// 서버가 끝냈다고 확정한 상태(PARTIAL = 부족 있이 끝남)
  bool get finished => state == 'DONE' || state == 'PARTIAL';
}

@immutable
final class CdcTaskLine {
  const CdcTaskLine({
    required this.sku,
    required this.productName,
    required this.lot,
    required this.locationCode,
    required this.plannedQty,
    required this.pickedQty,
    required this.shortQty,
  });

  final String sku;
  final String? productName;
  final String lot;
  final String locationCode;
  final int plannedQty;

  /// 서버에 이미 반영된 실피킹·부족
  final int pickedQty;
  final int shortQty;

  /// 아직 보내지 않은 수량
  int get remaining => plannedQty - pickedQty - shortQty;

  /// 줄 구분(계약: 줄은 SKU·LOT·위치로 맞춘다)
  String get key => '$sku|$lot|$locationCode';
}

/// 피킹 결과 한 줄(계약 pick-results lines)
@immutable
final class CdcPickLine {
  const CdcPickLine({
    required this.line,
    required this.pickedQty,
    required this.shortQty,
    this.shortReason,
  });

  final CdcTaskLine line;
  final int pickedQty;
  final int shortQty;

  /// NOT_FOUND·DAMAGED·EXPIRED·LOCATION_BLOCKED·OTHER — 부족이 있을 때만
  final String? shortReason;
}

/// 다음 작업 받기 결과 — 받을 작업이 없으면 [CdcNoTask].
sealed class CdcNextTask {
  const CdcNextTask();
}

final class CdcGotTask extends CdcNextTask {
  const CdcGotTask(this.task);
  final CdcTask task;
}

final class CdcNoTask extends CdcNextTask {
  const CdcNoTask();
}

/// 부족 사유(계약 shortReason)
const cdcShortReasons = [
  'NOT_FOUND',
  'DAMAGED',
  'EXPIRED',
  'LOCATION_BLOCKED',
  'OTHER',
];

/// 계약 Task → 화면 모델. 필수 값이 없으면 계약 위반.
CdcTask cdcTaskFromContract(co.Task t) {
  String? str(String? v) => v == null || v.isEmpty ? null : v;
  final id = t.taskId;
  final state = t.state;
  if (id == null || state == null) {
    throw const ContractViolationFailure('Task 에 taskId·state 가 없다');
  }
  return CdcTask(
    taskId: id,
    taskNumber: str(t.taskNumber),
    waveNumber: str(t.waveNumber),
    trfNumbers: t.trfNumbers ?? const [],
    kind: t.kind?.value ?? 'PICK',
    pickMethod: t.pickMethod?.value,
    pickMode: t.pickMode?.value,
    regionCode: str(t.regionCode),
    zone: str(t.zone),
    floor: str(t.floor),
    dueAt: t.dueAt,
    state: state.value,
    version: t.version ?? 0,
    lines: [
      for (final l in t.lines ?? const <co.TaskLinesInner>[])
        CdcTaskLine(
          sku: l.sku ?? '',
          productName: str(l.productName),
          lot: l.lot ?? '',
          locationCode: l.locationCode ?? '',
          plannedQty: l.plannedQty ?? 0,
          pickedQty: l.pickedQty ?? 0,
          shortQty: l.shortQty ?? 0,
        ),
    ],
  );
}
