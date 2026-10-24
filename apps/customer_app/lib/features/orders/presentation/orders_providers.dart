import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/order_status.dart';
import '../../../shared/providers.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../checkout/data/mock_checkout_repository.dart';
import '../../checkout/presentation/checkout_controller.dart';
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

/// 배송 도착 예상 갱신 간격(SSE 를 붙이기 전까지 조회로 갱신한다).
final etaRefreshIntervalProvider = Provider<Duration>(
  (_) => const Duration(seconds: 30),
);

/// 본인 주문 목록. 비회원이면 null(빈 목록과 구분).
final orderListProvider = FutureProvider.autoDispose<OrderPage?>((ref) async {
  if (ref.watch(sessionProvider) is! MemberSession) return null;
  return ref.watch(ordersRepositoryProvider).list();
});

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
