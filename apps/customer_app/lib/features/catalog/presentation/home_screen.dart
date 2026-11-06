import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers.dart';
import '../../../shared/ui_state_of.dart';
import '../../address/presentation/address_controller.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../checkout/domain/checkout.dart';
import '../../checkout/presentation/delivery_select_screen.dart'
    show modeLabel, optionSubtitle, windowText;
import '../../orders/domain/orders.dart';
import '../../orders/presentation/orders_providers.dart' show orderStatusText;
import '../../payment/presentation/payment_controller.dart';
import '../domain/catalog.dart';
import 'catalog_providers.dart';
import 'home_providers.dart';
import 'widgets/product_tile_card.dart';

/// SCR-HOME-001. 영역별 부분 실패는 그 영역만 다시 불러온다.
/// 위에서부터 결과 불명 결제·진행 중 주문·배송 방식 요약, 고정 탭(홈·랭킹·신상품), 탭 본문 순서다.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  HomeTab _tab = HomeTab.home;

  GoRouter? _router;
  String? _lastPath;

  /// 마지막 홈 조회가 끝난 시각(성공·실패 모두). null 이면 아직 첫 조회 중이다.
  DateTime? _loadedAt;

  @override
  void initState() {
    super.initState();
    ref.listenManual(homeProvider, (_, next) {
      if (next.isLoading) return;
      _loadedAt = ref.read(homeClockProvider)();
    }, fireImmediately: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.maybeOf(context);
    if (router == _router) return;
    _router?.routerDelegate.removeListener(_onRouteChanged);
    _router = router;
    _lastPath = _path;
    router?.routerDelegate.addListener(_onRouteChanged);
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onRouteChanged);
    super.dispose();
  }

  /// 맨 위 화면의 위치. `push` 로 올린 화면(상품 상세 등)은 `uri` 가 그대로라 맨 위 경로로 본다.
  String? get _path =>
      _router?.routerDelegate.currentConfiguration.lastOrNull?.matchedLocation;

  /// 홈이 다시 보이면(상세에서 뒤로·다른 탭에서 홈으로) 오래된 홈을 다시 읽는다.
  void _onRouteChanged() {
    final path = _path;
    final was = _lastPath;
    _lastPath = path;
    if (path != '/' || was == '/') return;
    // 내비게이션 알림 안에서 provider 를 바꾸지 않게 한 박자 뒤에 한다
    scheduleMicrotask(() {
      if (mounted) _refreshIfStale();
    });
  }

  void _refreshIfStale() {
    final at = _loadedAt;
    if (at == null) return; // 첫 조회 중
    if (ref.read(homeClockProvider)().difference(at) < homeStaleAfter) return;
    _refresh().ignore(); // 실패는 홈 화면이 오류로 보인다
  }

  Future<HomeView> _refresh() {
    ref
      ..invalidate(homeDeliveryOptionsProvider)
      ..invalidate(homeInProgressOrderProvider)
      // 다시 불러온 영역도 새 홈 응답으로 바꾼다(남겨 두면 그 영역만 옛 가격이다)
      ..invalidate(sectionRetryProvider);
    if (_tab != HomeTab.home) ref.invalidate(homeTabProvider(_tab));
    return ref.refresh(homeProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mock = ref.watch(envProvider) == PmartEnv.mock;
    // 새로 고침(invalidate·refresh) 중에는 Riverpod 가 이전 홈을 AsyncData 로 둔다 — 자리 표시로 깜빡이지 않는다.
    // 쇼핑 주소가 바뀐 재조회는 AsyncLoading 이라 자리 표시를 보인다(다른 센터 상품을 남기지 않는다).
    final state = uiStateOf(
      ref.watch(homeProvider),
      isEmpty: (h) => h.sections.isEmpty && h.banners.isEmpty,
    );
    return Scaffold(
      appBar: AppBar(
        title: const _AddressChip(),
        actions: [
          IconButton(
            key: const ValueKey('home-notifications'),
            icon: const Icon(Icons.notifications_none),
            tooltip: l10n.noticeTitle,
            onPressed: () => context.push('/notifications'),
          ),
          if (mock)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(label: Text(l10n.mockModeBadge)),
            ),
        ],
      ),
      // 첫 로딩은 가운데 원형 표시 대신 자리 표시 블록을 그린다(§17).
      body: state is UiLoading<HomeView>
          ? const HomeSkeleton()
          : UiStateView<HomeView>(
              state: state,
              onRetry: () => ref.invalidate(homeProvider),
              ready: (context, home) {
                final tab = home.tabs.contains(_tab) ? _tab : HomeTab.home;
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    children: [
                      const _PendingPaymentBanner(),
                      const _InProgressOrderCard(),
                      const _DeliverySummaryCard(),
                      if (home.tabs.length > 1)
                        _HomeTabs(
                          tabs: home.tabs,
                          selected: tab,
                          onSelected: (t) => setState(() => _tab = t),
                        ),
                      if (tab == HomeTab.home) ...[
                        for (final b in home.banners) _BannerCard(b),
                        for (final s in home.sections)
                          _SectionView(
                            key: ValueKey('section-${s.sectionId}'),
                            section: s,
                            layoutVersion: home.layoutVersion,
                          ),
                      ] else
                        _TabBody(
                          key: ValueKey('home-tab-body-${tab.name}'),
                          tab: tab,
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

String homeTabLabel(AppLocalizations l10n, HomeTab t) => switch (t) {
  HomeTab.home => l10n.tabHome,
  HomeTab.ranking => l10n.tabRanking,
  HomeTab.isNew => l10n.tabNew,
};

/// 서버가 준 고정 탭(`HomeLayout.tabs`). 할인 탭(DEAL)은 1차 제외라 계약에 없다.
class _HomeTabs extends StatelessWidget {
  const _HomeTabs({
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });

  final List<HomeTab> tabs;
  final HomeTab selected;
  final ValueChanged<HomeTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Wrap(
        spacing: 8,
        children: [
          for (final t in tabs)
            ChoiceChip(
              key: ValueKey('home-tab-${t.name}'),
              label: Text(homeTabLabel(l10n, t)),
              selected: t == selected,
              onSelected: (_) => onSelected(t),
            ),
        ],
      ),
    );
  }
}

/// 랭킹·신상품 탭 본문. 실패는 이 탭만 오류로 보인다(빈 탭으로 바꾸지 않는다).
class _TabBody extends ConsumerWidget {
  const _TabBody({super.key, required this.tab});

  final HomeTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final provider = homeTabProvider(tab);
    return switch (ref.watch(provider)) {
      AsyncData(:final value) when value.sections.isEmpty => Padding(
        key: const ValueKey('home-tab-empty'),
        padding: const EdgeInsets.all(16),
        child: Text(l10n.sectionEmpty),
      ),
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in value.sections)
            _SectionView(
              key: ValueKey('section-${s.sectionId}'),
              section: s,
              layoutVersion: value.layoutVersion,
              vertical: true,
            ),
        ],
      ),
      AsyncError() => _InlineFailure(
        key: const ValueKey('home-tab-failed'),
        text: l10n.sectionUnavailable,
        onRetry: () => ref.invalidate(provider),
      ),
      _ => const _SkeletonRail(),
    };
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard(this.banner);

  final HomeBanner banner;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: SizedBox(
        height: 96,
        child: Center(
          child: Text(
            banner.altText ?? '',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
    ),
  );
}

/// 진열 영역 하나. 홈 탭은 가로 진열, 랭킹·신상품 탭은 세로 목록([vertical]).
/// 배치 지정 필드가 계약에 없어 배치는 앱이 정한다(순위·NEW 배지는 서버 값).
class _SectionView extends ConsumerWidget {
  const _SectionView({
    super.key,
    required this.section,
    required this.layoutVersion,
    this.vertical = false,
  });

  final HomeSection section;
  final int layoutVersion;
  final bool vertical;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final retry = ref.watch(sectionRetryProvider(section.sectionId));
    final shown = switch (retry) {
      AsyncData(:final value) => value,
      _ => section,
    };
    final Widget body;
    if (shown.available) {
      body = shown.items.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.sectionEmpty),
            )
          : vertical
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final tile in shown.items)
                    ProductTileCard(
                      tile: tile,
                      onTap: () => context.push('/products/${tile.productId}'),
                    ),
                ],
              ),
            )
          : SizedBox(
              height: ProductTileCard.railHeight(context),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: shown.items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 4),
                itemBuilder: (context, i) => SizedBox(
                  width: 280,
                  child: ProductTileCard(
                    tile: shown.items[i],
                    onTap: () =>
                        context.push('/products/${shown.items[i].productId}'),
                  ),
                ),
              ),
            );
    } else {
      final loading = retry?.isLoading ?? false;
      body = Padding(
        key: ValueKey('section-unavailable-${section.sectionId}'),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            const Icon(Icons.error_outline),
            const SizedBox(width: 8),
            Expanded(child: Text(l10n.sectionUnavailable)),
            TextButton(
              onPressed: loading
                  ? null
                  : () => ref
                        .read(sectionRetryProvider(section.sectionId).notifier)
                        .retry(section, layoutVersion),
              child: loading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.sectionRetry),
            ),
          ],
        ),
      );
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(section.title, style: theme.textTheme.titleLarge),
                ),
                if (shown.hasViewAll)
                  TextButton(
                    key: ValueKey('section-view-all-${section.sectionId}'),
                    onPressed: () => context.push(
                      '/sections/${shown.sectionId}',
                      extra: SectionRef(shown, layoutVersion),
                    ),
                    child: Text(l10n.sectionViewAll),
                  ),
              ],
            ),
          ),
          if (section.subtitle case final sub? when sub.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(sub, style: theme.textTheme.bodySmall),
            ),
          body,
        ],
      ),
    );
  }
}

