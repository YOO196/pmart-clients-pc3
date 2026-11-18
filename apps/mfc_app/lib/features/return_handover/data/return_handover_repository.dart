import 'package:dio/dio.dart';
import 'package:pmart_api_delivery_execution/pmart_api_delivery_execution.dart'
    as exe;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../domain/return_handover.dart';

abstract interface class ReturnHandoverRepository {
  /// `GET /return-handovers?mfcId=` — 반납을 기다리는 회수·반납 배송과 번호(번호가 없으면 서버가 이때 만든다).
  Future<List<ReturnHandoverView>> waiting(String mfcId);

  /// `POST /return-handovers/{deliveryId}/code-reissues` — 새 번호, 틀린 횟수 0, 잠김 풀림. 같은 키는 같은 결과.
  Future<ReissueOutcome> reissue(
    String deliveryId, {
    required IdempotencyKey key,
  });
}

final class ApiReturnHandoverRepository implements ReturnHandoverRepository {
  ApiReturnHandoverRepository(Dio dio)
    : _api = exe.PmartApiDeliveryExecution(dio: dio).getReturnHandoversApi();

  final exe.ReturnHandoversApi _api;

  @override
  Future<List<ReturnHandoverView>> waiting(String mfcId) async {
    final res = await pmartGuard(() => _api.listReturnHandovers(mfcId: mfcId));
    final body = res.data ?? (throw const ContractViolationFailure('목록 본문 없음'));
    return [for (final r in body.items) returnHandoverFromContract(r)];
  }

  @override
  Future<ReissueOutcome> reissue(
    String deliveryId, {
    required IdempotencyKey key,
  }) async {
    try {
      final res = await pmartGuard(
        () => _api.reissueReturnHandoverCode(
          deliveryId: deliveryId,
          idempotencyKey: key.value,
          xSourceSystem: sourceSystem,
          extra: commandOptions(key).extra,
        ),
      );
      final r = res.data;
      if (r == null) return const ReissueUnknown();
      return Reissued(returnHandoverFromContract(r));
    } on PmartFailure catch (f) {
      return reissueFailureToOutcome(f);
    }
  }
}

ReissueOutcome reissueFailureToOutcome(PmartFailure f) => switch (f) {
  UnknownResultFailure() => const ReissueUnknown(),
  ProblemFailure(:final problem)
      when problem.code == ProblemCode.idempotencyConflict &&
          problem.retryable =>
    const ReissueUnknown(),
  ProblemFailure(:final problem) => ReissueRejected(problem.code),
  _ => throw f,
};

ReturnHandoverView returnHandoverFromContract(exe.ReturnHandover r) =>
    ReturnHandoverView(
      deliveryId: r.deliveryId,
      deliveryNumber: r.deliveryNumber,
      purpose: switch (r.purpose) {
        'CLAIM_RETURN' => ReturnPurpose.claimReturn,
        'MISDELIVERY_RECOVERY' => ReturnPurpose.misdeliveryRecovery,
        'FAILED_DELIVERY_RETURN' => ReturnPurpose.failedDeliveryReturn,
        _ => ReturnPurpose.other,
      },
      state: r.state,
      riderId: r.riderId,
      code: r.code,
      failedAttempts: r.failedAttempts,
      locked: r.locked,
      issuedAt: r.issuedAt,
    );
