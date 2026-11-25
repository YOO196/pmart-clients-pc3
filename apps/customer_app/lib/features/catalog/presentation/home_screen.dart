import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/cart_icon_button.dart';
import '../../../shared/floating_cart_bar.dart';
import '../../../shared/notice.dart';
import '../../../shared/providers.dart';
import '../../../shared/ui_state_of.dart';
import '../../address/domain/address.dart' show Serviceability;
import '../../address/presentation/address_controller.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../checkout/domain/checkout.dart';
import '../../checkout/presentation/delivery_select_screen.dart'
    show modeLabel, optionSubtitle, windowText;
import '../../../shared/order_status.dart' show OrderStatus;
import '../../orders/domain/orders.dart';
import '../../payment/presentation/payment_controller.dart';
import '../domain/catalog.dart';
import 'catalog_providers.dart';
import 'home_popup.dart';
import 'home_providers.dart';
import 'category_browse_screen.dart' show openCategoryBrowse;
import '../../cart/presentation/cart_controller.dart'
    show cartControllerProvider;
import '../../coupons/domain/coupon.dart'
    show CouponCampaign, CouponDiscountType;
import '../../coupons/presentation/coupon_controller.dart'
    show couponCampaignsProvider;
import '../../coupons/presentation/coupon_screens.dart'
    show CouponCampaignSheet;
import 'widgets/category_art.dart';
import 'widgets/delivery_badges.dart';
import 'widgets/product_tile_card.dart';
import '../../../shared/network_image.dart';

