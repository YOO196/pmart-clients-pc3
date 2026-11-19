import 'package:dio/dio.dart';
import 'package:pmart_api_cart/pmart_api_cart.dart' as api;
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart' show sourceSystem;
import '../domain/cart.dart';
import '../domain/cart_merge.dart';
import 'cart_repository.dart' show cartFromContract;
import 'mock_cart_repository.dart';

/// 주문서 로그인 뒤 비회원 장바구니 병합(SCR-CART-MERGE-001, BR-50 회신 — cart 0.2.2).
/// 서버는 병합하라는 신호를 주지 않는다. 앱이 로그인 전 비회원 장바구니를 읽어 품목이 있으면 고객 확인을 받아 부른다.
abstract interface class CartMergeRepository {
  /// `GET /carts/{비회원 cartId}`(비회원 토큰). 실패는 [PmartFailure] — 빈 장바구니로 보지 않는다.
  Future<Cart> guestCart(String guestCartId);

  /// `POST /carts/{회원 cartId}/merges`(회원 토큰 + X-Guest-Token). 결과 불명은 같은 [key] 로 다시 보낸다
  /// (같은 키 = 기존 병합 결과, 중복 합산 없음). 소유 불일치(403)는 비회원 토큰을 갱신해 같은 키로 한 번 더.
  Future<MergeOutcome> merge({
    required String memberCartId,
    required int memberCartVersion,
    required Cart guest,
    required List<MergeItemRequest> items,
    required IdempotencyKey key,
  });
}

final class ApiCartMergeRepository implements CartMergeRepository {
  ApiCartMergeRepository({
    required Dio memberDio,
    required Dio guestDio,
    required this.guestTokens,
    required this.refreshGuest,
  }) : _merges = api.PmartApiCart(dio: memberDio).getMergesApi(),
       _guestCarts = api.PmartApiCart(dio: guestDio).getCartsApi();

  final api.MergesApi _merges;
  final api.CartsApi _guestCarts;

  /// 비회원 토큰(로그인 뒤에도 따로 남아 있다). 값은 X-Guest-Token 으로만 보내고 로그에 남기지 않는다.
  final TokenStore guestTokens;
  final TokenRefresher refreshGuest;

  @override
  Future<Cart> guestCart(String guestCartId) async {
    final res = await pmartGuard(
      () => _guestCarts.getCart(cartId: guestCartId),
    );
    return cartFromContract(
      res.data ?? (throw const ContractViolationFailure('비회원 장바구니 본문 없음')),
    );
  }

  /// 비회원 access token 을 새로 받는다. 못 받으면 false.
  Future<bool> _renewGuestToken() async {
    final refresh = await guestTokens.readRefreshToken();
    if (refresh == null) return false;
    final pair = await refreshGuest(refresh);
    if (pair == null) return false;
    await guestTokens.save(pair);
    return true;
  }

  Future<api.MergeResult?> _send({
    required String memberCartId,
    required int memberCartVersion,
    required Cart guest,
    required List<MergeItemRequest> items,
    required IdempotencyKey key,
  }) async {
    var token = guestTokens.accessToken;
    if (token == null && await _renewGuestToken()) {
      token = guestTokens.accessToken;
    }
    if (token == null) {
      throw const ProblemFailure(
        Problem(status: 403, code: MergeProblemCode.forbiddenOwner),
      );
    }
    final res = await pmartGuard(
      () => _merges.mergeCart(
        cartId: memberCartId,
        idempotencyKey: key.value,
        xSourceSystem: sourceSystem,
        xGuestToken: token!,
        xExpectedVersion: memberCartVersion,
        mergeCartRequest: api.MergeCartRequest(
          sourceCartId: guest.cartId,
          sourceCartVersion: guest.version,
          expectedVersion: memberCartVersion,
          items: [
            for (final i in items)
              api.MergeCartRequestItemsInner(
                sourceItemId: i.sourceItemId,
                sku: i.sku,
                quantity: i.quantity,
              ),
          ],
        ),
        extra: commandOptions(key, expectedVersion: memberCartVersion).extra,
      ),
    );
    return res.data;
  }

  @override
  Future<MergeOutcome> merge({
    required String memberCartId,
    required int memberCartVersion,
    required Cart guest,
    required List<MergeItemRequest> items,
    required IdempotencyKey key,
  }) async {
    Future<api.MergeResult?> send() => _send(
      memberCartId: memberCartId,
      memberCartVersion: memberCartVersion,
      guest: guest,
      items: items,
      key: key,
    );
    try {
      api.MergeResult? body;
      try {
        body = await send();
      } on ProblemFailure catch (f) {
        // 비회원 토큰 만료·무효 — 갱신한 뒤 같은 키로(앞 요청은 거절이라 기록이 없다).
        if (f.problem.code != MergeProblemCode.forbiddenOwner ||
            !await _renewGuestToken()) {
          rethrow;
        }
        body = await send();
      } on UnknownResultFailure {
        body = await send();
      }
      if (body == null) return const MergeUnknown();
      return MergeAnswered(mergeResultFromContract(body));
    } on UnknownResultFailure {
      return const MergeUnknown();
    } on ProblemFailure catch (f) {
      if (f.problem.code == MergeProblemCode.versionConflict) {
        return const MergeVersionConflict();
      }
      rethrow;
    }
  }
}

