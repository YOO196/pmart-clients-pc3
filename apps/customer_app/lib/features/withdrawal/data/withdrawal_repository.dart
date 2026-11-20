import 'package:dio/dio.dart';
import 'package:pmart_api_customer/pmart_api_customer.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../../auth/domain/auth.dart' show SocialProvider;
import '../domain/withdrawal.dart';

/// 회원 탈퇴(customer 0.12.0 `withdrawals`, ADR-0077). 재인증 토큰·사유 원문은 로그에 남기지 않는다.
abstract interface class WithdrawalRepository {
  /// `GET /me/withdrawals` — 최근 것부터.
  Future<List<Withdrawal>> list();

  /// `POST /me/withdrawals`. [providerToken] 은 지금 로그인한 그 소셜로 다시 받은 ID 토큰.
  /// 같은 [key] 재전송은 처음 접수를 다시 하지 않는다. 실패는 [PmartFailure]
  /// (401 PROVIDER_REJECTED·403 REAUTHENTICATION_MISMATCH·409 INVALID_STATE·503).
  Future<Withdrawal> request({
    required SocialProvider provider,
    required String providerToken,
    String? reasonCode,
    String? reasonText,
    required IdempotencyKey key,
  });

  /// `POST /me/withdrawals/{id}/revocations` — 대기 중일 때만. 끝난 탈퇴는 409.
  Future<Withdrawal> revoke(
    String withdrawalId, {
    required SocialProvider provider,
    required String providerToken,
    required IdempotencyKey key,
  });
}

final class ApiWithdrawalRepository implements WithdrawalRepository {
  ApiWithdrawalRepository(Dio dio)
    : _api = api.PmartApiCustomer(dio: dio).getWithdrawalsApi();

  final api.WithdrawalsApi _api;

  @override
  Future<List<Withdrawal>> list() async {
    final res = await pmartGuard(() => _api.listWithdrawals());
    final body =
        res.data ?? (throw const ContractViolationFailure('탈퇴 목록 본문 없음'));
    return [for (final w in body.items) withdrawalFromContract(w)];
  }

  @override
  Future<Withdrawal> request({
    required SocialProvider provider,
    required String providerToken,
    String? reasonCode,
    String? reasonText,
    required IdempotencyKey key,
  }) async {
    final res = await pmartGuard(
      () => _api.requestWithdrawal(
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        requestWithdrawalRequest: api.RequestWithdrawalRequest(
          provider: switch (provider) {
            SocialProvider.kakao =>
              api.RequestWithdrawalRequestProviderEnum.KAKAO,
            SocialProvider.naver =>
              api.RequestWithdrawalRequestProviderEnum.NAVER,
            SocialProvider.apple =>
              api.RequestWithdrawalRequestProviderEnum.APPLE,
            SocialProvider.google =>
              api.RequestWithdrawalRequestProviderEnum.GOOGLE,
          },
          providerToken: providerToken,
          reasonCode: reasonCode,
          reasonText: reasonText,
        ),
        extra: commandOptions(key).extra,
      ),
    );
    // 본문이 없으면 접수됐는지 모른다 — 같은 키로 다시 물을 수 있게 결과 불명으로.
    return withdrawalFromContract(
      res.data ?? (throw UnknownResultFailure(requestId: key.value)),
    );
  }

  @override
  Future<Withdrawal> revoke(
    String withdrawalId, {
    required SocialProvider provider,
    required String providerToken,
    required IdempotencyKey key,
  }) async {
    final res = await pmartGuard(
      () => _api.revokeWithdrawal(
        withdrawalId: withdrawalId,
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        revokeWithdrawalRequest: api.RevokeWithdrawalRequest(
          provider: switch (provider) {
            SocialProvider.kakao =>
              api.RevokeWithdrawalRequestProviderEnum.KAKAO,
            SocialProvider.naver =>
              api.RevokeWithdrawalRequestProviderEnum.NAVER,
            SocialProvider.apple =>
              api.RevokeWithdrawalRequestProviderEnum.APPLE,
            SocialProvider.google =>
              api.RevokeWithdrawalRequestProviderEnum.GOOGLE,
          },
          providerToken: providerToken,
        ),
        extra: commandOptions(key).extra,
      ),
    );
    return withdrawalFromContract(
      res.data ?? (throw UnknownResultFailure(requestId: key.value)),
    );
  }
}

