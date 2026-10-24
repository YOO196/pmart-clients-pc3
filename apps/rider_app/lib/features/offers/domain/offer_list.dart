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
    this.dropAreaLabel,
    this.estimatedFee,
  });

  final String offerId;

  /// 서버 기준 남은 응답 시간. 단말 시계로 계산하지 않는다. 0이 돼도 만료 확정이 아니다.
  final int? remainingSec;
  final DateTime? expiresAt;
  final String? dropAreaLabel;
  final int? estimatedFee;
}
