import 'package:flutter/foundation.dart';

enum ShipmentState {
  preparing,
  ready,
  partiallyHandedOver,
  handedOver,
  cancelled,
  closedPartial,
  unknown,
}

enum PackageState { open, sealed, handedOver, invalidated, voided, unknown }

/// 인계 fence. HANDOVER_IN_PROGRESS 동안 재포장·취소·다른 기사 인계를 막는다.
enum FenceState { none, inProgress, committed, expired, unknown }

enum TemperatureZone { ambient, chilled, frozen }

@immutable
class ContentLine {
  const ContentLine({
    required this.orderLineId,
    required this.sku,
    required this.qty,
    this.lotId,
  });

  final String orderLineId;
  final String sku;
  final int qty;
  final String? lotId;
}

@immutable
class PackageView {
  const PackageView({
    required this.packageId,
    required this.packageVersion,
    required this.version,
    required this.state,
    required this.contents,
    required this.fence,
    this.qrCode,
    this.bagCount,
    this.temperatureZone,
    this.stagingLocation,
    this.handoverCode,
  });

  final String packageId;

  /// 포장 라벨에 크게 찍는 6자리 숫자(fulfillment 0.13.0 `Package.handoverCode`). 라이더가 QR 대신 이 숫자를
  /// 넣어 인계받는다. 화면·라벨에서 포장을 가리키는 번호(ADR-0070) — 시스템 포장 ID 대신.
  final String? handoverCode;

  /// 올려 둔 출하대기 랙(fulfillment 0.20.0 `Package.stagingLocation`). null 이면 아직 패킹대.
  final String? stagingLocation;

  /// 재포장마다 오른다. QR 에 들어간다.
  final int packageVersion;
  final int version;
  final PackageState state;
  final String? qrCode;
  final List<ContentLine> contents;
  final int? bagCount;
  final String? temperatureZone;
  final FenceState fence;

  /// 재포장할 수 있는지(안내용). 인계 전 밀봉 상태이고 fence 가 없을 때만. 최종 판정은 서버.
  bool get canRepack =>
      state == PackageState.sealed && fence == FenceState.none;
}

@immutable
class ShipmentView {
  const ShipmentView({
    required this.shipmentId,
    required this.version,
    required this.state,
    required this.packages,
    this.orderId,
    this.orderNumber,
    this.deliveryId,
    this.holdReason,
    this.dispatchRequest,
  });

  final String shipmentId;
  final String? orderId;

  /// 화면용 주문번호 8자리(fulfillment 0.13.0) — 점원이 라이더·상담원과 같은 번호로 말한다. 번호 전 주문은 null.
  final String? orderNumber;

  /// 배송번호. 출하 준비(ShipmentReady) 전에는 없을 수 있다.
  final String? deliveryId;
  final int version;
  final ShipmentState state;
  final String? holdReason;
  final List<PackageView> packages;

  /// 서버에 남은 배차 요청(없으면 null). 점원 요청이든 자동 요청이든 출고당 하나다.
  final DispatchRequestView? dispatchRequest;

  /// 유효 포장(밀봉·인계)에 담긴 orderLine 별 수량.
  Map<String, int> get packedByLine {
    final m = <String, int>{};
    for (final p in packages) {
      if (p.state != PackageState.sealed &&
          p.state != PackageState.handedOver) {
        continue;
      }
      for (final c in p.contents) {
        m[c.orderLineId] = (m[c.orderLineId] ?? 0) + c.qty;
      }
    }
    return m;
  }
}

/// 밀봉·재포장 결과.
@immutable
sealed class PackOutcome {
  const PackOutcome();
}

final class PackDone extends PackOutcome {
  const PackDone(this.package);

  final PackageView package;
}

final class PackRejected extends PackOutcome {
  const PackRejected(this.code);

  final String code;
}

/// 밀봉됐는지 모른다. 같은 키로만 다시 보낸다(포장을 새로 만들지 않는다).
final class PackUnknown extends PackOutcome {
  const PackUnknown();
}

/// 출하대기 랙에 올리기(`POST /packages/{id}/staging`, BR-52 R20) 결과.
sealed class StageOutcome {
  const StageOutcome();
}

/// 서버가 랙 위치를 기록했다(같은 랙 다시 찍기도 그대로).
final class StageDone extends StageOutcome {
  const StageDone(this.stagingLocation);

  final String stagingLocation;
}

