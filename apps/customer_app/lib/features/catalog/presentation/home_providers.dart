import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/order_status.dart';
import '../../../shared/providers.dart';
import '../../../shared/shopping_context.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../checkout/data/checkout_repository.dart';
import '../../checkout/domain/checkout.dart';
import '../../checkout/presentation/checkout_controller.dart';
import '../../orders/domain/orders.dart';
import '../../orders/presentation/orders_providers.dart';
import '../domain/catalog.dart';
import 'catalog_providers.dart';

/// 홈 고정 탭(랭킹·신상품) 구성. 홈 탭은 [homeProvider] 를 쓴다(계약 `GET /storefront/home?tab=`).
final homeTabProvider = FutureProvider.autoDispose.family<HomeView, HomeTab>(
  (ref, tab) => ref
      .watch(catalogRepositoryProvider)
      .home(mfcId: ref.watch(currentMfcIdProvider), tab: tab),
);

/// 홈 배송 방식 요약(`GET /delivery-options`). 상품액 없이 물어 기본 배달팁만 받는다(적용액·무료는 장바구니·주문서가 서버 값으로).
/// 담당 센터가 없으면(주소 없음·권역 밖) 물을 수 없으므로 null — 카드를 그리지 않는다(0원·"무료"로 채우지 않음).
final homeDeliveryOptionsProvider =
    FutureProvider.autoDispose<List<DeliveryOption>?>((ref) async {
      final mfcId = ref.watch(currentMfcIdProvider);
      if (mfcId == null) return null;
      final member = ref.watch(sessionProvider) is MemberSession;
      // 비회원도 된다(계약: 회원·비회원 토큰 모두). 실서버 비회원은 비회원 토큰으로 묻는다(장바구니와 같은 방식).
      final repo = switch (ref.watch(envProvider)) {
        PmartEnv.local when !member => ApiCheckoutRepository(
          ref.watch(guestDioProvider),
        ),
        _ => ref.watch(checkoutRepositoryProvider),
      };
      return repo.options(mfcId);
    });

/// 홈에서 "진행 중"으로 보는 주문 상태(앞일수록 먼저 보인다). 계약 `GET /orders?status=` 는 상태를 하나만 받아 상태마다 묻는다.
const homeInProgressStatuses = <OrderStatus>[
  OrderStatus.inDelivery,
  OrderStatus.partiallyDelivered,
  OrderStatus.partiallyHandedOver,
  OrderStatus.preparing,
  OrderStatus.confirmed,
];

/// 홈 진행 중 주문 한 건. 비회원이거나 진행 중 주문이 정말 없으면 null(카드 없음).
/// 상태별 조회가 하나라도 실패했는데 찾은 주문이 없으면 오류로 던진다 — "진행 중 주문 없음"으로 보이지 않는다.
final homeInProgressOrderProvider = FutureProvider.autoDispose<OrderListItem?>((
  ref,
) async {
  if (ref.watch(sessionProvider) is! MemberSession) return null;
  final repo = ref.watch(ordersRepositoryProvider);
  final results = await Future.wait([
    for (final s in homeInProgressStatuses)
      // 동기 예외도 그 상태 하나의 실패로 모은다.
      Future.sync(() => repo.list(status: s))
          .then<({OrderPage? page, PmartFailure? failure})>(
            (p) => (page: p, failure: null),
            onError: (Object e) => (
              page: null,
              failure: e is PmartFailure ? e : ContractViolationFailure(e),
            ),
          ),
  ]);
  for (final r in results) {
    // 서버가 다른 상태를 섞어 주어도 진행 중이 아닌 주문은 쓰지 않는다.
    final hit = r.page?.items
        .where((o) => homeInProgressStatuses.contains(o.status))
        .firstOrNull;
    if (hit != null) return hit;
  }
  final failure = results.map((r) => r.failure).nonNulls.firstOrNull;
  if (failure != null) throw failure;
  return null;
});

