import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/wishlist_repository.dart';
import '../domain/wishlist.dart';

final wishlistRepositoryProvider = Provider<WishlistRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockWishlistRepository(),
    PmartEnv.local => ApiWishlistRepository(ref.watch(dioProvider)),
  },
);

/// 찜·빼기 한 번의 결과. 서버가 반영한 뒤에만 [added]·[removed] 다.
sealed class WishToggle {
  const WishToggle();
}

final class WishAdded extends WishToggle {
  const WishAdded();
}

final class WishRemoved extends WishToggle {
  const WishRemoved();
}

/// 최대 개수를 넘었다. [limit] 은 서버가 준 값(없으면 null).
final class WishLimitExceeded extends WishToggle {
  const WishLimitExceeded(this.limit);

  final int? limit;
}

/// 지금은 찜할 수 없는 계정 상태(탈퇴 신청 이후).
final class WishNotAllowed extends WishToggle {
  const WishNotAllowed();
}

/// 찜 정보를 아직 못 읽었다(읽는 중·조회 실패) — 찜했는지 모르는 채로 바꾸지 않는다.
final class WishUnavailable extends WishToggle {
  const WishUnavailable();
}

/// 그 밖의 실패·결과 불명.
final class WishFailed extends WishToggle {
  const WishFailed();
}

/// 내가 찜한 상품 ID(하트 표시용 — customer 0.13.0 `GET /me/wishlist-product-ids`).
/// 로그인·앱 시작 때 한 번 받아 두고, 찜·빼기는 서버가 반영한 뒤 여기서 고친다(카드마다 묻지 않는다).
/// 비회원이면 null — 부르지 않는다.
final wishlistIdsProvider = AsyncNotifierProvider<WishlistIds, Set<String>?>(
  WishlistIds.new,
);

class WishlistIds extends AsyncNotifier<Set<String>?> {
  WishlistRepository get _repo => ref.read(wishlistRepositoryProvider);

  @override
  Future<Set<String>?> build() async {
    if (ref.watch(sessionProvider) is! MemberSession) return null;
    return (await ref.watch(wishlistRepositoryProvider).productIds()).toSet();
  }

  /// 찜했으면 빼고, 아니면 찜한다. 결과를 모르면 같은 키로 한 번 더 보낸다(두 요청 모두 멱등).
  Future<WishToggle> toggle(String productId) async {
    final before = state.value;
    if (before == null || state.hasError) return const WishUnavailable();
    final wished = before.contains(productId);
    final key = IdempotencyKey.generate();
    Future<void> send() => wished
        ? _repo.remove(productId, key: key)
        : _repo.add(productId, key: key);
    try {
      try {
        await send();
      } on UnknownResultFailure {
        await send();
      }
    } on ProblemFailure catch (f) {
      return switch (f.problem.code) {
        WishlistProblemCode.limitExceeded => WishLimitExceeded(
          int.tryParse(
            {for (final d in f.problem.details) d.field: d.reason}['limit'] ??
                '',
          ),
        ),
        WishlistProblemCode.invalidState => const WishNotAllowed(),
        _ => const WishFailed(),
      };
    } on PmartFailure {
      return const WishFailed();
    }
    if (!ref.mounted) return wished ? const WishRemoved() : const WishAdded();
    // 그 사이 다른 상품을 찜했을 수 있다 — 지금 값에서 이 상품만 고친다.
    final now = {...?state.value};
    wished ? now.remove(productId) : now.add(productId);
    state = AsyncData(now);
    // 하트 아래 찜 수는 서버 값으로 다시 읽는다(앱이 ±1 하지 않는다).
    ref.invalidate(productWishCountProvider(productId));
    return wished ? const WishRemoved() : const WishAdded();
  }
}

/// 상품 찜 수(customer 0.17.0 BR-100 R3, 비회원도). 상세·리뷰 전체 보기 하트 아래 숫자.
final productWishCountProvider = FutureProvider.autoDispose.family<int, String>(
  (ref, productId) =>
      ref.watch(wishlistRepositoryProvider).wishCount(productId),
);