CartMergeResult mergeResultFromContract(api.MergeResult r) => CartMergeResult(
  mergeId: r.mergeId,
  state: switch (r.state) {
    api.MergeResultStateEnum.MERGE_PENDING => MergeState.pending,
    api.MergeResultStateEnum.MERGE_PARTIAL => MergeState.partial,
    api.MergeResultStateEnum.MERGE_CONFIRMED => MergeState.confirmed,
    api.MergeResultStateEnum.MERGE_REJECTED => MergeState.rejected,
    _ => MergeState.unknown,
  },
  items: [
    for (final i in r.items ?? <api.MergeResultItemsInner>[])
      MergeItem(
        sourceItemId: i.sourceItemId,
        sku: i.sku,
        requestedQuantity: i.requestedQuantity,
        mergedQuantity: i.mergedQuantity,
        reasonCode: i.reasonCode,
        result: switch (i.result) {
          api.MergeResultItemsInnerResultEnum.MERGED => MergeItemResult.merged,
          api.MergeResultItemsInnerResultEnum.REJECTED =>
            MergeItemResult.rejected,
          _ => MergeItemResult.unknown,
        },
      ),
  ],
);

/// ⚠ 화면 개발·시험용 목. 목 장바구니는 회원·비회원을 나누지 않으므로 비회원 장바구니를 따로 둔다
/// (기본은 비어 있어 목 앱 흐름은 예전처럼 바로 주문서로 간다). 합친 품목은 [member] 에 더한다.
final class MockCartMergeRepository implements CartMergeRepository {
  MockCartMergeRepository({
    MockCartRepository? member,
    MockCartRepository? guest,
  }) : member = member ?? MockCartRepository(latency: Duration.zero),
       guest =
           guest ?? MockCartRepository(latency: Duration.zero, seeded: false);

  final MockCartRepository member;
  final MockCartRepository guest;

  /// 이 SKU 는 거절한다(SKU → reasonCode).
  Map<String, String> rejectSkus = const {};

  /// 이 SKU 는 이 수량까지만 받는다(넘으면 QUANTITY_LIMIT_EXCEEDED — 회원 장바구니 + 이관분 상한 흉내).
  Map<String, int> maxQuantity = const {};

  /// 다음 조회 1회 실패.
  PmartFailure? failNextGuestRead;

  /// 다음 병합 1회 결과(지정하면 그대로 돌려준다 — 반영하지 않음).
  MergeOutcome? nextOutcome;

  /// 받은 병합 요청(키, 항목). 같은 키 재전송을 센다.
  final requests = <(String, List<MergeItemRequest>)>[];
  final _done = <String, CartMergeResult>{};
  int _seq = 0;

  @override
  Future<Cart> guestCart(String guestCartId) async {
    if (failNextGuestRead case final f?) {
      failNextGuestRead = null;
      throw f;
    }
    return guest.get(guestCartId);
  }

  @override
  Future<MergeOutcome> merge({
    required String memberCartId,
    required int memberCartVersion,
    required Cart guest,
    required List<MergeItemRequest> items,
    required IdempotencyKey key,
  }) async {
    requests.add((key.value, items));
    if (nextOutcome case final o?) {
      nextOutcome = null;
      return o;
    }
    if (_done[key.value] case final r?) return MergeAnswered(r);
    final results = <MergeItem>[];
    final source = await this.guest.get(guest.cartId);
    for (final i in items) {
      final src = source.lines
          .where((l) => l.cartItemId == i.sourceItemId)
          .firstOrNull;
      final reason =
          src == null || src.sku != i.sku || i.quantity > src.quantity
          ? MergeProblemCode.sourceItemChanged
          : rejectSkus[i.sku] ??
                switch (maxQuantity[i.sku]) {
                  final int max when i.quantity > max =>
                    'QUANTITY_LIMIT_EXCEEDED',
                  _ => null,
                };
      if (reason != null) {
        results.add(
          MergeItem(
            sourceItemId: i.sourceItemId,
            sku: i.sku,
            requestedQuantity: i.quantity,
            result: MergeItemResult.rejected,
            reasonCode: reason,
          ),
        );
        continue;
      }
      member.seedLine(i.sku, i.quantity);
      // 서버처럼 다 옮기면 비회원 장바구니에서 지우고, 일부만 옮기면 나머지를 남긴다.
      await this.guest.change(
        guest.cartId,
        i.quantity == src!.quantity
            ? RemoveItem(cartItemId: i.sourceItemId)
            : SetQuantity(
                cartItemId: i.sourceItemId,
                quantity: src.quantity - i.quantity,
              ),
        key: IdempotencyKey.generate(),
        expectedVersion: this.guest.version,
      );
      results.add(
        MergeItem(
          sourceItemId: i.sourceItemId,
          sku: i.sku,
          requestedQuantity: i.quantity,
          mergedQuantity: i.quantity,
          result: MergeItemResult.merged,
        ),
      );
    }
    final merged = results.where((r) => r.result == MergeItemResult.merged);
    final result = CartMergeResult(
      mergeId: 'merge-${++_seq}',
      state: merged.isEmpty
          ? MergeState.rejected
          : merged.length == results.length
          ? MergeState.confirmed
          : MergeState.partial,
      items: results,
    );
    _done[key.value] = result;
    return MergeAnswered(result);
  }
}
