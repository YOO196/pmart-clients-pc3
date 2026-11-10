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
  });

  final String packageId;

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
    this.deliveryId,
    this.holdReason,
    this.dispatchRequest,
  });

  final String shipmentId;
  final String? orderId;

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

enum RepackReason { damagedBag, contentChange, labelUnreadable, shortageAdjust }

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
  static const orderCancelled = 'ORDER_CANCELLED';
}
