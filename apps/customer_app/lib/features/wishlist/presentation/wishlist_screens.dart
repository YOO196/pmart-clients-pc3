import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart' show PmartFailure;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../../shared/floating_cart_bar.dart';
import '../../../shared/cart_icon_button.dart';
import '../../../shared/notice.dart';
import '../../cart/domain/cart.dart';
import '../../cart/presentation/cart_controller.dart';
import '../../cart/presentation/cart_messages.dart';
import '../../catalog/presentation/widgets/product_tile_card.dart'
    show ProductImage, ProductTileCard;
import '../../catalog/presentation/widgets/quick_add_button.dart'
    show quickAddProduct;
import '../domain/wishlist.dart';
import 'wish_heart_button.dart';
import 'wishlist_controller.dart';

/// 마이 → 찜한 상품(최근 찜한 순, 아래로 내리면 다음 쪽). 품절·판매 종료도 남기고 표시한다.
/// 비회원은 조회하지 않고 로그인 안내만. 조회 실패는 "찜한 상품 없음"이 아니다.
class WishlistScreen extends ConsumerStatefulWidget {
  const WishlistScreen({super.key});

  @override
  ConsumerState<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends ConsumerState<WishlistScreen> {
  static const _size = 20;

  AsyncValue<void> _first = const AsyncLoading();
  final _items = <WishlistItem>[];
  int _total = 0;
  int _page = 0;
  bool _loadingMore = false;
  bool _moreFailed = false;

  bool get _hasMore => _items.length < _total;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    // 비회원으로 열었다가 [로그인]으로 들어오면 그때 읽는다(안 하면 계속 불러오는 중으로 남는다).
    ref.listenManual(sessionProvider, (prev, next) {
      if (prev is! MemberSession && next is MemberSession) _load();
    });
  }

