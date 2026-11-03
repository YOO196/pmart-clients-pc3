import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../../address/presentation/address_screens.dart' show LoginRequired;
import '../../checkout/presentation/delivery_select_screen.dart'
    show windowText;
import '../../checkout/presentation/order_sheet_screen.dart' show tipReasonText;
import '../../checkout/presentation/shipping_address_view.dart';
import '../../claims/domain/claims.dart';
import '../../claims/presentation/claims_controller.dart'
    show orderClaimsProvider;
import '../../claims/presentation/claims_screens.dart'
    show claimStateText, claimTypeText;
import '../../../shared/order_status.dart';
import '../domain/orders.dart';
import 'orders_providers.dart';

String _money(AppLocalizations l10n, int? v) => switch (v) {
  final int a => formatKrw(a),
  null => l10n.amountUnavailable,
};

/// SCR-ORDER-LIST-001. 조회 실패를 "주문 없음"으로 보이지 않는다.
class OrderListScreen extends ConsumerWidget {
  const OrderListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(orderListProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.ordersTitle),
        // 결제 완료에서 주문 상세로 바로 오면(go) 뒤에 화면이 없다. 그때는 마이로 돌아간다.
        leading: context.canPop()
            ? null
            : IconButton(
                key: const ValueKey('orders-back'),
                icon: const BackButtonIcon(),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => context.go('/my'),
              ),
      ),
      body: switch (value) {
        AsyncData(value: null) => LoginRequired(
          message: l10n.ordersLoginNeeded,
        ),
        _ => UiStateView<OrderPage?>(
          state: uiStateOf(value, isEmpty: (p) => p!.items.isEmpty),
          onRetry: () => ref.invalidate(orderListProvider),
          empty: (_) => Center(
            key: const ValueKey('orders-empty'),
            child: Text(l10n.ordersEmpty),
          ),
          ready: (context, page) => RefreshIndicator(
            onRefresh: () => ref.refresh(orderListProvider.future),
            child: ListView(
              children: [
                for (final o in page!.items)
                  ListTile(
                    key: ValueKey('order-${o.orderId}'),
                    title: Text(orderStatusText(l10n, o.status)),
                    subtitle: Text(
                      [
                        if (o.orderedAt case final t?) formatSeoulDateTime(t),
                        if (o.itemCount case final n?) l10n.ordersItemCount(n),
                      ].join(' · '),
                    ),
                    trailing: Text(_money(l10n, o.totalAmount)),
                    onTap: () async {
                      await context.push('/orders/${o.orderId}');
                      // 상세에서 취소·변경을 했을 수 있다. 돌아오면 목록을 다시 읽는다.
                      if (context.mounted) ref.invalidate(orderListProvider);
                    },
                  ),
              ],
            ),
          ),
        ),
      },
    );
  }
}

/// SCR-ORDER-DETAIL-001. 주문 당시 스냅샷 + 원천별 기준시각. 분할배송은 배송별로 보인다.
class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final provider = orderDetailProvider(orderId);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.orderDetailTitle)),
      body: UiStateView<OrderDetail>(
        state: uiStateOf(ref.watch(provider)),
        onRetry: () => ref.invalidate(provider),
        ready: (context, o) => RefreshIndicator(
          onRefresh: () => ref.refresh(provider.future),
          child: _OrderBody(order: o),
        ),
      ),
    );
  }
}

class _OrderBody extends ConsumerWidget {
  const _OrderBody({required this.order});

  final OrderDetail order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final o = order;
    final byLine = {for (final l in o.lines) l.orderLineId: l};

