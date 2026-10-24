import 'package:dio/dio.dart';
import 'package:pmart_api_delivery_execution/pmart_api_delivery_execution.dart'
    as ex;
import 'package:pmart_api_mfc_fulfillment/pmart_api_mfc_fulfillment.dart' as mf;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../domain/delivery.dart';

abstract interface class DeliveryRepository {
  Future<DeliveryView> get(String deliveryId);

  /// 진행 중 배송(`GET /riders/me/deliveries`). 실패는 [PmartFailure].
  Future<List<DeliveryView>> myActive();

  /// 큐에 저장된 수행 명령(가게 도착·픽업·고객 도착·전달 완료·실패)을 같은 키로 보낸다.
  Future<SendResult> send(QueueItem item);

  /// BR-24: 전달지 정보 경로가 없다. 목만 값을 준다.
  Future<DropInfo?> dropInfo(String deliveryId);
}

/// 포장 QR 인계(mfc-fulfillment).
abstract interface class HandoverRepository {
  Future<HandoverStep> authorize(
    String packageId, {
    required String riderId,
    required String deliveryId,
    required String scannedCode,
    required IdempotencyKey key,
  });

  Future<HandoverStep> commit(
    String packageId, {
    required String authorizationId,
    required int fenceVersion,
    required String riderId,
    required IdempotencyKey key,
  });

  Future<HandoverResolutionView> resolution(String packageId);
}

/// 전달 사진 업로드. BR-07(업로드 API 없음) — 목만 참조를 돌려준다.
abstract interface class EvidenceUploader {
  /// 업로드 성공 시 참조. 실패는 [PmartFailure].
  Future<String> upload(String localPhotoId);
}

/// 포장 QR 원문에서 packageId 를 꺼낸다. BR-23: QR 형식이 계약에 없어 목 형식(`PMART-PKG:{id}:v{n}`)을 가정한다.
String? packageIdFromQr(String code) {
  final parts = code.trim().split(':');
  if (parts.length != 3 ||
      parts[0] != 'PMART-PKG' ||
      !parts[2].startsWith('v')) {
    return null;
  }
  return parts[1];
}

final class ApiDeliveryRepository implements DeliveryRepository {
  ApiDeliveryRepository(Dio dio)
    : _exec = ex.PmartApiDeliveryExecution(dio: dio).getExecutionApi(),
      _me = ex.PmartApiDeliveryExecution(dio: dio).getMeApi();

  final ex.ExecutionApi _exec;
  final ex.MeApi _me;

  @override
  Future<DeliveryView> get(String deliveryId) async {
    final res = await pmartGuard(
      () => _exec.getDeliveryExecution(deliveryId: deliveryId),
    );
    return deliveryFromContract(
      res.data ??
          (throw const ContractViolationFailure('DeliveryExecution 본문 없음')),
    );
  }

  @override
  Future<List<DeliveryView>> myActive() async {
    final res = await pmartGuard(() => _me.listMyDeliveries());
    return [
      for (final d in res.data?.items ?? const <ex.DeliveryExecution>[])
        deliveryFromContract(d),
    ].where((d) => isActive(d.state)).toList();
  }

