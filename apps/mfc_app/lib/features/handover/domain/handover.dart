import 'package:flutter/foundation.dart';

import '../../packing/domain/packing.dart' show FenceState, PackageState;

/// 포장 인계 판정(`HandoverResolution.verdict`).
enum HandoverVerdict { ready, stopped, inProgress, handedOver, unknown }

/// 인계의 재고 반영 상태. APPLIED 만 재고 차감 확정이다.
enum InventoryApply {
  notRequested,
  processing,
  applied,
  rejected,
  unknownResult,
}

/// 점원 확인 결과(`POST /packages/{id}/handover-checks`).
enum HandoverCheck {
  /// 포장대에 있음 → 허가 해제.
  atStation,

  /// 포장대에 없음 → 허가 라이더에게 인계된 것으로 확정.
  takenByRider,
}

@immutable
class LastCheckView {
  const LastCheckView({required this.result, this.checkedBy, this.checkedAt});

  final HandoverCheck result;
  final String? checkedBy;
  final DateTime? checkedAt;
}

/// `GET /packages/{id}/handover-resolution` 한 건. 조회 사본이라 확정 근거로 쓰지 않는다.
@immutable
class HandoverView {
  const HandoverView({
    required this.packageId,
    required this.packageState,
    required this.verdict,
    required this.fence,
    required this.inventory,
    required this.checkRequired,
    this.packageVersion,
    this.fenceExpiresAt,
    this.handoverId,
    this.shipmentId,
    this.orderId,
    this.orderNumber,
    this.handoverCode,
    this.packingLocation,
    this.riderId,
    this.lastCheck,
    this.fresh = true,
  });

  final String packageId;
  final int? packageVersion;
  final PackageState packageState;
  final HandoverVerdict verdict;
  final FenceState fence;
  final DateTime? fenceExpiresAt;
  final String? handoverId;
  final InventoryApply inventory;

  /// 허가가 만료됐지만 확정 요청이 없어 점원 확인이 필요하다.
  final bool checkRequired;
  final String? shipmentId;
  final String? orderId;

  /// 화면용 주문번호(fulfillment 0.21.0 `HandoverResolution.orderNumber`, ADR-0070).
  final String? orderNumber;

  /// 포장 라벨 인계 번호(0.21.0 — 새 포장 4자리, 예전 포장 6자리).
  final String? handoverCode;
  final String? packingLocation;
  final String? riderId;
  final LastCheckView? lastCheck;

  /// `asOf.freshness == CURRENT`.
  final bool fresh;
}

/// 라이더 화면 표기(rider 0.18.0 `GET /riders/display-names`) — "김*수 · 482913".
@immutable
class RiderLabel {
  const RiderLabel({this.riderNumber, this.nameMasked});

  final String? riderNumber;

  /// 가린 이름(첫·끝 글자). 탈퇴로 지워졌으면 null.
  final String? nameMasked;

  /// 둘 다 없으면 null(화면은 "라이더").
  String? get text {
    final parts = [?nameMasked, ?riderNumber];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

@immutable
class HandoverCheckList {
  const HandoverCheckList({required this.items, required this.fresh});

  final List<HandoverView> items;
  final bool fresh;
}

/// 점원 확인 결과.
@immutable
sealed class CheckOutcome {
  const CheckOutcome();
}

final class CheckDone extends CheckOutcome {
  const CheckDone(this.resolution);

  final HandoverView resolution;
}

final class CheckRejected extends CheckOutcome {
  const CheckRejected(this.code);

  final String code;
}

/// 확인이 반영됐는지 모른다. 같은 키로만 다시 보낸다.
final class CheckUnknown extends CheckOutcome {
  const CheckUnknown();
}

/// 포장 QR 원문(`PKG:<packageId>:<packageVersion>`, fulfillment authorizePackageHandover 설명 0.4.0)을 해석한다.
/// 형식이 아니면 null — 서버에 보내지 않고 "포장 QR 이 아니에요"로 안내한다.
({String packageId, int version})? parsePackageQr(String raw) {
  final s = raw.trim();
  if (!s.startsWith('PKG:')) return null;
  final cut = s.lastIndexOf(':');
  if (cut <= 4) return null;
  final id = s.substring(4, cut);
  final version = int.tryParse(s.substring(cut + 1));
  if (id.isEmpty || version == null || version < 1) return null;
  return (packageId: id, version: version);
}

abstract final class HandoverProblemCode {
  static const fenceActive = 'FENCE_ACTIVE';
  static const invalidState = 'INVALID_STATE';
}

enum EtaStatus { available, locating, pending, finalized, unknown }

enum DeliveryStage {
  unassigned,
  toStore,
  atStore,
  toCustomer,
  atCustomer,
  done,
  unknown,
}

/// 라이더 픽업 ETA(점원은 pickupEta 를 받는다).
@immutable
class PickupEtaView {
  const PickupEtaView({
    required this.stage,
    required this.status,
    this.etaAt,
    this.remainingSeconds,
    this.fresh = true,
  });

  final DeliveryStage stage;
  final EtaStatus status;
  final DateTime? etaAt;
  final int? remainingSeconds;
  final bool fresh;
}
