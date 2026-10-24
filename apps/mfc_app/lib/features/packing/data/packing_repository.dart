import 'package:dio/dio.dart';
import 'package:pmart_api_delivery_dispatch/pmart_api_delivery_dispatch.dart'
    as dsp;
import 'package:pmart_api_mfc_fulfillment/pmart_api_mfc_fulfillment.dart'
    as api;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../domain/packing.dart';

abstract interface class PackingRepository {
  Future<ShipmentView> shipment(String shipmentId);

  /// `POST /shipments/{id}/packages`. 같은 키 재전송은 같은 포장을 돌려준다.
  Future<PackOutcome> seal(
    String shipmentId,
    List<ContentLine> contents, {
    required int bagCount,
    required TemperatureZone zone,
    bool containsAlcohol = false,
    String? packedBy,
    required IdempotencyKey key,
  });

  /// `POST /packages/{id}/repackings`. 새 포장 버전(새 QR), 옛 라벨은 무효.
  Future<PackOutcome> repack(
    String packageId,
    RepackReason reason, {
    required IdempotencyKey key,
  });

  /// `POST /dispatch-requests`(202). 같은 배송의 진행 중 시도가 있으면 그 시도를 돌려준다.
  Future<String?> requestDispatch({
    required String deliveryId,
    required String mfcId,
    required int packagingMinutes,
    required int bagCount,
    required bool coldChain,
    required List<String> packageIds,
    bool containsAlcohol = false,
    required IdempotencyKey key,
  });

  Future<DispatchView> dispatch(String requestId);
}

final class ApiPackingRepository implements PackingRepository {
  ApiPackingRepository(Dio dio)
    : _shipments = api.PmartApiMfcFulfillment(dio: dio).getShipmentsApi(),
      _dispatch = dsp.PmartApiDeliveryDispatch(dio: dio)
          .getDispatchRequestsApi();

  final api.ShipmentsApi _shipments;
  final dsp.DispatchRequestsApi _dispatch;

  @override
  Future<ShipmentView> shipment(String shipmentId) async {
    final res = await pmartGuard(
      () => _shipments.getShipment(shipmentId: shipmentId),
    );
    return shipmentFromContract(
      res.data ?? (throw const ContractViolationFailure('Shipment 본문 없음')),
    );
  }

  @override
  Future<PackOutcome> seal(
    String shipmentId,
    List<ContentLine> contents, {
    required int bagCount,
    required TemperatureZone zone,
    bool containsAlcohol = false,
    String? packedBy,
    required IdempotencyKey key,
  }) => _pack(
    () => _shipments.sealPackage(
      shipmentId: shipmentId,
      idempotencyKey: key.value,
      xSourceSystem: sourceSystem,
      sealPackageRequest: api.SealPackageRequest(
        contents: [for (final c in contents) _line(c)],
        bagCount: bagCount,
        containsAlcohol: containsAlcohol,
        temperatureZone: switch (zone) {
          TemperatureZone.ambient =>
            api.SealPackageRequestTemperatureZoneEnum.AMBIENT,
          TemperatureZone.chilled =>
            api.SealPackageRequestTemperatureZoneEnum.CHILLED,
          TemperatureZone.frozen =>
            api.SealPackageRequestTemperatureZoneEnum.FROZEN,
        },
        packedBy: packedBy,
      ),
      extra: commandOptions(key).extra,
    ),
  );

  @override
  Future<PackOutcome> repack(
    String packageId,
    RepackReason reason, {
    required IdempotencyKey key,
  }) => _pack(
    () => _shipments.repackPackage(
      packageId: packageId,
      idempotencyKey: key.value,
      xSourceSystem: sourceSystem,
      repackPackageRequest: api.RepackPackageRequest(
        reason: switch (reason) {
          RepackReason.damagedBag =>
            api.RepackPackageRequestReasonEnum.DAMAGED_BAG,
          RepackReason.contentChange =>
            api.RepackPackageRequestReasonEnum.CONTENT_CHANGE,
          RepackReason.labelUnreadable =>
            api.RepackPackageRequestReasonEnum.LABEL_UNREADABLE,
          RepackReason.shortageAdjust =>
            api.RepackPackageRequestReasonEnum.SHORTAGE_ADJUST,
        },
      ),
      extra: commandOptions(key).extra,
    ),
  );

  Future<PackOutcome> _pack(
    Future<Response<api.Package>> Function() call,
  ) async {
    try {
      final res = await pmartGuard(call);
      final p = res.data;
      if (p == null) return const PackUnknown();
      return PackDone(packageFromContract(p));
    } on PmartFailure catch (f) {
      return packFailureToOutcome(f);
    }
  }

