import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart';
import '../../../shared/shopping_context.dart';
import '../../auth/domain/auth.dart' show MemberSession;
import '../../auth/presentation/auth_controller.dart';
import '../data/cart_repository.dart';
import '../data/mock_cart_repository.dart';
import '../domain/cart.dart';

final cartRepositoryProvider = Provider<CartRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockCartRepository(),
    // 회원은 회원 토큰, 비회원은 비회원 토큰(POST /auth/guest-sessions, ADR-0022)으로 같은 API 를 부른다.
    PmartEnv.local => ApiCartRepository(
      ref.watch(sessionProvider) is MemberSession
          ? ref.watch(dioProvider)
          : ref.watch(guestDioProvider),
    ),
  },
);

/// 결과 불명 원결과 조회 간격·횟수. 화면이 열려 있는 동안만 짧게 확인한다.
final cartResolvePolicyProvider = Provider<({Duration interval, int attempts})>(
  (_) => (interval: const Duration(seconds: 2), attempts: 5),
);

/// 수량 ± 를 모아 보내는 대기 시간. 연속 탭을 최종 수량 한 번으로 보낸다(탭마다 왕복 2번 하지 않게).
final cartStepperDelayProvider = Provider<Duration>(
  (_) => const Duration(milliseconds: 350),
);

/// 장바구니 변경 상태(C 1265: CART_STABLE / CHANGE_PENDING / CHANGE_UNKNOWN).
enum CartSync { stable, pending, unknown }

/// 직전 변경의 안내. 화면은 이 값으로 문구를 고른다.
@immutable
sealed class CartNotice {
  const CartNotice();
}

final class NoticeRejected extends CartNotice {
  const NoticeRejected(this.rejection);

  final CartChangeRejected rejection;
}

/// 다른 곳에서 장바구니가 바뀌어 최신으로 다시 불러왔다. 고객이 다시 확인한다.
final class NoticeReloadedAfterConflict extends CartNotice {
  const NoticeReloadedAfterConflict();
}

/// 원결과 조회 결과 반영되지 않았다. 다시 시도할 수 있다.
final class NoticeNotApplied extends CartNotice {
  const NoticeNotApplied();
}

/// 반영 뒤 최신 장바구니를 받지 못했다. 보이는 목록은 직전 확정본이다.
final class NoticeReloadFailed extends CartNotice {
  const NoticeReloadFailed();
}

@immutable
class CartState {
  const CartState({
    required this.cart,
    this.sync = CartSync.stable,
    this.busyItemId,
    this.notice,
  });

  /// 서버가 마지막으로 확정한 장바구니. 낙관적 반영을 하지 않는다.
  final Cart cart;
  final CartSync sync;

  /// 진행 중·불명인 변경이 걸린 품목(담기는 null).
  final String? busyItemId;
  final CartNotice? notice;

  bool get canChange => sync == CartSync.stable;
}

final cartControllerProvider = AsyncNotifierProvider<CartController, CartState>(
  CartController.new,
);

class CartController extends AsyncNotifier<CartState> {
  /// 결과 불명인 변경의 키. 원결과 조회에만 쓴다(같은 행위의 재전송도 이 키).
  IdempotencyKey? _unknownKey;

  CartRepository get _repo => ref.read(cartRepositoryProvider);

  @override
  Future<CartState> build() async {
    _unknownKey = null;
    // 로그인·로그아웃하면 그 주체의 장바구니를 연다(일반 로그인은 자동 병합 없음).
    ref.watch(sessionProvider);
    final cart = await ref
        .watch(cartRepositoryProvider)
        .open(mfcId: ref.watch(currentMfcIdProvider));
    return CartState(cart: cart);
  }

  CartState? get _current => state.value;

  void _set(CartState next) {
    if (ref.mounted) state = AsyncData(next);
  }

  /// 변경 1회. 진행 중이거나 결과 불명인 변경이 있으면 받지 않는다(null).
  Future<CartChangeOutcome?> submit(CartChange change) async {
    final current = _current;
    if (current == null || !current.canChange) return null;
    final key = IdempotencyKey.generate();
    final itemId = switch (change) {
      AddItem() => null,
      SetQuantity(:final cartItemId) => cartItemId,
      SetSelected(:final cartItemId) => cartItemId,
      RemoveItem(:final cartItemId) => cartItemId,
    };
    _set(
      CartState(cart: current.cart, sync: CartSync.pending, busyItemId: itemId),
    );
    final outcome = await _repo.change(
      current.cart.cartId,
      change,
      key: key,
      expectedVersion: current.cart.version,
    );
    if (!ref.mounted) return outcome;
    if (outcome is CartChangeUnknown) {
      _unknownKey = key;
      _set(
        CartState(
          cart: current.cart,
          sync: CartSync.unknown,
          busyItemId: itemId,
        ),
      );
      return _resolve(attempts: ref.read(cartResolvePolicyProvider).attempts);
    }
    return _settle(outcome);
  }

  /// "다시 확인". 원결과만 조회한다(변경을 다시 보내지 않는다).
  Future<CartChangeOutcome?> checkAgain() => _resolve(attempts: 1);

  Future<CartChangeOutcome?> _resolve({required int attempts}) async {
    final key = _unknownKey;
    final current = _current;
    if (key == null || current == null) return null;
    final interval = ref.read(cartResolvePolicyProvider).interval;
    for (var i = 0; i < attempts; i++) {
      if (i > 0) await Future<void>.delayed(interval);
      if (!ref.mounted) return null;
      final outcome = await _repo.lookup(current.cart.cartId, key);
      if (!ref.mounted) return null;
      if (outcome is! CartChangeUnknown) {
        _unknownKey = null;
        return _settle(outcome);
      }
    }
    // 아직 모른다. "확인 중"을 유지하고 같은 행위를 새로 실행하지 못하게 둔다.
    return const CartChangeUnknown();
  }

  Future<CartChangeOutcome> _settle(CartChangeOutcome outcome) async {
    final current = _current!;
    switch (outcome) {
      case CartChangeApplied():
        await _reload(current.cart, notice: null);
      case CartVersionConflict():
        await _reload(
          current.cart,
          notice: const NoticeReloadedAfterConflict(),
        );
      case CartChangeRejected():
        _set(CartState(cart: current.cart, notice: NoticeRejected(outcome)));
      case CartChangeNotApplied():
        _set(CartState(cart: current.cart, notice: const NoticeNotApplied()));
      case CartChangeUnknown():
        break;
    }
    return outcome;
  }

  Future<void> _reload(Cart previous, {required CartNotice? notice}) async {
    try {
      final fresh = await _repo.get(previous.cartId);
      _set(CartState(cart: fresh, notice: notice));
    } on PmartFailure {
      _set(CartState(cart: previous, notice: const NoticeReloadFailed()));
    }
  }

  /// 안내를 지운다(고객이 확인함).
  void dismissNotice() {
    final current = _current;
    if (current == null || current.notice == null) return;
    _set(
      CartState(
        cart: current.cart,
        sync: current.sync,
        busyItemId: current.busyItemId,
      ),
    );
  }

  /// 최신 장바구니를 다시 받는다. 변경 진행 중에는 하지 않는다.
  Future<void> refresh() async {
    final current = _current;
    if (current == null) {
      ref.invalidateSelf();
      return;
    }
    if (!current.canChange) return;
    await _reload(current.cart, notice: null);
  }
}
