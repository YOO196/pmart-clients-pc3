import 'package:flutter/foundation.dart';

/// 입고 작업(mfc-inbound InboundTask) — 품질검사(INSPECT)·적치(PUTAWAY).
enum InboundTaskKind { inspect, putaway, unknown }

@immutable
class InboundTaskView {
  const InboundTaskView({
    required this.taskId,
    required this.kind,
    required this.receiptId,
    required this.sku,
    required this.lotId,
    required this.locationCode,
    required this.plannedQty,
    required this.doneQty,
    required this.completed,
    required this.version,
    this.parentTaskId,
  });

  final String taskId;
  final InboundTaskKind kind;
  final String receiptId;
  final String? parentTaskId;
  final String sku;

  /// 품질검사 = 수령 LOT, 적치 = 나뉜 LOT.
  final String lotId;

  /// 출발 위치.
  final String locationCode;
  final int plannedQty;
  final int doneQty;
  final bool completed;
  final int version;

  int get remainingQty => plannedQty - doneQty;
}

/// 품질검사 결과 한 줄. 같은 제조 LOT 표기·소비기한은 같은 LOT 이 된다.
@immutable
class InspectionResult {
  const InspectionResult({
    required this.qty,
    required this.quarantined,
    this.sourceLotRef,
    this.expiryDate,
    this.manufactureDate,
  });

  final int qty;

  /// 격리 판정. 아니면 정상.
  final bool quarantined;

  /// 상품에 찍힌 제조 LOT 표기.
  final String? sourceLotRef;

  /// 소비기한(yyyy-MM-dd).
  final String? expiryDate;

  /// 제조일(yyyy-MM-dd). 오늘 이후·소비기한 이후면 서버가 400.
  final String? manufactureDate;
}

/// 품질검사·적치 실행 결과(APPLIED 일 때만 확정).
@immutable
class InboundTaskExecutionView {
  const InboundTaskExecutionView({
    required this.executionId,
    required this.task,
    this.commitId,
    this.createdTaskIds = const [],
  });

  final String executionId;
  final InboundTaskView? task;
  final String? commitId;

  /// 품질검사가 만든 적치 작업.
  final List<String> createdTaskIds;
}

/// 회수품 검수 판정.
enum ReturnVerdict { resale, dispose }

enum TempZone { ambient, chilled, frozen }

/// 폐기 사유(계약 값).
enum DisposeReason {
  temperatureZone('TEMPERATURE_ZONE'),
  fresh('FRESH'),
  opened('OPENED'),
  damaged('DAMAGED'),
  expired('EXPIRED'),
  other('OTHER');

  const DisposeReason(this.wire);

  final String wire;
}

/// 회수품 검수 한 줄. 재판매는 상온·미개봉·신선 아님일 때만(아니면 서버 422 RESALE_NOT_ALLOWED).
@immutable
class ReturnInspectionLine {
  const ReturnInspectionLine({
    required this.sku,
    required this.qty,
    required this.verdict,
    required this.zone,
    required this.opened,
    this.orderLineId,
    this.lotId,
    this.fresh = false,
    this.disposeReason,
  });

  final String sku;
  final String? orderLineId;
  final String? lotId;
  final int qty;
  final ReturnVerdict verdict;
  final TempZone zone;
  final bool fresh;
  final bool opened;
  final DisposeReason? disposeReason;

  /// 화면 안내용 — 최종 판정은 서버.
  bool get resaleAllowed => zone == TempZone.ambient && !fresh && !opened;
}

abstract final class QualityProblemCode {
  static const resaleNotAllowed = 'RESALE_NOT_ALLOWED';
  static const qtyExceedsReceived = 'QTY_EXCEEDS_RECEIVED';
}