    /// 취소·변경·처리 내역 화면에 다녀오면 주문이 바뀌었을 수 있다. 돌아올 때 상세·목록을 다시 읽는다.
    Future<void> visit(String location) async {
      await context.push(location);
      if (!context.mounted) return;
      ref.invalidate(orderDetailProvider(o.orderId));
      ref.invalidate(orderClaimsProvider(o.orderId));
      ref.invalidate(orderListProvider);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          orderStatusText(l10n, o.status),
          key: const ValueKey('order-status'),
          style: theme.textTheme.headlineSmall,
        ),
        Text(l10n.payOrderNumber(o.orderId), style: theme.textTheme.bodySmall),
        if (o.window case final w?) Text(windowText(w)),
        for (final s in o.staleSources)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              s.asOf == null
                  ? l10n.sourceStaleNoTime
                  : l10n.sourceStale(formatSeoulTime(s.asOf!)),
              key: ValueKey('stale-${s.system}'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        if (o.isSplit)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(l10n.splitShipment(o.shipments.length)),
          ),
        for (final (i, s) in o.shipments.indexed)
          Card(
            key: ValueKey('shipment-${s.shipmentId}'),
            margin: const EdgeInsets.only(top: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          o.isSplit
                              ? l10n.shipmentN(
                                  i + 1,
                                  shipmentStateText(l10n, s.state),
                                )
                              : shipmentStateText(l10n, s.state),
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      if (s.deliveryId case final id?)
                        TextButton(
                          key: ValueKey('track-$id'),
                          onPressed: () => context.push('/deliveries/$id'),
                          child: Text(l10n.trackDelivery),
                        ),
                    ],
                  ),
                  // 주문 당시 상품명·옵션 사본(BR-35). 없을 때만 sku.
                  for (final sl in s.lines)
                    Text(
                      '${byLine[sl.orderLineId]?.title ?? sl.orderLineId} · ${l10n.cartLineQuantity(sl.qty)}',
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        // 주문 당시 배송지 사본(BR-37). 주소록을 다시 부르지 않는다.
        Text(l10n.checkoutAddress, style: theme.textTheme.titleMedium),
        ShippingAddressView(address: o.shippingAddress),
        const SizedBox(height: 16),
        Text(l10n.checkoutItems, style: theme.textTheme.titleMedium),
        for (final l in o.lines) _LineTile(line: l),
        const SizedBox(height: 16),
        Text(l10n.checkoutAmounts, style: theme.textTheme.titleMedium),
        _Row(l10n.amountItems, _money(l10n, o.quote?.itemAmount)),
        if (o.quote case final q?)
          _Row(
            '${l10n.amountTip} (${tipReasonText(l10n, q.tipReason)})',
            _money(l10n, q.deliveryTip),
          ),
        _Row(l10n.amountBag, _money(l10n, o.quote?.bagFee)),
        _Row(l10n.amountTotal, _money(l10n, o.quote?.totalAmount)),
        if ((o.refundedAmount ?? 0) > 0)
          _Row(
            l10n.refundedAmount,
            formatKrw(o.refundedAmount!),
            key: const ValueKey('refunded'),
          ),
        _ClaimsSection(order: o, onVisit: visit),
        const SizedBox(height: 16),
        // 버튼은 요청 진입일 뿐이다. 가능 여부는 서버가 판정한다.
        if (o.deliveryMode == 'SCHEDULED' && o.status == OrderStatus.confirmed)
          OutlinedButton(
            key: const ValueKey('reschedule'),
            onPressed: () => visit('/orders/${o.orderId}/reschedule'),
            child: Text(l10n.rescheduleTitle),
          ),
        if (switch (o.status) {
          OrderStatus.confirmed ||
          OrderStatus.preparing ||
          OrderStatus.partiallyHandedOver => true,
          _ => false,
        })
          OutlinedButton(
            key: const ValueKey('cancel-order'),
            onPressed: () => visit('/orders/${o.orderId}/cancel'),
            child: Text(l10n.cancelTitle),
          ),
      ],
    );
  }
}

/// 주문의 처리 내역(취소·반품·교환). 서버는 주문 상세의 `claims` 를 아직 비워 보내므로 `GET /claims?orderId=` 로 받고,
/// 상세에 들어 있는 항목이 있으면 합친다. 조회 실패는 "내역 없음"으로 보이지 않는다.
class _ClaimsSection extends ConsumerWidget {
  const _ClaimsSection({required this.order, required this.onVisit});

  final OrderDetail order;
  final Future<void> Function(String location) onVisit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final provider = orderClaimsProvider(order.orderId);
    final value = ref.watch(provider);
    final fetched = value.value ?? const <ClaimSummaryView>[];
    final ids = {for (final c in fetched) c.claimId};
    final items = [
      ...fetched,
      for (final c in order.claims)
        if (!ids.contains(c.claimId))
          ClaimSummaryView(
            claimId: c.claimId,
            orderId: order.orderId,
            type: claimTypeFromWire(c.type),
            state: claimStateFromWire(c.state),
          ),
    ];
    // 취소한 주문이 아니면 처리 내역 영역을 두지 않는다. 조회 실패도 취소된 주문(내역이 있어야 하는 주문)에서만
    // 보인다 — 취소하지 않은 주문마다 실패 문구가 뜨지 않게(사용자 요청 2026-11-03).
    final failed =
        value.hasError &&
        !value.hasValue &&
        (order.status == OrderStatus.cancelled || order.claims.isNotEmpty);
    if (items.isEmpty && !failed) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(l10n.orderClaimsTitle, style: theme.textTheme.titleMedium),
        if (failed)
          Row(
            key: const ValueKey('order-claims-failed'),
            children: [
              Expanded(
                child: Text(
                  l10n.orderClaimsLoadFailed,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
              TextButton(
                onPressed: () => ref.invalidate(provider),
                child: Text(l10n.checkoutCheckAgain),
              ),
            ],
          ),
        for (final c in items)
          ListTile(
            key: ValueKey('order-claim-${c.claimId}'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.assignment_return_outlined),
            title: Text(claimTypeText(l10n, c.type)),
            subtitle: Text(
              [
                claimStateText(l10n, c.state),
                if (c.openedAt case final t?)
                  l10n.claimOpenedAt(formatSeoulDateTime(t)),
              ].join(' · '),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onVisit('/claims/${c.claimId}'),
          ),
      ],
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line});