  @override
  Future<SendResult> send(QueueItem item) async {
    final id = item.targetId;
    final p = item.payload;
    final key = item.id;
    final extra = commandOptions(item.key).extra;
    final occurredAt = DateTime.tryParse(p['occurredAt'] as String? ?? '');
    try {
      final res = await pmartGuard(
        () => switch (item.kind) {
          DeliveryCommandKind.storeArrival => _exec.reportStoreArrival(
            deliveryId: id,
            idempotencyKey: key,
            xSourceSystem: sourceSystem,
            transitionRequest: ex.TransitionRequest(occurredAt: occurredAt),
            extra: extra,
          ),
          DeliveryCommandKind.pickup => _exec.reportPickup(
            deliveryId: id,
            idempotencyKey: key,
            xSourceSystem: sourceSystem,
            reportPickupRequest: ex.ReportPickupRequest(
              occurredAt: occurredAt,
              handoverIds: (p['handoverIds']! as List).cast<String>(),
            ),
            extra: extra,
          ),
          DeliveryCommandKind.customerArrival => _exec.reportCustomerArrival(
            deliveryId: id,
            idempotencyKey: key,
            xSourceSystem: sourceSystem,
            transitionRequest: ex.TransitionRequest(occurredAt: occurredAt),
            extra: extra,
          ),
          DeliveryCommandKind.completion => _exec.reportCompletion(
            deliveryId: id,
            idempotencyKey: key,
            xSourceSystem: sourceSystem,
            completionRequest: completionRequestFromPayload(p),
            extra: extra,
          ),
          DeliveryCommandKind.failure => _exec.reportFailure(
            deliveryId: id,
            idempotencyKey: key,
            xSourceSystem: sourceSystem,
            reportFailureRequest: ex.ReportFailureRequest(
              occurredAt: occurredAt,
              reason: ex.ReportFailureRequestReasonEnum.values.firstWhere(
                (r) => r.value == p['reason'],
                orElse: () => ex.ReportFailureRequestReasonEnum.OTHER,
              ),
              detail: p['detail'] as String?,
            ),
            extra: extra,
          ),
          _ => throw ArgumentError(item.kind),
        },
      );
      return switch (res.data?.status.value) {
        'APPLIED' => const SendApplied(),
        'ACCEPTED' => SendAccepted(resultId: res.data?.resultId),
        'REJECTED' => SendRejected(
          res.data?.nextAction ?? ProblemCode.domainRejected,
        ),
        _ => const SendUnknown(),
      };
    } on PmartFailure catch (f) {
      return transitionFailureToSend(f);
    }
  }

  @override
  Future<DropInfo?> dropInfo(String deliveryId) async =>
      // BR-24: 계약에 라이더용 전달지 조회가 없다.
      null;
}

final class ApiHandoverRepository implements HandoverRepository {
  ApiHandoverRepository(Dio dio)
    : _handovers = mf.PmartApiMfcFulfillment(dio: dio).getHandoversApi();

  final mf.HandoversApi _handovers;

  @override
  Future<HandoverStep> authorize(
    String packageId, {
    required String riderId,
    required String deliveryId,
    required String scannedCode,
    required IdempotencyKey key,
  }) => _step(() async {
    final res = await _handovers.authorizePackageHandover(
      packageId: packageId,
      idempotencyKey: key.value,
      xSourceSystem: sourceSystem,
      authorizePackageHandoverRequest: mf.AuthorizePackageHandoverRequest(
        riderId: riderId,
        deliveryId: deliveryId,
        scannedCode: scannedCode,
        scannedAt: DateTime.now().toUtc(),
      ),
      extra: commandOptions(key).extra,
    );
    final a = res.data;
    if (a?.handoverAuthorizationId == null || a?.fenceVersion == null) {
      return const HandoverUnknown();
    }
    return HandoverAuthorized(
      authorizationId: a!.handoverAuthorizationId!,
      fenceVersion: a.fenceVersion!,
    );
  });

  @override
  Future<HandoverStep> commit(
    String packageId, {
    required String authorizationId,
    required int fenceVersion,
    required String riderId,
    required IdempotencyKey key,
  }) => _step(() async {
    final res = await _handovers.commitPackageHandover(
      packageId: packageId,
      idempotencyKey: key.value,
      xSourceSystem: sourceSystem,
      commitPackageHandoverRequest: mf.CommitPackageHandoverRequest(
        handoverAuthorizationId: authorizationId,
        fenceVersion: fenceVersion,
        riderId: riderId,
      ),
      extra: commandOptions(key).extra,
    );
    final r = res.data;
    // 재고 차감까지 확정(APPLIED)일 때만 인계 완료. UNKNOWN_RESULT 는 판정 조회로 해소한다.
    return switch (r?.status) {
      mf.HandoverCommitResultStatusEnum.APPLIED => HandoverCommitted(
        r!.handoverId,
      ),
      mf.HandoverCommitResultStatusEnum.REJECTED => HandoverRejected(
        r!.nextAction ?? ProblemCode.domainRejected,
      ),
      _ => const HandoverUnknown(),
    };
  });