/// 409 INVALID_STATE(밀봉 안 됨·이미 인계·무효) · 422 STAGING_REJECTED(랙 아님) 등.
final class StageRejected extends StageOutcome {
  const StageRejected(this.code);

  final String code;
}

/// 올렸는지 모른다(시간 초과·503). 같은 키로만 다시 보낸다.
final class StageUnknown extends StageOutcome {
  const StageUnknown();
}

enum RepackReason { damagedBag, contentChange, labelUnreadable, shortageAdjust }

/// 봉투 나누기(`POST /shipments/{id}/repackings` — 포장 사이 재구성) 결과.
sealed class RegroupOutcome {
  const RegroupOutcome();
}

/// 새 포장들(새 ID·새 QR). 이전 포장은 INVALIDATED.
final class RegroupDone extends RegroupOutcome {
  const RegroupDone(this.packages);

  final List<PackageView> packages;
}

final class RegroupRejected extends RegroupOutcome {
  const RegroupRejected(this.code);

  final String code;
}

/// 나눠졌는지 모른다 — 같은 키·같은 나눔으로만 다시.
final class RegroupUnknown extends RegroupOutcome {
  const RegroupUnknown();
}

/// 포장 [p] 를 둘로 나눈다: [moved](주문 줄 → 옮길 수량)만큼 새 봉투로, 나머지는 남는 봉투로.
/// 한 주문 줄이 여러 LOT 줄이면 앞 줄부터 옮긴다(LOT 는 그대로 — 합계가 같아야 서버가 받는다).
/// 둘 중 하나가 비면 null.
({List<ContentLine> keep, List<ContentLine> move})? splitContents(
  PackageView p,
  Map<String, int> moved,
) {
  final left = {...moved};
  final keep = <ContentLine>[];
  final move = <ContentLine>[];
  for (final c in p.contents) {
    final m = (left[c.orderLineId] ?? 0).clamp(0, c.qty);
    left[c.orderLineId] = (left[c.orderLineId] ?? 0) - m;
    if (m > 0) {
      move.add(
        ContentLine(
          orderLineId: c.orderLineId,
          sku: c.sku,
          qty: m,
          lotId: c.lotId,
        ),
      );
    }
    if (c.qty - m > 0) {
      keep.add(
        ContentLine(
          orderLineId: c.orderLineId,
          sku: c.sku,
          qty: c.qty - m,
          lotId: c.lotId,
        ),
      );
    }
  }
  if (keep.isEmpty || move.isEmpty) return null;
  return (keep: keep, move: move);
}

/// 배차 요청이 어떻게 생겼나. 점원 요청(MANUAL) 또는 출하 준비 시 자동(AUTO_ON_READY).
enum DispatchTrigger { manual, autoOnReady, unknown }

/// 배차 요청(D-5). 요청 ≠ 배정 — 라이더를 찾는 일은 delivery-dispatch 가 한다.
@immutable
class DispatchRequestView {
  const DispatchRequestView({
    required this.trigger,
    required this.estimatedReadyAt,
    required this.requestedAt,
    this.estimatedPackMinutes,
  });

  final DispatchTrigger trigger;
  final int? estimatedPackMinutes;

  /// 서버가 정한 예상 포장 완료 시각(UTC).
  final DateTime estimatedReadyAt;
  final DateTime requestedAt;
}

/// 배차 요청 결과.
@immutable
sealed class DispatchOutcome {
  const DispatchOutcome();
}

/// 요청됨(새로 요청했거나 이미 요청돼 있던 것).
final class DispatchDone extends DispatchOutcome {
  const DispatchDone(this.request);

  final DispatchRequestView request;
}

final class DispatchRejected extends DispatchOutcome {
  const DispatchRejected(this.code);

  final String code;
}

/// 요청됐는지 모른다. 같은 키로 다시 보내면 서버가 그 요청을 돌려준다(출고당 한 번).
final class DispatchUnknown extends DispatchOutcome {
  const DispatchUnknown();
}

abstract final class PackProblemCode {
  static const contentMismatch = 'CONTENT_MISMATCH';
  static const invalidState = 'INVALID_STATE';

  /// 랙 올리기 — 찍은 칸이 출하대기 랙이 아님(fulfillment 0.20.0 / inventory 0.29.0).
  static const stagingRejected = 'STAGING_REJECTED';
  static const orderCancelled = 'ORDER_CANCELLED';
}
