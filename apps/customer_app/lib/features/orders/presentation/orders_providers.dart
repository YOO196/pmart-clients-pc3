import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/order_status.dart';
import '../../../shared/providers.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../checkout/data/mock_checkout_repository.dart';
import '../../checkout/presentation/checkout_controller.dart';
import '../../payment/domain/payment.dart' show PaymentSummary;
import '../../payment/presentation/payment_controller.dart'
    show paymentRepositoryProvider;
import '../data/mock_orders_repository.dart';
import '../data/orders_repository.dart';
import '../domain/orders.dart';

final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockOrdersRepository(
      checkout: switch (ref.watch(checkoutRepositoryProvider)) {
        final MockCheckoutRepository m => m,
        _ => null,
      },
      now: ref.watch(clockProvider),
    ),
    PmartEnv.local => ApiOrdersRepository(ref.watch(dioProvider)),
  },
);

/// 배송 도착 예상 주기 조회 간격. 실시간 구독(SSE)이 끊긴 동안만 쓴다.
final etaRefreshIntervalProvider = Provider<Duration>(
  (_) => const Duration(seconds: 30),
);

/// 실시간 구독 재연결 대기([attempt] 는 1부터). 1·2·4·…초, 최대 60초.
final trackingReconnectDelayProvider = Provider<Duration Function(int attempt)>(
  (_) => (attempt) {
    final seconds = 1 << (attempt - 1).clamp(0, 6);
    return Duration(seconds: seconds > 60 ? 60 : seconds);
  },
);

/// 예약 시간 변경 요청 진입을 보일지. 계약: 예약배달이고 상품 준비 전(CONFIRMED)만 받는다. 가능 여부는 서버가 최종 판정한다.
bool canRequestTimeChange(OrderDetail o) =>
    o.deliveryMode == 'SCHEDULED' && o.status == OrderStatus.confirmed;

/// 주문 취소(`POST /claims`) 진입을 보일지. 가능 여부는 서버가 최종 판정한다.
bool canRequestCancel(OrderDetail o) => switch (o.status) {
  OrderStatus.confirmed ||
  OrderStatus.preparing ||
  OrderStatus.partiallyHandedOver => true,
  _ => false,
};

/// 본인 주문 목록. [status] 가 있으면 그 상태만(계약 `GET /orders?status=`). 비회원이면 null(빈 목록과 구분).
final orderListProvider = FutureProvider.autoDispose
    .family<OrderPage?, OrderStatus?>((ref, status) async {
      if (ref.watch(sessionProvider) is! MemberSession) return null;
      return ref.watch(ordersRepositoryProvider).list(status: status);
    });

/// 주문 목록의 상태 필터(앞에서부터 "전체" 다음 차례). 계약 `status` 는 하나만 받으므로 묶음 필터(진행 중 등)는 두지 않는다.
const orderListFilters = <OrderStatus>[
  OrderStatus.confirmed,
  OrderStatus.preparing,
  OrderStatus.inDelivery,
  OrderStatus.completed,
  OrderStatus.cancelled,
];

/// 주문의 결제 수단(`GET /payments/{paymentAttemptId}`). 실패는 오류로 남는다("정보 없음"으로 바꾸지 않는다).
final orderPaymentProvider = FutureProvider.autoDispose
    .family<PaymentSummary, String>(
      (ref, paymentAttemptId) =>
          ref.watch(paymentRepositoryProvider).payment(paymentAttemptId),
    );

final orderDetailProvider = FutureProvider.autoDispose
    .family<OrderDetail, String>(
      (ref, orderId) => ref.watch(ordersRepositoryProvider).get(orderId),
    );

final deliveryEtaProvider = FutureProvider.autoDispose
    .family<DeliveryEtaView, String>(
      (ref, deliveryId) => ref.watch(ordersRepositoryProvider).eta(deliveryId),
    );

/// 주문 상태 → 고객 문구(잠정, BR-12).
String orderStatusText(AppLocalizations l10n, OrderStatus s) => switch (s) {
  OrderStatus.draft || OrderStatus.resourcePending => l10n.osChecking,
  OrderStatus.paymentPending => l10n.osPaymentPending,
  OrderStatus.paymentUnknown => l10n.osPaymentUnknown,
  OrderStatus.confirmed => l10n.osConfirmed,
  OrderStatus.preparing => l10n.osPreparing,
  OrderStatus.partiallyHandedOver => l10n.osPartiallyHandedOver,
  OrderStatus.inDelivery => l10n.osInDelivery,
  OrderStatus.partiallyDelivered => l10n.osPartiallyDelivered,
  OrderStatus.completed => l10n.osCompleted,
  OrderStatus.cancelled => l10n.osCancelled,
  OrderStatus.expired => l10n.osExpired,
  OrderStatus.unknown => l10n.osUnknown,
};

String shipmentStateText(AppLocalizations l10n, ShipmentState s) => switch (s) {
  ShipmentState.planned => l10n.shPlanned,
  ShipmentState.preparing => l10n.shPreparing,
  ShipmentState.ready => l10n.shReady,
  ShipmentState.handedOver => l10n.shHandedOver,
  ShipmentState.inDelivery => l10n.shInDelivery,
  ShipmentState.delivered => l10n.shDelivered,
  ShipmentState.failed => l10n.shFailed,
  ShipmentState.cancelled => l10n.shCancelled,
  ShipmentState.unknown => l10n.shUnknown,
};

String stageText(AppLocalizations l10n, DeliveryStage s) => switch (s) {
  DeliveryStage.unassigned => l10n.stUnassigned,
  DeliveryStage.toStore => l10n.stToStore,
  DeliveryStage.atStore => l10n.stAtStore,
  DeliveryStage.toCustomer => l10n.stToCustomer,
  DeliveryStage.atCustomer => l10n.stAtCustomer,
  DeliveryStage.done => l10n.stDone,
  DeliveryStage.unknown => l10n.stUnknown,
};