  Future<HandoverStep> _step(Future<HandoverStep> Function() call) async {
    try {
      return await pmartGuard(call);
    } on UnknownResultFailure {
      return const HandoverUnknown();
    } on ProblemFailure catch (f) {
      if (f.problem.code == ProblemCode.idempotencyConflict &&
          f.problem.retryable) {
        return const HandoverUnknown();
      }
      return HandoverRejected(f.problem.code);
    }
  }

  @override
  Future<HandoverResolutionView> resolution(String packageId) async {
    final res = await pmartGuard(
      () => _handovers.getHandoverResolution(packageId: packageId),
    );
    final r = res.data;
    return HandoverResolutionView(
      verdict: switch (r?.verdict?.value) {
        'STOPPED' => HandoverVerdict.stopped,
        'HANDOVER_IN_PROGRESS' => HandoverVerdict.inProgress,
        'HANDED_OVER' => HandoverVerdict.handedOver,
        _ => HandoverVerdict.unknown,
      },
      handoverId: r?.handoverId,
    );
  }
}

final class UnavailableEvidenceUploader implements EvidenceUploader {
  const UnavailableEvidenceUploader();

  @override
  Future<String> upload(String localPhotoId) async =>
      // BR-07: 파일 업로드 API 가 없다.
      throw const ContractViolationFailure('BR-07 업로드 경로 없음');
}

bool isActive(ExecutionState s) => switch (s) {
  ExecutionState.completed ||
  ExecutionState.failed ||
  ExecutionState.cancelled ||
  ExecutionState.returnedToStore => false,
  _ => true,
};

SendResult transitionFailureToSend(PmartFailure f) => switch (f) {
  UnknownResultFailure(:final transport)
      when transport == DioExceptionType.connectionError =>
    const SendOffline(),
  UnknownResultFailure() => const SendUnknown(),
  NetworkFailure() => const SendOffline(),
  ProblemFailure(:final problem)
      when problem.code == ProblemCode.idempotencyConflict &&
          problem.retryable =>
    const SendUnknown(),
  ProblemFailure(:final problem) => SendRejected(problem.code),
  _ => const SendUnknown(),
};

ex.CompletionRequest completionRequestFromPayload(Map<String, Object?> p) =>
    ex.CompletionRequest(
      occurredAt: DateTime.tryParse(p['occurredAt'] as String? ?? ''),
      method: p['method'] == 'FACE'
          ? ex.CompletionRequestMethodEnum.FACE
          : ex.CompletionRequestMethodEnum.CONTACTLESS,
      evidence: ex.CompletionRequestAllOfEvidence(
        photoRefs: (p['photoRefs']! as List).cast<String>(),
        takenAt: DateTime.parse(p['takenAt']! as String),
        placement: ex.CompletionRequestAllOfEvidencePlacementEnum.values
            .firstWhere(
              (v) => v.value == p['placement'],
              orElse: () =>
                  ex.CompletionRequestAllOfEvidencePlacementEnum.OTHER,
            ),
      ),
    );

DeliveryView deliveryFromContract(ex.DeliveryExecution d) => DeliveryView(
  deliveryId:
      d.deliveryId ?? (throw const ContractViolationFailure('deliveryId 없음')),
  version: d.version ?? 0,
  state: ExecutionState.fromWire(d.state?.value),
  orderId: d.orderId,
  mfcId: d.mfcId,
  packageIds: d.packageIds ?? const [],
  handoverIds: d.handoverIds ?? const [],
);