/// 진행 중 주문의 도착 예상(주문 상세의 배송 → `GET /deliveries/{id}/eta`). 배송 중인 배송이 없으면 null.
/// 실패는 오류로 남기고 화면은 시간을 그리지 않는다(위치 실패 ≠ 배송 실패).
final homeOrderEtaProvider = FutureProvider.autoDispose
    .family<DeliveryEtaView?, String>((ref, orderId) async {
      final repo = ref.watch(ordersRepositoryProvider);
      final order = await repo.get(orderId);
      final deliveryId = order.shipments
          .where(
            (s) => s.state == ShipmentState.inDelivery && s.deliveryId != null,
          )
          .firstOrNull
          ?.deliveryId;
      if (deliveryId == null) return null;
      return repo.eta(deliveryId);
    });

/// 진행 중 주문 중 도착 예상을 물어볼 만한 상태(배송이 출발한 뒤).
bool homeOrderHasEta(OrderStatus s) =>
    s == OrderStatus.inDelivery ||
    s == OrderStatus.partiallyDelivered ||
    s == OrderStatus.partiallyHandedOver;

/// "전체보기"로 연 영역. 같은 영역·같은 홈 구성이면 같은 키다.
@immutable
class SectionRef {
  const SectionRef(this.section, this.layoutVersion);

  final HomeSection section;
  final int layoutVersion;

  @override
  bool operator ==(Object other) =>
      other is SectionRef &&
      other.section.sectionId == section.sectionId &&
      other.layoutVersion == layoutVersion;

  @override
  int get hashCode => Object.hash(section.sectionId, layoutVersion);
}

/// 영역 전체보기 목록(`GET /storefront/sections/{id}/items`, `nextCursor` 로 이어 받기).
final sectionItemsProvider = AsyncNotifierProvider.autoDispose
    .family<SectionItemsController, ProductListState, SectionRef>(
      SectionItemsController.new,
    );

class SectionItemsController extends AsyncNotifier<ProductListState> {
  SectionItemsController(this.target);

  final SectionRef target;

  Future<HomeSection> _fetch(String? cursor) async {
    try {
      return await ref
          .read(catalogRepositoryProvider)
          .section(
            target.section,
            layoutVersion: target.layoutVersion,
            mfcId: ref.read(currentMfcIdProvider),
            cursor: cursor,
          );
    } on ProblemFailure catch (e) {
      // 홈 구성이 바뀌었으면 이 목록은 낡았다. 홈을 다시 받게 하고 오류로 보인다.
      if (e.problem.code == 'LAYOUT_VERSION_CHANGED') {
        ref.invalidate(homeProvider);
      }
      rethrow;
    }
  }

  @override
  Future<ProductListState> build() async {
    ref.watch(currentMfcIdProvider);
    // 자동 랭킹 테마는 서버가 상위 N 을 한 번에 준다(다음 묶음 없음) — 받은 목록을 그대로.
    if (target.section.rankedComplete) {
      return ProductListState(items: target.section.items, nextCursor: null);
    }
    final first = await _fetch(null);
    return ProductListState(items: first.items, nextCursor: first.nextCursor);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(
      ProductListState(
        items: current.items,
        nextCursor: current.nextCursor,
        loadingMore: true,
      ),
    );
    try {
      final page = await _fetch(current.nextCursor);
      if (!ref.mounted) return;
      final seen = {for (final t in current.items) t.productId};
      state = AsyncData(
        ProductListState(
          // 같은 묶음을 다시 받아도 중복으로 붙이지 않는다(계약 설명).
          items: [
            ...current.items,
            ...page.items.where((t) => !seen.contains(t.productId)),
          ],
          nextCursor: page.nextCursor,
        ),
      );
    } on PmartFailure catch (e) {
      if (!ref.mounted) return;
      state = AsyncData(
        ProductListState(
          items: current.items,
          nextCursor: current.nextCursor,
          loadMoreFailure: e,
        ),
      );
    }
  }
}