/// SCR-HOME-001. 영역별 부분 실패는 그 영역만 다시 불러온다.
/// 위에서부터 결과 불명 결제·진행 중 주문·배송 방식 요약, 고정 탭(홈·랭킹·신상품), 탭 본문 순서다.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const _slideDuration = Duration(milliseconds: 260);

  /// 좌우로 이만큼(논리 픽셀) 끌어야 옆 탭으로 넘어간다 — 화면 폭 360 의 약 1/4.
  static const _swipeMinDistance = 90.0;

  HomeTab _tab = HomeTab.home;

  /// 고른 MD 탭(storefront 0.9.0 customTabs). null 이면 고정 탭([_tab]).
  String? _customTab;

  /// 기간이 끝나 지운 MD 탭(시각이 지났거나 서버가 404 TAB_NOT_FOUND).
  final _goneTabs = <String>{};

  /// 탭 바뀜 미끄럼 방향(사용자 2026-11-23 "탭 이동할 때 좌우 슬라이딩"): 오른쪽 탭으로 가면 1(오른쪽에서 들어옴),
  /// 왼쪽이면 -1. [_tabIndex] 는 마지막으로 그린 탭 순서.
  int _slideFrom = 0;
  int? _tabIndex;

  /// 좌우로 끈 거리(사용자 2026-11-23 "안 민감한 선에서 좌우 드래그로 탭 넘기기").
  double _swipeDx = 0;

  GoRouter? _router;
  String? _lastPath;

  /// 마지막 홈 조회가 끝난 시각(성공·실패 모두). null 이면 아직 첫 조회 중이다.
  DateTime? _loadedAt;

  /// 다른 화면이 연 탭 요청(카테고리 추천 타일 — 인기·신상·기획전, 사용자 2026-11-22).
  void _applyTabRequest() {
    final req = ref.read(homeTabRequestProvider.notifier).take();
    if (req == null) return;
    final home = ref.read(homeProvider).value;
    final now = ref.read(homeClockProvider)();
    setState(() {
      if (req.firstCustom) {
        // 지금 기간 안 첫 MD 탭, 없으면 홈.
        _customTab = home?.customTabs
            .where(
              (c) =>
                  !_goneTabs.contains(c.tabKey) &&
                  (c.endsAt == null || c.endsAt!.isAfter(now)),
            )
            .firstOrNull
            ?.tabKey;
        _tab = HomeTab.home;
      } else {
        _customTab = null;
        _tab = req.tab ?? HomeTab.home;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual(homeTabRequestProvider, (_, _) => _applyTabRequest());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyTabRequest();
    });
    ref.listenManual(homeProvider, (_, next) {
      if (next.isLoading) return;
      _loadedAt = ref.read(homeClockProvider)();
    }, fireImmediately: true);
    // 홈 팝업(storefront POPUP): 이번 실행에 한 번, 홈이 맨 위일 때만.
    ref.listenManual(homePopupProvider, (_, next) {
      final banners = next.value;
      if (banners == null || banners.isEmpty) return;
      if (ref.read(popupSessionProvider).shown) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _path != '/' || ref.read(popupSessionProvider).shown) {
          return;
        }
        showHomePopup(
          context,
          ref,
          banners,
          onOpen: (b) {
            final home = ref.read(homeProvider).value;
            if (home != null && mounted) openHomeBanner(context, b, home);
          },
        ).ignore();
      });
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
    if (_customTab case final k?) {
      ref.invalidate(customTabProvider(k));
    } else if (_tab != HomeTab.home) {
      ref.invalidate(homeTabProvider(_tab));
    }
    return ref.refresh(homeProvider.future);
  }

  /// MD 탭의 기간이 끝났다(시각이 지났거나 서버가 404 TAB_NOT_FOUND) — 탭을 지우고, 보던 탭이면 홈으로.
  void _dropCustomTab(String tabKey) {
    if (!mounted || _goneTabs.contains(tabKey)) return;
    setState(() {
      _goneTabs.add(tabKey);
      if (_customTab == tabKey) {
        _customTab = null;
        _tab = HomeTab.home;
      }
    });
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      // 사용자 2026-11-21 "주소가 왼쪽으로", 검색은 하단 탭과 겹쳐 뺌, 장바구니는 머리줄에만(하단 탭은 주문내역).
      // 홈 상단바 D안(사용자 2026-11-21 확정, 초안 `../고객앱 ui/01_홈_상단바` — 색은 앱 팔레트): 흰 바탕 + 아래 얇은 선,
      // 높이 58, 주소 위에 작은 배송 상태 줄(서버 배송 방식 값 — 없으면 줄 없음), 오른쪽 알림·장바구니.
      appBar: AppBar(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        // 홈 탭바 A안(사용자 2026-11-21 확정, 초안 `../고객앱 ui/05_홈_탭바`): 상단바와 탭 사이 선을 없앤다 — 선은 탭 줄 아래 한 줄만.
        // 내리면 위에 붙는 검색창이 옅은 그림자로 경계를 보인다.
        // 레퍼런스 2026-11-25 홈: 배너 위까지 245px/1080(탭 글자 아래 → 배너 32px).
        toolbarHeight: 52.3,
        centerTitle: false,
        titleSpacing: 16,
        title: const _AddressChip(),
        actions: [
          IconButton(
            key: const ValueKey('home-notifications'),
            icon: const PmartLineIcon(PmartLineIcons.bell, size: 26),
            tooltip: l10n.noticeTitle,
            onPressed: () => context.push('/notifications'),
          ),
          // 하단 탭에서 검색이 빠져(가운데 = 찜) 상단바에 돋보기(레퍼런스 홈: 홈·검색·장바구니).
          IconButton(
            key: const ValueKey('home-top-search'),
            icon: const PmartLineIcon(PmartLineIcons.search, size: 26),
            tooltip: l10n.navSearch,
            onPressed: () => context.push('/search'),
          ),
          const CartIconButton(key: ValueKey('home-top-cart'), size: 26),
          const SizedBox(width: 6),
          if (mock)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: PmartTag(l10n.mockModeBadge)),
            ),
        ],
      ), // 첫 로딩은 가운데 원형 표시 대신 자리 표시 블록을 그린다(§17).
      body: state is UiLoading<HomeView>
          ? const HomeSkeleton()
          : UiStateView<HomeView>(
              state: state,
              onRetry: () => ref.invalidate(homeProvider),
              ready: (context, home) {
                final now = ref.read(homeClockProvider)();
                final customs = [
                  for (final c in home.customTabs)
                    if (!_goneTabs.contains(c.tabKey) &&
                        (c.endsAt == null || c.endsAt!.isAfter(now)))
                      c,
                ];
                final custom = customs
                    .where((c) => c.tabKey == _customTab)
                    .firstOrNull;
                final tab = home.tabs.contains(_tab) ? _tab : HomeTab.home;
                final isHome = custom == null && tab == HomeTab.home;
                // 탭 순서: 고정 탭 → MD 탭. 바뀌었으면 미끄럼 방향을 정한다(첫 그림은 미끄럼 없음).
                final order = <Object>[
                  ...home.tabs,
                  ...customs.map((c) => c.tabKey),
                ];
                final index = order.indexOf(custom?.tabKey ?? tab);
                if (_tabIndex != null && index != _tabIndex) {
                  _slideFrom = index > _tabIndex! ? 1 : -1;
                }
                _tabIndex = index;
                final slideKey = custom?.tabKey ?? tab.name;
                void goTo(int i) {
                  if (i < 0 || i >= order.length) return;
                  final next = order[i];
                  setState(() {
                    if (next is HomeTab) {
                      _tab = next;
                      _customTab = null;
                    } else {
                      _customTab = next as String;
                    }
                  });
                }

                // 진행 중 주문은 화면 아래에 떠 있는 카드(레퍼런스 3-1 배달중). 목록 끝이 가리지 않게 아래 여백을 둔다.
                return Stack(
                  children: [
                    RawGestureDetector(
                      // 좌우로 길게 끌면 옆 탭으로. 안쪽 가로 목록(배너·상품 줄)은 그 목록이 먼저 받는다.
                      // 덜 민감하게: 가로로 판정하는 거리를 기본의 2배로(살짝 비스듬한 세로 스크롤은 세로로),
                      // 놓을 때 [_swipeMinDistance] 이상 끌었어야 넘긴다.
                      gestures: {
                        if (order.length > 1)
                          HorizontalDragGestureRecognizer:
                              GestureRecognizerFactoryWithHandlers<
                                HorizontalDragGestureRecognizer
                              >(
                                () =>
                                    HorizontalDragGestureRecognizer(
                                        debugOwner: this,
                                      )
                                      // 누른 자리부터 잰다(가로 판정 전 움직임도 거리에 넣는다).
                                      ..dragStartBehavior =
                                          DragStartBehavior.down
                                      ..gestureSettings =
                                          const DeviceGestureSettings(
                                            touchSlop: kTouchSlop * 2,
                                          ),
                                (HorizontalDragGestureRecognizer r) {
                                  r
                                    ..onStart = (DragStartDetails _) {
                                      _swipeDx = 0;
                                    }
                                    ..onUpdate = (DragUpdateDetails d) {
                                      _swipeDx += d.delta.dx;
                                    }
                                    ..onEnd = (DragEndDetails d) {
                                      final v = d.primaryVelocity ?? 0;
                                      if (_swipeDx.abs() < _swipeMinDistance ||
                                          (v != 0 && v.sign != _swipeDx.sign)) {
                                        return;
                                      }
                                      goTo(index + (_swipeDx < 0 ? 1 : -1));
                                    };
                                },
                              ),
                      },
                      child: RefreshIndicator(
                        onRefresh: _refresh,
                        // 사용자 요청(2026-11-20): 아래로 내려도 검색창은 위에 붙어 남는다(배너·배송 안내는 올라간다).
                        child: CustomScrollView(
                          key: const ValueKey('home-scroll'),
                          slivers: [
                            SliverList.list(
                              children: [
                                // 상단바가 흰 바탕이 되어(D안) 그 아래 회색 번짐을 뺐다.
                                const Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SizedBox(height: 4),
                                    _PendingPaymentBanner(),
                                    _InProgressOrderCard(),
                                  ],
                                ),
                                if (home.tabs.length > 1 || customs.isNotEmpty)
                                  _HomeTabs(
                                    key: const ValueKey('home-tabs'),
                                    tabs: home.tabs,
                                    selected: custom == null ? tab : null,
                                    onSelected: (t) => setState(() {
                                      _tab = t;
                                      _customTab = null;
                                    }),
                                    customTabs: customs,
                                    selectedCustom: custom?.tabKey,
                                    onSelectedCustom: (k) =>
                                        setState(() => _customTab = k),
                                    onCustomGone: _dropCustomTab,
                                  ),
                                if (isHome)
                                  _SlideIn(
                                    key: ValueKey('slide-top-$slideKey'),
                                    from: _slideFrom,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        const _OutOfAreaStrip(),
                                        // HOME_TOP 배너(가로 넘기기). 없으면 자리를 비운다.
                                        if (home.banners
                                                .where((b) => !b.middle)
                                                .toList()
                                            case final top when top.isNotEmpty)
                                          BannerPager(
                                            key: const ValueKey(
                                              'home-banners-top',
                                            ),
                                            banners: top,
                                            intervalSeconds:
                                                home.bannerIntervalSeconds,
                                            onOpen: (b) => openHomeBanner(
                                              context,
                                              b,
                                              home,
                                            ),
                                          ),
                                        // 사용자 캡처(2026-11-20 홈): 배너 아래 배송 안내 → 회색 띠 → 검색·카테고리
                                        const _DeliverySummaryCard(),
                                        const PmartSectionGap(height: 8),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            if (isHome)
                              const SliverPersistentHeader(
                                pinned: true,
                                delegate: _PinnedSearchBar(),
                              ),
                            SliverList.list(
                              children: [
                                // 영역마다 따로 감싼다(한 Column 으로 묶으면 화면 밖 영역까지 한꺼번에 만든다).
                                for (final (i, w) in <Widget>[
                                  if (isHome) ...[
                                    const _CategoryShortcuts(),
                                    // 레퍼런스: 둘째 줄 이름 아래 → 회색 띠 98px/1080.
                                    const SizedBox(height: 23.9),
                                    const PmartSectionGap(height: 10),
                                    // 레퍼런스: 섹션마다 회색 띠(약 8dp)로 나눈다.
                                    for (final (i, s)
                                        in home.sections.indexed) ...[
                                      if (i > 0)
                                        const PmartSectionGap(height: 8),
                                      // HOME_MIDDLE 배너는 첫 영역 아래(storefront 0.7.0)
                                      if (i == 1)
                                        if (home.banners
                                                .where((b) => b.middle)
                                                .toList()
                                            case final mid when mid.isNotEmpty)
                                          BannerPager(
                                            key: const ValueKey(
                                              'home-banners-middle',
                                            ),
                                            banners: mid,
                                            intervalSeconds:
                                                home.bannerIntervalSeconds,
                                            onOpen: (b) => openHomeBanner(
                                              context,
                                              b,
                                              home,
                                            ),
                                          ),
                                      // 배너 묶음(storefront 0.10.0 kind BANNER) — 받은 순서 그대로 이 자리에서 넘겨 보기
                                      if (s.kind == SectionKind.banner)
                                        BannerPager(
                                          key: ValueKey(
                                            'section-${s.sectionId}',
                                          ),
                                          banners: s.banners,
                                          intervalSeconds:
                                              s.intervalSeconds ??
                                              home.bannerIntervalSeconds,
                                          onOpen: (b) =>
                                              openHomeBanner(context, b, home),
                                        )
                                      else
                                        _SectionView(
                                          key: ValueKey(
                                            'section-${s.sectionId}',
                                          ),
                                          section: s,
                                          layoutVersion: home.layoutVersion,
                                        ),
                                    ],
                                  ] else if (custom != null)
                                    _CustomTabBody(
                                      key: ValueKey(
                                        'home-tab-body-${custom.tabKey}',
                                      ),
                                      tabKey: custom.tabKey,
                                      onGone: _dropCustomTab,
                                    )
                                  else
                                    _TabBody(
                                      key: ValueKey(
                                        'home-tab-body-${tab.name}',
                                      ),
                                      tab: tab,
                                    ),
                                ].indexed)
                                  _SlideIn(
                                    key: ValueKey('slide-$slideKey-$i'),
                                    from: _slideFrom,
                                    child: w,
                                  ),
                                // 아래 떠 있는 카드·막대가 목록 끝을 가리지 않게
                                const SizedBox(height: 170),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ), // 배달 중 카드 위, 장바구니 막대 아래(사용자 캡처 2026-11-20 홈 — 둘 다 있으면 위아래로)
                    const Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      // 알림(스낵바)이 배달 중 카드·장바구니 막대를 덮지 않게 위로 띄운다.
                      child: NoticeClearance(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _InProgressOrderCard(floating: true),
                            FloatingCartBar(),
                          ],
                        ),
                      ),
                    ),
                  ],
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

/// 서버가 준 고정 탭(`HomeLayout.tabs`) 뒤에 MD 탭(storefront 0.9.0 `customTabs`, 서버 순서).
/// 할인 탭(DEAL)은 1차 제외라 계약에 없다. MD 탭에 타이머가 있으면 이름 위에 남은 시간(레퍼런스 "오늘만특가" 자리),
/// 기간이 끝나면 [onCustomGone].
class _HomeTabs extends StatefulWidget {
  const _HomeTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelected,
    this.customTabs = const [],
    this.selectedCustom,
    this.onSelectedCustom,
    this.onCustomGone,
  });

  final List<HomeTab> tabs;

  /// 고른 고정 탭(MD 탭을 골랐으면 null).
  final HomeTab? selected;
  final ValueChanged<HomeTab> onSelected;
  final List<CustomTab> customTabs;
  final String? selectedCustom;
  final ValueChanged<String>? onSelectedCustom;
  final ValueChanged<String>? onCustomGone;

  @override
  State<_HomeTabs> createState() => _HomeTabsState();
}

class _HomeTabsState extends State<_HomeTabs> {
  /// 고른 탭 — 좌우로 끌어 화면 밖 탭으로 가면 탭 줄을 그 탭이 보이게 민다.
  final _selectedKey = GlobalKey();

  @override
  void didUpdateWidget(_HomeTabs old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected ||
        old.selectedCustom != widget.selectedCustom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _selectedKey.currentContext;
        if (c != null && c.mounted) {
          Scrollable.ensureVisible(
            c,
            alignment: 0.5,
            duration: _HomeScreenState._slideDuration,
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabs;
    final selected = widget.selected;
    final onSelected = widget.onSelected;
    final customTabs = widget.customTabs;
    final selectedCustom = widget.selectedCustom;
    final onSelectedCustom = widget.onSelectedCustom;
    final onCustomGone = widget.onCustomGone;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget tab({
      required Key key,
      required String label,
      required bool on,
      required VoidCallback onTap,
      Widget? above,
    }) => InkWell(
      key: key,
      onTap: onTap,
      child: Container(
        key: on ? _selectedKey : null,
        // 상단바와 탭 글자 사이 숨 쉴 간격(A안 약 12 = 위 4 + 여기 8).
        padding: const EdgeInsets.fromLTRB(11, 8, 11, 7.4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2.5,
              color: on ? scheme.onSurface : Colors.transparent,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?above,
            Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 16,
                fontWeight: on ? FontWeight.w800 : FontWeight.w400,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          // 타이머가 붙은 탭만 위로 높다 — 이름은 아래 줄에 맞춘다(레퍼런스 탭 줄).
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final t in tabs)
              tab(
                key: ValueKey('home-tab-${t.name}'),
                label: homeTabLabel(l10n, t),
                on: t == selected,
                onTap: () => onSelected(t),
              ),
            for (final c in customTabs)
              _TabExpiry(
                key: ValueKey('home-tab-expiry-${c.tabKey}'),
                endsAt: c.endsAt,
                onExpired: () => onCustomGone?.call(c.tabKey),
                child: tab(
                  key: ValueKey('home-tab-${c.tabKey}'),
                  label: c.title,
                  on: c.tabKey == selectedCustom,
                  onTap: () => onSelectedCustom?.call(c.tabKey),
                  above: c.showTimer && c.endsAt != null
                      ? _TabCountdown(
                          key: ValueKey('home-tab-timer-${c.tabKey}'),
                          endsAt: c.endsAt!,
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// MD 탭 이름 위 남은 시간(작은 빨간 글, 1초마다).
class _TabCountdown extends ConsumerStatefulWidget {
  const _TabCountdown({super.key, required this.endsAt});

  final DateTime endsAt;

  @override
  ConsumerState<_TabCountdown> createState() => _TabCountdownState();
}

class _TabCountdownState extends ConsumerState<_TabCountdown> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.endsAt.difference(ref.read(homeClockProvider)());
    return Text(
      remainingClock(left),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w700,
        // 사용자 2026-11-23 "분홍": 타이머 테마·쿠폰 만료 칩과 같은 팔레트 강조색(빨강 #F2383B 은 팔레트 밖).
        color: Theme.of(context).colorScheme.tertiary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// [endsAt] 이 되면 [onExpired] 를 한 번 부른다(없으면 아무것도 하지 않는다).
class _TabExpiry extends ConsumerStatefulWidget {
  const _TabExpiry({
    super.key,
    required this.endsAt,
    required this.onExpired,
    required this.child,
  });

  final DateTime? endsAt;
  final VoidCallback onExpired;
  final Widget child;

  @override
  ConsumerState<_TabExpiry> createState() => _TabExpiryState();
}

class _TabExpiryState extends ConsumerState<_TabExpiry> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final end = widget.endsAt;
    if (end != null) {
      final left = end.difference(ref.read(homeClockProvider)());
      _timer = Timer(
        left.isNegative ? Duration.zero : left,
        () => widget.onExpired(),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// MD 탭 본문(`GET /storefront/custom-tabs/{tabKey}`, 영역 모양은 랭킹·신상품 탭과 같다).
/// 기간이 지나 404 TAB_NOT_FOUND 면 [onGone](탭을 지우고 홈으로). 그 밖의 실패는 이 탭만 오류.
class _CustomTabBody extends ConsumerWidget {
  const _CustomTabBody({super.key, required this.tabKey, required this.onGone});

  final String tabKey;
  final ValueChanged<String> onGone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final provider = customTabProvider(tabKey);
    final value = ref.watch(provider);
    if (value case AsyncError(
      error: ProblemFailure(problem: Problem(code: 'TAB_NOT_FOUND')),
    )) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onGone(tabKey));
      return const SizedBox.shrink();
    }
    return switch (value) {
      AsyncData(:final value) when value.sections.isEmpty => Padding(
        key: const ValueKey('home-tab-empty'),
        padding: const EdgeInsets.all(16),
        child: Text(l10n.sectionEmpty),
      ),
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in value.sections)
            if (s.kind == SectionKind.banner)
              BannerPager(
                key: ValueKey('section-${s.sectionId}'),
                banners: s.banners,
                intervalSeconds: s.intervalSeconds,
                onOpen: (b) => openHomeBanner(context, b, value),
              )
            else
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
            if (s.kind == SectionKind.banner)
              BannerPager(
                key: ValueKey('section-${s.sectionId}'),
                banners: s.banners,
                intervalSeconds: s.intervalSeconds,
                onOpen: (b) => openHomeBanner(context, b, value),
              )
            else
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

/// 배너 자동 넘김 앱 기본 간격(서버 값이 없을 때, 백엔드 요청서 7번 "예 4초").
const bannerDefaultInterval = Duration(seconds: 4);

/// 넘겨 보는 배너. 오른쪽 아래에 `1 / N`.
/// storefront 0.10.0(백엔드 요청서 7번): 2개 이상이면 [interval](서버 값, 없으면 4초)마다 다음 장으로 — 마지막 다음은 첫 장으로
/// 이어진다. 손으로 넘기거나 누르고 있는 동안은 멈추고, 손을 떼면 그때부터 다시 센다. 1개면 넘기지 않는다.
class BannerPager extends StatefulWidget {
  const BannerPager({
    super.key,
    required this.banners,
    required this.onOpen,
    this.intervalSeconds,
  });

  final List<HomeBanner> banners;
  final void Function(HomeBanner) onOpen;

  /// 서버가 준 넘김 간격(초). null 이면 [bannerDefaultInterval].
  final int? intervalSeconds;

  @override
  State<BannerPager> createState() => _BannerPagerState();
}

class _BannerPagerState extends State<BannerPager> {
  /// 끝없이 넘기려고 가운데쯤에서 시작한다(쪽 번호는 배너 수로 나눈 나머지).
  /// 시작 쪽은 배너 수의 배수여야 첫 배너부터 보인다 — 10000 으로 고정했더니 6장이면 5번째부터 보였다(사용자 2026-11-24).
  static int _loopStart(int count) => count > 1 ? count * 1000 : 0;

  late final PageController _controller = PageController(
    initialPage: _loopStart(widget.banners.length),
  );
  late int _index = _controller.initialPage;
  Timer? _timer;
  bool _touching = false;

  int get _count => widget.banners.length;

  Duration get _interval => switch (widget.intervalSeconds) {
    final s? when s > 0 => Duration(seconds: s),
    _ => bannerDefaultInterval,
  };

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(BannerPager old) {
    super.didUpdateWidget(old);
    if (old.banners.length != widget.banners.length) {
      // 배너 수가 바뀌면(새로고침 등) 새 수의 배수로 옮겨 첫 배너부터 다시 보인다.
      _index = _loopStart(_count);
      if (_controller.hasClients) _controller.jumpToPage(_index);
    }
    if (old.intervalSeconds != widget.intervalSeconds ||
        old.banners.length != widget.banners.length) {
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (_count < 2 || _touching) return;
    _timer = Timer(_interval, () {
      if (!mounted || !_controller.hasClients) return;
      _controller.animateToPage(
        _index + 1,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final banners = widget.banners;
    final page = _count == 0 ? 0 : _index % _count;
    // 사용자 캡처(2026-11-20 홈): 화면 폭을 꽉 채운 배너(약 3:1). 서버 배너 그림은 1984×793.
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: SizedBox(
        // 사용자 레퍼런스 2026-11-25 홈: 359px/1080 폭(3.008:1).
        // 캡처로 잰 배너 칸이 8px 컸다(탭 아래 선·아래 여백 포함) — 3dp 줄여 359px 에 맞춘다.
        height: MediaQuery.sizeOf(context).width / 3.008 - 3,
        child: ClipRRect(
          borderRadius: BorderRadius.zero,
          child: Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  // 손으로 끌기 시작하면 멈추고, 끝나면 그때부터 다시 센다.
                  if (n is ScrollStartNotification && n.dragDetails != null) {
                    _touching = true;
                    _timer?.cancel();
                  } else if (n is ScrollEndNotification && _touching) {
                    _touching = false;
                    _schedule();
                  }
                  return false;
                },
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _count > 1 ? null : _count,
                  onPageChanged: (i) {
                    setState(() => _index = i);
                    _schedule();
                  },
                  itemBuilder: (context, i) {
                    final b = banners[i % _count];
                    return GestureDetector(
                      key: ValueKey('banner-${b.bannerId}'),
                      onTap: b.link == BannerLink.none
                          ? null
                          : () => widget.onOpen(b),
                      child: _BannerCard(b),
                    );
                  },
                ),
              ),
              if (_count > 1)
                Positioned(
                  right: 12,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${page + 1} / $_count',
                      key: const ValueKey('banner-page'),
                      // 레퍼런스 배너 쪽 번호는 보통 굵기(labelSmall 은 테마 w600).
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BannerCard extends ConsumerWidget {
  const _BannerCard(this.banner);

  final HomeBanner banner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // 서버가 배너 그림을 주면 그 그림을 쓴다. 없거나 받지 못하면 색 바탕 + 대체 문구.
    // 화면 폭만큼만 디코딩(원본 크기로 풀면 넘길 때 끊긴다 — 사용자 2026-11-20 스크롤 끊김).
    final px =
        MediaQuery.sizeOf(context).width *
        MediaQuery.devicePixelRatioOf(context);
    // 서버 축소본(BR-99 `?w=`)을 받는다 — 원본 PNG 를 받지 않게.
    final image = resolveImageUrl(
      withImageWidth(banner.imageUrl, px),
      ref.watch(imageOriginProvider),
    );
    final fallback = _fallback(theme, scheme);
    if (image == null) return fallback;
    return pmartNetworkImage(
      image,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: px.round(),
      semanticLabel: banner.altText,
      errorBuilder: (_, _, _) => fallback,
    );
  }

  Widget _fallback(ThemeData theme, ColorScheme scheme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            Color.lerp(scheme.primaryContainer, scheme.primary, 0.32)!,
          ],
        ),
      ),
      child: Stack(
        children: [
          // 장식(그림 자산 없이): 오른쪽에 옅은 원 두 개
          Positioned(
            right: -24,
            bottom: -40,
            child: _Bubble(size: 150, color: scheme.surface, alpha: 0.35),
          ),
          Positioned(
            right: 76,
            top: -30,
            child: _Bubble(size: 80, color: scheme.surface, alpha: 0.25),
          ),
          const Positioned(
            right: 10,
            top: 6,
            bottom: 2,
            width: 130,
            child: BannerArt(),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 22, right: 136),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                banner.altText ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 홈 검색창을 위에 붙여 두는 머리(내려도 사라지지 않는다). 흰 바탕이라 아래 내용이 비치지 않는다.
class _PinnedSearchBar extends SliverPersistentHeaderDelegate {
  const _PinnedSearchBar();

  // 레퍼런스 2026-11-25: 위 16.6 + 칸 45.7 + 아래 4.
  static const extent = 66.3;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      Material(
        color: Theme.of(context).colorScheme.surface,
        // 붙어 있을 때(아래 내용 위)만 옅은 그림자로 경계를 보인다.
        elevation: overlaps ? 1 : 0,
        shadowColor: Colors.black26,
        child: const Align(
          alignment: Alignment.bottomCenter,
          child: _HomeSearchBar(),
        ),
      );

  @override
  bool shouldRebuild(_PinnedSearchBar oldDelegate) => false;
}

/// 홈의 검색창(누르면 검색 탭으로).
class _HomeSearchBar extends StatelessWidget {
  const _HomeSearchBar();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16.6, 16, 4),
      child: InkWell(
        key: const ValueKey('home-search'),
        borderRadius: BorderRadius.circular(22.85),
        onTap: () => context.push('/search'),
        child: Container(
          height: 45.7,
          padding: const EdgeInsets.only(left: 18, right: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22.85),
            border: Border.all(color: scheme.onSurface, width: 1.1),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.searchHint,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const PmartLineIcon(PmartLineIcons.search, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// 상위 카테고리 바로가기(동그란 칸 + 이름, 가로로 넘긴다). 카테고리 그림이 계약에 없어 첫 글자를 넣는다.
/// 조회 중·실패면 그리지 않는다(카테고리 탭이 상태를 직접 보인다).
class _CategoryShortcuts extends ConsumerWidget {
  const _CategoryShortcuts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final roots = (ref.watch(categoriesProvider).value ?? const [])
        .where((n) => n.depth == 1)
        .toList();
    if (roots.isEmpty) return const SizedBox.shrink();
    // 사용자 레퍼런스 2026-11-25 홈(1080px 실측): 원 50 · 칸 폭 67.8 · 줄 간격 76.1 · 검색창 아래 16 · 이름 9.8.
    final labelHeight = MediaQuery.textScalerOf(context).scale(12);
    final cell = math.max(76.1, 50 + 3.5 + labelHeight + 10);
    final twoRows = roots.length > 5;
    return SizedBox(
      height: (twoRows ? cell * 2 : cell) + 12,
      child: GridView.builder(
        key: const ValueKey('home-categories'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10.1, 12, 10.1, 0),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: twoRows ? 2 : 1,
          mainAxisExtent: 67.8,
          mainAxisSpacing: 0,
        ),
        itemCount: roots.length,
        itemBuilder: (context, i) {
          final c = roots[i];
          return InkWell(
            key: ValueKey('home-category-${c.categoryId}'),
            borderRadius: BorderRadius.circular(12),
            onTap: () =>
                openCategoryBrowse(context, c.categoryId, title: c.name),
            child: Column(
              children: [
                // 사용자 캡처(2026-11-20 홈): 동그란 그림 약 44dp
                CategoryArt(name: c.name, size: 50, radius: 25),
                const SizedBox(height: 3.5),
                Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 9.8,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.size, required this.color, required this.alpha});

  final double size;
  final Color color;
  final double alpha;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: alpha),
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
    // 순위 진열은 사진 위 숫자 줄만큼 칸이 높다.
    final hasRank = shown.items.any(
      (t) => t.badge == DisplayBadge.rank && t.rank != null,
    );
    final Widget body;
    if (shown.available) {
      body = shown.items.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.sectionEmpty),
            )
          // 홈의 순위 진열(자동 랭킹 테마): 레퍼런스 "16. 지금 TOP 30" — 순위 숫자를 단 3칸 × 2줄, 나머지는 전체 보기.
          : !vertical && shown.ranked
          ? _RankGrid(items: shown.items.take(rankGridCount).toList())
          : vertical
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 12,
                runSpacing: 16,
                children: [
                  for (final tile in shown.items)
                    SizedBox(
                      width: ProductTileCard.gridWidthOf(context),
                      height: ProductTileCard.heightFor(
                        context,
                        ProductTileCard.gridWidthOf(context),
                        rank: hasRank,
                      ),
                      child: ProductTileCard(
                        rail: true,
                        tile: tile,
                        onTap: () => context.push(
                          '/products/${tile.productId}',
                          extra: tile,
                        ),
                      ),
                    ),
                ],
              ),
            )
          : SizedBox(
              height: ProductTileCard.heightFor(
                context,
                ProductTileCard.railWidthOf(context),
                rank: hasRank,
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: shown.items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) => SizedBox(
                  width: ProductTileCard.railWidthOf(context),
                  child: ProductTileCard(
                    rail: true,
                    tile: shown.items[i],
                    onTap: () => context.push(
                      '/products/${shown.items[i].productId}',
                      extra: shown.items[i],
                    ),
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
            const PmartLineIcon(PmartLineIcons.alert, size: 22),
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
    final scheme = Theme.of(context).colorScheme;
    final endsAt = section.showTimer ? section.endsAt : null;
    final hasViewAll =
        shown.hasViewAll ||
        (!vertical &&
            shown.rankedComplete &&
            shown.items.length > rankGridCount);
    void openAll() => context.push(
      '/sections/${shown.sectionId}',
      extra: SectionRef(shown, layoutVersion),
    );
    // 초안 06-D 띠형(timerStyle BAND): 머리를 연분홍 띠로, 전체보기는 상품 줄 아래 넓은 버튼.
    if (endsAt != null && section.timerStyle == TimerStyle.band) {
      final band = Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TimerBandHeader(
              key: ValueKey('section-timer-band-${section.sectionId}'),
              title: section.title,
              subtitle: section.subtitle,
              endsAt: endsAt,
            ),
            const SizedBox(height: 12),
            body,
            if (hasViewAll)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: OutlinedButton(
                  key: ValueKey('section-view-all-${section.sectionId}'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    foregroundColor: scheme.onSurface,
                    side: BorderSide(color: scheme.outlineVariant),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(fontSize: 14),
                  ),
                  onPressed: openAll,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.sectionViewAll),
                      const PmartLineIcon(
                        PmartLineIcons.chevronRight,
                        size: 15,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
      return SectionExpiry(endsAt: endsAt, child: band);
    }
    final view = Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PmartSectionHeader(
            title: section.title,
            subtitle: section.subtitle,
            // 타이머 테마(storefront 0.9.0 showTimer): 남은 시간 알약은 제목 위 줄에 — 옆에 두면 긴 제목이 좁은
            // 칸에 여러 줄로 꺾였다(사용자 2026-11-21 "테마 이름이 너무 좁게 잡혀").
            // 초안 06-C 라벨형(timerStyle LABEL·값 없음): 제목 위 분홍 글자, 알약 바탕 없음(BR-84).
            titleTop: endsAt == null
                ? null
                : SectionCountdown(
                    key: ValueKey('section-timer-${section.sectionId}'),
                    endsAt: endsAt,
                  ),
            trailing: hasViewAll
                ? TextButton(
                    key: ValueKey('section-view-all-${section.sectionId}'),
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onSurface,
                      textStyle: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontSize: 14),
                    ),
                    onPressed: openAll,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.sectionViewAll),
                        const PmartLineIcon(
                          PmartLineIcons.chevronRight,
                          size: 15,
                        ),
                      ],
                    ),
                  )
                : null,
          ),
          body,
        ],
      ),
    );
    // 끝 시각이 지나면 영역을 숨긴다(다음 홈 조회부터는 서버도 뺀다).
    return endsAt == null ? view : SectionExpiry(endsAt: endsAt, child: view);
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
          const PmartLineIcon(PmartLineIcons.alert, size: 20),
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
  /// [floating] 이면 화면 아래 떠 있는 알약만(초안 12 v2 H), 아니면 목록 안 실패 한 줄만.
  const _InProgressOrderCard({this.floating = false});

  final bool floating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return switch (ref.watch(homeInProgressOrderProvider)) {
      AsyncData(value: final order?) when floating => Align(
        alignment: Alignment.centerRight,
        child: _DeliveringPill(order: order),
      ),
      AsyncError() when !floating => _InlineFailure(
        key: const ValueKey('home-order-failed'),
        text: l10n.homeOrderFailed,
        onRetry: () => ref.invalidate(homeInProgressOrderProvider),
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// 홈 알약의 짧은 단계 말(초안 12 H — 상품 준비 중 / 배달 시작 / 배달 중 / 곧 도착). 라이더 단계(서버 ETA stage)가
/// 있으면 그것을, 없으면 주문 상태로. 주문 확인(준비 전)은 "주문 확인".
String deliveryPhaseShort(
  AppLocalizations l10n, {
  required OrderStatus status,
  DeliveryStage? stage,
}) => switch (stage) {
  DeliveryStage.atCustomer => l10n.homePillNear,
  DeliveryStage.toCustomer => l10n.homePillDelivering,
  DeliveryStage.toStore || DeliveryStage.atStore => l10n.homePillStarted,
  _ => switch (status) {
    OrderStatus.confirmed => l10n.homePillConfirmed,
    OrderStatus.preparing ||
    OrderStatus.partiallyHandedOver => l10n.homePillPreparing,
    _ => l10n.homePillDelivering,
  },
};

/// 초안 12 v2 H: 장바구니 막대 위 오른쪽 작은 검은 알약 "(스쿠터) 13분 배달 중 ›". 누르면 주문 상세.
/// 홈이 보일 때마다(처음·탭 돌아옴·위 화면 닫힘·앱이 다시 앞으로) 오른쪽에서 미끄러져 들어와 4초 뒤 사라진다.
/// 홈에 있는 동안 단계가 바뀌면 다시 4초. "동작 줄이기"면 미끄러짐 없이 흐림만. 남은 분은 서버 도착 예상만.
class _DeliveringPill extends ConsumerStatefulWidget {
  const _DeliveringPill({required this.order});

  final OrderListItem order;

  /// 보이는 시간(사용자 2026-11-23 확정).
  static const hold = Duration(seconds: 4);

  @override
  ConsumerState<_DeliveringPill> createState() => _DeliveringPillState();
}

class _DeliveringPillState extends ConsumerState<_DeliveringPill>
    with SingleTickerProviderStateMixin {
  // 들어옴 0.65초(앞 0.3초는 화면 전환과 겹치지 않게 기다림) · 나감 0.3초.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
    reverseDuration: const Duration(milliseconds: 300),
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.46, 1, curve: Curves.easeOutCubic),
    reverseCurve: Curves.easeInCubic,
  );
  Timer? _hold;
  bool _visible = false;
  String? _lastLabel;
  late final AppLifecycleListener _life = AppLifecycleListener(
    onResume: () {
      if (_visible) _show();
    },
  );

  @override
  void initState() {
    super.initState();
    _life; // 앱이 다시 앞으로 오면 다시 띄운다.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 홈이 보이는지: 탭(TickerMode)·위에 쌓인 화면(isCurrent). 안 보이다 보이면 다시 띄운다.
    final visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    if (visible && !_visible) _show();
    if (!visible) _hideNow();
    _visible = visible;
  }

  void _show() {
    _hold?.cancel();
    _c.forward(from: _c.value > 0.5 ? 0.46 : 0);
    _hold = Timer(_DeliveringPill.hold + _c.duration!, () {
      if (mounted) _c.reverse();
    });
  }

  void _hideNow() {
    _hold?.cancel();
    _c.value = 0;
  }

  @override
  void dispose() {
    _hold?.cancel();
    _life.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final order = widget.order;
    final eta = homeOrderHasEta(order.status)
        ? ref.watch(homeOrderEtaProvider(order.orderId)).value
        : null;
    final label = deliveryPhaseShort(
      l10n,
      status: order.status,
      stage: eta?.stage,
    );
    // 홈에 있는 동안 단계가 바뀌면 다시 4초(남은 분만 바뀌면 다시 띄우지 않는다).
    if (_lastLabel != null && _lastLabel != label && _visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _show();
      });
    }
    _lastLabel = label;
    final minutes = switch (eta) {
      DeliveryEtaView(
        status: EtaStatus.available,
        :final int remainingSeconds,
      ) =>
        (remainingSeconds / 60).ceil(),
      _ => null,
    };
    final reduce = MediaQuery.disableAnimationsOf(context);
    final pill = Material(
      key: const ValueKey('home-order-card'),
      color: const Color(0xF2232428),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      elevation: 3,
      child: InkWell(
        onTap: () => context.push('/orders/${order.orderId}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(7, 7, 12, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const PmartLineIcon(
                  PmartLineIcons.scooter,
                  size: 20,
                  color: Color(0xFFB9A8FF),
                ),
              ),
              const SizedBox(width: 8),
              if (minutes != null) ...[
                Text(
                  l10n.homeOrderEtaMinutes(minutes),
                  key: const ValueKey('home-order-eta'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFB9A8FF),
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                key: const ValueKey('home-order-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 2),
              const PmartLineIcon(
                PmartLineIcons.chevronRight,
                size: 16,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
    return AnimatedBuilder(
      animation: _t,
      child: pill,
      builder: (context, child) {
        // 다 사라졌으면 자리도 누를 곳도 없다(장바구니 막대는 아래에 붙어 있어 움직이지 않는다).
        if (_c.isDismissed) return const SizedBox.shrink();
        final v = _t.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Opacity(
            opacity: v.clamp(0.0, 1.0),
            child: reduce
                ? child
                : FractionalTranslation(
                    translation: Offset((1 - v) * 1.1, 0),
                    child: child,
                  ),
          ),
        );
      },
    );
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

/// 배달 요약(사용자 새 UI 2026-11-24 — "알뜰배달 29~44분 · 최소주문 15,000원 [배달안내]",
/// 아래 "30,000원부터 배달팁 0원 ›" 줄과 쿠폰 줄). 값은 서버 값만 — 없으면 그 조각을 빼고 지어내지 않는다.
/// 최소 주문·배달팁 구간·운영 시간은 `GET /delivery-options` 계약에 없어 목만 채운다(BR-96). 실서버에서는
/// 최소 주문을 장바구니 서버 값(cart `minOrderAmount`)으로 보이고, 배달팁 0원 줄은 구간이 오기 전까지 숨는다.
class _DeliverySummary extends ConsumerWidget {
  const _DeliverySummary({required this.options});

  final List<DeliveryOption> options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final night = options.any(
      (o) => !o.available && o.reason == UnavailableReason.nightTime,
    );
    final earliest = options
        .where((o) => o.mode == DeliveryMode.scheduled)
        .firstOrNull
        ?.earliestSlot;
    // 지금 받을 수 있는 즉시 방식. 없으면(심야 등) 예약 안내.
    // 사용자 UI 는 알뜰배달을 먼저 보인다(가능하면 알뜰, 아니면 한집).
    final now = DeliveryGuideSheet.instantOf(options)
        .where((o) => o.available)
        .firstOrNull;
    final cartMin = ref
        .watch(cartControllerProvider)
        .value
        ?.cart
        .minOrderAmount;
    final minOrder = now?.minOrderAmount ?? cartMin;
    final freeFrom = now?.freeTipFrom;
    void openGuide() => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => DeliveryGuideSheet(options: options),
    );
    // 사용자 새 UI 실측(사용자 폰 캡처 1080px = 411dp, 1dp = 2.625px): 제목 15.5 굵게, 최소주문 14, 가운데 점 연회색.
    final strong = theme.textTheme.titleMedium?.copyWith(
      fontSize: 15.5,
      fontWeight: FontWeight.w700,
    );
    final minSpan = minOrder == null
        ? null
        : TextSpan(
            children: [
              TextSpan(
                text: ' · ',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  color: scheme.outlineVariant,
                ),
              ),
              TextSpan(
                text: l10n.homeMinOrder(formatKrw(minOrder)),
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
              ),
            ],
          );
    final Widget headline;
    if (night || now == null) {
      headline = Text(l10n.homeNightNotice, style: strong);
    } else {
      final eta = now.eta;
      final title = switch (eta) {
        Eta(:final int minMinutes, :final int maxMinutes) when !eta.notSet =>
          l10n.homeModeEta(modeLabel(l10n, now.mode), minMinutes, maxMinutes),
        _ => modeLabel(l10n, now.mode),
      };
      headline = Text.rich(
        TextSpan(
          children: [
            TextSpan(text: title, style: strong),
            ?minSpan,
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13.6, 16, 7),
      child: Column(
        key: const ValueKey('home-delivery-card'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            key: night || now == null
                ? const ValueKey('home-night-notice')
                : const ValueKey('home-delivery-now'),
            padding: const EdgeInsets.fromLTRB(3.8, 0, 0, 13.3),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      headline,
                      if ((night || now == null) && earliest != null)
                        Text(
                          l10n.optionEarliestSlot(windowText(earliest)),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                // 작은 회색 알약(실측 약 53×20dp, 글 11.5).
                Material(
                  key: const ValueKey('home-delivery-guide'),
                  color: scheme.surfaceContainer,
                  shape: const StadiumBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: openGuide,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2.5,
                      ),
                      child: Text(
                        l10n.homeDeliveryGuide,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11.5,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (freeFrom != null)
            _HomeInfoRow(
              key: const ValueKey('home-free-tip'),
              color: scheme.surfaceContainer,
              icon: const ShieldPercentIcon(),
              text: Text(
                l10n.homeFreeTipFrom(formatKrw(freeFrom)),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              trailing: const PmartLineIcon(
                PmartLineIcons.chevronRight,
                size: 16,
                strokeWidth: 2,
              ),
              onTap: openGuide,
            ),
          const _HomeCouponRow(),
        ],
      ),
    );
  }
}

/// 회색(또는 연보라) 둥근 한 줄(실측 높이 45dp·모서리 11dp, 안쪽 왼쪽 14dp): 그림 · 글 · 오른쪽 표시.
class _HomeInfoRow extends StatelessWidget {
  const _HomeInfoRow({
    super.key,
    required this.color,
    required this.icon,
    required this.text,
    required this.trailing,
    required this.onTap,
    this.trailingPad = 14,
  });

  final Color color;
  final Widget icon;
  final Widget text;
  final Widget trailing;
  final VoidCallback onTap;
  final double trailingPad;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10.3),
    child: Material(
      color: color,
      borderRadius: BorderRadius.circular(11.4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(13.7, 0, trailingPad, 0),
          child: SizedBox(
            // 레퍼런스 121px/1080.
            height: 46.1,
            child: Row(
              children: [
                SizedBox(width: 14.5, child: Center(child: icon)),
                const SizedBox(width: 8),
                Expanded(child: text),
                trailing,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// 쿠폰 줄(사용자 새 UI): 받을 수 있는 쿠폰 첫 장 이름 + "외 N개", 오른쪽 받기 동그라미 → "할인받고 주문해요" 시트.
/// 회원만, 받을 수 있는 쿠폰이 있을 때만. 조회 실패·없음이면 줄을 그리지 않는다(홈의 부가 정보).
class _HomeCouponRow extends ConsumerWidget {
  const _HomeCouponRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final campaigns =
        ref.watch(couponCampaignsProvider).value ?? const <CouponCampaign>[];
    final open = [
      for (final c in campaigns)
        if (!c.reachedLimit && !c.soldOut) c,
    ];
    if (open.isEmpty) return const SizedBox.shrink();
    final first = open.first;
    final style = theme.textTheme.titleSmall?.copyWith(
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
    );
    final label = open.length > 1
        ? l10n.homeCouponMore(first.name, open.length - 1)
        : first.name;
    // 이름 안의 할인 금액(예 "7,000원")만 주 색 — 이름은 서버 값 그대로.
    final amount = switch (first.discount.type) {
      CouponDiscountType.amount => formatKrw(first.discount.value),
      CouponDiscountType.rate => '${first.discount.value}%',
    };
    final at = label.indexOf(amount);
    return _HomeInfoRow(
      key: const ValueKey('home-coupon'),
      // 실측 #EEF0FF 같은 아주 연한 보라(브랜드 주 색 8%).
      color: Color.alphaBlend(
        scheme.primary.withValues(alpha: 0.08),
        scheme.surface,
      ),
      icon: const CouponFilledIcon(),
      trailingPad: 10.7,
      text: Text.rich(
        at < 0
            ? TextSpan(text: label)
            : TextSpan(
                children: [
                  TextSpan(text: label.substring(0, at)),
                  TextSpan(
                    text: amount,
                    style: TextStyle(color: scheme.primary),
                  ),
                  TextSpan(text: label.substring(at + amount.length)),
                ],
              ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
      trailing: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: scheme.primary,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: PmartLineIcon(
          PmartLineIcons.download,
          size: 13.5,
          strokeWidth: 2.4,
          color: scheme.onPrimary,
        ),
      ),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        builder: (_) => const CouponCampaignSheet(),
      ),
    );
  }
}

/// "배달 안내" 시트(사용자 새 UI 2026-11-24): 24시간 주문 가능(운영 시간·새벽은 예약), 방식마다 이름 + 표 + 예상시간 +
/// 배달팁 구간. 값은 서버 값만 — 구간이 없으면 기본 배달팁 한 줄, 운영 시간이 없으면 그 줄을 뺀다(BR-96).
/// 간격은 사용자 폰 캡처 실측(1080px = 411dp, 1dp = 2.625px): 좌우 20, 제목 18 굵게, 본문 14, 줄 간격 25.
class DeliveryGuideSheet extends StatelessWidget {
  const DeliveryGuideSheet({super.key, required this.options});

  final List<DeliveryOption> options;

  /// `HH:mm`(24:00 포함) → `오전 8:00`. 표시만.
  static String clock(String hhmm) {
    final parts = hhmm.split(':').map(int.parse).toList();
    final hour = parts[0] % 24;
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final noon = hour < 12 ? '오전' : '오후';
    return '$noon $h12:${parts[1].toString().padLeft(2, '0')}';
  }

  /// 사용자 UI 순서: 알뜰 → 한집(예약은 위 "24시간 주문 가능"이 대신한다).
  static List<DeliveryOption> instantOf(List<DeliveryOption> options) => [
    for (final m in const [DeliveryMode.bundled, DeliveryMode.single])
      ...options.where((o) => o.mode == m),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scheduled = options.any((o) => o.mode == DeliveryMode.scheduled);
    final hours = options.map((o) => o.serviceHours).nonNulls.firstOrNull;
    final instant = instantOf(options);
    final title18 = theme.textTheme.titleMedium?.copyWith(
      fontSize: 18,
      height: 1.3,
      fontWeight: FontWeight.w700,
    );
    final body = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      height: 1.47,
    );
    final grey = body?.copyWith(color: scheme.onSurfaceVariant);
    Widget bullet(String text, TextStyle? style, {Key? key}) => Row(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('• ', style: style),
        Expanded(child: Text(text, style: style)),
      ],
    );
    Widget row(String left, String right, {bool strong = false}) => Row(
      children: [
        Expanded(child: Text(left, style: grey)),
        Text(
          right,
          style: body?.copyWith(fontWeight: strong ? FontWeight.w700 : null),
        ),
      ],
    );
    List<Widget> tipRows(DeliveryOption o) {
      final rows = <Widget>[];
      if (!o.available) {
        rows.add(row(optionSubtitle(l10n, o), ''));
      } else if (o.tipTiers case final tiers? when tiers.isNotEmpty) {
        for (final t in tiers) {
          rows.add(
            row(
              l10n.deliveryGuideFrom(formatKrw(t.fromAmount)),
              t.tip == 0 ? l10n.deliveryGuideTipFree : formatKrw(t.tip),
              strong: t.tip == 0,
            ),
          );
        }
      } else if (o.tip?.base case final int base) {
        rows.add(row(l10n.deliveryGuideBaseTip, formatKrw(base)));
      }
      return [
        for (final (i, r) in rows.indexed) ...[
          if (i > 0) const SizedBox(height: 4.5),
          r,
        ],
      ];
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SingleChildScrollView(
          key: const ValueKey('delivery-guide-sheet'),
          padding: const EdgeInsets.fromLTRB(19.8, 12.6, 12, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(l10n.deliveryGuideTitle, style: title18),
                  ),
                  // 회색 동그라미 닫기(실측 지름 33dp).
                  Material(
                    key: const ValueKey('delivery-guide-close'),
                    color: scheme.surfaceContainer,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      child: SizedBox.square(
                        dimension: 38,
                        child: Center(
                          child: Semantics(
                            label: MaterialLocalizations.of(context)
                                .closeButtonTooltip,
                            button: true,
                            child: const PmartLineIcon(
                              PmartLineIcons.close,
                              size: 22,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 7.8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (scheduled) ...[
                      const SizedBox(height: 18.8),
                      Text(l10n.deliveryGuideAllDay, style: title18),
                      const SizedBox(height: 11.9),
                      if (hours != null) ...[
                        bullet(
                          l10n.deliveryGuideHours(
                            clock(hours.start),
                            clock(hours.end),
                          ),
                          body,
                          key: const ValueKey('delivery-guide-hours'),
                        ),
                        const SizedBox(height: 4.5),
                      ],
                      bullet(l10n.deliveryGuideNight, body),
                    ],
                    for (final (i, o) in instant.indexed) ...[
                      // 위 글머리 줄 → 방식 이름 25.2dp, 앞 방식 마지막 줄 → 다음 방식 이름 31.3dp(실측).
                      SizedBox(height: i == 0 ? 25.2 : 31.3),
                      Row(
                        key: ValueKey('delivery-guide-${o.mode.name}'),
                        children: [
                          Text(modeLabel(l10n, o.mode), style: title18),
                          const SizedBox(width: 3.5),
                          if (o.mode == DeliveryMode.bundled)
                            const BundledBadge()
                          else
                            const SingleBadge(),
                          if (o.eta case Eta(
                            :final int minMinutes,
                            :final int maxMinutes,
                            notSet: false,
                          ))
                            Container(
                              margin: const EdgeInsets.only(left: 7.6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainer,
                                borderRadius: BorderRadius.circular(4.5),
                              ),
                              child: Text(
                                l10n.deliveryGuideEta(minMinutes, maxMinutes),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5.8),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: scheme.surfaceContainerHigh,
                      ),
                      const SizedBox(height: 6.5),
                      ...tipRows(o),
                    ],
                    const SizedBox(height: 24.4),
                    bullet(l10n.deliveryGuideNote1, grey),
                    for (final o in instant) ...[
                      const SizedBox(height: 4.5),
                      bullet(
                        o.mode == DeliveryMode.bundled
                            ? l10n.deliveryGuideNoteBundled
                            : l10n.deliveryGuideNoteSingle,
                        grey,
                      ),
                    ],
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

/// 홈 첫 로딩 자리 표시. 회색 블록만 그린다(새 패키지 없이).
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) => PmartShimmer(
    child: ListView(
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
    ),
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
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 배송지를 고르기 전에는 배송 상태를 말하지 않는다(어느 주소로 가능한지 모름).
          if (book?.shoppingAddress != null) const _DeliveryStatusLine(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  text,
                  overflow: TextOverflow.ellipsis,
                  // D안: 주소 16.5 굵게.
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontSize: 16.5, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 2),
              const PmartLineIcon(PmartLineIcons.chevronDown, size: 17),
            ],
          ),
        ],
      ),
    );
  }
}

/// 주소 위 작은 배송 상태 줄(D안 "● 배송 가능 · 약 30분 도착"). 서버 배송 방식(`GET /delivery-options`) 값만 쓴다:
/// 바로 받는 방식(단독·묶음)이 가능하면 "배송 가능"(도착 시간은 넣지 않음 — 사용자 2026-11-23), 예약만 가능하면 "예약배달 가능",
/// 서버가 모두 불가라고 하면 "지금은 배송할 수 없어요"(회색). 불러오는 중·실패·주소 없음·미설정(CONFIG_REQUIRED)·
/// 모름(UNKNOWN)은 줄을 그리지 않는다 — 실패를 "불가"로 보이지 않는다(실패 안내는 아래 배송 안내 칸이 한다).
class _DeliveryStatusLine extends ConsumerWidget {
  const _DeliveryStatusLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // 초안 11-C(회색, 사용자 2026-11-23): 서버가 권역 밖이라고 판정한 주소면 배송 방식을 묻지 않고(센터 없음) 회색 불가 줄.
    // 초안 11-E(사용자 2026-11-23 "넣는다"): 판정 모름(확인 중·중첩·보완 필요·조회 불명)은 불가가 아니라 "확인 중".
    switch (ref.watch(_shoppingServiceabilityProvider)) {
      case Serviceability.outOfArea:
        return _statusLine(
          context,
          l10n.homeTopOutOfArea,
          scheme.onSurfaceVariant,
        );
      case Serviceability.unknown:
        return _statusLine(
          context,
          l10n.homeTopServiceUnknown,
          scheme.onSurfaceVariant,
        );
      case Serviceability.serviceable || null:
        break;
    }
    final options = ref.watch(homeDeliveryOptionsProvider).value;
    if (options == null || options.isEmpty) return const SizedBox.shrink();
    final now = options
        .where((o) => o.available && o.mode != DeliveryMode.scheduled)
        .toList();
    final (String text, bool ok) = switch (now) {
      // 도착 시간은 넣지 않는다(사용자 2026-11-23 "30분 도착은 안넣을거야") — 즉시 배송이 되면 늘 "배송 가능".
      [_, ...] => (l10n.homeTopDeliverable, true),
      []
          when options.any(
            (o) => o.available && o.mode == DeliveryMode.scheduled,
          ) =>
        (l10n.homeTopScheduledOnly, true),
      []
          when options.every(
            (o) => o.availability == OptionAvailability.unavailable,
          ) =>
        (l10n.homeTopUndeliverable, false),
      _ => ('', false),
    };
    if (text.isEmpty) return const SizedBox.shrink();
    return _statusLine(
      context,
      text,
      ok ? scheme.primary : scheme.onSurfaceVariant,
    );
  }

  Widget _statusLine(BuildContext context, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Row(
        key: const ValueKey('home-delivery-status'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 쇼핑 주소가 서버 판정으로 권역 밖(`OUT_OF_SERVICE_AREA`)인지. 판정 모름·주소 없음·조회 실패는 false(불가로 보이지 않음).
final _shoppingServiceabilityProvider = Provider.autoDispose<Serviceability?>(
  (ref) => ref.watch(
    addressBookProvider.select((v) => v.value?.shoppingAddress?.serviceability),
  ),
);

/// 초안 11-C(회색, 사용자 2026-11-23): 권역 밖 주소면 홈 맨 위 회색 띠 "이 주소는 아직 배달하지 않아요" + [주소 바꾸기 ›].
/// 초안 11-E: 판정 모름이면 같은 회색 띠 "배달 가능 여부를 확인하고 있어요" + [다시 확인](주소 목록 다시 읽기).
/// 상품 둘러보기는 그대로 둔다.
class _OutOfAreaStrip extends ConsumerWidget {
  const _OutOfAreaStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_shoppingServiceabilityProvider);
    if (state != Serviceability.outOfArea && state != Serviceability.unknown) {
      return const SizedBox.shrink();
    }
    final unknown = state == Serviceability.unknown;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: ValueKey(unknown ? 'home-service-unknown' : 'home-out-of-area'),
          borderRadius: BorderRadius.circular(12),
          onTap: unknown
              ? () => ref.invalidate(addressBookProvider)
              : () => context.push('/addresses'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        unknown
                            ? l10n.homeServiceUnknownTitle
                            : l10n.homeOutOfAreaTitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        unknown
                            ? l10n.homeServiceUnknownBody
                            : l10n.homeOutOfAreaBody,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  unknown ? l10n.homeServiceRecheck : l10n.homeOutOfAreaChange,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                PmartLineIcon(
                  unknown
                      ? PmartLineIcons.refresh
                      : PmartLineIcons.chevronRight,
                  size: 16,
                  color: scheme.onSurface,
                ),
              ],
            ),
          ),
        ),
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
          leading: const PmartLineIcon(PmartLineIcons.receipt),
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

/// 배너 누르기(storefront 0.7.0): 영역 → 그 영역 전체 보기, 상품 → 상세, 카테고리 → 그 카테고리 목록.
/// 배너를 누르면 갈 곳. 진열 영역 링크는 [home] 의 영역에서 찾는다(모르면 가지 않음).
void openHomeBanner(BuildContext context, HomeBanner b, HomeView? home) {
  final ref = b.linkRef;
  if (ref == null || ref.isEmpty) return;
  switch (b.link) {
    case BannerLink.section:
      if (home == null) return;
      final section = home.sections
          .where((s) => s.sectionId == ref)
          .firstOrNull;
      if (section != null) {
        context.push(
          '/sections/${section.sectionId}',
          extra: SectionRef(section, home.layoutVersion),
        );
      }
    case BannerLink.product:
      context.push('/products/$ref');
    case BannerLink.category:
      openCategoryBrowse(context, ref);
    case BannerLink.none:
      break;
  }
}

/// 남은 시간 "HH:MM:SS"(시간은 24 를 넘을 수 있다). 음수는 0.
String remainingClock(Duration d) {
  final s = d.isNegative ? 0 : d.inSeconds;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(s ~/ 3600)}:${two(s % 3600 ~/ 60)}:${two(s % 60)}';
}

/// 타이머 테마의 남은 시간 — 초안 06-C 라벨형: 분홍(tertiary) 시계 + "05:12:30 남음", 바탕 없음. 1초마다 줄어든다.
/// (전에는 빨간 알약 #F2383B — 팔레트 밖이라 초안대로 tertiary. MD 탭 이름 위 타이머도 2026-11-23 분홍으로.)
class SectionCountdown extends ConsumerStatefulWidget {
  const SectionCountdown({super.key, required this.endsAt});

  final DateTime endsAt;

  @override
  ConsumerState<SectionCountdown> createState() => _SectionCountdownState();
}

class _SectionCountdownState extends ConsumerState<SectionCountdown> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final left = widget.endsAt.difference(ref.read(homeClockProvider)());
    final pink = theme.colorScheme.tertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PmartLineIcon(
          PmartLineIcons.clock,
          size: 14,
          color: pink,
          strokeWidth: 2,
        ),
        const SizedBox(width: 4),
        Text(
          l10n.sectionTimeLeft(remainingClock(left)),
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: pink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// 초안 06-D 띠형 머리: 연분홍(tertiaryContainer) 띠 — 왼쪽 제목(2줄까지)·부제, 오른쪽 시·분·초 흰 칸 + "남은 시간".
class _TimerBandHeader extends ConsumerStatefulWidget {
  const _TimerBandHeader({
    super.key,
    required this.title,
    required this.endsAt,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final DateTime endsAt;

  @override
  ConsumerState<_TimerBandHeader> createState() => _TimerBandHeaderState();
}

class _TimerBandHeaderState extends ConsumerState<_TimerBandHeader> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final parts = remainingClock(
      widget.endsAt.difference(ref.read(homeClockProvider)()),
    ).split(':');
    final digit = theme.textTheme.titleMedium?.copyWith(
      fontSize: 17,
      fontWeight: FontWeight.w800,
      color: scheme.tertiary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget box(String v) => Container(
      width: 34,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(v, style: digit),
    );
    final colon = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Text(':', style: digit),
    );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                    color: scheme.onTertiaryContainer,
                  ),
                ),
                if (widget.subtitle case final s? when s.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      s,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  box(parts[0]),
                  colon,
                  box(parts[1]),
                  colon,
                  box(parts[2]),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l10n.sectionTimeLeftCaption,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11.5,
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// [endsAt] 이 지나면 [child] 를 숨긴다(이미 지났으면 처음부터 숨김).
class SectionExpiry extends ConsumerStatefulWidget {
  const SectionExpiry({super.key, required this.endsAt, required this.child});

  final DateTime endsAt;
  final Widget child;

  @override
  ConsumerState<SectionExpiry> createState() => _SectionExpiryState();
}

class _SectionExpiryState extends ConsumerState<SectionExpiry> {
  Timer? _timer;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(SectionExpiry old) {
    super.didUpdateWidget(old);
    if (old.endsAt != widget.endsAt) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final left = widget.endsAt.difference(ref.read(homeClockProvider)());
    _expired = left <= Duration.zero;
    if (!_expired) {
      _timer = Timer(left, () {
        if (mounted) setState(() => _expired = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _expired ? const SizedBox.shrink() : widget.child;
}

/// 홈 순위 진열에 보이는 칸 수(3칸 × 2줄, 레퍼런스 "16. 지금 TOP 30").
const rankGridCount = 6;

/// 순위 숫자를 단 3칸 격자(좌우 16, 칸 사이 8).
class _RankGrid extends StatelessWidget {
  const _RankGrid({required this.items});

  final List<ProductTile> items;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 16 * 2 - 8 * 2) / 3;
    final height = ProductTileCard.heightFor(context, width, rank: true);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 16,
        children: [
          for (final tile in items)
            SizedBox(
              key: ValueKey('rank-grid-${tile.productId}'),
              width: width,
              height: height,
              child: ProductTileCard(
                rail: true,
                tile: tile,
                onTap: () =>
                    context.push('/products/${tile.productId}', extra: tile),
              ),
            ),
        ],
      ),
    );
  }
}

/// 탭이 바뀌면 내용이 옆에서 미끄러져 들어온다([from] 1 = 오른쪽에서, -1 = 왼쪽에서, 0 = 그대로).
/// 탭마다 key 가 달라 새로 만들어질 때 한 번만 움직인다.
class _SlideIn extends StatefulWidget {
  const _SlideIn({super.key, required this.from, required this.child});

  final int from;
  final Widget child;

  @override
  State<_SlideIn> createState() => _SlideInState();
}

class _SlideInState extends State<_SlideIn>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: _HomeScreenState._slideDuration,
    value: widget.from == 0 ? 1 : 0,
  )..forward();
  late final _offset = Tween(
    begin: Offset(0.35 * widget.from, 0),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: SlideTransition(
      position: _offset,
      child: FadeTransition(opacity: _c, child: widget.child),
    ),
  );
}