  @override
  Future<String?> requestDispatch({
    required String deliveryId,
    required String mfcId,
    required int packagingMinutes,
    required int bagCount,
    required bool coldChain,
    required List<String> packageIds,
    bool containsAlcohol = false,
    required IdempotencyKey key,
  }) async {
    await pmartGuard(
      () => _dispatch.createDispatchRequest(
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        dispatchRequest: dsp.DispatchRequest(
          deliveryId: deliveryId,
          mfcId: mfcId,
          packageSpec: dsp.PackageSpec(
            packagingMinutes: packagingMinutes,
            bagCount: bagCount,
            coldChain: coldChain,
            containsAlcohol: containsAlcohol,
            packageIds: packageIds,
          ),
        ),
        extra: commandOptions(key).extra,
      ),
    );
    // 결과 조회 경로의 requestId 는 Idempotency-Key 다.
    return key.value;
  }

  @override
  Future<DispatchView> dispatch(String requestId) async {
    final res = await pmartGuard(
      () => _dispatch.getDispatchRequest(requestId: requestId),
    );
    return dispatchFromContract(
      res.data ??
          (throw const ContractViolationFailure('DispatchAttempt 본문 없음')),
    );
  }
}

api.PackageContentLine _line(ContentLine c) => api.PackageContentLine(
  orderLineId: c.orderLineId,
  sku: c.sku,
  qty: c.qty,
  lotId: c.lotId,
);

PackOutcome packFailureToOutcome(PmartFailure f) => switch (f) {
  UnknownResultFailure() => const PackUnknown(),
  ProblemFailure(:final problem)
      when problem.code == ProblemCode.idempotencyConflict &&
          problem.retryable =>
    const PackUnknown(),
  ProblemFailure(:final problem) => PackRejected(problem.code),
  _ => throw f,
};

PackageView packageFromContract(api.Package p) => PackageView(
  packageId:
      p.packageId ?? (throw const ContractViolationFailure('packageId 없음')),
  packageVersion: p.packageVersion ?? 1,
  version: p.version ?? 0,
  state: switch (p.state?.value) {
    'OPEN' => PackageState.open,
    'SEALED' => PackageState.sealed,
    'HANDED_OVER' => PackageState.handedOver,
    'INVALIDATED' => PackageState.invalidated,
    'VOIDED' => PackageState.voided,
    _ => PackageState.unknown,
  },
  qrCode: p.qrCode,
  contents: [
    for (final c in p.contents ?? const <api.PackageContentLine>[])
      ContentLine(
        orderLineId: c.orderLineId,
        sku: c.sku,
        qty: c.qty,
        lotId: c.lotId,
      ),
  ],
  bagCount: p.bagCount,
  temperatureZone: p.temperatureZone,
  fence: switch (p.fence?.state?.value) {
    null || 'NONE' => FenceState.none,
    'HANDOVER_IN_PROGRESS' => FenceState.inProgress,
    'COMMITTED' => FenceState.committed,
    'EXPIRED' => FenceState.expired,
    _ => FenceState.unknown,
  },
);

ShipmentView shipmentFromContract(api.Shipment s) => ShipmentView(
  shipmentId:
      s.shipmentId ?? (throw const ContractViolationFailure('shipmentId 없음')),
  orderId: s.orderId,
  deliveryId: s.deliveryId,
  version: s.version ?? 0,
  state: switch (s.state?.value) {
    'PREPARING' => ShipmentState.preparing,
    'READY' => ShipmentState.ready,
    'PARTIALLY_HANDED_OVER' => ShipmentState.partiallyHandedOver,
    'HANDED_OVER' => ShipmentState.handedOver,
    'CANCELLED' => ShipmentState.cancelled,
    'CLOSED_PARTIAL' => ShipmentState.closedPartial,
    _ => ShipmentState.unknown,
  },
  holdReason: s.holdReason,
  packages: [
    for (final p in s.packages ?? const <api.Package>[]) packageFromContract(p),
  ],
);

DispatchView dispatchFromContract(dsp.DispatchAttempt a) => DispatchView(
  state: switch (a.state?.value) {
    'SEARCHING' => DispatchState.searching,
    'OFFERING' => DispatchState.offering,
    'ASSIGNED' => DispatchState.assigned,
    'FAILED' => DispatchState.failed,
    'CANCELLED' => DispatchState.cancelled,
    _ => DispatchState.unknown,
  },
  failureReason: a.failureReason?.value,
  splitCount: a.splitCount,
);