Withdrawal withdrawalFromContract(api.Withdrawal w) => Withdrawal(
  withdrawalId: w.withdrawalId,
  state: WithdrawalState.fromWire(w.state.value),
  requestedAt: w.requestedAt,
  completedAt: w.completedAt,
  lastCheckedAt: w.lastCheckedAt,
  obligations: [
    for (final o
        in w.openObligations ?? const <api.WithdrawalOpenObligationsInner>[])
      WithdrawalObligation(
        kind: ObligationKind.fromWire(o.kind),
        ref: switch (o.ref?.trim()) {
          null || '' => null,
          final r => r,
        },
      ),
  ],
);

/// ⚠ 화면 개발·시험용 목. 데이터는 계약 JSON(`Withdrawal`)으로 둔다.
final class MockWithdrawalRepository implements WithdrawalRepository {
  MockWithdrawalRepository({
    this.latency = const Duration(milliseconds: 200),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration latency;
  final DateTime Function() _now;

  /// 지금까지의 탈퇴 기록(최근 것이 앞).
  final items = <Map<String, Object?>>[];

  /// 다음 접수가 막히는 의무(비면 바로 완료). 예: `[{'kind': 'ORDER_IN_PROGRESS', 'ref': 'order-seed-4'}]`
  List<Map<String, Object?>> obligationsNext = const [];

  /// 다음 접수 결과를 "확인 중"(UNKNOWN)으로.
  bool unknownNext = false;

  /// 다음 요청(접수·철회)을 이 오류로 실패시킨다.
  PmartFailure? failNext;

  /// 다음 목록 조회를 실패시킨다.
  PmartFailure? failNextList;

  final requestKeys = <String>[];
  final revokeKeys = <String>[];

  /// 접수에 실려 온 값(시험 확인용 — 토큰은 남기지 않는다).
  final requests =
      <({SocialProvider provider, String? reasonCode, String? reasonText})>[];
  final _byKey = <String, Map<String, Object?>>{};
  int _seq = 0;

  Future<void> _wait() => Future<void>.delayed(latency);

  Withdrawal _out(Map<String, Object?> json) => withdrawalFromContract(
    api.Withdrawal.fromJson(Map<String, dynamic>.of(json)),
  );

  @override
  Future<List<Withdrawal>> list() async {
    await _wait();
    if (failNextList case final f?) {
      failNextList = null;
      throw f;
    }
    return [for (final w in items) _out(w)];
  }

  @override
  Future<Withdrawal> request({
    required SocialProvider provider,
    required String providerToken,
    String? reasonCode,
    String? reasonText,
    required IdempotencyKey key,
  }) async {
    await _wait();
    requestKeys.add(key.value);
    if (failNext case final f?) {
      failNext = null;
      throw f;
    }
    if (_byKey[key.value] case final previous?) return _out(previous);
    if (items.any(
      (w) => WithdrawalState.fromWire(w['state'] as String?).waiting,
    )) {
      throw const ProblemFailure(
        Problem(status: 409, code: WithdrawalProblemCode.invalidState),
      );
    }
    requests.add((
      provider: provider,
      reasonCode: reasonCode,
      reasonText: reasonText,
    ));
    final at = _now().toUtc().toIso8601String();
    final blocked = obligationsNext.isNotEmpty;
    final json = <String, Object?>{
      'withdrawalId': 'wd-${++_seq}',
      'state': unknownNext
          ? 'UNKNOWN'
          : blocked
          ? 'BLOCKED_BY_OBLIGATIONS'
          : 'COMPLETED',
      'requestedAt': at,
      'lastCheckedAt': at,
      'completedAt': (unknownNext || blocked) ? null : at,
      'openObligations': blocked ? obligationsNext : <Object?>[],
    };
    unknownNext = false;
    obligationsNext = const [];
    items.insert(0, json);
    return _out(_byKey[key.value] = json);
  }

  @override
  Future<Withdrawal> revoke(
    String withdrawalId, {
    required SocialProvider provider,
    required String providerToken,
    required IdempotencyKey key,
  }) async {
    await _wait();
    revokeKeys.add(key.value);
    if (failNext case final f?) {
      failNext = null;
      throw f;
    }
    final json = items
        .where((w) => w['withdrawalId'] == withdrawalId)
        .firstOrNull;
    if (json == null) {
      throw const ProblemFailure(Problem(status: 404, code: 'NOT_FOUND'));
    }
    final state = WithdrawalState.fromWire(json['state'] as String?);
    if (state == WithdrawalState.revoked) return _out(json);
    if (!state.waiting) {
      throw const ProblemFailure(
        Problem(status: 409, code: WithdrawalProblemCode.invalidState),
      );
    }
    json['state'] = 'REVOKED';
    json['revokedAt'] = _now().toUtc().toIso8601String();
    json['openObligations'] = <Object?>[];
    return _out(json);
  }
}
