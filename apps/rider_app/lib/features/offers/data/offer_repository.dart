import 'package:dio/dio.dart';
import 'package:pmart_api_delivery_dispatch/pmart_api_delivery_dispatch.dart';
import 'package:pmart_core/pmart_core.dart';

import '../domain/offer_list.dart';

abstract interface class OfferRepository {
  /// 내 활성 제안(state 생략 = SENT 이면서 만료 전). 실패는 [PmartFailure].
  Future<OfferList> activeOffers();
}

/// 실서버 구현(`GET /offers`, listMyOffers).
final class ApiOfferRepository implements OfferRepository {
  ApiOfferRepository(Dio dio)
    : _offers = PmartApiDeliveryDispatch(dio: dio).getOffersApi();

  final OffersApi _offers;

  @override
  Future<OfferList> activeOffers() async {
    final res = await pmartGuard(() => _offers.listMyOffers());
    final body = res.data;
    if (body == null) {
      throw const ContractViolationFailure('listMyOffers 본문 없음');
    }
    return offerListFromContract(body);
  }
}

/// 계약에 required 가 없어 모든 필드가 nullable 이다. 핵심 값이 없으면 빈 목록으로 메우지 않는다.
OfferList offerListFromContract(ListMyOffers200Response body) {
  final items = body.items;
  if (items == null) {
    throw const ContractViolationFailure('listMyOffers.items 없음');
  }
  return OfferList(
    offers: [
      for (final o in items)
        OfferItem(
          offerId:
              o.offerId ??
              (throw const ContractViolationFailure('Offer.offerId 없음')),
          remainingSec: o.remainingSec,
          expiresAt: o.expiresAt,
          dropAreaLabel: o.summary?.dropAreaLabel,
          estimatedFee: o.summary?.estimatedFee,
        ),
    ],
    pollAfter: switch (body.pollAfterSec) {
      final int s => Duration(seconds: s),
      null => null,
    },
    serverTime: body.serverTime,
  );
}
