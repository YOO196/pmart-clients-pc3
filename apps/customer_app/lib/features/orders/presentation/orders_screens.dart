import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart'
    show
        CommandStatus,
        IdempotencyKey,
        PmartFailure,
        ProblemFailure,
        UnknownResultFailure;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../../address/presentation/address_screens.dart' show LoginRequired;
import '../../address/presentation/map_pick_screen.dart' show GeoPoint;
import '../../checkout/presentation/delivery_select_screen.dart'
    show modeLabel, windowText;
import '../../checkout/presentation/order_sheet_screen.dart' show tipReasonText;
import '../../checkout/presentation/shipping_address_view.dart';
import '../../claims/domain/claims.dart';
import '../../claims/presentation/claims_controller.dart'
    show claimProvider, orderClaimsProvider;
import '../../claims/presentation/claims_screens.dart'
    show claimStateText, claimTypeText;
import '../../../shared/order_status.dart';
import '../../../shared/cart_icon_button.dart';
import '../../cart/domain/cart.dart';
import '../../cart/presentation/cart_controller.dart';
import '../../cart/presentation/cart_messages.dart';
import '../../catalog/presentation/catalog_providers.dart'
    show productDetailProvider;
import '../../catalog/presentation/widgets/discount_price.dart'
    show discountRateColor;
import '../../catalog/presentation/widgets/product_tile_card.dart'
    show ProductImage;
import '../../checkout/domain/checkout.dart'
    show ArrivalWindow, OutOfStockPreference;
import '../data/orders_repository.dart'
    show OrdersRepository, orderNotFinishedCode;
import '../domain/orders.dart';
import '../domain/tracking.dart';
import 'tracking_map.dart';
import 'orders_providers.dart';
import 'receipt_confirmation.dart';
import '../../../shared/notice.dart';
import '../../support/domain/inquiry.dart' show InquiryCategory;
import '../../support/presentation/inquiry_screens.dart' show InquiryFormArgs;
import '../../redelivery/presentation/redelivery_screens.dart'
    show RedeliveryPaymentsSection;

String _money(AppLocalizations l10n, int? v) => switch (v) {
  final int a => formatKrw(a),
  null => l10n.amountUnavailable,
};

/// SCR-ORDER-LIST-001. 조회 실패를 "주문 없음"으로 보이지 않는다.
/// 위 줄: 검색 · 조회 기간 · 상태(레퍼런스 9-1 "주문내역"). 기간 기본은 서버 기본(최근 3개월, order 0.12.0).
class OrderListScreen extends ConsumerStatefulWidget {
  const OrderListScreen({super.key});