/// 영역 하나의 조회 실패 한 줄 + 다시 확인. 실패를 "없음"으로 보이지 않는다.
class _InlineFailure extends StatelessWidget {
  const _InlineFailure({super.key, required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
          TextButton(onPressed: onRetry, child: Text(l10n.checkoutCheckAgain)),
        ],
      ),
    );
  }
}

/// 진행 중 주문(회원만). 상태·도착 예상은 서버 값만 보인다.
/// 조회 실패는 "주문 없음"이 아니라 실패 한 줄로 보인다. 비회원·진행 중 주문 없음은 그리지 않는다.
class _InProgressOrderCard extends ConsumerWidget {
  const _InProgressOrderCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return switch (ref.watch(homeInProgressOrderProvider)) {
      AsyncData(value: final order?) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Card(
          key: const ValueKey('home-order-card'),
          child: ListTile(
            leading: const Icon(Icons.delivery_dining_outlined),
            title: Text(orderStatusText(l10n, order.status)),
            subtitle: homeOrderHasEta(order.status)
                ? _OrderEtaLine(orderId: order.orderId)
                : null,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/orders/${order.orderId}'),
          ),
        ),
      ),
      AsyncError() => _InlineFailure(
        key: const ValueKey('home-order-failed'),
        text: l10n.homeOrderFailed,
        onRetry: () => ref.invalidate(homeInProgressOrderProvider),
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// 도착 예상 한 줄. 산출됐을 때만 그린다(위치 확인 중·조회 실패는 시간을 만들지 않는다).
class _OrderEtaLine extends ConsumerWidget {
  const _OrderEtaLine({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final eta = ref.watch(homeOrderEtaProvider(orderId)).value;
    final text = switch (eta) {
      DeliveryEtaView(
        status: EtaStatus.available,
        :final int remainingSeconds,
      ) =>
        l10n.etaRemaining((remainingSeconds / 60).ceil()),
      DeliveryEtaView(status: EtaStatus.available, :final DateTime etaAt) =>
        l10n.etaAt(formatSeoulTime(etaAt)),
      _ => null,
    };
    if (text == null) return const SizedBox.shrink();
    return Text(text, key: const ValueKey('home-order-eta'));
  }
}

/// 배송 방식 요약 + 심야 예약 안내(`GET /delivery-options`). 값은 서버 판정 그대로다.
/// 센터가 없으면 그리지 않고, 조회 실패는 실패 한 줄로 보인다("무료"·0원으로 채우지 않는다).
class _DeliverySummaryCard extends ConsumerWidget {
  const _DeliverySummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return switch (ref.watch(homeDeliveryOptionsProvider)) {
      AsyncData(value: final options?) when options.isNotEmpty =>
        _DeliverySummary(options: options),
      AsyncError() => _InlineFailure(
        key: const ValueKey('home-delivery-failed'),
        text: l10n.homeDeliveryFailed,
        onRetry: () => ref.invalidate(homeDeliveryOptionsProvider),
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _DeliverySummary extends StatelessWidget {
  const _DeliverySummary({required this.options});

  final List<DeliveryOption> options;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final night = options.any(
      (o) => !o.available && o.reason == UnavailableReason.nightTime,
    );
    final earliest = options
        .where((o) => o.mode == DeliveryMode.scheduled)
        .firstOrNull
        ?.earliestSlot;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        key: const ValueKey('home-delivery-card'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (night)
                Padding(
                  key: const ValueKey('home-night-notice'),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.nightlight_outlined, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.homeNightNotice,
                              style: theme.textTheme.titleSmall,
                            ),
                            if (earliest != null)
                              Text(
                                l10n.optionEarliestSlot(windowText(earliest)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              for (final o in options)
                // 심야로 막힌 방식은 위 안내가 대신한다.
                if (!(night && o.reason == UnavailableReason.nightTime))
                  Padding(
                    key: ValueKey('home-delivery-${o.mode.name}'),
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 88,
                          child: Text(
                            modeLabel(l10n, o.mode),
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                        Expanded(child: Text(_optionSummary(l10n, o))),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 방식 한 줄 요약. 불가면 사유, 가능하면 예상시간·기본 배달팁·가장 빠른 시간(서버 값만).
/// 상품액 없이 물었으므로 팁은 기본값만 있다 — 무료 여부는 장바구니·주문서에서 서버가 판정한다.
String _optionSummary(AppLocalizations l10n, DeliveryOption o) {
  if (!o.available) return optionSubtitle(l10n, o);
  final eta = o.eta;
  return [
    if (eta != null && !eta.notSet)
      switch ((eta.minMinutes, eta.maxMinutes)) {
        (final int a, final int b) => l10n.optionEta(a, b),
        _ => null,
      },
    if (o.tip?.base case final int base) l10n.homeTipBase(formatKrw(base)),
    if (o.earliestSlot case final w?) l10n.optionEarliestSlot(windowText(w)),
  ].nonNulls.join(' · ');
}

/// 홈 첫 로딩 자리 표시. 회색 블록만 그린다(새 패키지 없이).
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('home-skeleton'),
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.symmetric(vertical: 12),
    children: const [
      _Block(height: 72),
      _Block(height: 32, width: 200),
      _Block(height: 96),
      _SkeletonRail(),
      _SkeletonRail(),
    ],
  );
}

class _SkeletonRail extends StatelessWidget {
  const _SkeletonRail();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(height: 12),
      _Block(height: 20, width: 160),
      Row(
        children: [
          Expanded(child: _Block(height: 120)),
          Expanded(child: _Block(height: 120)),
        ],
      ),
    ],
  );
}

class _Block extends StatelessWidget {
  const _Block({required this.height, this.width});

  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  );
}

/// 현재 쇼핑 주소. 누르면 주소 관리로 간다.
class _AddressChip extends ConsumerWidget {
  const _AddressChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final member = ref.watch(sessionProvider) is MemberSession;
    final book = ref.watch(addressBookProvider).value;
    // 비회원도 비회원 배송지를 고르면 그 주소를 보인다.
    final text = switch (book?.shoppingAddress) {
      final a? => a.label ?? a.roadAddress,
      null => member ? l10n.homeAddressNone : l10n.homeAddressGuest,
    };
    return InkWell(
      key: const ValueKey('home-address'),
      onTap: () => context.push('/addresses'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.place_outlined, size: 20),
          const SizedBox(width: 4),
          Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
          const Icon(Icons.expand_more),
        ],
      ),
    );
  }
}

/// 앱을 다시 켰을 때 결과를 모르는 결제가 있으면 알린다. 결론은 결제 화면이 서버에서 확인한다.
class _PendingPaymentBanner extends ConsumerWidget {
  const _PendingPaymentBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pending = ref.watch(pendingCheckoutsProvider).value ?? const [];
    if (pending.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        key: const ValueKey('pending-payment'),
        child: ListTile(
          leading: const Icon(Icons.payment),
          title: Text(l10n.pendingPaymentBanner),
          trailing: TextButton(
            onPressed: () => context.push('/payments/${pending.first}'),
            child: Text(l10n.pendingPaymentOpen),
          ),
        ),
      ),
    );
  }
}
