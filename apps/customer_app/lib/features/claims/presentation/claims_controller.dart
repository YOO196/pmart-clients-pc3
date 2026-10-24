import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart';
import '../../checkout/domain/checkout.dart' show ArrivalWindow;
import '../../orders/data/mock_orders_repository.dart';
import '../../orders/domain/orders.dart';
import '../../orders/presentation/orders_providers.dart';
import '../data/claims_repository.dart';
import '../data/mock_claims_repository.dart';
import '../domain/claims.dart';

final claimsRepositoryProvider = Provider<ClaimsRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockClaimsRepository(
      orders: switch (ref.watch(ordersRepositoryProvider)) {
        final MockOrdersRepository m => m,
        _ => null,
      },
    ),
    PmartEnv.local => ApiClaimsRepository(ref.watch(dioProvider)),
  },
);

/// 비동기 요청(철회·시간 변경) 결과 조회 간격·횟수.
final requestPollPolicyProvider = Provider<({Duration interval, int attempts})>(
  (_) => (interval: const Duration(seconds: 2), attempts: 5),
);

final claimProvider = FutureProvider.autoDispose.family<ClaimView, String>(
  (ref, claimId) => ref.watch(claimsRepositoryProvider).get(claimId),
);

/// 품목별로 취소를 고를 수 있는 수량(안내용 상한). 실제 가능 수량은 서버가 판정한다.
int cancellableHint(OrderLineView l) {
  final n =
      (l.originalQty ?? 0) -
      (l.cancelledBeforeShipQty ?? 0) -
      (l.handedOverQty ?? 0);
  return n < 0 ? 0 : n;
}

@immutable
sealed class CommandOutcome<T> {
  const CommandOutcome();
}

final class CommandDone<T> extends CommandOutcome<T> {
  const CommandDone(this.value);

  final T value;
}

final class CommandRejected<T> extends CommandOutcome<T> {
  const CommandRejected(this.code);

  final String code;
}

/// 반영 여부를 아직 모른다. 같은 키로만 다시 확인한다.
final class CommandUnknown<T> extends CommandOutcome<T> {
  const CommandUnknown();
}

/// 취소 접수. 같은 키·같은 본문 재전송은 기존 클레임을 돌려준다.
class CancelRequester {
  CancelRequester(this._repo);

  final ClaimsRepository _repo;
  IdempotencyKey? _key;

  Future<CommandOutcome<ClaimView>> submit(
    String orderId,
    List<CancelLine> lines,
    CancelReason reason,
  ) async {
    // 결과를 모르는 직전 시도가 있으면 같은 키로 다시 보낸다(새 취소가 아니다).
    final key = _key ??= IdempotencyKey.generate();
    for (var i = 0; i < 3; i++) {
      try {
        final claim = await _repo.requestCancel(
          orderId,
          lines,
          reason,
          key: key,
        );
        _key = null;
        return CommandDone(claim);
      } on UnknownResultFailure {
        continue;
      } on ProblemFailure catch (f) {
        _key = null;
        return CommandRejected(f.problem.code);
      }
    }
    return const CommandUnknown();
  }
}

final cancelRequesterProvider = Provider.family<CancelRequester, String>(
  (ref, orderId) => CancelRequester(ref.watch(claimsRepositoryProvider)),
);

/// 철회 요청 → 결과 조회. 확인 중에는 "철회 확인 중"이다.
Future<RequestState> withdrawClaim(Ref ref, ClaimView claim) async {
  final repo = ref.read(claimsRepositoryProvider);
  final policy = ref.read(requestPollPolicyProvider);
  final key = IdempotencyKey.generate();
  try {
    await repo.withdraw(
      claim.claimId,
      expectedVersion: claim.version,
      key: key,
    );
  } on UnknownResultFailure {
    // 접수됐는지 모른다. 조회로 확인한다.
  } on ProblemFailure {
    return RequestState.rejected;
  }
  return _poll(policy, () => repo.withdrawal(claim.claimId, key));
}

Future<RequestState> _poll(
  ({Duration interval, int attempts}) policy,
  Future<RequestState> Function() query,
) async {
  var last = RequestState.unknown;
  for (var i = 0; i < policy.attempts; i++) {
    if (i > 0) await Future<void>.delayed(policy.interval);
    try {
      last = await query();
    } on PmartFailure {
      last = RequestState.unknown;
    }
    if (last == RequestState.confirmed || last == RequestState.rejected) {
      return last;
    }
  }
  return last;
}

final withdrawClaimProvider =
    Provider<Future<RequestState> Function(ClaimView)>(
      (ref) =>
          (claim) => withdrawClaim(ref, claim),
    );

/// 예약시간 변경 요청 → 결과 조회. 확정 전에는 옛 시간·새 시간을 동시에 확정으로 보이지 않는다.
final requestTimeChangeProvider =
    Provider<
      Future<CommandOutcome<RequestState>> Function(OrderDetail, ArrivalWindow)
    >((ref) {
      return (order, window) async {
        final repo = ref.read(ordersRepositoryProvider);
        final key = IdempotencyKey.generate();
        try {
          await repo.requestTimeChange(
            order.orderId,
            window,
            expectedVersion: order.version,
            key: key,
          );
        } on UnknownResultFailure {
          // 접수 여부를 모른다. 결과 조회로 확인한다.
        } on ProblemFailure catch (f) {
          return CommandRejected(f.problem.code);
        }
        final state = await _poll(
          ref.read(requestPollPolicyProvider),
          () => repo.timeChange(order.orderId, key),
        );
        return CommandDone(state);
      };
    });
