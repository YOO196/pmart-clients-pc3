import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../domain/cart_merge.dart';
import 'cart_controller.dart';
import 'cart_merge_screen.dart' show cartMergeRepositoryProvider;

/// 비회원일 때 마지막으로 본 장바구니 ID(품목이 있을 때만). 로그인하면 이 장바구니를 회원 장바구니로 옮긴다.
final lastGuestCartIdProvider = NotifierProvider<LastGuestCart, String?>(
  LastGuestCart.new,
);

class LastGuestCart extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? id) => state = id;
}

/// [주문하기]에서 로그인 중이면 그 흐름이 병합 확인 화면(고른 것만)을 연다 — 자동으로 옮기지 않는다(두 번 옮기지 않게).
final checkoutLoginPendingProvider =
    NotifierProvider<_CheckoutLoginPending, bool>(_CheckoutLoginPending.new);

class _CheckoutLoginPending extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool v) => state = v;
}

/// 로그인(가입 포함)하면 비회원 장바구니를 **모두** 회원 장바구니로 옮긴다 — 마이페이지·첫 화면 등 [주문하기] 밖에서
/// 로그인하면 담아 둔 것이 사라지던 것(사용자 2026-11-25 "열심히 담아 놓은 거 다 없어졌잖아").
/// 결과 불명은 같은 키로 한 번 더, 회원 장바구니가 그 사이 바뀌었으면 새로 읽어 한 번 더. 실패해도 로그인은 그대로
/// (비회원 장바구니는 서버에 남아 있다).
Future<void> carryGuestCartOnLogin(ProviderContainer container) async {
  if (container.read(checkoutLoginPendingProvider)) return;
  final guestCartId = container.read(lastGuestCartIdProvider);
  if (guestCartId == null) return;
  final repo = container.read(cartMergeRepositoryProvider);
  try {
    final guest = await repo.guestCart(guestCartId);
    if (guest.lines.isEmpty) return;
    final items = [
      for (final l in guest.lines)
        MergeItemRequest(
          sourceItemId: l.cartItemId,
          sku: l.sku,
          quantity: l.quantity,
        ),
    ];
    for (var attempt = 0; attempt < 2; attempt++) {
      final member = (await container.read(cartControllerProvider.future)).cart;
      // 회원 장바구니를 아직 못 받았으면(같은 장바구니) 옮기지 않는다.
      if (member.cartId == guestCartId) return;
      final key = IdempotencyKey.generate();
      var outcome = await repo.merge(
        memberCartId: member.cartId,
        memberCartVersion: member.version,
        guest: guest,
        items: items,
        key: key,
      );
      if (outcome is MergeUnknown) {
        outcome = await repo.merge(
          memberCartId: member.cartId,
          memberCartVersion: member.version,
          guest: guest,
          items: items,
          key: key,
        );
      }
      container.invalidate(cartControllerProvider);
      if (outcome is! MergeVersionConflict) break;
    }
    container.read(lastGuestCartIdProvider.notifier).set(null);
  } on PmartFailure {
    // 못 옮겼다 — 비회원 장바구니는 서버에 남아 있다.
  }
}