  @override
  ConsumerState<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends ConsumerState<OrderListScreen> {
  /// 상태 필터. null 이면 전체. 서버에 `status` 로 묻는다(앱에서 거르지 않는다).
  OrderStatus? _status;
  OrderPeriod _period = OrderPeriod.months3;

  /// 적용한 상품명 검색어(서버 `q`). null 이면 검색 안 함.
  String? _q;
  bool _searching = false;
  final _searchCtl = TextEditingController();

  /// [더보기]를 누른 주문(카드에 나머지 줄을 그린다).
  final _expanded = <String>{};

  /// 카드의 상품 한 줄: 사진 / 이름 / 금액·수량 / ⊕.
  Widget _cardLine(
    ThemeData theme,
    AppLocalizations l10n, {
    required String id,
    required String? productId,
    required String? imageUrl,
    required String sku,
    required String name,
    required int? amount,
    required int quantity,
  }) {
    final scheme = theme.colorScheme;
    return Padding(
      key: ValueKey('order-line-$id'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          // 사진·이름을 누르면 상품 상세(사용자 2026-11-21). 상품 ID 가 없는 옛 주문 줄은 누를 수 없다.
          Expanded(
            child: InkWell(
              key: ValueKey('order-line-open-$id'),
              borderRadius: BorderRadius.circular(8),
              onTap: productId == null
                  ? null
                  : () => context.push(
                      '/products/${Uri.encodeComponent(productId)}',
                    ),
              child: Row(
                children: [
                  _ListLineImage(
                    key: ValueKey('order-line-image-$id'),
                    productId: productId,
                    imageUrl: imageUrl,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: amount == null ? '' : formatKrw(amount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(
                                text: '  ${l10n.cartLineQuantity(quantity)}',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 주문내역에서도 바로 담는다(레퍼런스 9-2 ⊕, 사용자 2026-11-20). 담을 수 있는지는 장바구니 서버가 판정한다.
          ReorderButton(
            key: ValueKey('order-line-add-$id'),
            sku: sku,
            quantity: quantity,
          ),
        ],
      ),
    );
  }

  /// 앞 5줄 뒤: 접혀 있으면 [더보기], 펼치면 주문 상세의 나머지 줄 + [접기].
  List<Widget> _moreLines(
    ThemeData theme,
    AppLocalizations l10n,
    OrderListItem o,
  ) {
    final scheme = theme.colorScheme;
    Widget toggle(String key, String label, PmartLineIcons icon) => Center(
      child: TextButton(
        key: ValueKey('$key-${o.orderId}'),
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurface,
          textStyle: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        onPressed: () => setState(() {
          if (!_expanded.remove(o.orderId)) _expanded.add(o.orderId);
        }),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            const SizedBox(width: 4),
            PmartLineIcon(icon, size: 16),
          ],
        ),
      ),
    );
    if (!_expanded.contains(o.orderId)) {
      return [
        toggle('order-more', l10n.ordersMore, PmartLineIcons.chevronDown),
      ];
    }
    final shown = {for (final l in o.lines) l.orderLineId};
    final detail = ref.watch(orderDetailProvider(o.orderId));
    return [
      switch (detail) {
        AsyncData(:final value) => Column(
          key: ValueKey('order-more-lines-${o.orderId}'),
          children: [
            for (final l in value.lines)
              if (!shown.contains(l.orderLineId))
                _cardLine(
                  theme,
                  l10n,
                  id: l.orderLineId,
                  productId: l.productId,
                  imageUrl: l.imageUrl,
                  sku: l.sku,
                  name: l.title,
                  // 주문상세 줄과 같이: 서버 줄 금액, 없으면(옛 응답) 단가
                  amount: l.lineAmount ?? l.unitPrice,
                  quantity: l.originalQty ?? 0,
                ),
          ],
        ),
        AsyncError() => Row(
          key: ValueKey('order-more-failed-${o.orderId}'),
          children: [
            Expanded(
              child: Text(
                l10n.ordersMoreFailed,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(orderDetailProvider(o.orderId)),
              child: Text(l10n.faqRetry),
            ),
          ],
        ),
        _ => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      },
      toggle('order-less', l10n.ordersLess, PmartLineIcons.chevronUp),
    ];
  }

  OrderListQuery get _query =>
      OrderListQuery(status: _status, period: _period, q: _q);

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  String _periodText(AppLocalizations l10n, OrderPeriod p) => switch (p) {
    OrderPeriod.months3 => l10n.ordersPeriod3m,
    OrderPeriod.months6 => l10n.ordersPeriod6m,
    OrderPeriod.year1 => l10n.ordersPeriod1y,
    OrderPeriod.all => l10n.ordersPeriodAll,
  };

  /// 레퍼런스(사용자 캡처 2026-11-20 "조회 기간"·"주문 상태·정보" 시트): 제목 + ✕, 회색 묶음 이름,
  /// 테두리 알약(고르면 검게), 아래 [↻ 초기화][적용]. 고른 값은 [적용]을 눌러야 들어간다.
  Future<(T,)?> _chipSheet<T>({
    required String title,
    String? group,
    required List<(T, String, String)> options,
    required T initial,
    required T reset,
  }) => showModalBottomSheet<(T,)>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      var picked = initial;
      final l10n = AppLocalizations.of(context);
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 8, 12),
            child: Column(
              key: const ValueKey('orders-sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('orders-sheet-close'),
                      tooltip: l10n.actionClose,
                      icon: const PmartLineIcon(PmartLineIcons.close, size: 24),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                if (group != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 2),
                    child: Text(
                      group,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.outline,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (value, key, label) in options)
                        Material(
                          color: value == picked
                              ? scheme.onSurface
                              : scheme.surface,
                          shape: StadiumBorder(
                            side: BorderSide(
                              color: value == picked
                                  ? scheme.onSurface
                                  : scheme.outlineVariant,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: ValueKey(key),
                            onTap: () => setSheet(() => picked = value),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 10,
                              ),
                              child: Text(
                                label,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontSize: 15,
                                  color: value == picked
                                      ? scheme.surface
                                      : scheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('orders-sheet-reset'),
                        onPressed: () => setSheet(() => picked = reset),
                        icon: const PmartLineIcon(
                          PmartLineIcons.refresh,
                          size: 18,
                        ),
                        label: Text(l10n.ordersReset),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(110, 50),
                          foregroundColor: scheme.onSurface,
                          side: BorderSide(color: scheme.outlineVariant),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          key: const ValueKey('orders-sheet-apply'),
                          onPressed: () => Navigator.of(context).pop((picked,)),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          child: Text(l10n.ordersApply),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Future<void> _pickPeriod(AppLocalizations l10n) async {
    final picked = await _chipSheet<OrderPeriod>(
      title: l10n.ordersPeriod,
      options: [
        for (final p in OrderPeriod.values)
          (p, 'orders-period-${p.name}', _periodText(l10n, p)),
      ],
      initial: _period,
      reset: OrderPeriod.months3,
    );
    if (picked != null && mounted) setState(() => _period = picked.$1);
  }

  Future<void> _pickStatus(AppLocalizations l10n) async {
    final picked = await _chipSheet<OrderStatus?>(
      title: l10n.ordersStatusPill,
      group: l10n.ordersStatusGroup,
      options: [
        for (final s in <OrderStatus?>[null, ...orderListFilters])
          (
            s,
            'orders-filter-${s?.name ?? 'all'}',
            s == null ? l10n.ordersFilterAll : orderStatusText(l10n, s),
          ),
      ],
      initial: _status,
      reset: null,
    );
    if (picked != null && mounted) setState(() => _status = picked.$1);
  }

  void _applySearch() {
    final q = _searchCtl.text.trim();
    setState(() => _q = q.isEmpty ? null : q);
  }

  void _closeSearch() {
    _searchCtl.clear();
    setState(() {
      _searching = false;
      _q = null;
    });
  }

  Widget _pill({
    required Key key,
    required Widget label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: Material(
        key: key,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? scheme.onSurface : scheme.outlineVariant,
          ),
        ),
        // 레퍼런스 9-1: 고른 조건은 검게 채운 알약
        color: selected ? scheme.onSurface : scheme.surface,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          // 알약 높이는 줄(목록 높이)이 정한다 — 글자는 가운데에 두고 위아래로 자르지 않는다(사용자 2026-11-20 "글자 깨짐").
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              widthFactor: 1,
              child: IconTheme.merge(
                data: IconThemeData(
                  color: selected ? scheme.surface : scheme.onSurface,
                ),
                child: DefaultTextStyle.merge(
                  // 레퍼런스 9-1 을 1080px 로 재면 "조회 기간" 153px ≈ 14sp, 알약 높이 98px ≈ 33dp.
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    height: 1.2,
                    color: selected ? scheme.surface : scheme.onSurface,
                  ),
                  child: label,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = orderListProvider(_query);
    final value = ref.watch(provider);
    final filters = SizedBox(
      height: 53,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(15, 10, 15, 10),
        children: [
          // 레퍼런스(사용자 캡처): 조건이 걸리면 맨 앞에 ↻ 초기화
          if (_status != null || _q != null || _period != OrderPeriod.months3)
            _pill(
              key: const ValueKey('orders-reset'),
              selected: false,
              onTap: () {
                _searchCtl.clear();
                setState(() {
                  _status = null;
                  _q = null;
                  _searching = false;
                  _period = OrderPeriod.months3;
                });
              },
              label: const PmartLineIcon(PmartLineIcons.refresh, size: 18),
            ),
          _pill(
            key: const ValueKey('orders-search-open'),
            selected: _q != null,
            onTap: () => setState(() => _searching = true),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PmartLineIcon(PmartLineIcons.search, size: 16),
                const SizedBox(width: 4),
                Text(_q ?? l10n.ordersSearch),
              ],
            ),
          ),
          _pill(
            key: const ValueKey('orders-period'),
            selected: _period != OrderPeriod.months3,
            onTap: () => _pickPeriod(l10n),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _period == OrderPeriod.months3
                      ? l10n.ordersPeriod
                      : _periodText(l10n, _period),
                ),
                const SizedBox(width: 2),
                const PmartLineIcon(PmartLineIcons.chevronDown, size: 16),
              ],
            ),
          ),
          _pill(
            key: const ValueKey('orders-status'),
            selected: _status != null,
            onTap: () => _pickStatus(l10n),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _status == null
                      ? l10n.ordersStatusPill
                      : orderStatusText(l10n, _status!),
                ),
                const SizedBox(width: 2),
                const PmartLineIcon(PmartLineIcons.chevronDown, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        // 레퍼런스 9-1: 왼쪽 큰 제목 + 오른쪽 장바구니
        centerTitle: false,
        titleSpacing: context.canPop() ? pmartLeftTitleSpacing : 20,
        titleTextStyle: Theme.of(context).appBarTheme.titleTextStyle
            ?.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
        title: Text(l10n.ordersTitle),
        actions: const [CartIconButton(), SizedBox(width: 6)],
        // 하단 탭 "주문내역"(사용자 2026-11-21) — 탭 첫 화면이라 뒤로 버튼이 없다.
      ),
      body: switch (value) {
        AsyncData(value: null) => LoginRequired(
          message: l10n.ordersLoginNeeded,
        ),
        _ => Column(
          children: [
            if (_searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 6, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('orders-search-field'),
                        controller: _searchCtl,
                        autofocus: true,
                        maxLength: 100,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: l10n.ordersSearchHint,
                          counterText: '',
                          isDense: true,
                          prefixIcon: const Padding(
                            padding: EdgeInsets.all(10),
                            child: PmartLineIcon(
                              PmartLineIcons.search,
                              size: 18,
                            ),
                          ),
                        ),
                        onSubmitted: (_) => _applySearch(),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('orders-search-close'),
                      icon: const PmartLineIcon(PmartLineIcons.close),
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                      onPressed: _closeSearch,
                    ),
                  ],
                ),
              ),
            filters,
            Expanded(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: _list(l10n, provider, value),
              ),
            ),
          ],
        ),
      },
    );
  }

  /// 주문 카드 한 장: 배송 방식·상태 · "주문 상세" 알약 / 주문 시각(크게) / 대표 상품 · 금액 / (끝난 주문) 같은 상품 담기.
  Widget _orderCard(
    BuildContext context,
    AppLocalizations l10n,
    OrderListItem o,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mode = o.deliveryMode;
    final summary = switch ((o.representativeName, o.othersQty)) {
      (final String name, final int others) when others > 0 =>
        l10n.ordersRepresentative(name, others),
      (final String name, _) when o.representativeQty != null =>
        l10n.ordersRepresentativeOnly(name, o.representativeQty!),
      (final String name, _) => name,
      // 2026-11-02 전 주문은 상품명 사본이 없다 → "상품 N개".
      (null, _) when o.itemCount != null => l10n.ordersItemCount(o.itemCount!),
      _ => null,
    };
    final ongoing = !o.canHide;
    Widget outlined(
      String key,
      String label,
      VoidCallback onTap, {
      bool strong = false,
      PmartLineIcons? lead,
    }) => Expanded(
      child: OutlinedButton(
        key: ValueKey(key),
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
          foregroundColor: scheme.onSurface,
          side: BorderSide(
            color: strong ? scheme.onSurface : scheme.outlineVariant,
            width: strong ? 1.4 : 1,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: theme.textTheme.titleSmall?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: Text(label),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 레퍼런스 9-1: 방식(굵게) ··· 오른쪽 회색 알약 "주문상세"
        Row(
          children: [
            Expanded(
              child: Text(
                mode != null
                    ? modeLabel(l10n, mode)
                    : orderStatusText(l10n, o.status),
                key: mode != null ? ValueKey('order-mode-${o.orderId}') : null,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            // 레퍼런스 9-1 1: 알약 58px ≈ 19dp, 글자 112px ≈ 11sp
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                l10n.orderDetailTitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  height: 1.2,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        // 담당 센터 이름(order 0.17.0 — 레퍼런스 9-2 카드 머리). 모르면 줄 없이.
        if (o.mfcName case final name?)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              name,
              key: ValueKey('order-mfc-${o.orderId}'),
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 10),
        // 진행 중: 큰 굵은 글씨로 지금 상태, 아래 주문 시각. 끝난 주문: 날짜 · 상태 한 줄.
        if (ongoing) ...[
          Text(
            orderStatusText(l10n, o.status),
            key: ValueKey('order-status-${o.orderId}'),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 21.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (o.orderedAt case final t?)
            Text(
              l10n.ordersOrderedAt(formatSeoulDateTime(t)),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ] else
          Row(
            children: [
              if (o.orderedAt case final t?)
                Text(
                  '${formatSeoulDate(t)} · ',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              Text(
                orderStatusText(l10n, o.status),
                key: ValueKey('order-status-${o.orderId}'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: o.status == OrderStatus.cancelled
                      ? scheme.error
                      : scheme.onSurface,
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 12),
        // 상품 줄(order 0.17.0 — 레퍼런스 9-2): 사진 / 이름 / 금액·수량. 사진은 줄에 주소가 없어(BR-71) 상품 상세의
        // 대표 사진을 쓴다(주문상세 줄과 같은 방식, 사용자 2026-11-20). 못 받으면 빈 사진 자리.
        // 서버가 앞 5개만 준다 — 더 있으면(전체 수량 > 보인 수량) [더보기]로 주문 상세를 받아 나머지 줄을 이어 그린다
        // (사용자 2026-11-20 "더보기로 바꿔줘"). 받는 중·실패는 그 자리에 보이고, 실패를 빈 목록으로 두지 않는다.
        for (final l in o.lines)
          _cardLine(
            theme,
            l10n,
            id: l.orderLineId,
            productId: l.productId,
            imageUrl: l.imageUrl,
            sku: l.sku,
            name: [?l.productName, ?l.optionLabel].join(' · '),
            amount: l.lineAmount,
            quantity: l.quantity,
          ),
        if (o.moreQty != null) ..._moreLines(theme, l10n, o),
        if (o.lines.isNotEmpty) ...[
          const Divider(height: 1),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            // 상품 줄이 있으면 왼쪽은 "결제금액", 없으면(예전 서버·사본 없음) 대표 상품 요약.
            if (o.lines.isNotEmpty)
              Expanded(
                child: Text(
                  l10n.amountTotal,
                  style: theme.textTheme.bodyLarge?.copyWith(fontSize: 14.5),
                ),
              )
            else if (summary != null)
              Expanded(
                child: Text(
                  summary,
                  key: ValueKey('order-summary-${o.orderId}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15),
                ),
              )
            else
              const Spacer(),
            const SizedBox(width: 8),
            Text(
              _money(l10n, o.totalAmount),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        if (ongoing) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              outlined(
                'order-help-${o.orderId}',
                l10n.orderHelp,
                () => context.push('/orders/${o.orderId}/help'),
              ),
              const SizedBox(width: 8),
              outlined(
                'order-track-${o.orderId}',
                l10n.ordersTrack,
                () => context.push('/orders/${o.orderId}/tracking'),
                strong: true,
              ),
            ],
          ),
        ],
        // 끝난 주문: 카드 아래 넓은 [같은 상품 담기](레퍼런스 9-2 1, 사용자 2026-11-20). 카드에 안 보인 상품이
        // 있으면(서버가 앞 5개만 줌) 전부 담을 수 있는 주문상세로 간다.
        if (!ongoing && o.lines.isNotEmpty) ...[
          const SizedBox(height: 14),
          o.moreQty == null
              ? ReorderAllButton(
                  key: ValueKey('order-reorder-all-${o.orderId}'),
                  lines: [
                    for (final l in o.lines) (sku: l.sku, quantity: l.quantity),
                  ],
                )
              : ReorderAllButton.goDetail(
                  key: ValueKey('order-reorder-all-${o.orderId}'),
                  onPressed: () => context.push('/orders/${o.orderId}'),
                ),
        ],
        // 목록 카드의 [삭제]는 뺐다(사용자 2026-11-23 "주문마다 붙어 있는 삭제 버튼 지워") — 삭제는 주문 상세 맨 아래에서만.
      ],
    );
  }

  Widget _list(
    AppLocalizations l10n,
    FutureProvider<OrderPage?> provider,
    AsyncValue<OrderPage?> value,
  ) {
    final filtered = _status != null;
    final narrowed = _q != null || _period != OrderPeriod.months3;
    return UiStateView<OrderPage?>(
      loading: (_) => const PmartListSkeleton(thumb: true, rows: 4),
      state: uiStateOf(value, isEmpty: (p) => p!.items.isEmpty),
      onRetry: () => ref.invalidate(provider),
      // 조건이 걸려 있으면 "주문 없음"이 아니라 "이 조건의 주문 없음"이다.
      empty: (_) => Center(
        key: ValueKey(
          narrowed
              ? 'orders-empty-search'
              : filtered
              ? 'orders-empty-filtered'
              : 'orders-empty',
        ),
        // 레퍼런스 9-1 1: 돋보기 그림 + 굵은 두 줄 + 테두리 알약 [일단 검색! >]
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PmartLineIcon(
              PmartLineIcons.search,
              size: 44,
              strokeWidth: 2.2,
            ),
            const SizedBox(height: 40),
            Text(
              narrowed
                  ? l10n.ordersEmptySearch
                  : filtered
                  ? l10n.ordersEmptyFiltered
                  : l10n.ordersEmpty,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 16,
                height: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              key: const ValueKey('orders-empty-search-go'),
              onPressed: () => context.go('/search'),
              style: OutlinedButton.styleFrom(
                shape: const StadiumBorder(),
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.fromLTRB(18, 0, 12, 0),
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                textStyle: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(fontSize: 16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.ordersEmptyGoSearch),
                  const SizedBox(width: 4),
                  const PmartLineIcon(PmartLineIcons.chevronRight, size: 18),
                ],
              ),
            ),
          ],
        ),
      ),
      ready: (context, page) => RefreshIndicator(
        onRefresh: () => ref.refresh(provider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
          children: [
            for (final o in page!.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  key: ValueKey('order-${o.orderId}'),
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () async {
                      await context.push('/orders/${o.orderId}');
                      // 상세에서 취소·변경을 했을 수 있다. 돌아오면 목록을 다시 읽는다.
                      if (context.mounted) ref.invalidate(orderListProvider);
                    },
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        18,
                        20,
                        o.canHide ? 6 : 18,
                      ),
                      child: _orderCard(context, l10n, o),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 주문 내역에서 삭제(숨기기): 확인 창 → `POST /orders/{id}/hides`(order 0.12.0 — 끝난 주문만, 아니면 409
/// `ORDER_NOT_FINISHED`). 결과를 모르면 같은 키로 한 번 더 보낸다(계약: 같은 키는 같은 결과). 서버 목록이 정본이라
/// 결과와 상관없이 목록을 다시 읽는다. 서버가 받아들였으면(APPLIED·ACCEPTED) true.
/// 목록 줄의 [삭제]와 주문 상세 맨 아래 [주문내역 삭제]가 같이 쓴다.
Future<bool> confirmAndHideOrder(
  BuildContext context,
  WidgetRef ref,
  String orderId, {
  void Function(bool sending)? onSending,
}) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.ordersHideTitle),
      content: Text(l10n.ordersHideBody),
      actions: [
        TextButton(
          key: const ValueKey('orders-hide-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.ordersHideCancel),
        ),
        FilledButton(
          key: const ValueKey('orders-hide-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.ordersHideConfirm),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  onSending?.call(true);
  final repo = ref.read(ordersRepositoryProvider);
  final key = IdempotencyKey.generate();
  String message;
  var done = false;
  try {
    CommandStatus status;
    try {
      status = await repo.hide(orderId, key: key);
    } on UnknownResultFailure {
      status = await repo.hide(orderId, key: key);
    }
    done = status == CommandStatus.applied || status == CommandStatus.accepted;
    message = switch (status) {
      CommandStatus.applied => l10n.ordersHideDone,
      CommandStatus.accepted => l10n.ordersHideAccepted,
      _ => l10n.ordersHideFailed,
    };
  } on ProblemFailure catch (f) {
    message = f.problem.code == orderNotFinishedCode
        ? l10n.ordersHideNotFinished
        : l10n.ordersHideFailed;
  } on PmartFailure {
    message = l10n.ordersHideFailed;
  }
  onSending?.call(false);
  ref.invalidate(orderListProvider);
  if (context.mounted) showNotice(context, message);
  return done;
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
      appBar: AppBar(
        titleTextStyle: Theme.of(context).appBarTheme.titleTextStyle
            ?.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
        title: Text(l10n.orderDetailTitle),
        actions: const [CartIconButton(), SizedBox(width: 6)],
      ),
      body: UiStateView<OrderDetail>(
        loading: (_) => const PmartDetailSkeleton(image: false),
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
    Future<void> visit(String location, {Object? extra}) async {
      await context.push(location, extra: extra);
      if (!context.mounted) return;
      ref.invalidate(orderDetailProvider(o.orderId));
      ref.invalidate(orderClaimsProvider(o.orderId));
      ref.invalidate(orderListProvider);
    }

    final scheme = theme.colorScheme;
    final mode = switch (o.deliveryMode) {
      'SINGLE' => l10n.modeSingle,
      'BUNDLED' => l10n.modeBundled,
      'SCHEDULED' => l10n.modeScheduled,
      _ => null,
    };
    Widget small(
      String key,
      String label,
      VoidCallback onTap, {
      PmartLineIcons? lead,
      bool chevron = false,
    }) => OutlinedButton(
      key: ValueKey(key),
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 9),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        textStyle: theme.textTheme.bodySmall?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (lead != null) ...[
            PmartLineIcon(lead, size: 14),
            const SizedBox(width: 3),
          ],
          Text(label),
          if (chevron)
            const PmartLineIcon(PmartLineIcons.chevronRight, size: 14),
        ],
      ),
    );
    Widget wide(
      String key,
      String label,
      VoidCallback onTap, {
      bool strong = false,
      PmartLineIcons? lead,
    }) => Expanded(
      child: OutlinedButton(
        key: ValueKey(key),
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
          foregroundColor: scheme.onSurface,
          backgroundColor: scheme.surface,
          side: BorderSide(
            color: strong ? scheme.onSurface : scheme.outlineVariant,
            width: strong ? 1.4 : 1,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: theme.textTheme.titleSmall?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (lead != null) ...[
              PmartLineIcon(lead, size: 19, strokeWidth: 1.8),
              const SizedBox(width: 5),
            ],
            Flexible(child: Text(label)),
          ],
        ),
      ),
    );
    final itemsKey = GlobalObjectKey('$hashCode-items');
    final payKey = GlobalObjectKey('$hashCode-pay');
    final deliveryKey = GlobalObjectKey('$hashCode-delivery');
    void jump(GlobalKey k) {
      final c = k.currentContext;
      if (c != null) {
        Scrollable.ensureVisible(
          c,
          duration: const Duration(milliseconds: 250),
        );
      }
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      // 사용자 2026-11-21 "주문상세 너무 다닥다닥" — 레퍼런스 9-1 3-1 간격(블록 사이 16~24, 구획 사이 32, 카드 안 18).
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 레퍼런스 9-1 3-2: 요약 카드 — 큰 제목(예약 시간 또는 상태 문장), 방식·주문번호, 카드 안 작은 단추, 센터 줄
          _DetailBox(
            children: [
              Text(
                // 배송 단계 문구(배송현황·홈 현황판과 같은 제목, 사용자 2026-11-21). 예약 확정(준비 전)이면
                // 레퍼런스 9-1 3-2 "10월 11일 (일)" 줄바꿈 "오전 8:00~오전 9:00 예약".
                deliveryPhaseText(
                  l10n,
                  status: o.status,
                  deliveryMode: o.deliveryMode,
                  reservedTitle: switch (o.window) {
                    final w? => reservedHeadline(l10n, w),
                    null => null,
                  },
                ).title,
                key: const ValueKey('order-headline'),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              DefaultTextStyle.merge(
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // "알뜰배달 · 반품 완료"처럼 방식 · 상태 한 줄(상태가 취소·반품이면 빨강)
                    Wrap(
                      children: [
                        if (mode != null) Text('$mode · '),
                        Text(
                          orderStatusText(l10n, o.status),
                          key: const ValueKey('order-status'),
                          style: o.status == OrderStatus.cancelled
                              ? TextStyle(color: scheme.error)
                              : null,
                        ),
                      ],
                    ),
                    Text(
                      l10n.payOrderNumber(o.displayNumber),
                      key: const ValueKey('order-number'),
                    ),
                  ],
                ),
              ),
              // 버튼은 요청 진입일 뿐이다. 가능 여부는 서버가 판정한다.
              if (canRequestCancel(o) || canRequestTimeChange(o)) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  children: [
                    if (canRequestCancel(o))
                      small(
                        'cancel-order',
                        l10n.cancelTitle,
                        () => visit('/orders/${o.orderId}/cancel'),
                        lead: PmartLineIcons.clearCircle,
                      ),
                    if (canRequestTimeChange(o))
                      small(
                        'reschedule',
                        l10n.rescheduleTitle,
                        () => visit('/orders/${o.orderId}/reschedule'),
                        chevron: true,
                      ),
                  ],
                ),
              ],
              if (!canRequestCancel(o) && cancelClosedByPreparing(o))
                // 피킹이 시작되면 앱에서 취소할 수 없다(ADR-0060) — 버튼 대신 안내.
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.cancelClosedPreparing,
                    key: const ValueKey('cancel-closed-preparing'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              if (o.mfcName case final name?) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      name,
                      key: const ValueKey('order-center'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          // 주문 상태마다 버튼이 다르다(레퍼런스 9-1·9-2, 사용자 2026-11-21) — 문의는 접수일 뿐 주문을 바꾸지 않는다.
          //  · 취소된 주문: 버튼 없음(9-1 3-1)
          //  · 배송 완료: [반품·교환] [문의하기](9-2 2) — 반품 접수는 고객센터만이라(claim 0.2.0) 환불 문의로 잇는다
          //  · 예약 확정(준비 전): [문의하기](9-1 3-2)
          //  · 준비~배달 중: [문의하기] [배달 현황] — 배송 ID 를 몰라도 지도부터 뜬다(BR-61)
          if (switch (orderDetailActions(o)) {
                final actions when actions.isNotEmpty => actions,
                _ => null,
              }
              case final actions?) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                for (final (i, a) in actions.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  switch (a) {
                    OrderDetailAction.returnExchange => wide(
                      'order-return-exchange',
                      l10n.orderReturnExchange,
                      () => visit(
                        '/support/inquiries/new',
                        extra: InquiryFormArgs(
                          orderId: o.orderId,
                          category: InquiryCategory.refund,
                        ),
                      ),
                    ),
                    OrderDetailAction.inquiry => wide(
                      'order-inquiry',
                      l10n.orderInquiry,
                      () => visit('/orders/${o.orderId}/help'),
                      lead: PmartLineIcons.questionBubble,
                    ),
                    OrderDetailAction.track => wide(
                      'order-track',
                      l10n.ordersTrack,
                      () => visit('/orders/${o.orderId}/tracking'),
                      strong: true,
                    ),
                  },
                ],
              ],
            ),
          ],
          // 오배송 다시 배송비 결제(있을 때만). 알림 "결제 필요"(목적지 ORDER)를 열면 이 주문 상세로 온다.
          RedeliveryPaymentsSection(orderId: o.orderId),
          for (final s in o.staleSources)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                s.asOf == null
                    ? l10n.sourceStaleNoTime
                    : l10n.sourceStale(formatSeoulTime(s.asOf!)),
                key: ValueKey('stale-${s.system}'),
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
          const SizedBox(height: 24),
          // 구획 칩: 누르면 그 구획으로
          Row(
            children: [
              for (final (i, (key, label, target)) in [
                ('order-tab-items', l10n.orderTabItems, itemsKey),
                ('order-tab-pay', l10n.orderTabPay, payKey),
                ('order-tab-delivery', l10n.orderTabDelivery, deliveryKey),
              ].indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Material(
                    color: i == 0 ? scheme.onSurface : scheme.surface,
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: i == 0
                            ? scheme.onSurface
                            : scheme.outlineVariant,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: ValueKey(key),
                      onTap: () => jump(target),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: Text(
                          label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: i == 0 ? scheme.surface : scheme.onSurface,
                            fontWeight: i == 0 ? FontWeight.w700 : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (o.isSplit)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l10n.splitShipment(o.shipments.length)),
            ),
          // 배송 완료된 배송 칸은 그리지 않는다(사용자 2026-11-21 — 위 단계 제목이 이미 "배달이 완료됐어요"를 말한다).
          // 단, 방금 "받았어요"를 눌러 결과(완료·접수·확인 중)를 보이는 배송은 남긴다 — 결과·다시 확인을 숨기지 않는다.
          // 취소된 주문은 배송 칸을 그리지 않는다(사용자 2026-11-23 "주문취소됐을 때 배송 취소 컴포넌트 없애") — 위 제목이
          // 이미 "주문이 취소됐어요"를 말한다.
          for (final (i, s) in o.shipments.indexed)
            if (o.status != OrderStatus.cancelled &&
                (s.state != ShipmentState.delivered ||
                    (s.deliveryId != null &&
                        ref.watch(
                          receiptConfirmationProvider((
                            orderId: o.orderId,
                            deliveryId: s.deliveryId!,
                          )),
                        ) is! ReceiptIdle)))
              Card(
                key: ValueKey('shipment-${s.shipmentId}'),
                margin: const EdgeInsets.only(top: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 6, 12),
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
                              onPressed: () => visit(
                                '/deliveries/$id?orderId=${Uri.encodeQueryComponent(o.orderId)}',
                              ),
                              child: Text(l10n.trackDelivery),
                            ),
                        ],
                      ),
                      // 주문 당시 상품명·옵션 사본(BR-35). 없을 때만 sku.
                      for (final sl in s.lines)
                        Text(
                          '${byLine[sl.orderLineId]?.title ?? sl.orderLineId} · ${l10n.cartLineQuantity(sl.qty)}',
                        ),
                      // "받았어요"(수령 확인): 배송 중인 배송만 도착 예상 단계를 묻는다. 누른 뒤에는 결과를 남긴다.
                      if (s.deliveryId case final id?
                          when s.state == ShipmentState.handedOver ||
                              s.state == ShipmentState.inDelivery ||
                              ref.watch(
                                receiptConfirmationProvider((
                                  orderId: o.orderId,
                                  deliveryId: id,
                                )),
                              ) is! ReceiptIdle)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ReceiptConfirmation(
                            orderId: o.orderId,
                            deliveryId: id,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 32),
          KeyedSubtree(
            key: itemsKey,
            child: _OrderLinesSection(order: o),
          ),
          const SizedBox(height: 32),
          _DetailTitle(l10n.orderTabPay, key: payKey),
          _DetailBox(
            children: [
              _Row(l10n.amountItems, _money(l10n, o.quote?.listItemAmount)),
              if (o.quote case final q?)
                _Row(
                  '${l10n.amountTip} (${tipReasonText(l10n, q.tipReason)})',
                  _money(l10n, q.deliveryTip),
                ),
              _Row(l10n.amountBag, _money(l10n, o.quote?.bagFee)),
              // 할인(order 0.18.0 — 서버 값만, 0 이면 줄을 두지 않는다).
              if (o.quote?.promotionDiscount case final d? when d > 0)
                _Row(l10n.amountPromotion, formatKrw(d, negative: true)),
              if (o.quote?.couponDiscount case final d? when d > 0)
                _Row(
                  // 주문 조회도 쿠폰 이름을 준다(order 0.19.0). 없으면 "쿠폰 할인".
                  o.quote?.coupon?.name ?? l10n.amountCoupon,
                  formatKrw(d, negative: true),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Divider(
                  height: 2,
                  thickness: 1.6,
                  color: scheme.onSurface,
                ),
              ),
              _Row(
                (o.refundedAmount ?? 0) > 0
                    ? l10n.amountTotalInitial
                    : l10n.amountTotal,
                _money(l10n, o.quote?.totalAmount),
                strong: true,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Divider(height: 1),
              ),
              _PaymentMethodRow(paymentAttemptId: o.paymentAttemptId),
              if ((o.refundedAmount ?? 0) > 0)
                _Row(
                  l10n.refundedAmount,
                  formatKrw(o.refundedAmount!),
                  key: const ValueKey('refunded'),
                ),
            ],
          ),
          _ClaimsSection(order: o, onVisit: visit),
          const SizedBox(height: 32),
          // 배달 정보: 주문 당시 배송지 사본(BR-37, 주소록을 다시 부르지 않는다) + 요청사항·품절 시 처리.
          _DetailTitle(l10n.orderTabDelivery, key: deliveryKey),
          _DeliveryInfoBox(order: o),
          // 리뷰 쓰기 칸은 뺐다(사용자 2026-11-21) — 리뷰는 마이 > 리뷰관리에서.
          // 끝난 주문(완료·취소·만료)은 맨 아래 [주문내역 삭제](order 0.12.0 숨기기 — 최종 판정은 서버).
          if (switch (o.status) {
            OrderStatus.completed ||
            OrderStatus.cancelled ||
            OrderStatus.expired => true,
            _ => false,
          }) ...[
            const SizedBox(height: 32),
            _HideOrderButton(orderId: o.orderId),
          ],
        ],
      ),
    );
  }
}

/// 주문 상세 맨 아래 [주문내역 삭제] — 숨기면 목록에서 빠지고 이 화면을 닫는다(상세 조회는 그대로 된다).
class _HideOrderButton extends ConsumerStatefulWidget {
  const _HideOrderButton({required this.orderId});
  final String orderId;
  @override
  ConsumerState<_HideOrderButton> createState() => _HideOrderButtonState();
}

class _HideOrderButtonState extends ConsumerState<_HideOrderButton> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      key: const ValueKey('order-detail-hide'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: scheme.onSurfaceVariant,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: _busy
          ? null
          : () async {
              final done = await confirmAndHideOrder(
                context,
                ref,
                widget.orderId,
                onSending: (b) {
                  if (mounted) setState(() => _busy = b);
                },
              );
              if (done && context.mounted && context.canPop()) context.pop();
            },
      child: Text(l10n.orderDetailHide),
    );
  }
}

/// 주문 상세의 구획 제목(카드 밖).
class _DetailTitle extends StatelessWidget {
  const _DetailTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    // 레퍼런스 9-1 3-1: 제목은 카드보다 조금 안쪽, 카드까지 약 14
    padding: const EdgeInsets.fromLTRB(6, 0, 6, 14),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 16),
    ),
  );
}

/// 주문 상세의 테두리 카드.
class _DetailBox extends StatelessWidget {
  const _DetailBox({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    // 레퍼런스 9-1 3-1: 카드 안 좌우 약 18, 모서리 16
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
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
    final scheme = theme.colorScheme;
    // 다른 칸(주문 상품·결제 정보·배달 정보)과 같은 모양: 제목 + 테두리 카드, 칸 사이 32(사용자 2026-11-23 "처리 내역 디자인 통일").
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        _DetailTitle(l10n.orderClaimsTitle),
        _DetailBox(
          children: [
            if (failed)
              Row(
                key: const ValueKey('order-claims-failed'),
                children: [
                  Expanded(
                    child: Text(
                      l10n.orderClaimsLoadFailed,
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(provider),
                    child: Text(l10n.checkoutCheckAgain),
                  ),
                ],
              ),
            // 취소된 주문이면 가장 최근 취소 클레임의 사유로 자동 취소인지 본다(주문 상세 `claims` 는 아직 비어 있다)
            if (order.status == OrderStatus.cancelled)
              if (items.where((c) => c.type == ClaimType.cancel).firstOrNull
                  case final latest?)
                _AutoCancelNotice(claimId: latest.claimId),
            for (final (i, c) in items.indexed) ...[
              if (i > 0 || failed) const Divider(height: 20),
              InkWell(
                key: ValueKey('order-claim-${c.claimId}'),
                onTap: () => onVisit('/claims/${c.claimId}'),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 배달 정보 칸과 같은 글자·간격(이름 16 → 6 → 값 15 회색, 사용자 2026-11-23).
                          Text(
                            claimTypeText(l10n, c.type),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            [
                              claimStateText(l10n, c.state, type: c.type),
                              if (c.openedAt case final t?)
                                l10n.claimOpenedAt(formatSeoulDateTime(t)),
                            ].join(' · '),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 15,
                              height: 1.45,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PmartLineIcon(
                      PmartLineIcons.chevronRight,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// 시스템 자동 전체 취소 안내(백엔드 공지 2026-11-07). 주문이 취소로 확정된 뒤에만 그린다.
/// 클레임 조회가 실패하거나 아직이면 아무것도 보이지 않는다 — 처리 내역 줄은 그대로 있어 눌러 볼 수 있다.
class _AutoCancelNotice extends ConsumerWidget {
  const _AutoCancelNotice({required this.claimId});

  final String claimId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auto = ref.watch(claimProvider(claimId)).value?.autoCancelled;
    if (auto != true) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        AppLocalizations.of(context).claimAutoCancelled,
        key: const ValueKey('order-auto-cancelled'),
      ),
    );
  }
}

/// 결제 수단(`GET /payments/{paymentAttemptId}.method`). 조회 실패는 "정보 없음"이 아니라 실패 + 다시 조회.
class _PaymentMethodRow extends ConsumerWidget {
  const _PaymentMethodRow({required this.paymentAttemptId});

  final String? paymentAttemptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final id = paymentAttemptId;
    if (id == null) {
      return _Row(
        l10n.orderPaymentMethod,
        l10n.orderPaymentMethodNone,
        key: const ValueKey('order-payment-method'),
      );
    }
    final provider = orderPaymentProvider(id);
    final value = ref.watch(provider);
    if (value.hasError && !value.hasValue) {
      return Row(
        key: const ValueKey('order-payment-method-failed'),
        children: [
          Expanded(
            child: Text(
              l10n.orderPaymentMethodFailed,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
          TextButton(
            onPressed: () => ref.invalidate(provider),
            child: Text(l10n.checkoutCheckAgain),
          ),
        ],
      );
    }
    return _Row(l10n.orderPaymentMethod, switch (value) {
      AsyncData(:final value) => value.method ?? l10n.orderPaymentMethodNone,
      _ => l10n.orderPaymentMethodChecking,
    }, key: const ValueKey('order-payment-method'));
  }
}

/// 지난 주문 상품을 다시 담는 변경. 같은 SKU 가 이미 있으면 그 줄 수량에 더한다(사용자 2026-11-23 "같은 상품 장바구니에
/// 있다고 뜨지 말고 추가해줘") — 담기(AddItem)는 절대 수량 설정이라 있는 줄은 SetQuantity(있는 수량 + 주문 수량)로 보낸다.
/// 상한 초과 등은 서버가 거절하고 그 이유를 보인다.
CartChange reorderChange(Cart cart, String sku, int quantity) {
  final qty = quantity < 1 ? 1 : quantity;
  final inCart = cart.lineForSku(sku);
  return inCart == null
      ? AddItem(sku: sku, quantity: qty)
      : SetQuantity(
          cartItemId: inCart.cartItemId,
          quantity: inCart.quantity + qty,
        );
}

/// 주문 상품 + "같은 상품 담기"(Commerce 주문내역: 과거 주문 수정이 아니라 현재 조건의 새 담기, 성공 항목만 담김).
/// 품목마다 기존 장바구니 담기 경로(AddItem)로 보내고 결과를 그 줄에 보인다. "전체 다시 담기"는 차례로 보낸다.
class _OrderLinesSection extends ConsumerStatefulWidget {
  const _OrderLinesSection({required this.order});

  final OrderDetail order;

  @override
  ConsumerState<_OrderLinesSection> createState() => _OrderLinesSectionState();
}

class _OrderLinesSectionState extends ConsumerState<_OrderLinesSection> {
  /// [같은 상품 담기]로 이미 담은 줄 — 다시 누르면 담기지 않은 줄만 보낸다.
  final _done = <String>{};

  /// 지금 담는 줄(⊕) 또는 전체(null 이 아니면 줄 id, '*' 는 전체).
  String? _busy;

  String _outcomeText(AppLocalizations l10n, CartChangeOutcome? o) =>
      switch (o) {
        null => l10n.reorderBusy,
        final o => cartOutcomeText(l10n, o),
      };

  void _say(String text, {bool toCart = false}) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).notice(
      text,
      action: toCart
          ? SnackBarAction(
              label: l10n.cartGoToCart,
              onPressed: () => context.push('/cart'),
            )
          : null,
    );
  }

  /// 줄 ⊕ — 누를 때마다 1개씩(상품 카드·찜 + 와 같은 규칙, 사용자 2026-11-23). 결과는 아래 알림.
  Future<void> _addOne(OrderLineView line) async {
    if (_busy != null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = line.orderLineId);
    try {
      final cart = await ref.read(cartControllerProvider.future);
      final before = cart.cart.lineForSku(line.sku)?.quantity ?? 0;
      final outcome = await ref
          .read(cartControllerProvider.notifier)
          .submitWhenReady(reorderChange(cart.cart, line.sku, 1));
      if (!mounted) return;
      // 서버가 반영한 뒤에만 담긴 수량을 알린다.
      if (outcome is CartChangeApplied) {
        _say(l10n.cartInCart(before + 1), toCart: true);
      } else {
        _say(_outcomeText(l10n, outcome));
      }
    } on PmartFailure {
      if (mounted) _say(l10n.cartUnavailableForAdd);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// [같은 상품 담기] — 지난 주문 수량대로 차례로. 거절은 건너뛰고, 결과 모름·장바구니 바쁨이면 멈춘다.
  /// 결과는 알림 한 줄(담은 수 + 담지 못한 첫 사유).
  Future<void> _addAll(List<OrderLineView> lines) async {
    if (_busy != null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = '*');
    var added = 0;
    String? problem;
    try {
      for (final l in lines) {
        if (_done.contains(l.orderLineId)) continue;
        final cart = await ref.read(cartControllerProvider.future);
        final outcome = await ref
            .read(cartControllerProvider.notifier)
            .submitWhenReady(
              reorderChange(cart.cart, l.sku, l.originalQty ?? 1),
            );
        if (outcome is CartChangeApplied) {
          _done.add(l.orderLineId);
          added++;
          continue;
        }
        problem ??= _outcomeText(l10n, outcome);
        if (outcome == null || outcome is CartChangeUnknown) break;
      }
    } on PmartFailure {
      problem ??= l10n.cartUnavailableForAdd;
    } finally {
      if (mounted) setState(() => _busy = null);
    }
    if (!mounted) return;
    _say(switch ((added, problem)) {
      (_, null) => l10n.reorderAllAdded(added),
      (0, final p?) => p,
      (final n, final p?) => l10n.reorderAllSome(n, p),
    }, toCart: added > 0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final lines = widget.order.lines;
    // 레퍼런스 9-1 3-1: "주문 상품" 제목 + 테두리 카드 안에 줄·같은 상품 담기(사용자 2026-11-21 "다닥다닥").
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DetailTitle(l10n.orderTabItems),
        _DetailBox(
          children: [
            for (final (i, l) in lines.indexed) ...[
              // 레퍼런스 9-1 3-3: 줄과 줄 사이 옅은 선
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.6,
                  ),
                ),
              _LineTile(
                line: l,
                first: i == 0,
                // 레퍼런스 9-1 3-3: 줄마다 동그란 ⊕(글자 "담기" 아님)
                // 레퍼런스 9-1 3-3: 원 72px ≈ 24dp
                action: reorderCircle(
                  context: context,
                  key: ValueKey('reorder-${l.orderLineId}'),
                  size: 24,
                  tooltip: l10n.reorderLine,
                  onPressed: _busy != null ? null : () => _addOne(l),
                  icon: _busy == l.orderLineId
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const PmartLineIcon(PmartLineIcons.plus, size: 20),
                ),
              ),
            ],
            // 레퍼런스 9-1 3-3: 목록 아래 넓은 테두리 단추 "같은 상품 담기"
            if (lines.isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                key: const ValueKey('reorder-all'),
                style: OutlinedButton.styleFrom(
                  // 레퍼런스 9-1 3-3: 139px ≈ 46dp, 모서리 8dp
                  minimumSize: const Size.fromHeight(46),
                  foregroundColor: theme.colorScheme.onSurface,
                  side: BorderSide(
                    color: theme.colorScheme.onSurface,
                    width: 1.2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: _busy != null ? null : () => _addAll(lines),
                child: Text(l10n.reorderAll),
              ),
              const SizedBox(height: 8),
              Text(l10n.reorderNote, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ],
    );
  }
}

/// 주문 상품 한 줄(레퍼런스 9-1 3-3): 사진 · 이름 / 옵션 / **금액** 수량 · 오른쪽 ⊕.
/// 사진은 주문 행에 없어 지금 상품의 대표 사진을 쓴다(상품 조회 — 못 읽으면 자리 그림).
class _LineTile extends ConsumerWidget {
  const _LineTile({required this.line, this.action, this.first = false});

  /// 카드의 첫 줄 — 위 여백을 다른 카드(결제·배달 정보)와 같게 줄인다(사용자 2026-11-23 "카드 안 간격 같게").
  final bool first;

  final OrderLineView line;
  final Widget? action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l = line;
    // "전달 N개·취소 N개·반품 N개" 줄은 두지 않는다(사용자 2026-11-21 "제발 없애라고", 앞서 2026-11-20 "미출고"도 뺌).
    // 취소·반품은 아래 "처리 내역"과 결제 정보의 환불 금액에서 서버 값으로 보인다.
    final product = switch (l.productId) {
      final id? => ref.watch(productDetailProvider(id)).value,
      null => null,
    };
    // 사진은 서버 줄 값(order 0.19.0 BR-71)이 먼저, 없으면(옛 응답·조회 실패) 상품 조회의 대표 사진.
    final imageUrl = l.imageUrl ?? product?.mainImageUrl;
    // 레퍼런스 9-1 "지금 더 할인 중" — 그 옵션이 지금 기간 할인 중일 때(pricing 서버 값). 못 읽으면 없음.
    final nowOnSale =
        product?.options.where((o) => o.sku == l.sku).firstOrNull?.discount !=
        null;
    // 금액: 서버 행 금액이 먼저, 없으면 단가(옛 응답).
    final amount = l.lineAmount ?? l.unitPrice;
    return Padding(
      key: ValueKey('line-${l.orderLineId}'),
      // 레퍼런스 9-1 3-3: 줄 사이를 넉넉히(위아래 약 18dp) — 전에는 10dp 라 다닥다닥 붙어 보였다(사용자 2026-11-20).
      padding: EdgeInsets.only(top: first ? 6 : 18, bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProductImage(
            key: ValueKey('line-image-${l.orderLineId}'),
            url: imageUrl,
            size: 56,
            radius: 8,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (nowOnSale)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      l10n.orderLineNowOnSale,
                      key: ValueKey('line-now-sale-${l.orderLineId}'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: discountRateColor,
                      ),
                    ),
                  ),
                // 주문 당시 상품명 사본(BR-35). 없을 때만 sku.
                Text(
                  l.productName ?? l.sku,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                if (l.productName != null && l.optionLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '• ${l.optionLabel!}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        height: 1.4,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    children: [
                      if (amount != null)
                        TextSpan(
                          text: '${formatKrw(amount)}  ',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      if (l.originalQty case final q?)
                        TextSpan(
                          text: l10n.cartLineQuantity(q),
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                  key: ValueKey('line-amount-${l.orderLineId}'),
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                ),
                // 이 줄에 나눠 넣은 할인(order 0.18.0 `discountShare` — 기간 할인 + 쿠폰). 서버 값만, 0 이면 없음.
                if (l.discountShare case final d? when d > 0)
                  Text(
                    l10n.orderLineDiscount(formatKrw(d, negative: true)),
                    key: ValueKey('line-discount-${l.orderLineId}'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 13,
                      color: scheme.primary,
                    ),
                  ),
              ],
            ),
          ),
          if (action case final a?) ...[const SizedBox(width: 8), a],
        ],
      ),
    );
  }
}

/// 주문내역 카드 상품 줄의 대표 사진(레퍼런스 9-2 약 56dp 둥근 네모). 상품 ID 가 없거나 못 받으면 빈 자리.
class _ListLineImage extends ConsumerWidget {
  const _ListLineImage({
    super.key,
    required this.productId,
    required this.imageUrl,
  });

  final String? productId;

  /// 서버가 준 사진(order 0.19.0). 있으면 상품을 따로 조회하지 않는다.
  final String? imageUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ProductImage(
    url: switch ((imageUrl, productId)) {
      (final u?, _) => u,
      (null, final id?) =>
        ref.watch(productDetailProvider(id)).value?.mainImageUrl,
      _ => null,
    },
    size: 56,
    radius: 8,
  );
}

/// 주문내역 카드의 넓은 [같은 상품 담기](레퍼런스 9-2 1). 줄마다 차례로 담는다 — 이미 담긴 상품은 건너뛰고,
/// 거절되면 그 줄은 넘어가며, 결과 불명·장바구니 바쁨·조회 실패면 멈춘다(같은 키 재전송은 장바구니 컨트롤러가 한다).
/// 결과는 서버가 반영한 것만 센다.
class ReorderAllButton extends ConsumerStatefulWidget {
  const ReorderAllButton({super.key, required this.lines}) : onPressed = null;

  /// 카드에 다 보이지 않는 주문 — 주문상세로 보낸다.
  const ReorderAllButton.goDetail({super.key, required this.onPressed})
    : lines = const [];

  final List<({String sku, int quantity})> lines;
  final VoidCallback? onPressed;

  @override
  ConsumerState<ReorderAllButton> createState() => _ReorderAllButtonState();
}

class _ReorderAllButtonState extends ConsumerState<ReorderAllButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    var added = 0;
    String? stop;
    String? rejected;
    try {
      for (final line in widget.lines) {
        final cart = await ref.read(cartControllerProvider.future);
        final outcome = await ref
            .read(cartControllerProvider.notifier)
            .submitWhenReady(reorderChange(cart.cart, line.sku, line.quantity));
        switch (outcome) {
          case null:
            stop = l10n.reorderBusy;
          case CartChangeApplied():
            added++;
          case CartChangeRejected():
            rejected ??= cartOutcomeText(l10n, outcome);
          default:
            stop = cartOutcomeText(l10n, outcome);
        }
        if (stop != null) break;
      }
    } on PmartFailure {
      stop = l10n.cartUnavailableForAdd;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.notice(
      stop ??
          rejected ??
          (added > 0 ? l10n.reorderAllAdded(added) : l10n.reorderAllInCart),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // 레퍼런스 9-1 2 주문내역: 105px ≈ 35dp, 글자 234px ≈ 14sp 굵게
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(35),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: theme.textTheme.titleSmall?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      onPressed: _busy ? null : (widget.onPressed ?? _run),
      child: _busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(l10n.reorderAll),
    );
  }
}

/// 지난 주문의 상품을 장바구니에 다시 담는 동그란 ⊕(주문내역 카드). 이미 담긴 상품이면 그 수량에 더한다.
/// 결과는 알림으로 — 서버가 반영한 뒤에만 "담았어요"라고 한다.
class ReorderButton extends ConsumerStatefulWidget {
  const ReorderButton({super.key, required this.sku, required this.quantity});

  final String sku;
  final int quantity;

  @override
  ConsumerState<ReorderButton> createState() => _ReorderButtonState();
}

class _ReorderButtonState extends ConsumerState<ReorderButton> {
  bool _busy = false;

  Future<void> _add() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    String text;
    try {
      final cart = await ref.read(cartControllerProvider.future);
      final outcome = await ref
          .read(cartControllerProvider.notifier)
          .submitWhenReady(
            reorderChange(cart.cart, widget.sku, widget.quantity),
          );
      text = outcome == null
          ? l10n.reorderBusy
          : cartOutcomeText(l10n, outcome);
    } on PmartFailure {
      text = l10n.cartUnavailableForAdd;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.notice(text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 레퍼런스 9-1 2 주문내역: 원 88px ≈ 29dp, + 약 14dp
    return reorderCircle(
      context: context,
      size: 29,
      lightOutline: true,
      tooltip: l10n.reorderLine,
      onPressed: _busy ? null : _add,
      icon: _busy
          ? const SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const PmartLineIcon(PmartLineIcons.plus, size: 24),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {super.key, this.strong = false});

  final String label;
  final String value;

  /// 합계 줄처럼 굵고 크게.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = strong
        ? text.titleMedium?.copyWith(fontSize: 16)
        : text.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          // 레퍼런스 9-1 3-1: 결제금액 값은 이름보다 크다(약 18.5sp).
          Text(value, style: strong ? style?.copyWith(fontSize: 18.5) : style),
        ],
      ),
    );
  }
}

/// SCR-TRACK-001. 위치 조회 실패는 배송 실패가 아니다. 다른 고객 정보는 받지도 보이지도 않는다.
///
/// 실시간 구독(`GET /deliveries/{id}/stream`)으로 갱신하고, 끊기면 재연결(1·2·4…초)을 시도하는 동안
/// 도착 예상(`GET /deliveries/{id}/eta`)을 주기 조회한다. 화면을 닫거나 앱이 가려지면 연결을 닫는다.
/// [orderId] 가 있으면(주문 상세에서 진입) 주문·배송 상태로 4단계와 예약 시각·변경/취소 진입을 보인다.
///
/// 라이더 지도(레퍼런스 8-5): 배달 중(TO_CUSTOMER·AT_CUSTOMER)이면 지도 위에 라이더·내 배송지 마커를 그리고
/// 아래 시트에 진행을 보인다. 라이더 위치는 구독의 `ETA_UPDATED` 에 실린 `eta.riderLocation` 으로 옮긴다
/// (PC 5 요청 2026-11-19 — 서버는 새 위치를 3초 안에 보낸다). 구독이 끊겼거나 다시 붙는 동안에만
/// `GET /eta` 를 [riderLocationRefreshIntervalProvider](10초)마다 읽는다. 서버가 위치를 주지 않으면 마커를 숨기고,
/// 받은 지 60초가 넘은 위치는 흐리게 + "라이더 위치를 확인하고 있어요".
class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key, required this.deliveryId, this.orderId});

  final String deliveryId;
  final String? orderId;

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

/// 실시간 연결 상태. [polling] 일 때만 "주기적으로 확인" 문구를 보인다.
enum _Live { connecting, live, polling, ended, paused }

class _TrackingScreenState extends ConsumerState<TrackingScreen>
    with WidgetsBindingObserver {
  /// 이 화면에서 아직 끝나지 않은 주문을 본 적이 있는지 — 있으면 끝나는 순간에도 막지 않는다.
  bool _sawInProgress = false;

  late final OrdersRepository _repo;
  StreamSubscription<TrackingEvent>? _sub;
  Timer? _poll;
  Timer? _retry;

  /// 구독이 없는 동안의 라이더 위치 다시 읽기(10초).
  Timer? _locPoll;
  int _failures = 0;
  String? _lastEventId;

  /// 구독으로 받은 최신 도착 예상. 주기 조회로 넘어가면 비운다(조회 값이 더 새롭다).
  DeliveryEtaView? _live;
  _Live _mode = _Live.connecting;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(ordersRepositoryProvider);
    WidgetsBinding.instance.addObserver(this);
    _connect();
    _startLocationPoll();
  }

  /// 구독이 끊겼거나 다시 붙는 동안(배달 중일 때만) 도착 예상을 다시 읽어 라이더 위치를 새로 받는다.
  /// 구독이 붙어 있으면 읽지 않는다 — 위치는 `ETA_UPDATED` 로 온다. 픽업 전·끝난 뒤엔 서버가 위치를 주지 않는다.
  void _startLocationPoll() {
    _locPoll?.cancel();
    _locPoll = Timer.periodic(ref.read(riderLocationRefreshIntervalProvider), (
      _,
    ) {
      if (!mounted ||
          _mode == _Live.paused ||
          _mode == _Live.ended ||
          _mode == _Live.live) {
        return;
      }
      final stage =
          (_live ?? ref.read(deliveryEtaProvider(widget.deliveryId)).value)
              ?.stage;
      if (_isDelivering(stage)) {
        ref.invalidate(deliveryEtaProvider(widget.deliveryId));
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_mode == _Live.paused) _resume();
      case AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        _pause();
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    _poll?.cancel();
    _poll = null;
    _retry?.cancel();
    _retry = null;
    _locPoll?.cancel();
    _locPoll = null;
  }

  void _pause() {
    if (_mode == _Live.paused || _mode == _Live.ended) return;
    _stop();
    if (mounted) setState(() => _mode = _Live.paused);
  }

  void _resume() {
    if (_mode != _Live.paused) return;
    _failures = 0;
    _refreshAll();
    setState(() {
      _live = null;
      _mode = _Live.connecting;
    });
    _connect();
    _startLocationPoll();
  }

  void _refreshAll() {
    ref.invalidate(deliveryEtaProvider(widget.deliveryId));
    _refreshOrder();
  }

  void _refreshOrder() {
    if (widget.orderId case final id?) ref.invalidate(orderDetailProvider(id));
  }

  void _connect() {
    _sub?.cancel();
    _sub = _repo
        .track(widget.deliveryId, lastEventId: _lastEventId)
        .listen(
          _onEvent,
          onError: (Object _) => _onDrop(),
          onDone: _onDone,
          cancelOnError: true,
        );
  }

  void _onEvent(TrackingEvent e) {
    if (!mounted) return;
    _lastEventId = e.id ?? _lastEventId;
    _failures = 0;
    _retry?.cancel();
    _retry = null;
    _poll?.cancel();
    _poll = null;
    final current =
        _live ?? ref.read(deliveryEtaProvider(widget.deliveryId)).value;
    setState(() {
      _mode = e.type == TrackingEventType.streamEnd ? _Live.ended : _Live.live;
      if (e.eta case final eta?) {
        _live = eta;
      } else if (e.type == TrackingEventType.stageChanged &&
          e.stage != null &&
          current != null) {
        _live = current.withStage(e.stage!);
      }
    });
    // 단계가 바뀌거나 배송이 끝나면 주문·배송 상태를 서버에 다시 묻는다(완료 여부는 그 값으로만).
    if (e.type == TrackingEventType.stageChanged ||
        e.type == TrackingEventType.streamEnd) {
      _refreshOrder();
    }
  }

  void _onDone() {
    _sub = null;
    if (!mounted) return;
    if (_mode == _Live.ended) {
      // 서버가 배송 종료 뒤 닫았다. 다시 붙지 않고 마지막 값을 한 번 확인한다.
      _refreshAll();
      return;
    }
    _onDrop();
  }

  /// 끊김·연결 실패: 주기 조회로 넘어가고, 늘어나는 간격으로 다시 붙는다. 배송 실패가 아니다.
  void _onDrop() {
    _sub = null;
    if (!mounted || _mode == _Live.paused || _mode == _Live.ended) return;
    _failures++;
    setState(() {
      _mode = _Live.polling;
      _live = null;
    });
    if (_poll == null) {
      ref.invalidate(deliveryEtaProvider(widget.deliveryId));
      _poll = Timer.periodic(ref.read(etaRefreshIntervalProvider), (_) {
        if (mounted) _refreshAll();
      });
    }
    _retry?.cancel();
    _retry = Timer(ref.read(trackingReconnectDelayProvider)(_failures), () {
      if (mounted && _mode == _Live.polling) _connect();
    });
  }

  /// 취소·시간 변경 화면에 다녀오는 동안은 연결을 닫고, 돌아오면 주문·배송을 다시 읽고 다시 붙는다.
  Future<void> _visit(String location) async {
    _pause();
    await context.push(location);
    if (!mounted) return;
    ref.invalidate(orderListProvider);
    _refreshAll();
    _resume();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = deliveryEtaProvider(widget.deliveryId);
    final value = ref.watch(provider);
    final order = switch (widget.orderId) {
      final id? => ref.watch(orderDetailProvider(id)),
      null => null,
    };
    // 이미 배달이 끝난 주문을 열면 배송현황을 보이지 않는다(레퍼런스 10-4) — "주문내역에서 확인해주세요" 안내.
    // 보고 있던 배송이 끝나는 순간은 그대로 "배달 완료" 단계를 보인다.
    switch (order?.value?.status) {
      case OrderStatus.completed when !_sawInProgress:
        return TrackClosedNotice(orderId: widget.orderId!);
      case final s? when s != OrderStatus.completed:
        _sawInProgress = true;
      default:
        break;
    }
    final live = _live;
    // 배송현황은 늘 지도 화면이다(사용자 2026-11-19 "지도 바로 뜨게"). 라이더 위치는 배달 중에만 서버가 준다 —
    // 구독 값이 있으면 그것만(null 이면 숨김 — 예전 조회 값으로 채우지 않는다), 구독이 없으면 조회 값.
    final current = live ?? value.value;
    final rider = _isDelivering(current?.stage) ? current?.riderLocation : null;
    final ship = order?.value?.shippingAddress;
    final home = switch ((ship?.lat, ship?.lng)) {
      (final double lat, final double lng) => (lat: lat, lng: lng),
      // 사본에 핀이 없으면 배송지 도로명을 서버 주소 변환으로 찾아 지도 가운데·집 마커로 쓴다.
      _ => switch (ship?.roadAddress) {
        final road? => ref.watch(trackingHomeProvider(road)).value,
        null => null,
      },
    };
    final Widget sheet = switch (value) {
      _ when current != null => _TrackBody(
        eta: current,
        deliveryId: widget.deliveryId,
        order: order,
        polling: _mode == _Live.polling,
        onVisit: _visit,
        sheet: true,
        rider: rider,
      ),
      // 조회 실패: "배송 실패"가 아니라 "위치를 불러오지 못함"이다.
      AsyncError() => Padding(
        key: const ValueKey('eta-failed'),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          children: [
            Text(l10n.etaLoadFailed, textAlign: TextAlign.center),
            if (_mode == _Live.polling) ...[
              const SizedBox(height: 8),
              Text(
                l10n.trackLiveFallback,
                key: const ValueKey('track-live-fallback'),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => ref.invalidate(provider),
              child: Text(l10n.checkoutCheckAgain),
            ),
          ],
        ),
      ),
      // 초안 13-D: 원형 진행 표시 대신 회색 자리 표시.
      _ => const TrackSheetLoading(),
    };
    return _mapScaffold(context, sheet, rider, home);
  }

  Widget _mapScaffold(
    BuildContext context,
    Widget sheet,
    RiderPosition? rider,
    GeoPoint? home,
  ) {
    final orderId = widget.orderId;
    return TrackMapLayout(
      map: TrackingMap(
        rider: switch (rider) {
          final r? => (lat: r.lat, lng: r.lng),
          null => null,
        },
        riderStale: rider?.stale ?? false,
        home: home,
      ),
      sheet: sheet,
      onInquiry: orderId == null ? null : () => _visit('/orders/$orderId/help'),
    );
  }
}

/// 배달이 끝난 주문의 배송현황 자리(레퍼런스 10-4): 흐린 지도 위 가운데 안내 "선택하신 주문의 배달 상태는
/// 주문내역에서 확인해주세요" + [확인] → 그 주문 상세로.
class TrackClosedNotice extends StatelessWidget {
  const TrackClosedNotice({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      key: const ValueKey('track-closed'),
      body: Stack(
        children: [
          const Positioned.fill(child: TrackingMap(rider: null, home: null)),
          Positioned.fill(
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.5)),
          ),
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                    child: Text(
                      l10n.trackClosedNotice,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  InkWell(
                    key: const ValueKey('track-closed-ok'),
                    onTap: () => GoRouter.of(context).go('/orders/$orderId'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        l10n.startConfirm,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 레퍼런스 8-5: 지도 전체 + 아래 끌어 올리는 시트(진행·도착 예상). 위 왼쪽 뒤로, 오른쪽 문의하기.
class TrackMapLayout extends StatelessWidget {
  const TrackMapLayout({
    super.key,
    required this.map,
    required this.sheet,
    this.onInquiry,
    this.sheetFraction = TrackingMap.sheetFraction,
  });

  /// 처음 시트 높이(화면 비율). 레퍼런스 8: 배달 중은 약 절반, 주문 확인·예약은 거의 위까지.
  final double sheetFraction;

  final Widget map;
  final Widget sheet;
  final VoidCallback? onInquiry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      key: const ValueKey('track-map-mode'),
      body: Stack(
        children: [
          Positioned.fill(child: map),
          DraggableScrollableSheet(
            initialChildSize: sheetFraction,
            minChildSize: 0.3,
            maxChildSize: 0.92,
            builder: (context, scroll) => DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                boxShadow: const [
                  BoxShadow(blurRadius: 12, color: Color(0x22000000)),
                ],
              ),
              child: SingleChildScrollView(controller: scroll, child: sheet),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Material(
                    color: theme.colorScheme.surface,
                    shape: const CircleBorder(),
                    elevation: 2,
                    // 레퍼런스 8: 왼쪽 위 ✕
                    child: IconButton(
                      key: const ValueKey('track-close'),
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                      icon: const PmartLineIcon(PmartLineIcons.close, size: 22),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  const Spacer(),
                  if (onInquiry case final tap?)
                    Material(
                      color: theme.colorScheme.surface,
                      shape: const StadiumBorder(),
                      elevation: 2,
                      child: InkWell(
                        key: const ValueKey('track-map-inquiry'),
                        customBorder: const StadiumBorder(),
                        onTap: tap,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          // 레퍼런스: 글자만 있는 흰 알약 "문의하기"
                          child: Text(
                            l10n.orderInquiry,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 주문 단위 배송 현황(`/orders/{orderId}/tracking`). 주문 응답에 배송 ID(`shipments[].deliveryId`)가 있으면
/// 그 배송의 실시간 화면([TrackingScreen])을 그대로 보이고, 없으면(BR-61 — 지금 서버는 shipments 를 비워 준다)
/// 지도(내 배송지)·주문 단계만 보인다. 라이더 위치는 배송 ID 가 있어야 서버에 물을 수 있어 그때까지 보이지 않는다.
class OrderTrackingScreen extends ConsumerStatefulWidget {
  const OrderTrackingScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

/// 배송 ID 가 아직 없으면(배차 전 — 서버는 배송이 생긴 뒤 shipments 를 채운다, BR-61) [orderLinkPollIntervalProvider]
/// 마다 주문을 다시 읽어, 배송이 생기는 대로 실시간 화면(라이더 위치)으로 넘어간다. 앱이 가려지면 멈춘다.
class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen>
    with WidgetsBindingObserver {
  /// 이 화면에서 아직 끝나지 않은 주문을 본 적이 있는지 — 있으면 끝나는 순간에도 막지 않는다.
  bool _sawInProgress = false;

  Timer? _poll;

  String get orderId => widget.orderId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _start() {
    _poll?.cancel();
    _poll = Timer.periodic(ref.read(orderLinkPollIntervalProvider), (_) {
      if (!mounted) return;
      final o = ref.read(orderDetailProvider(orderId)).value;
      final linked = o?.shipments.any((s) => s.deliveryId != null) ?? false;
      if (linked) {
        _poll?.cancel();
        return;
      }
      ref.invalidate(orderDetailProvider(orderId));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        ref.invalidate(orderDetailProvider(orderId));
        _start();
      case AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        _poll?.cancel();
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  /// 취소·예약 변경 화면에 다녀오면 주문을 다시 읽는다(취소됐으면 버튼이 사라지고 단계가 바뀐다).
  Future<void> _visit(String location) async {
    _poll?.cancel();
    await context.push(location);
    if (!mounted) return;
    ref.invalidate(orderListProvider);
    ref.invalidate(orderDetailProvider(orderId));
    _start();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(orderDetailProvider(orderId));
    final o = value.value;
    // 이미 배달이 끝난 주문을 열면 배송현황을 보이지 않는다(레퍼런스 10-4 "배송완료 이후 알림 클릭해도 배송현황 볼 수 없음").
    switch (o?.status) {
      case OrderStatus.completed when !_sawInProgress:
        return TrackClosedNotice(orderId: orderId);
      case final s? when s != OrderStatus.completed:
        _sawInProgress = true;
      default:
        break;
    }
    final deliveryIds = [
      for (final s in o?.shipments ?? const <ShipmentView>[]) ?s.deliveryId,
    ];
    if (deliveryIds.isNotEmpty) {
      // 분할 배송이면 아직 끝나지 않은 첫 배송.
      final open = o!.shipments
          .where(
            (s) =>
                s.deliveryId != null &&
                s.state != ShipmentState.delivered &&
                s.state != ShipmentState.cancelled,
          )
          .firstOrNull;
      return TrackingScreen(
        deliveryId: open?.deliveryId ?? deliveryIds.first,
        orderId: orderId,
      );
    }
    final ship = o?.shippingAddress;
    final home = switch ((ship?.lat, ship?.lng)) {
      (final double lat, final double lng) => (lat: lat, lng: lng),
      _ => switch (ship?.roadAddress) {
        final road? => ref.watch(trackingHomeProvider(road)).value,
        null => null,
      },
    };
    final Widget sheet = switch (value) {
      _ when o != null => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Builder(
              builder: (context) {
                // 배송 단계 문구(레퍼런스 8-2 "주문을 확인했어요" / 8-4 예약) — 주문상세·홈 현황판과 같다.
                final phase = deliveryPhaseText(
                  l10n,
                  status: o.status,
                  deliveryMode: o.deliveryMode,
                  reservedTitle: switch (o.window) {
                    final w? => reservedHeadline(l10n, w),
                    null => null,
                  },
                );
                // 예약 확정(준비 전): 설명 줄 대신 변경 안내를 정보 칸으로(초안 13-B-4).
                final reserved =
                    o.status == OrderStatus.confirmed &&
                    o.deliveryMode == 'SCHEDULED' &&
                    o.window != null;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TrackSheetHead(
                      mode: deliveryModeText(l10n, o.deliveryMode),
                      headline: phase.title,
                      headlineKey: 'order-track-status',
                      subtitle: reserved ? null : phase.subtitle,
                      receipt: true,
                      calendar: reserved,
                    ),
                    // 초안 13-B: 작은 줄 대신 회색 정보 칸.
                    TrackInfo(
                      key: const ValueKey('track-no-delivery'),
                      text: l10n.trackRiderNotLinked,
                      tone: TrackInfoTone.muted,
                    ),
                    if (reserved && phase.subtitle != null)
                      TrackInfo(
                        text: phase.subtitle!,
                        tone: TrackInfoTone.muted,
                      ),
                    // 레퍼런스 8-2·초안 13-B-1(사용자 2026-11-23 "넣어"): 상품 준비 전(CONFIRMED)만 취소·예약 변경.
                    // 배달 중 화면과 같은 규칙([canRequestCancel]·[canRequestTimeChange]), 가능 여부는 서버가 최종 판정.
                    if (canRequestCancel(o) || canRequestTimeChange(o))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            if (canRequestCancel(o))
                              TextButton(
                                key: const ValueKey('track-cancel'),
                                style: trackPillButtonStyle(Theme.of(context)),
                                onPressed: () =>
                                    _visit('/orders/$orderId/cancel'),
                                child: Text(l10n.cancelTitle),
                              ),
                            if (canRequestTimeChange(o))
                              TextButton(
                                key: const ValueKey('track-reschedule'),
                                style: trackPillButtonStyle(Theme.of(context)),
                                onPressed: () =>
                                    _visit('/orders/$orderId/reschedule'),
                                child: Text(l10n.rescheduleTitle),
                              ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            _TrackSteps(progress: trackProgressOf(order: o.status)),
            OrderSheetDetails(order: o),
          ],
        ),
      ),
      AsyncError() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(l10n.trackOrderFailed, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => ref.invalidate(orderDetailProvider(orderId)),
              child: Text(l10n.checkoutCheckAgain),
            ),
          ],
        ),
      ),
      // 초안 13-D: 원형 진행 표시 대신 회색 자리 표시.
      _ => const TrackSheetLoading(),
    };
    // 레퍼런스 8-2·8-4: 배차 전(주문 확인·예약)은 시트를 거의 위까지.
    // 문의하기는 배정 전에도(초안 13-B ④, 사용자 2026-11-23) — 배달 중 화면과 같은 곳으로.
    return TrackMapLayout(
      map: TrackingMap(rider: null, home: home),
      sheet: sheet,
      sheetFraction: 0.85,
      onInquiry: () => context.push('/orders/$orderId/help'),
    );
  }
}

/// 배달 중(라이더가 내 상품을 받은 뒤 ~ 끝나기 전) — 서버가 고객에게 라이더 위치를 주는 단계(tracking 0.6.0).
bool _isDelivering(DeliveryStage? s) =>
    s == DeliveryStage.toCustomer || s == DeliveryStage.atCustomer;

class _TrackBody extends StatelessWidget {
  const _TrackBody({
    required this.eta,
    required this.deliveryId,
    required this.order,
    required this.polling,
    required this.onVisit,
    this.sheet = false,
    this.rider,
  });

  final DeliveryEtaView eta;
  final String deliveryId;

  /// 지도 아래 시트로 그린다(남은 시간을 크게, 라이더 위치 시각). 아니면 원래 목록.
  final bool sheet;

  /// 시트일 때 라이더 위치(없거나 오래됐으면 "확인하고 있어요").
  final RiderPosition? rider;

  /// null 이면 주문을 모르고 들어왔다(알림 등). 배송 정보만으로 그린다.
  final AsyncValue<OrderDetail>? order;
  final bool polling;
  final Future<void> Function(String location) onVisit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final e = eta;
    final o = order?.value;
    final shipment = o?.shipments
        .where((s) => s.deliveryId == deliveryId)
        .firstOrNull;
    final progress = trackProgressOf(
      order: o?.status,
      shipment: shipment?.state,
      stage: e.stage,
    );
    final scheduled = o?.deliveryMode == 'SCHEDULED';
    final window = o?.window ?? e.window;
    final etaLine = switch (e.status) {
      EtaStatus.available when e.etaAt != null => l10n.etaAt(
        formatSeoulTime(e.etaAt!),
      ),
      EtaStatus.locating => l10n.etaLocating,
      EtaStatus.pending => l10n.etaPending,
      EtaStatus.finalized => l10n.stDone,
      _ => l10n.etaPending,
    };
    final remainingMin =
        e.status == EtaStatus.available && e.remainingSeconds != null
        ? (e.remainingSeconds! / 60).ceil()
        : null;
    // 배송 단계 문구(주문상세·홈 현황판과 같다, 사용자 2026-11-21). 주문을 모르고 들어왔으면(알림 등) 라이더 단계 문장.
    final phase = o == null
        ? null
        : deliveryPhaseText(
            l10n,
            status: o.status,
            deliveryMode: o.deliveryMode,
            stage: e.stage,
            reservedTitle: switch (window) {
              final w? => reservedHeadline(l10n, w),
              null => null,
            },
          );
    // 예약 확정(준비 전)이면 머리 제목이 예약 시간이다(레퍼런스 8-4) — 아래 예약 칸을 따로 두지 않는다.
    final reservedHead =
        sheet &&
        scheduled &&
        window != null &&
        o?.status == OrderStatus.confirmed &&
        remainingMin == null;
    final delayed =
        (e.delayedBySeconds ?? 0) > 0 && e.status == EtaStatus.available;
    // 초안 13-B·E(사용자 2026-11-23): 머리 아래 작은 줄을 쌓지 않고 정보 칸 최대 2개.
    // 우선순위: 늦어짐(분홍) → 실시간 끊김(+기준 시각) → 라이더 위치 시각 / 확인 중 → 기준 시각 → 예약 변경 안내.
    final infos = <Widget>[
      if (delayed)
        TrackInfo(
          key: const ValueKey('eta-delayed'),
          text: l10n.etaDelayed((e.delayedBySeconds! / 60).ceil()),
          tone: TrackInfoTone.warn,
        ),
      if (polling)
        TrackInfo(
          key: const ValueKey('track-live-fallback'),
          text: [
            l10n.trackLiveFallback,
            if (e.asOf case final t?) l10n.asOfTime(formatSeoulTime(t)),
          ].join(' · '),
          tone: TrackInfoTone.muted,
        )
      // 위치가 없거나(서버가 주지 않음) 받은 지 60초가 넘었으면 지어내지 않고 확인 중이라고만.
      else if (rider case final r? when !r.stale && r.recordedAt != null)
        TrackInfo(
          key: const ValueKey('track-rider-at'),
          text: l10n.trackRiderLocationAt(formatSeoulTime(r.recordedAt!)),
        )
      else if (_isDelivering(e.stage))
        TrackInfo(
          key: const ValueKey('track-rider-locating'),
          text: l10n.trackRiderLocating,
          tone: TrackInfoTone.muted,
        )
      else if (e.asOf case final t?)
        TrackInfo(
          text: e.freshness == Freshness.current
              ? l10n.asOfTime(formatSeoulTime(t))
              : l10n.sourceStale(formatSeoulTime(t)),
          tone: TrackInfoTone.muted,
        ),
      // 예약 확정(준비 전): 설명 줄 대신 변경 안내를 정보 칸으로(초안 13-B-4).
      if (reservedHead && phase?.subtitle != null)
        TrackInfo(text: phase!.subtitle!, tone: TrackInfoTone.muted)
      else if (scheduled &&
          window != null &&
          o != null &&
          canRequestTimeChange(o))
        TrackInfo(text: l10n.trackRescheduleNote, tone: TrackInfoTone.muted),
    ].take(2).toList();
    final modeName = deliveryModeText(l10n, o?.deliveryMode);
    final children = <Widget>[
      // 시트 머리(레퍼런스 8-2·8-4·8-5): 배달 방식 → 큰 제목("N분 남음 오후 6:50" 또는 단계 제목) → 한 줄 설명.
      if (sheet) ...[
        TrackSheetHead(
          // 묶음배달 도착 구간은 시트 맨 아래 줄 대신 방식 옆에(초안 13-B).
          mode: !scheduled && window != null && modeName != null
              ? '$modeName · ${windowText(window)}'
              : modeName,
          headline: remainingMin != null
              ? l10n.trackRemainingShort(remainingMin)
              : phase?.title ?? etaLine,
          headlineKey: remainingMin != null
              ? 'track-sheet-remaining'
              : reservedHead
              ? 'track-reserved'
              : phase != null
              ? 'track-phase'
              : 'eta-line',
          // 초안 13 "오후 6:50 도착"(사용자 2026-11-23 추천대로 — 무슨 시각인지 분명하게).
          time: remainingMin != null && e.etaAt != null
              ? l10n.trackArriveAtTime(formatSeoulTime(e.etaAt!))
              : null,
          subtitle: reservedHead
              ? null
              : phase?.subtitle ?? stageText(l10n, e.stage),
          receipt: phase != null && !_isDelivering(e.stage),
          calendar: reservedHead,
        ),
        ...infos,
      ],
      // 예약배달: 서버가 준 도착 구간을 크게. 변경·취소는 진입만, 가능 여부는 서버가 판정한다.
      if (scheduled && window != null && !reservedHead) ...[
        Text(
          l10n.trackReservedWindow(windowText(window)),
          key: const ValueKey('track-reserved'),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (!sheet && o != null && canRequestTimeChange(o))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.trackRescheduleNote,
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
      if (o != null && (canRequestTimeChange(o) || canRequestCancel(o)))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 8,
            children: [
              // 회색 알약(초안 13-B, 레퍼런스 8-2 "주문취소").
              if (canRequestCancel(o))
                TextButton(
                  key: const ValueKey('track-cancel'),
                  style: trackPillButtonStyle(theme),
                  onPressed: () => onVisit('/orders/${o.orderId}/cancel'),
                  child: Text(l10n.cancelTitle),
                ),
              if (canRequestTimeChange(o))
                TextButton(
                  key: const ValueKey('track-reschedule'),
                  style: trackPillButtonStyle(theme),
                  onPressed: () => onVisit('/orders/${o.orderId}/reschedule'),
                  child: Text(l10n.rescheduleTitle),
                ),
            ],
          ),
        ),
      if (order case AsyncError() when o == null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            l10n.trackOrderFailed,
            key: const ValueKey('track-order-failed'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      const SizedBox(height: 16),
      _TrackSteps(progress: progress),
      if (sheet && o != null) OrderSheetDetails(order: o),
      if (progress.halted)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            switch ((shipment?.state, o?.status)) {
              (ShipmentState.failed || ShipmentState.cancelled, _) =>
                shipmentStateText(l10n, shipment!.state),
              (_, final s?) => orderStatusText(l10n, s),
              _ => l10n.osUnknown,
            },
            key: const ValueKey('track-halted'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      // 주문 일부만 다음 단계에 갔다(PARTIALLY_*). 단계는 앞당기지 않고 그대로 알린다.
      if (progress.partial && o != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            orderStatusText(l10n, o.status),
            key: const ValueKey('track-partial'),
          ),
        ),
      const SizedBox(height: 24),
      if (!sheet) ...[
        Text(
          stageText(l10n, e.stage),
          key: const ValueKey('eta-stage'),
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          etaLine,
          key: const ValueKey('eta-line'),
          style: theme.textTheme.titleMedium,
        ),
        if (remainingMin != null) Text(l10n.etaRemaining(remainingMin)),
        // 배달 중인데 서버가 아직 라이더 위치를 주지 않음 — 위치를 지어내지 않고 확인 중이라고만.
        if (_isDelivering(e.stage))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.trackRiderLocating,
              key: const ValueKey('track-rider-locating'),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
      // 아래 줄들은 목록 모양([sheet] 아님)에서만. 시트에서는 머리 아래 정보 칸으로 옮겼다(초안 13-B ③).
      if (!sheet && !scheduled && window != null) Text(windowText(window)),
      if (!sheet && delayed)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TrackInfo(
            key: const ValueKey('eta-delayed'),
            text: l10n.etaDelayed((e.delayedBySeconds! / 60).ceil()),
            tone: TrackInfoTone.warn,
          ),
        ),
      if (!sheet && polling)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            l10n.trackLiveFallback,
            key: const ValueKey('track-live-fallback'),
            style: theme.textTheme.bodySmall,
          ),
        ),
      if (!sheet)
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
    ];
    if (sheet) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
    }
    return ListView(padding: const EdgeInsets.all(24), children: children);
  }
}

/// 4단계 진행 표시. 서버 상태로 정한 [TrackProgress] 만 그린다(멈춤이면 어느 단계도 진행으로 칠하지 않는다).
class _TrackSteps extends StatelessWidget {
  const _TrackSteps({required this.progress});

  final TrackProgress progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final current = progress.halted ? null : progress.step;
    final labels = {
      TrackStep.confirmed: l10n.trackStepConfirmed,
      TrackStep.preparing: l10n.trackStepPreparing,
      TrackStep.delivering: l10n.trackStepDelivering,
      TrackStep.delivered: l10n.trackStepDelivered,
    };
    return Column(
      key: const ValueKey('track-steps'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 레퍼런스 8-5: 점을 선으로 잇고, 지난 단계는 채운 점, 지금 단계는 오토바이, 남은 단계는 회색 점.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final step in TrackStep.values)
              Expanded(
                child: Column(
                  children: [
                    SizedBox(
                      height: 26,
                      child: Row(
                        children: [
                          Expanded(
                            child: step.index == 0
                                ? const SizedBox()
                                : _StepLine(
                                    on:
                                        current != null &&
                                        step.index <= current.index,
                                  ),
                          ),
                          _StepDot(
                            done: current != null && step.index < current.index,
                            current: step == current,
                          ),
                          Expanded(
                            child: step.index == TrackStep.values.length - 1
                                ? const SizedBox()
                                : _StepLine(
                                    on:
                                        current != null &&
                                        step.index < current.index,
                                  ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      labels[step]!,
                      key: ValueKey(
                        step == current
                            ? 'track-step-current-${step.name}'
                            : 'track-step-${step.name}',
                      ),
                      textAlign: TextAlign.center,
                      // 초안 13-B: 단계 이름 13, 지금 단계는 진한 색 + 굵게.
                      style: step == current
                          ? theme.textTheme.titleSmall?.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            )
                          : theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 13,
                              color: theme.colorScheme.outline,
                            ),
                    ),
                    // 레퍼런스 8-5: 배달 중이면 지금 단계 아래 말풍선 "내 주소로 오는 중"
                    // 말풍선은 단계 칸(폭 1/4)보다 넓을 수 있어 칸 밖으로 넘치게 둔다(가운데 맞춤 — 초안 13-B).
                    if (step == current && step == TrackStep.delivering)
                      SizedBox(
                        height: 26,
                        child: OverflowBox(
                          maxWidth: 200,
                          child: Container(
                            key: const ValueKey('track-step-bubble'),
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              l10n.trackStepComingBubble,
                              maxLines: 1,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11.5,
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
        if (current == null && !progress.halted)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.trackStepChecking,
              key: const ValueKey('track-step-unknown'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 3,
      decoration: BoxDecoration(
        color: on ? scheme.primary : scheme.outlineVariant,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.done, required this.current});

  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (current) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: ScooterGlyph(size: 26, color: scheme.primary),
      );
    }
    return Container(
      width: 13,
      height: 13,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? scheme.primary : scheme.outlineVariant,
      ),
    );
  }
}

/// 주문 `deliveryMode`(SINGLE·BUNDLED·SCHEDULED) → 화면 이름. 모르는 값·없음이면 null(보이지 않는다).
String? deliveryModeText(AppLocalizations l10n, String? mode) => switch (mode) {
  'SINGLE' => l10n.modeSingle,
  'BUNDLED' => l10n.modeBundled,
  'SCHEDULED' => l10n.modeScheduled,
  _ => null,
};

/// 배송 현황 시트 머리(레퍼런스 8-5): 손잡이, 배달 방식, 큰 제목(+시각), 단계 문장, 오른쪽 배달 그림.
class TrackSheetHead extends StatelessWidget {
  const TrackSheetHead({
    super.key,
    required this.headline,
    required this.headlineKey,
    this.mode,
    this.time,
    this.subtitle,
    this.receipt = false,
    this.calendar = false,
  });

  /// 배차 전(주문 확인·예약)이면 오른쪽 그림이 영수증(레퍼런스 8-4), 배달 중이면 오토바이(8-5).
  final bool receipt;

  /// 예약 확정(준비 전)이면 오른쪽 그림이 달력(초안 13-B-4, 사용자 2026-11-23). [receipt] 보다 먼저.
  final bool calendar;

  final String? mode;
  final String headline;
  final String headlineKey;
  final String? time;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (mode case final m?)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      // 초안 13-B(사용자 2026-11-23): 방식 13 회색 · 제목 23 굵게 · 시각 14 회색 · 설명 15 회색.
                      child: Text(
                        m,
                        key: const ValueKey('track-mode'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 6,
                    children: [
                      Text(
                        headline,
                        key: ValueKey(headlineKey),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                      if (time case final t?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            t,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (subtitle case final sub?)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        sub,
                        key: const ValueKey('eta-stage'),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontSize: 15,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // 오른쪽 배달 그림(직접 그린 선 그림 — 레퍼런스 캐릭터 그림은 쓰지 않는다).
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: calendar || receipt
                  ? PmartLineIcon(
                      calendar
                          ? PmartLineIcons.calendar
                          : PmartLineIcons.receipt,
                      key: ValueKey(
                        calendar ? 'track-art-calendar' : 'track-art-receipt',
                      ),
                      size: 40,
                      strokeWidth: 1.6,
                      color: theme.colorScheme.primary,
                    )
                  : ScooterGlyph(size: 44, color: theme.colorScheme.primary),
            ),
          ],
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

/// 시트 머리 아래 정보 칸(초안 13-B·E): 둥근 회색 칸 + 점 + 한 줄. 늦어짐은 분홍 칸(tertiary).
/// 라이더 위치 시각·확인 중·실시간 끊김·기준 시각·배정 전 안내를 작은 줄로 쌓지 않고 이 칸에 담는다.
enum TrackInfoTone { normal, muted, warn }

class TrackInfo extends StatelessWidget {
  const TrackInfo({
    super.key,
    required this.text,
    this.tone = TrackInfoTone.normal,
  });

  final String text;
  final TrackInfoTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (bg, fg, dot) = switch (tone) {
      TrackInfoTone.warn => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        scheme.tertiary,
      ),
      TrackInfoTone.muted => (
        scheme.surfaceContainer,
        scheme.onSurfaceVariant,
        scheme.outline,
      ),
      TrackInfoTone.normal => (
        scheme.surfaceContainer,
        scheme.onSurfaceVariant,
        scheme.primary,
      ),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12.5,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 시트 안 작은 버튼(초안 13-B): 회색 알약(레퍼런스 8-2 "주문취소" 모양).
ButtonStyle trackPillButtonStyle(ThemeData theme) => TextButton.styleFrom(
  backgroundColor: theme.colorScheme.surfaceContainerHigh,
  foregroundColor: theme.colorScheme.onSurface,
  shape: const StadiumBorder(),
  visualDensity: VisualDensity.compact,
  padding: const EdgeInsets.symmetric(horizontal: 14),
  // 글꼴은 테마에서(따로 TextStyle 을 만들면 앱 글꼴이 빠진다).
  textStyle: theme.textTheme.labelLarge?.copyWith(
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
  ),
);

/// 시트 불러오는 중(초안 13-D): 원형 진행 표시 대신 머리·정보 칸·단계 자리의 회색 자리 표시.
class TrackSheetLoading extends StatelessWidget {
  const TrackSheetLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: const ValueKey('track-sheet-loading'),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: PmartShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PmartBone(width: 60, height: 13),
                      SizedBox(height: 10),
                      PmartBone(width: 170, height: 24),
                      SizedBox(height: 10),
                      PmartBone(width: 220, height: 15),
                    ],
                  ),
                ),
                SizedBox(width: 12),
                PmartBone(height: 72, circle: true),
              ],
            ),
            const SizedBox(height: 14),
            const PmartBone(width: double.infinity, height: 32, radius: 8),
            const SizedBox(height: 24),
            Row(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(width: 18),
                  const Expanded(
                    child: PmartBone(width: double.infinity, height: 6),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 시트 아래(레퍼런스 8-5·예약 화면): "배달정보 자세히"(배달주소·요청사항), 주문한 센터·"상세내역", 주문 상품, 총 결제금액.
/// 모두 주문 응답의 서버 값. 센터 이름은 `mfcName`(order 0.15.0), 없으면 브랜드만.
class OrderSheetDetails extends StatefulWidget {
  const OrderSheetDetails({super.key, required this.order});

  final OrderDetail order;

  @override
  State<OrderSheetDetails> createState() => _OrderSheetDetailsState();
}

class _OrderSheetDetailsState extends State<OrderSheetDetails> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final o = widget.order;
    final divider = Divider(
      height: 28,
      color: theme.colorScheme.outlineVariant,
    );
    final small = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 15,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        // "배달정보 자세히 ∨" — 회색 둥근 칸, 누르면 배달주소·요청사항.
        Material(
          color: theme.colorScheme.surfaceContainerHigh,
          shape: const StadiumBorder(),
          child: InkWell(
            key: const ValueKey('track-delivery-info'),
            customBorder: const StadiumBorder(),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    l10n.trackDeliveryInfo,
                    style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15),
                  ),
                  const SizedBox(width: 4),
                  PmartLineIcon(
                    _open
                        ? PmartLineIcons.chevronUp
                        : PmartLineIcons.chevronDown,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_open)
          Padding(
            key: const ValueKey('track-delivery-info-body'),
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.trackAddress,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                ShippingAddressView(address: o.shippingAddress),
                const SizedBox(height: 14),
                Text(
                  l10n.trackRequest,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  o.deliveryNote?.trim().isNotEmpty ?? false
                      ? o.deliveryNote!
                      : l10n.trackRequestNone,
                  key: const ValueKey('track-request'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 28),
        // 주문한 센터 + 상세내역
        Row(
          children: [
            Expanded(
              child: Text(
                // 센터 이름(BR-62) — 없으면 브랜드만(ID 를 보이지 않는다).
                switch (o.mfcName) {
                  final n? => '${l10n.trackStoreName} $n',
                  null => l10n.trackStoreName,
                },
                key: const ValueKey('track-store'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            OutlinedButton(
              key: const ValueKey('track-order-detail'),
              style: OutlinedButton.styleFrom(
                shape: const StadiumBorder(),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: () => context.push('/orders/${o.orderId}'),
              child: Text(l10n.trackOrderDetail),
            ),
          ],
        ),
        divider,
        for (final l in o.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: small),
                Expanded(
                  child: Text(
                    '${l.title} ${l10n.cartLineQuantity(l.originalQty ?? 0)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: small,
                  ),
                ),
              ],
            ),
          ),
        divider,
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.trackTotalAmount,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              switch (o.quote?.totalAmount) {
                final int a => formatKrw(a),
                null => l10n.amountUnavailable,
              },
              key: const ValueKey('track-total'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 예약 주문 제목 — 레퍼런스 9-1 3-2·8-4 "10월 11일 (일)" 줄바꿈 "오전 8:00~오전 9:00 예약".
String reservedHeadline(AppLocalizations l10n, ArrivalWindow w) =>
    l10n.orderHeadlineReserved(
      DateFormat('M월 d일 (E)', 'ko').format(DateTime.parse(w.date)),
      windowText(w),
    );

/// 다시 담기 ⊕ 모양(레퍼런스 9-1 3-3·9-2 — 검은 1.5dp 테두리, 흰 바탕). 담은 뒤(누를 수 없음)는 옅게.
ButtonStyle reorderCircleStyle(ColorScheme scheme) => IconButton.styleFrom(
  foregroundColor: scheme.onSurface,
  backgroundColor: scheme.surface,
  side: BorderSide(color: scheme.onSurface, width: 1.5),
  disabledForegroundColor: scheme.outline,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

/// 다시 담기 ⊕. 보이는 원은 레퍼런스 크기([size] — 주문내역 29dp·주문상세 24dp)지만 손가락 칸은 40dp 다.
/// 원의 오른쪽 끝은 줄 끝에 그대로 맞춘다(넓힌 칸은 왼쪽·위아래로만).
Widget reorderCircle({
  required BuildContext context,
  Key? key,
  required double size,
  required String tooltip,
  required VoidCallback? onPressed,
  required Widget icon,
  bool lightOutline = false,
}) {
  const hit = 40.0;
  final scheme = Theme.of(context).colorScheme;
  final pad = (hit - size) / 2;
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onPressed,
    child: Padding(
      padding: EdgeInsets.fromLTRB(pad * 2, pad, 0, pad),
      child: IconButton.outlined(
        key: key,
        tooltip: tooltip,
        // 레퍼런스 9-1 2 주문내역은 원 둘레가 옅은 회색(+ 는 검정), 주문상세 3-3 은 검정.
        style: lightOutline
            ? reorderCircleStyle(scheme).copyWith(
                side: WidgetStatePropertyAll(
                  BorderSide(color: scheme.outlineVariant, width: 1.5),
                ),
              )
            : reorderCircleStyle(scheme),
        constraints: BoxConstraints.tightFor(width: size, height: size),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: icon,
      ),
    ),
  );
}

/// 주문상세 "배달 정보"(레퍼런스 9-1 3-1, 사용자 2026-11-21 "박스 안도 띄워놔야지"): 항목마다 제목 줄 + 회색 값 줄,
/// 항목 사이는 선과 위아래 여백. 배송지는 주문 당시 사본(BR-37) — 없으면 "배송지 정보 없음"(현재 주소로 대신하지 않는다).
class _DeliveryInfoBox extends StatelessWidget {
  const _DeliveryInfoBox({required this.order});

  final OrderDetail order;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final a = order.shippingAddress;
    Widget block(String label, List<Widget> values, {Key? key}) => Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16)),
          const SizedBox(height: 6),
          DefaultTextStyle.merge(
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 15,
              height: 1.45,
              color: scheme.onSurfaceVariant,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: values,
            ),
          ),
        ],
      ),
    );
    final entrance = a == null
        ? ''
        : [
            if (a.entranceMethod case final m?) entranceMethodText(l10n, m),
            ?a.entranceNote,
          ].join(' · ');
    final blocks = <Widget>[
      if (a == null)
        block(l10n.orderInfoAddress, [
          Text(
            l10n.shippingAddressUnavailable,
            key: const ValueKey('shipping-address-none'),
          ),
        ])
      else ...[
        block(l10n.orderInfoAddress, [
          Text(
            '${a.roadAddress} ${a.detailAddress}'.trim(),
            key: const ValueKey('shipping-address'),
          ),
        ]),
        // 받는 분·연락처는 없을 수 있다(BR-60) — 있는 것만.
        if ([?a.receiverName, ?a.receiverPhone] case final parts
            when parts.isNotEmpty)
          block(l10n.orderInfoReceiver, [Text(parts.join(' · '))]),
        if (entrance.isNotEmpty)
          block(l10n.orderInfoEntrance, [Text(entrance)]),
      ],
      if (order.deliveryNote case final n?)
        block(l10n.orderInfoRider, [
          Text(n),
        ], key: const ValueKey('order-note')),
      if (order.outOfStock case final p?)
        block(l10n.orderInfoOos, [
          Text(switch (p) {
            OutOfStockPreference.cancelOutOfStockOnly => l10n.oosOnly,
            OutOfStockPreference.cancelAll => l10n.oosAll,
          }),
        ], key: const ValueKey('order-oos')),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, b) in blocks.indexed) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.6),
              ),
            b,
          ],
        ],
      ),
    );
  }
}