  final OrderLineView line;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final l = line;
    // 서버가 나눠 준 수량만 보인다(앱에서 빼거나 더하지 않는다).
    final notes = [
      if ((l.cancelledBeforeShipQty ?? 0) > 0)
        l10n.qtyCancelled(l.cancelledBeforeShipQty!),
      if ((l.deliveredQty ?? 0) > 0) l10n.qtyDelivered(l.deliveredQty!),
      if ((l.returnedQty ?? 0) > 0) l10n.qtyReturned(l.returnedQty!),
      if ((l.unfulfilledQty ?? 0) > 0) l10n.qtyUnfulfilled(l.unfulfilledQty!),
    ];
    return ListTile(
      key: ValueKey('line-${l.orderLineId}'),
      contentPadding: EdgeInsets.zero,
      // 주문 당시 상품명·옵션 사본(BR-35). 없을 때만 sku.
      title: Text(l.title),
      subtitle: notes.isEmpty ? null : Text(notes.join(' · ')),
      trailing: Text(
        [
          if (l.originalQty case final q?) l10n.cartLineQuantity(q),
          if (l.unitPrice case final p?) formatKrw(p),
        ].join(' · '),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value),
      ],
    ),
  );
}

/// SCR-TRACK-001. 위치 조회 실패는 배송 실패가 아니다. 라이더 좌표·다른 고객 정보는 받지도 보이지도 않는다.
class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key, required this.deliveryId});

  final String deliveryId;

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(ref.read(etaRefreshIntervalProvider), (_) {
      if (mounted) ref.invalidate(deliveryEtaProvider(widget.deliveryId));
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = deliveryEtaProvider(widget.deliveryId);
    final value = ref.watch(provider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.trackTitle)),
      body: switch (value) {
        // 조회 실패: "배송 실패"가 아니라 "위치를 불러오지 못함"이다.
        AsyncError() when !value.hasValue => Center(
          key: const ValueKey('eta-failed'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.etaLoadFailed, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(provider),
                child: Text(l10n.checkoutCheckAgain),
              ),
            ],
          ),
        ),
        _ => UiStateView<DeliveryEtaView>(
          state: uiStateOf(value),
          onRetry: () => ref.invalidate(provider),
          ready: (context, e) => _EtaBody(eta: e),
        ),
      },
    );
  }
}

class _EtaBody extends StatelessWidget {
  const _EtaBody({required this.eta});

  final DeliveryEtaView eta;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final e = eta;
    final etaLine = switch (e.status) {
      EtaStatus.available when e.etaAt != null => l10n.etaAt(
        formatSeoulTime(e.etaAt!),
      ),
      EtaStatus.locating => l10n.etaLocating,
      EtaStatus.pending => l10n.etaPending,
      EtaStatus.finalized => l10n.stDone,
      _ => l10n.etaPending,
    };
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          stageText(l10n, e.stage),
          key: const ValueKey('eta-stage'),
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          etaLine,
          key: const ValueKey('eta-line'),
          style: theme.textTheme.titleLarge,
        ),
        if (e.status == EtaStatus.available && e.remainingSeconds != null)
          Text(l10n.etaRemaining((e.remainingSeconds! / 60).ceil())),
        if (e.window case final w?) Text(windowText(w)),
        if ((e.delayedBySeconds ?? 0) > 0 && e.status == EtaStatus.available)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.etaDelayed((e.delayedBySeconds! / 60).ceil()),
              key: const ValueKey('eta-delayed'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        if (e.asOf case final t?)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              e.freshness == Freshness.current
                  ? l10n.asOfTime(formatSeoulTime(t))
                  : l10n.sourceStale(formatSeoulTime(t)),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
