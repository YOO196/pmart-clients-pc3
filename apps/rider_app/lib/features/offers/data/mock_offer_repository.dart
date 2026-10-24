import 'package:pmart_api_delivery_dispatch/pmart_api_delivery_dispatch.dart';

import '../domain/offer_list.dart';
import 'offer_repository.dart';

/// 목 구현. 계약(`delivery-dispatch-service.yaml` listMyOffers) 모양 JSON 을 생성 모델로 읽는다.
final class MockOfferRepository implements OfferRepository {
  MockOfferRepository({this.latency = const Duration(milliseconds: 300)});

  final Duration latency;

  static const fixture = <String, Object?>{
    'items': [
      {
        'offerId': 'offer-mock-1',
        'attemptId': 'att-1',
        'deliveryId': 'dlv-1',
        'riderId': 'rider-mock-1',
        'sentAt': '2026-10-24T06:00:00Z',
        'expiresAt': '2026-10-24T06:01:00Z',
        'remainingSec': 42,
        'state': 'SENT',
        'summary': {
          'mfcId': 'MFC-MOCK-01',
          'dropAreaLabel': '목동 1단지',
          'distanceKm': 1.8,
          'weightG': 3200,
          'containsAlcohol': false,
          'estimatedFee': 3500,
        },
      },
    ],
    'page': {'nextCursor': null, 'size': 50},
    'serverTime': '2026-10-24T06:00:18Z',
    // 서버 잠정 기본값 5초. 클라이언트는 이 값을 하드코딩하지 않는다.
    'pollAfterSec': 5,
  };

  @override
  Future<OfferList> activeOffers() async {
    await Future<void>.delayed(latency);
    return offerListFromContract(ListMyOffers200Response.fromJson(fixture));
  }
}
