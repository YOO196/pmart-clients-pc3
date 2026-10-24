import 'package:dio/dio.dart';
import 'package:pmart_api_delivery_dispatch/pmart_api_delivery_dispatch.dart';
import 'package:pmart_api_rider/pmart_api_rider.dart' as rd;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../domain/offer_list.dart';

abstract interface class OfferRepository {
  /// 내 활성 제안(state 생략 = SENT 이면서 만료 전). 실패는 [PmartFailure].
  Future<OfferList> activeOffers();

  /// `POST /offers/{id}/responses`. 같은 키 재전송은 같은 판정을 돌려줘야 한다.
  Future<OfferOutcome> respond(
    String offerId, {
    required bool accept,
    RejectReason? reason,
    required IdempotencyKey key,
  });
}

/// 운행 상태·배차 설정(rider-service).
abstract interface class DutyRepository {
  Future<OperatingState> state();

  /// 실패는 [PmartFailure](403 계정 제한, 409 진행 배송 있음 등).
  Future<OperatingState> setState({
    required bool onDuty,
    required bool newDispatch,
    required int expectedVersion,
    String? mfcId,
    required IdempotencyKey key,
  });

  Future<DispatchMode> dispatchMode();
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

  @override
  Future<OfferOutcome> respond(
    String offerId, {
    required bool accept,
    RejectReason? reason,
    required IdempotencyKey key,
  }) async {
    try {
      final res = await pmartGuard(
        () => _offers.respondToOffer(
          offerId: offerId,
          idempotencyKey: key.value,
          xSourceSystem: sourceSystem,
          respondToOfferRequest: RespondToOfferRequest(
            response: accept
                ? RespondToOfferRequestResponseEnum.ACCEPT
                : RespondToOfferRequestResponseEnum.REJECT,
            rejectReason: switch (reason) {
              RejectReason.tooFar =>
                RespondToOfferRequestRejectReasonEnum.TOO_FAR,
              RejectReason.overCapacity =>
                RespondToOfferRequestRejectReasonEnum.OVER_CAPACITY,
              RejectReason.personal =>
                RespondToOfferRequestRejectReasonEnum.PERSONAL,
              RejectReason.other => RespondToOfferRequestRejectReasonEnum.OTHER,
              null => null,
            },
            // 단말 시각은 참고값이다. 판정은 서버 수신 시각.
            respondedAt: DateTime.now().toUtc(),
          ),
          extra: commandOptions(key).extra,
        ),
      );
      final r = res.data;
      return r == null ? const OfferUnknown() : offerOutcomeFromContract(r);
    } on UnknownResultFailure {
      return const OfferUnknown();
    } on ProblemFailure catch (f) {
      if (f.problem.code == ProblemCode.idempotencyConflict &&
          f.problem.retryable) {
        return const OfferUnknown();
      }
      rethrow;
    }
  }
}

final class ApiDutyRepository implements DutyRepository {
  ApiDutyRepository(Dio dio) : _me = rd.PmartApiRider(dio: dio).getMeApi();

  final rd.MeApi _me;

  @override
  Future<OperatingState> state() async {
    final res = await pmartGuard(() => _me.getMyOperatingState());
    return operatingStateFromContract(
      res.data ??
          (throw const ContractViolationFailure('OperatingState 본문 없음')),
    );
  }

  @override
  Future<OperatingState> setState({
    required bool onDuty,
    required bool newDispatch,
    required int expectedVersion,
    String? mfcId,
    required IdempotencyKey key,
  }) async {
    final res = await pmartGuard(
      () => _me.setMyOperatingState(
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        xExpectedVersion: expectedVersion,
        operatingStateRequest: rd.OperatingStateRequest(
          status: onDuty
              ? rd.OperatingStatus.ON_DUTY
              : rd.OperatingStatus.OFF_DUTY,
          newDispatchEnabled: onDuty && newDispatch,
          mfcId: mfcId,
        ),
        extra: commandOptions(key, expectedVersion: expectedVersion).extra,
      ),
    );
    return operatingStateFromContract(
      res.data ?? (throw UnknownResultFailure(requestId: key.value)),
    );
  }

  @override
  Future<DispatchMode> dispatchMode() async {
    final res = await pmartGuard(() => _me.getMyDispatchSettings());
    return res.data?.dispatchMode ==
            rd.DispatchSettingsDispatchModeEnum.AI_RECOMMENDED
        ? DispatchMode.aiRecommended
        : DispatchMode.normal;
  }
}

OperatingState operatingStateFromContract(rd.OperatingState s) =>
    OperatingState(
      onDuty: s.status == rd.OperatingStatus.ON_DUTY,
      newDispatchEnabled: s.newDispatchEnabled ?? false,
      version: s.version ?? 0,
      activeDeliveryCount: s.activeDeliveryCount ?? 0,
      mfcId: s.mfcId,
    );

OfferOutcome offerOutcomeFromContract(OfferResponseResult r) =>
    switch (r.outcome) {
      OfferResponseResultOutcomeEnum.ASSIGNED => OfferAssigned(
        deliveryId: r.deliveryId,
        assignmentId: r.assignmentId,
      ),
      OfferResponseResultOutcomeEnum.REJECTED => OfferRejected(
        consecutiveRejections: r.consecutiveRejections,
        rejectionNotice: r.rejectionNotice ?? false,
      ),
      OfferResponseResultOutcomeEnum.LATE => OfferLate(switch (r.lateReason) {
        OfferResponseResultLateReasonEnum.EXPIRED => LateReason.expired,
        OfferResponseResultLateReasonEnum.ALREADY_ASSIGNED =>
          LateReason.alreadyAssigned,
        OfferResponseResultLateReasonEnum.ORDER_CANCELLED =>
          LateReason.orderCancelled,
        OfferResponseResultLateReasonEnum.INELIGIBLE => LateReason.ineligible,
        null => LateReason.unknown,
      }),
    };

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
          deliveryId: o.deliveryId,
          dropAreaLabel: o.summary?.dropAreaLabel,
          estimatedFee: o.summary?.estimatedFee,
          distanceKm: o.summary?.distanceKm,
          weightG: o.summary?.weightG,
          containsAlcohol: o.summary?.containsAlcohol,
        ),
    ],
    pollAfter: switch (body.pollAfterSec) {
      final int s => Duration(seconds: s),
      null => null,
    },
    serverTime: body.serverTime,
  );
}
