import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart' show PmartFailure;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../catalog/presentation/widgets/product_tile_card.dart'
    show ProductImage;
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
      appBar: AppBar(title: Text(l10n.wishTitle)),
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
              ready: (context, _) => RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: _items.length + 2,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      // 초안 07-C 머리: "전체 12개"(수는 굵게). 편집(D)은 넣지 않음.
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
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
                      );
                    }
                    if (i <= _items.length) {
                      // 끝에서 5개 안쪽이 그려지면 다음 쪽. 실패했으면 자동으로 다시 부르지 않는다(버튼으로).
                      if (i >= _items.length - 5 &&
                          _hasMore &&
                          !_loadingMore &&
                          !_moreFailed) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _more(),
                        );
                      }
                      final w = _items[i - 1];
                      return _WishTile(
                        item: w,
                        onRemoved: () => setState(() {
                          _items.removeWhere((x) => x.productId == w.productId);
                          if (_total > 0) _total -= 1;
                        }),
                      );
                    }
                    if (_loadingMore) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (_moreFailed) {
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Text(
                              l10n.wishLoadMoreFailed,
                              key: const ValueKey('wishlist-more-failed'),
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                            TextButton(
                              onPressed: _more,
                              child: Text(l10n.startRetry),
                            ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
    );
  }
}

/// 찜 한 줄 — 초안 07-C: 사진 88(품절·판매 종료는 사진 아래 띠), 이름 2줄·가격 16 굵게, 오른쪽 위 하트,
/// 오른쪽 아래 [담기](옵션 하나면 바로 담기, 여럿이면 상세 — 카드 `+` 와 같은 규칙) / 못 사면 "담을 수 없어요".
/// 상품 정보를 못 읽은 줄은 지어내지 않고 그 말만, 담기 버튼도 두지 않는다.
class _WishTile extends ConsumerStatefulWidget {
  const _WishTile({required this.item, required this.onRemoved});

  final WishlistItem item;
  final VoidCallback onRemoved;

  @override
  ConsumerState<_WishTile> createState() => _WishTileState();
}

class _WishTileState extends ConsumerState<_WishTile> {
  bool _busy = false;

  Future<void> _add() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await quickAddProduct(context, ref, widget.item.productId);
    } finally {
      if (mounted) setState(() => _busy = false);
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
    final buttonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: theme.textTheme.labelLarge?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
    return InkWell(
      key: ValueKey('wish-${w.productId}'),
      onTap: () => context.push('/products/${w.productId}'),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox.square(
                dimension: 88,
                child: Stack(
                  children: [
                    Opacity(
                      opacity: w.infoMissing ? 0.45 : 1,
                      child: ProductImage(url: w.imageUrl, size: 88, radius: 0),
                    ),
                    if (label != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          key: ValueKey('wish-state-${w.productId}'),
                          height: 24,
                          alignment: Alignment.center,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.9),
                          child: Text(
                            label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: scheme.surface,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 88),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 초안 07-C: 하트는 이름 줄 오른쪽(누르는 자리만 넓게, 줄 높이는 이름만큼), [담기]는 그 아래 오른쪽 끝.
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const SizedBox(width: double.infinity),
                        Padding(
                          padding: const EdgeInsets.only(top: 2, right: 32),
                          child: Text(
                            w.infoMissing ? l10n.wishInfoMissing : w.name!,
                            key: ValueKey('wish-name-${w.productId}'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontSize: 15,
                              height: 1.35,
                              color: dim
                                  ? scheme.onSurfaceVariant
                                  : scheme.onSurface,
                            ),
                          ),
                        ),
                        Positioned(
                          top: -12,
                          right: -12,
                          child: WishHeartButton(
                            key: ValueKey('wish-heart-${w.productId}'),
                            productId: w.productId,
                            onChanged: (wished) {
                              if (!wished) widget.onRemoved();
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    if (!w.infoMissing)
                      if (w.price case final p?)
                        Text(
                          formatKrw(p),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: dim
                                ? scheme.onSurfaceVariant
                                : scheme.onSurface,
                          ),
                        ),
                    if (!w.infoMissing)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: w.saleState == WishSaleState.onSale
                              ? OutlinedButton.icon(
                                  key: ValueKey('wish-add-${w.productId}'),
                                  style: buttonStyle.copyWith(
                                    foregroundColor: WidgetStatePropertyAll(
                                      scheme.primary,
                                    ),
                                    side: WidgetStatePropertyAll(
                                      BorderSide(color: scheme.primary),
                                    ),
                                  ),
                                  onPressed: _busy ? null : _add,
                                  icon: _busy
                                      ? const SizedBox.square(
                                          dimension: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : PmartLineIcon(
                                          PmartLineIcons.cart,
                                          size: 16,
                                          color: scheme.primary,
                                        ),
                                  label: Text(l10n.wishAddToCart),
                                )
                              : OutlinedButton(
                                  key: ValueKey('wish-cannot-${w.productId}'),
                                  style: buttonStyle.copyWith(
                                    side: WidgetStatePropertyAll(
                                      BorderSide(color: scheme.outlineVariant),
                                    ),
                                  ),
                                  onPressed: null,
                                  child: Text(l10n.wishCannotAdd),
                                ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 64),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: PmartLineIcon(
                PmartLineIcons.heart,
                size: 34,
                color: scheme.tertiary,
              ),
            ),
            const SizedBox(height: 18),
            if (title case final t?) ...[
              Text(
                t,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 14,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            if (filled)
              FilledButton(
                key: const ValueKey('wishlist-login'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: onAction,
                child: Text(action),
              )
            else
              OutlinedButton(
                key: const ValueKey('wishlist-browse'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  foregroundColor: scheme.onSurface,
                  side: BorderSide(color: scheme.outlineVariant),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: onAction,
                child: Text(action),
              ),
          ],
        ),
      ),
    );
  }
}
