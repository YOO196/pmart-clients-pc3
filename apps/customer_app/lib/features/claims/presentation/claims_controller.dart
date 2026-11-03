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

/// 주문의 처리 내역 목록. 주문 상세의 `claims` 는 서버가 아직 비워 보내므로 `GET /claims?orderId=` 로 받는다
/// (백엔드 안내 2026-10-31 주문 취소 §6). 조회 실패는 "없음"이 아니라 실패로 보인다.
final orderClaimsProvider = FutureProvider.autoDispose
    .family<List<ClaimSummaryView>, String>(
      (ref, orderId) =>
          ref.watch(claimsRepositoryProvider).listForOrder(orderId),
    );

/// 클레임 화면이 끝 상태(CLOSED·REJECTED·WITHDRAWN)가 될 때까지 다시 조회하는 간격.
/// 백엔드: 보통 몇 초 안에 IN_PROGRESS → CLOSED(handoff 2026-10-31 주문 취소 §4).
final claimRefreshIntervalProvider = Provider<Duration>(
  (_) => const Duration(seconds: 3),
);

/// 주문 전체 취소 본문(모든 행 × 서버 미이행 수량). 모르는 행이 있으면 null.
List<CancelLine>? cancelLinesOf(OrderDetail order) => wholeOrderCancelLines([
  for (final l in order.lines)
    (orderLineId: l.orderLineId, unfulfilledQty: l.unfulfilledQty),
]);

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

/// 취소 접수. 한 번 누르면 한 번만 보낸다(자동 재전송 없음 — 백엔드 handoff 2026-10-31 주문 취소 §3).
/// - 결과를 모르면(5xx·타임아웃) 다시 보내지 않고 내 클레임 조회로 접수 여부를 확인한다.
/// - 그래도 모르면 키를 보관한다. 사용자가 "다시 확인"을 누를 때만 같은 키로 다시 보낸다(새 취소가 아니다).
/// - 501(미구현)·4xx 는 거절로 끝낸다(재시도 안 함).
class CancelRequester {
  CancelRequester(this._repo);

  final ClaimsRepository _repo;
  IdempotencyKey? _key;

  Future<CommandOutcome<ClaimView>> submit(
    String orderId,
    List<CancelLine> lines,
    CancelReason reason,
  ) async {
    final key = _key ??= IdempotencyKey.generate();
    try {
      final claim = await _repo.requestCancel(orderId, lines, reason, key: key);
      _key = null;
      return CommandDone(claim);
    } on UnknownResultFailure catch (f) {
      if ((f.problem?.status ?? f.httpStatus) == 501) {
        _key = null;
        return const CommandRejected(ClaimProblemCode.notImplemented);
      }
    } on ProblemFailure catch (f) {
      _key = null;
      return CommandRejected(f.problem.code);
    }
    try {
      final found = await _repo.findActiveCancel(orderId);
      if (found != null) {
        _key = null;
        return CommandDone(found);
      }
    } on PmartFailure {
      // 조회도 실패했다. 접수 여부를 모르는 채로 둔다.
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
