import 'package:flutter/foundation.dart';

/// 배송 수행 상태. GPS·버튼만으로 상태를 바꾸지 않는다(서버 확정).
enum ExecutionState {
  assigned,
  arrivedAtStore,
  pickedUp,
  arrivedAtCustomer,
  completed,
  failed,
  suspended,
  returnInProgress,
  returnPickedUp,
  returnedToStore,
  cancelled,
  unknown;

  static ExecutionState fromWire(String? w) => switch (w) {
    'ASSIGNED' => assigned,
    'ARRIVED_AT_STORE' => arrivedAtStore,
    'PICKED_UP' => pickedUp,
    'ARRIVED_AT_CUSTOMER' => arrivedAtCustomer,
    'COMPLETED' => completed,
    'FAILED' => failed,
    'SUSPENDED' => suspended,
    'RETURN_IN_PROGRESS' => returnInProgress,
    'RETURN_PICKED_UP' => returnPickedUp,
    'RETURNED_TO_STORE' => returnedToStore,
    'CANCELLED' => cancelled,
    _ => unknown,
  };
}

@immutable
class DeliveryView {
  const DeliveryView({
    required this.deliveryId,
    required this.version,
    required this.state,
    required this.packageIds,
    required this.handoverIds,
    this.orderId,
    this.mfcId,
  });

  final String deliveryId;
  final int version;
  final ExecutionState state;
  final String? orderId;
  final String? mfcId;

  /// 이 배송의 포장. 포장마다 스캔해야 한다.
  final List<String> packageIds;

  /// 서버가 확정한 인계(HandoverFact). 픽업 완료에 전부 필요하다.
  final List<String> handoverIds;
}

/// 전달지 정보. BR-24: 라이더가 볼 수 있는 계약 경로가 없어서 목에서만 채운다.
@immutable
class DropInfo {
  const DropInfo({this.addressSummary, this.requestNote});

  final String? addressSummary;
  final String? requestNote;
}

/// 포장 한 개의 인계 진행. 서버가 재고 차감까지 확정한 [handedOver] 만 인계 완료다.
enum HandoverPhase {
  waiting,
  authorizing,
  committing,
  handedOver,

  /// 결과를 모른다. 인계 판정 조회로만 해소한다(다시 스캔해 새 인계를 만들지 않는다).
  checking,
  rejected,

  /// 주문 취소 등으로 출고가 중지됐다.
  stopped,
}

@immutable
class PackageHandover {
  const PackageHandover({
    required this.packageId,
    required this.phase,
    this.handoverId,
    this.rejectCode,
  });

  final String packageId;
  final HandoverPhase phase;
  final String? handoverId;
  final String? rejectCode;
}

/// 스캔 결과(서버에 보내기 전 화면 대조 포함).
enum ScanVerdict { accepted, otherDelivery, duplicate, unreadable }

/// 인계 요청 결과.
@immutable
sealed class HandoverStep {
  const HandoverStep();
}

final class HandoverAuthorized extends HandoverStep {
  const HandoverAuthorized({
    required this.authorizationId,
    required this.fenceVersion,
  });

  final String authorizationId;
  final int fenceVersion;
}

final class HandoverCommitted extends HandoverStep {
  const HandoverCommitted(this.handoverId);

  final String handoverId;
}

final class HandoverRejected extends HandoverStep {
  const HandoverRejected(this.code);

  final String code;
}

final class HandoverUnknown extends HandoverStep {
  const HandoverUnknown();
}

/// 인계 판정 조회 결과.
enum HandoverVerdict { stopped, inProgress, handedOver, unknown }

@immutable
class HandoverResolutionView {
  const HandoverResolutionView({required this.verdict, this.handoverId});

  final HandoverVerdict verdict;
  final String? handoverId;
}

enum CompletionMethod { face, contactless }

enum Placement {
  handedToCustomer,
  frontDoor,
  securityOffice,
  deliveryBox,
  other,
}

enum FailureReason {
  customerAbsent,
  addressError,
  unreachable,
  refused,
  damaged,
  riderIncident,
  other,
}

abstract final class DeliveryCommandKind {
  static const storeArrival = 'store-arrival';
  static const pickup = 'pickup';
  static const customerArrival = 'customer-arrival';
  static const completion = 'completion';
  static const failure = 'failure';
}

abstract final class HandoverProblemCode {
  static const alreadyHandedOver = 'ALREADY_HANDED_OVER';
  static const packageInvalidated = 'PACKAGE_INVALIDATED';
  static const deliveryMismatch = 'DELIVERY_MISMATCH';
  static const fenceActive = 'FENCE_ACTIVE';
  static const handoverNotConfirmed = 'HANDOVER_NOT_CONFIRMED';
  static const evidenceRequired = 'EVIDENCE_REQUIRED';
}
