import 'package:flutter/foundation.dart';

/// `GET /offers` 결과(화면용).
@immutable
class OfferList {
  const OfferList({
    required this.offers,
    required this.pollAfter,
    required this.serverTime,
  });

  final List<OfferItem> offers;

  /// 서버가 정한 다음 조회 간격. null 이면 지금은 제안을 받을 수 없는 상태라 폴링을 멈춘다
  /// (회신 `2026-10-24-clients-reply-br06-offer-polling.md`).
  final Duration? pollAfter;

  final DateTime? serverTime;
}

@immutable
class OfferItem {
  const OfferItem({
    required this.offerId,
    required this.remainingSec,
    required this.expiresAt,
    this.deliveryId,
    this.dropAreaLabel,
    this.estimatedFee,
    this.distanceKm,
    this.weightG,
    this.containsAlcohol,
  });

  final String offerId;

  /// 서버 기준 남은 응답 시간. 단말 시계로 계산하지 않는다. 0이 돼도 만료 확정이 아니다.
  final int? remainingSec;
  final DateTime? expiresAt;
  final String? deliveryId;

  /// 라이더 표시용 요약(다른 고객 주소 비노출). 상세 주소는 수락 뒤 수행 화면에서만.
  final String? dropAreaLabel;
  final int? estimatedFee;
  final num? distanceKm;
  final int? weightG;
  final bool? containsAlcohol;
}

/// 늦은 수락 안내 4종(D 188~).
enum LateReason {
  expired,
  alreadyAssigned,
  orderCancelled,
  ineligible,
  unknown,
}

enum RejectReason { tooFar, overCapacity, personal, other }

/// 제안 응답 판정. 서버 수신 시각 기준이다.
@immutable
sealed class OfferOutcome {
  const OfferOutcome();
}

final class OfferAssigned extends OfferOutcome {
  const OfferAssigned({this.deliveryId, this.assignmentId});

  final String? deliveryId;
  final String? assignmentId;
}

final class OfferRejected extends OfferOutcome {
  const OfferRejected({
    this.consecutiveRejections,
    this.rejectionNotice = false,
  });

  final int? consecutiveRejections;

  /// 연속 거절 5회 안내(신규배차 OFF 권유).
  final bool rejectionNotice;
}

final class OfferLate extends OfferOutcome {
  const OfferLate(this.reason);

  final LateReason reason;
}

/// 판정을 받지 못했다. 같은 키로만 다시 보낸다.
final class OfferUnknown extends OfferOutcome {
  const OfferUnknown();
}

/// 운행 상태(rider-service). 신규배차 OFF 는 새 제안만 막는다(진행 배송은 그대로).
@immutable
class OperatingState {
  const OperatingState({
    required this.onDuty,
    required this.newDispatchEnabled,
    required this.version,
    this.activeDeliveryCount = 0,
    this.mfcId,
  });

  final bool onDuty;
  final bool newDispatchEnabled;
  final int version;
  final int activeDeliveryCount;
  final String? mfcId;
}

enum DispatchMode { normal, aiRecommended }
