import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart' show PmartFailure;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../../address/presentation/address_screens.dart' show LoginRequired;
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../catalog/presentation/widgets/product_tile_card.dart'
    show ProductImage;
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
      body: !member
          ? LoginRequired(message: l10n.wishLoginNeeded)
          : UiStateView<void>(
              loading: (_) => const PmartListSkeleton(thumb: true, rows: 4),
              state: uiStateOf(_first, isEmpty: (_) => _items.isEmpty),
              onRetry: _load,
              empty: (_) => Center(
                key: const ValueKey('wishlist-empty'),
                child: Text(l10n.wishEmpty),
              ),
              ready: (context, _) => RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: _items.length + 2,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                        child: Text(
                          l10n.wishCount(_total),
                          key: const ValueKey('wishlist-count'),
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

class _WishTile extends StatelessWidget {
  const _WishTile({required this.item, required this.onRemoved});

  final WishlistItem item;
  final VoidCallback onRemoved;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final w = item;
    // 품절·판매 종료는 남기되 흐리게 + 표시. 상품 정보를 못 읽은 것은 지어내지 않고 그 말만.
    final label = switch (w.saleState) {
      WishSaleState.soldOut => l10n.wishSoldOut,
      WishSaleState.ended => l10n.wishEnded,
      _ => null,
    };
    final dim = label != null || w.infoMissing;
    return InkWell(
      key: ValueKey('wish-${w.productId}'),
      onTap: () => context.push('/products/${w.productId}'),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Opacity(
              opacity: dim ? 0.45 : 1,
              child: ProductImage(url: w.imageUrl, size: 72, radius: 10),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    w.infoMissing ? l10n.wishInfoMissing : w.name!,
                    key: ValueKey('wish-name-${w.productId}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 15,
                      color: dim ? scheme.onSurfaceVariant : scheme.onSurface,
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
                          color: dim
                              ? scheme.onSurfaceVariant
                              : scheme.onSurface,
                        ),
                      ),
                  if (label != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        label,
                        key: ValueKey('wish-state-${w.productId}'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            WishHeartButton(
              key: ValueKey('wish-heart-${w.productId}'),
              productId: w.productId,
              onChanged: (wished) {
                if (!wished) onRemoved();
              },
            ),
          ],
        ),
      ),
    );
  }
}
