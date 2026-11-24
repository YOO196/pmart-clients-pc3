import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart';
import '../../orders/data/mock_orders_repository.dart';
import '../../orders/presentation/orders_providers.dart';
import '../data/mock_claims_repository.dart';
import '../data/return_request_repository.dart';
import '../domain/claims.dart';
import '../domain/return_request.dart';
import 'claims_controller.dart';

/// 반품·교환 신청(레퍼런스 12). 목은 주문·클레임 목 인스턴스를 같이 쓴다(접수하면 처리 내역에 바로 보인다).
/// 실서버는 계약이 없어(claim 0.2.0 — 인계 뒤 반품은 고객센터만) 신청할 수 없다고 답한다. BR-95.
final returnRequestRepositoryProvider = Provider<ReturnRequestRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => switch ((
      ref.watch(ordersRepositoryProvider),
      ref.watch(claimsRepositoryProvider),
    )) {
      (final MockOrdersRepository o, final MockClaimsRepository c) =>
        MockReturnRequestRepository(orders: o, claims: c),
      _ => const UnavailableReturnRequestRepository(),
    },
    PmartEnv.local => const UnavailableReturnRequestRepository(),
  },
);

/// 이 주문의 신청 자격(서버 판정). 실패는 실패로 보인다(빈 목록이 아니다).
final returnEligibilityProvider = FutureProvider.autoDispose
    .family<ReturnEligibility, String>(
      (ref, orderId) =>
          ref.watch(returnRequestRepositoryProvider).eligibility(orderId),
    );

/// 신청 접수. 한 번 누르면 한 번만 보낸다.
/// - 결과를 모르면(5xx·타임아웃) 키를 보관하고, 사용자가 "다시 확인"을 누를 때만 같은 키로 다시 보낸다(새 신청이 아니다).
/// - 결과를 모르는 동안 화면은 입력을 잠근다 — 내용이 바뀐 채 같은 키로 보내지 않게.
/// - 4xx 는 거절로 끝내고 키를 버린다.
class ReturnRequester {
  ReturnRequester(this._repo);

  final ReturnRequestRepository _repo;
  IdempotencyKey? _key;

  /// 결과를 모르는 신청이 있다(같은 키로만 다시 확인).
  bool get pending => _key != null;

  Future<CommandOutcome<ClaimView>> submit(ReturnRequestDraft draft) async {
    final key = _key ??= IdempotencyKey.generate();
    try {
      final claim = await _repo.submit(draft, key: key);
      _key = null;
      return CommandDone(claim);
    } on ProblemFailure catch (f) {
      _key = null;
      return CommandRejected(f.problem.code);
    } on UnknownResultFailure {
      return const CommandUnknown();
    } on PmartFailure {
      // 보내지도 못했다(연결 없음 등) — 같은 키로 다시 보내도 안전하다.
      return const CommandUnknown();
    }
  }
}