  Future<void> _load() async {
    if (ref.read(sessionProvider) is! MemberSession) return;
    setState(() => _first = const AsyncLoading());
    try {
      final p = await ref
          .read(wishlistRepositoryProvider)
          .list(page: 0, size: _size);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(p.items);
        _total = p.total;
        _page = 0;
        _moreFailed = false;
        _first = const AsyncData(null);
      });
    } on PmartFailure catch (e, st) {
      if (mounted) setState(() => _first = AsyncError(e, st));
    }
  }

  Future<void> _more() async {
    if (_loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
    });
    try {
      final p = await ref
          .read(wishlistRepositoryProvider)
          .list(page: _page + 1, size: _size);
      if (!mounted) return;
      final seen = {for (final w in _items) w.productId};
      setState(() {
        _items.addAll(p.items.where((w) => !seen.contains(w.productId)));
        _total = p.total;
        _page += 1;
        _loadingMore = false;
        // 서버가 더 주지 않으면 멈춘다(전체 수가 바뀌었을 수 있다).
        if (p.items.isEmpty) _total = _items.length;
      });
    } on PmartFailure {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _moreFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final member = ref.watch(sessionProvider) is MemberSession;
    return Scaffold(
      key: const ValueKey('wishlist'),
      // 사용자 폰 캡처(2026-11-26, 1080px = 411dp): 왼쪽 "찜" 굵게, 오른쪽 돋보기·장바구니(수).
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 20.5,
        automaticallyImplyLeading: false,
        title: Text(
          l10n.navWish,
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            key: const ValueKey('wishlist-search'),
            tooltip: l10n.searchTitle,
            onPressed: () => context.push('/search'),
            icon: const PmartLineIcon(PmartLineIcons.search, size: 24),
          ),
          const CartIconButton(size: 24),
          const SizedBox(width: 8),
        ],
      ),
      // 초안 07-E: 비회원도 빈 상태와 같은 틀(하트 동그라미 + 안내 + [로그인]).
      body: !member
          ? _WishEmpty(
              key: const ValueKey('wishlist-guest'),
              title: null,
              body: l10n.wishLoginNeeded,
              action: l10n.wishLogin,
              filled: true,
              onAction: () => context.push('/login'),
            )
          : UiStateView<void>(
              loading: (_) => const PmartListSkeleton(thumb: true, rows: 4),
              state: uiStateOf(_first, isEmpty: (_) => _items.isEmpty),
              onRetry: _load,
              empty: (_) => _WishEmpty(
                key: const ValueKey('wishlist-empty'),
                title: l10n.wishEmpty,
                body: l10n.wishEmptyGuide,
                action: l10n.wishBrowse,
                filled: false,
                onAction: () => context.go('/'),
              ),
              ready: (context, _) {
                final hasCart =
                    ref
                        .watch(cartControllerProvider)
                        .value
                        ?.cart
                        .lines
                        .isNotEmpty ??
                    false;
                final width = ProductTileCard.gridWidthOf(context);
                // 이름 2줄 + 재고 한계 줄 + 가격까지 — 글자 크기 설정만큼 늘린다.
                final extent =
                    width +
                    MediaQuery.textScalerOf(context).scale(84).clamp(84, 200);
                return Stack(
                  children: [
                    Positioned.fill(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: CustomScrollView(
                          slivers: [
                            // 초안 07 머리: "전체 12개"(수는 굵게). 편집은 넣지 않음.
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  14,
                                  16,
                                  10,
                                ),
                                child: Text.rich(
                                  key: const ValueKey('wishlist-count'),
                                  TextSpan(
                                    children: [
                                      TextSpan(text: '${l10n.wishCountHead} '),
                                      TextSpan(
                                        text: l10n.wishCountUnit(_total),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              sliver: SliverGrid.builder(
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 16,
                                      mainAxisExtent: extent,
                                    ),
                                itemCount: _items.length,
                                itemBuilder: (context, i) {
                                  // 끝에서 5개 안쪽이 그려지면 다음 쪽. 실패했으면 자동으로 다시 부르지 않는다(버튼으로).
                                  if (i >= _items.length - 5 &&
                                      _hasMore &&
                                      !_loadingMore &&
                                      !_moreFailed) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) => _more());
                                  }
                                  final w = _items[i];
                                  return _WishTile(
                                    key: ValueKey('wish-tile-${w.productId}'),
                                    item: w,
                                    onRemoved: () => setState(() {
                                      _items.removeWhere(
                                        (x) => x.productId == w.productId,
                                      );
                                      if (_total > 0) _total -= 1;
                                    }),
                                  );
                                },
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: _loadingMore
                                  ? const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    )
                                  : _moreFailed
                                  ? Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        children: [
                                          Text(
                                            l10n.wishLoadMoreFailed,
                                            key: const ValueKey(
                                              'wishlist-more-failed',
                                            ),
                                            style: TextStyle(
                                              color: theme.colorScheme.error,
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: _more,
                                            child: Text(l10n.startRetry),
                                          ),
                                        ],
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            SliverToBoxAdapter(
                              child: SizedBox(height: hasCart ? 110 : 24),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 아래 장바구니 막대(담긴 게 있을 때만, 다른 목록과 같은 것).
                    const Positioned(
                      left: 12,
                      right: 12,
                      bottom: 10,
                      child: FloatingCartBar(),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

/// 찜 카드 — 초안 07 v2 B-1(사용자 2026-11-23): 2열 격자(사진 정사각 · 이름 2줄 · 가격).
/// 사진 오른쪽 위 흰 동그라미 하트, 오른쪽 아래 흰 동그라미 +(카드 + 와 같은 규칙 — 옵션 하나면 1개 담기, 여럿이면 상세).
/// 장바구니에 그 상품 줄이 하나 있으면 + 자리가 사진 아래쪽 폭을 채운 "− N +" 알약(N 은 장바구니 서버 수량).
/// 품절·판매 종료는 사진에 어두운 막 + 글, + 없음, 가격 회색. 상품 정보를 못 읽은 줄은 지어내지 않고 그 말만.
class _WishTile extends ConsumerStatefulWidget {
  const _WishTile({super.key, required this.item, required this.onRemoved});

  final WishlistItem item;
  final VoidCallback onRemoved;

  @override
  ConsumerState<_WishTile> createState() => _WishTileState();
}

class _WishTileState extends ConsumerState<_WishTile> {
  bool _busy = false;

  /// 서버가 남은 수량으로 거절했을 때의 가용(재고 한계). 다른 수량이 반영되면 지운다.
  int? _limit;

  Future<void> _add() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await quickAddProduct(context, ref, widget.item.productId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 알약 +/− — 장바구니 화면과 같은 요청(수량 바꾸기, 0 이면 빼기). 실패면 원래 숫자 + 알림.
  Future<void> _step(CartLine line, int delta) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final next = line.quantity + delta;
    setState(() => _busy = true);
    final outcome = await ref
        .read(cartControllerProvider.notifier)
        .submitWhenReady(
          next <= 0
              ? RemoveItem(cartItemId: line.cartItemId)
              : SetQuantity(cartItemId: line.cartItemId, quantity: next),
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (outcome) {
        case CartChangeApplied():
          if (delta < 0) _limit = null;
        case CartChangeRejected(
          code: CartProblemCode.insufficientAvailableQuantity,
          :final availableQty?,
        ):
          _limit = availableQty;
        default:
          break;
      }
    });
    switch (outcome) {
      case CartChangeApplied():
        break;
      case CartChangeRejected(
        code: CartProblemCode.insufficientAvailableQuantity,
        availableQty: _?,
      ):
        break; // 알약 아래 분홍 줄로 알린다.
      case null:
        messenger.notice(l10n.reorderBusy);
      case final o:
        messenger.notice(cartOutcomeText(l10n, o));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final w = widget.item;
    final label = switch (w.saleState) {
      WishSaleState.soldOut => l10n.wishSoldOut,
      WishSaleState.ended => l10n.wishEnded,
      _ => null,
    };
    final dim = label != null || w.infoMissing;
    // 장바구니의 이 상품 줄(서버 값). 한 줄일 때만 알약 — 여러 옵션이 담겼으면 + (상세에서 고른다).
    final lines = [
      for (final l
          in ref.watch(cartControllerProvider).value?.cart.lines ??
              const <CartLine>[])
        if (l.productId == w.productId) l,
    ];
    final line = lines.length == 1 ? lines.single : null;
    final canAdd = !dim && w.saleState == WishSaleState.onSale;
    final width = ProductTileCard.gridWidthOf(context);
    return InkWell(
      key: ValueKey('wish-${w.productId}'),
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.push('/products/${w.productId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: width,
            child: Stack(
              children: [
                Opacity(
                  opacity: w.infoMissing ? 0.45 : 1,
                  child: ProductImage(url: w.imageUrl, size: width, radius: 10),
                ),
                if (label != null)
                  Positioned.fill(
                    child: Container(
                      key: ValueKey('wish-state-${w.productId}'),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        label,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.surface,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: WishHeartButton(
                    key: ValueKey('wish-heart-${w.productId}'),
                    productId: w.productId,
                    onImage: true,
                    // 사용자 2026-11-23 "시안은 너무 작고 적당히 줄여": 동그라미 34 → 30dp(시안 약 28).
                    size: 20,
                    onChanged: (wished) {
                      if (!wished) widget.onRemoved();
                    },
                  ),
                ),
                if (canAdd && line != null)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: _QtyPill(
                      key: ValueKey('wish-qty-${w.productId}'),
                      quantity: line.quantity,
                      busy: _busy,
                      plusEnabled: _limit == null || line.quantity < _limit!,
                      onMinus: () => _step(line, -1),
                      onPlus: () => _step(line, 1),
                    ),
                  )
                else if (canAdd)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: _RoundPlus(
                      key: ValueKey('wish-add-${w.productId}'),
                      busy: _busy,
                      onTap: _add,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            w.infoMissing ? l10n.wishInfoMissing : w.name!,
            key: ValueKey('wish-name-${w.productId}'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              height: 1.3,
              color: dim ? scheme.onSurfaceVariant : scheme.onSurface,
            ),
          ),
          if (_limit case final n? when line != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                l10n.wishStockLimit(n),
                key: ValueKey('wish-limit-${w.productId}'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.tertiary,
                ),
              ),
            ),
          const SizedBox(height: 4),
          if (!w.infoMissing)
            if (w.price case final p?)
              Text(
                formatKrw(p),
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: dim ? scheme.outline : scheme.onSurface,
                ),
              ),
        ],
      ),
    );
  }
}

/// 사진 오른쪽 아래 흰 동그라미 +(카드 [QuickAddButton] 과 같은 모양).
class _RoundPlus extends StatelessWidget {
  const _RoundPlus({super.key, required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 30,
      child: IconButton.filledTonal(
        tooltip: l10n.quickAddTooltip,
        padding: EdgeInsets.zero,
        iconSize: 20,
        style: IconButton.styleFrom(
          backgroundColor: scheme.surface,
          elevation: 2,
          shadowColor: Colors.black38,
          minimumSize: const Size.square(30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: busy ? null : onTap,
        icon: busy
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const PmartLineIcon(
                PmartLineIcons.plus,
                size: 20,
                strokeWidth: 2.4,
              ),
      ),
    );
  }
}

/// 사진 아래쪽 폭을 채운 흰 알약 "− N +"(보라 테두리). 누르는 동안 숫자 자리에 작은 회전 표시.
class _QtyPill extends StatelessWidget {
  const _QtyPill({
    super.key,
    required this.quantity,
    required this.busy,
    required this.plusEnabled,
    required this.onMinus,
    required this.onPlus,
  });

  final int quantity;
  final bool busy;
  final bool plusEnabled;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget side(
      String key,
      PmartLineIcons icon,
      VoidCallback? onTap,
      String tip,
    ) => InkResponse(
      key: ValueKey(key),
      onTap: busy ? null : onTap,
      radius: 18,
      child: Semantics(
        button: true,
        label: tip,
        child: SizedBox(
          width: 36,
          height: 34,
          child: Center(
            child: PmartLineIcon(
              icon,
              size: 16,
              strokeWidth: 2,
              color: onTap == null ? scheme.outlineVariant : scheme.primary,
            ),
          ),
        ),
      ),
    );
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: scheme.primary, width: 1.4),
      ),
      child: Row(
        children: [
          side(
            'wish-qty-minus',
            PmartLineIcons.minus,
            onMinus,
            l10n.cartDecrease,
          ),
          Expanded(
            child: Center(
              child: busy
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      '$quantity',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          side(
            'wish-qty-plus',
            PmartLineIcons.plus,
            plusEnabled ? onPlus : null,
            l10n.cartIncrease,
          ),
        ],
      ),
    );
  }
}

/// 초안 07-E 빈 상태·비회원: 연분홍 동그라미 하트 + 제목 + 안내 + 버튼(빈 상태는 테두리 [상품 둘러보기],
/// 비회원은 채운 [로그인]).
class _WishEmpty extends StatelessWidget {
  const _WishEmpty({
    super.key,
    required this.title,
    required this.body,
    required this.action,
    required this.filled,
    required this.onAction,
  });

  final String? title;
  final String body;
  final String action;
  final bool filled;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 사용자 폰 캡처(2026-11-26): 점선 사과 그림 69.6×62.8, 그 아래 62 띄우고 굵은 두 줄 15(줄 간격 21.3),
    // 그 아래 19.8 띄우고 테두리 알약 버튼(높이 38, 글 14.5 + ›).
    final text = title == null ? body : '$title\n$body';
    // 가로는 화면 가운데(사용자 2026-11-26 "왼쪽으로 치우쳐" — 폭을 꽉 채워 가운데 맞춤), 세로는 사과 그림 위가
    // 화면 위에서 412.5dp(캡처 실측) — 상태 막대·머리줄 높이를 빼서 본문 안 위치로.
    // 본문 안에서는 상태 막대 높이가 빠져 있어 화면(View)에서 읽는다.
    final view = View.of(context);
    final statusBar = view.padding.top / view.devicePixelRatio;
    final top = (412.5 - statusBar - kToolbarHeight).clamp(
      24.0,
      double.infinity,
    );
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: c.maxHeight,
            minWidth: c.maxWidth,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, top, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/wish_empty.png',
                  key: const ValueKey('wishlist-empty-art'),
                  width: 69.6,
                  height: 62.8,
                  color: const Color(0xFF111214),
                ),
                const SizedBox(height: 58),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 15,
                    height: 1.42,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111214),
                  ),
                ),
                const SizedBox(height: 16.5),
                SizedBox(
                  height: 38,
                  child: OutlinedButton(
                    key: ValueKey(
                      filled ? 'wishlist-login' : 'wishlist-browse',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF111214),
                      side: const BorderSide(
                        color: Color(0xFFD4D6D8),
                        width: 1.2,
                      ),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.fromLTRB(16.7, 0, 12, 0),
                      textStyle: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onPressed: onAction,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(action),
                        const SizedBox(width: 6),
                        const PmartLineIcon(
                          PmartLineIcons.chevronRight,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
