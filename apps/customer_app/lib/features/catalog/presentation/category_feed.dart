import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart' show PmartEnv;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/choice_sheet.dart';
import '../../../shared/providers.dart' show envProvider;
import '../domain/catalog.dart';
import 'catalog_providers.dart';
import 'product_list_view.dart' show sortLabel;
import 'widgets/category_art.dart';
import 'widgets/product_tile_card.dart';

/// 홈 할인·랭킹(베스트)·신상품 탭의 아래 목록(사용자 태블릿 나란히 보기 2026-11-26):
/// [위 내용] → (할인만, 목 모드) 할인율 칩 → **위에 붙는** 카테고리 줄 + "총 N개 상품" + 정렬 → 2칸 상품(끝까지 이어 받기).
/// 슬리버 묶음이라 홈 [CustomScrollView] 에 바로 넣는다.
class CategoryFeedSlivers extends ConsumerStatefulWidget {
  const CategoryFeedSlivers({
    super.key,
    required this.keyPrefix,
    required this.baseQuery,
    this.circles = false,
    this.rateChips = false,
    this.sortable = true,
    this.ranked = false,
    this.top = const [],
    this.slide,
  });

  /// 탭을 바꿀 때 옆에서 밀려 들어오는 효과(홈이 준다). 위 내용·붙는 줄·처음 몇 줄에만 씌운다
  /// — 내리다 새로 만들어지는 줄은 미끄러지지 않게.
  final Widget Function(Widget child, String id)? slide;

  /// 위젯 열쇠 앞말(`sale`·`best`·`new`) — `<앞말>-total`·`<앞말>-sort`·`<앞말>-category-<id>`.
  final String keyPrefix;

  /// 조건(할인만·정렬). 카테고리·할인율은 이 화면이 바꾼다.
  final ProductQuery baseQuery;

  /// 카테고리를 동그라미 그림으로(할인 탭). 아니면 글자 알약(랭킹·신상품).
  final bool circles;

  /// [전체 · 50% 초과 · 40% · 30% · 20%] — 계약에 할인율 조건이 없어(BR-112) 목 모드에서만.
  final bool rateChips;

  /// 오른쪽 정렬 단추.
  final bool sortable;

  /// 카드 위 순위 숫자(랭킹 베스트).
  final bool ranked;

  /// 맨 위에 둘 내용(배너 등).
  final List<Widget> top;

  @override
  ConsumerState<CategoryFeedSlivers> createState() =>
      _CategoryFeedSliversState();
}

class _CategoryFeedSliversState extends ConsumerState<CategoryFeedSlivers> {
  String? _category;
  late SortKey _sort = widget.baseQuery.sort;
  int? _rate;

  static const _rates = [50, 40, 30, 20];

  ProductQuery get _query => ProductQuery(
    onSale: widget.baseQuery.onSale,
    categoryId: _category,
    sort: _sort,
    minDiscountRate: _rate,
  );

  Future<void> _pickSort() async {
    final l10n = AppLocalizations.of(context);
    final keys = widget.baseQuery.onSale
        ? SortKey.values
        : SortKey.values.where((s) => s != SortKey.discountRate);
    final picked = await showChoiceSheet<SortKey>(
      context,
      title: l10n.sortTitle,
      closeKey: const ValueKey('sort-close'),
      selected: _sort,
      options: [
        for (final s in keys)
          (s, sortLabel(l10n, s), ValueKey('sort-${s.name}')),
      ],
    );
    if (picked != null && mounted) setState(() => _sort = picked);
  }

  Widget _slide(Widget child, String id) =>
      widget.slide?.call(child, id) ?? child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = widget.keyPrefix;
    final roots = (ref.watch(categoriesProvider).value ?? const [])
        .where((n) => n.depth == 1)
        .toList();
    final provider = productListProvider(_query);
    final list = ref.watch(provider);
    final value = list.value;
    final mock = ref.watch(envProvider) == PmartEnv.mock;

    // 레퍼런스 알약: 고른 것 검정 채움·흰 굵은 글, 나머지 옅은 테두리.
    Widget pill({
      required Key key,
      required String label,
      required bool on,
      required VoidCallback onTap,
    }) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? scheme.onSurface : scheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: on ? scheme.onSurface : scheme.outlineVariant,
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 14.5,
              fontWeight: on ? FontWeight.w700 : FontWeight.w400,
              color: on ? scheme.surface : scheme.onSurface,
            ),
          ),
        ),
      ),
    );

    // 카테고리 동그라미(지름 56 — 고르면 그림 위에 검은 테두리만, 그림 크기는 그대로).
    Widget circle({
      required Key key,
      required bool on,
      required Widget art,
      required String label,
      required VoidCallback onTap,
    }) => GestureDetector(
      key: key,
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 70,
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              foregroundDecoration: on
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.onSurface, width: 2),
                    )
                  : null,
              alignment: Alignment.center,
              child: art,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 13,
                fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );

    final categoryRow = widget.circles
        ? SizedBox(
            height: 86,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                circle(
                  key: ValueKey('$p-category-all'),
                  on: _category == null,
                  art: const PmartLineIcon(PmartLineIcons.grid, size: 26),
                  label: l10n.saleAll,
                  onTap: () => setState(() => _category = null),
                ),
                for (final c in roots)
                  circle(
                    key: ValueKey('$p-category-${c.categoryId}'),
                    on: _category == c.categoryId,
                    art: CategoryArt(name: c.name, size: 56, radius: 28),
                    label: c.name,
                    onTap: () => setState(() => _category = c.categoryId),
                  ),
              ],
            ),
          )
        : SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                pill(
                  key: ValueKey('$p-category-all'),
                  label: l10n.saleAll,
                  on: _category == null,
                  onTap: () => setState(() => _category = null),
                ),
                for (final c in roots)
                  pill(
                    key: ValueKey('$p-category-${c.categoryId}'),
                    label: c.name,
                    on: _category == c.categoryId,
                    onTap: () => setState(() => _category = c.categoryId),
                  ),
              ],
            ),
          );

    final totalRow = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              switch (value?.total) {
                final int n => l10n.saleTotal(n),
                null => '',
              },
              key: ValueKey('$p-total'),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 14,
                color: const Color(0xFF9A9CA0),
              ),
            ),
          ),
          if (widget.sortable)
            SizedBox(
              height: 32,
              child: OutlinedButton(
                key: ValueKey('$p-sort'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.onSurface,
                  side: BorderSide(color: scheme.outlineVariant),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                ),
                onPressed: _pickSort,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const PmartLineIcon(PmartLineIcons.sort, size: 15),
                    const SizedBox(width: 4),
                    Text(sortLabel(l10n, _sort)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    final notifier = ref.read(provider.notifier);
    Widget card(BuildContext context, int i) {
      final items = value!.items;
      if (i >= items.length - 6 &&
          value.hasMore &&
          !value.loadingMore &&
          value.loadMoreFailure == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) notifier.loadMore();
        });
      }
      final tile = items[i];
      final c = ProductTileCard(
        key: ValueKey('$p-tile-${tile.productId}'),
        rail: true,
        look: TileLook.grid2,
        tile: tile,
        onTap: () => context.push('/products/${tile.productId}', extra: tile),
      );
      if (!widget.ranked) return c;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${i + 1}',
            key: ValueKey('$p-rank-${tile.productId}'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          c,
        ],
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        for (final (i, w) in widget.top.indexed)
          SliverToBoxAdapter(child: _slide(w, 'top-$i')),
        if (widget.rateChips && mock)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 4),
              child: SizedBox(
                height: 36,
                child: ListView(
                  key: ValueKey('$p-rates'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    pill(
                      key: ValueKey('$p-rate-all'),
                      label: l10n.saleAll,
                      on: _rate == null,
                      onTap: () => setState(() => _rate = null),
                    ),
                    for (final (i, r) in _rates.indexed)
                      pill(
                        key: ValueKey('$p-rate-$r'),
                        label: i == 0
                            ? l10n.saleRateAbove(r)
                            : l10n.saleRate(r),
                        on: _rate == r,
                        onTap: () => setState(() => _rate = r),
                      ),
                  ],
                ),
              ),
            ),
          ),
        // 카테고리 줄만 위에 붙고, "총 N개 상품 · 정렬" 줄은 고정하지 않고 목록과 같이 올라간다
        // (사용자 2026-11-26 "총 N개 상품, 추천순 필터 있는 바는 고정이 아니라 접히게").
        PinnedHeaderSliver(
          child: ColoredBox(
            key: ValueKey('$p-bar'),
            color: scheme.surface,
            child: _slide(
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  categoryRow,
                  const SizedBox(height: 6),
                ],
              ),
              'bar',
            ),
          ),
        ),
        SliverToBoxAdapter(child: _slide(totalRow, 'total')),
        switch (list) {
          AsyncData(:final value) when value.items.isEmpty =>
            SliverToBoxAdapter(
              child: Padding(
                key: ValueKey('$p-empty'),
                padding: const EdgeInsets.all(24),
                child: Text(l10n.sectionEmpty, textAlign: TextAlign.center),
              ),
            ),
          AsyncData(:final value) => SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: () {
              final pairs = ProductPairRows(
                count: value.items.length,
                itemBuilder: card,
              );
              return SliverList.builder(
                itemCount: pairs.rows,
                itemBuilder: (context, r) {
                  final row = pairs.row(context, r);
                  return r < 3 ? _slide(row, 'row-$r') : row;
                },
              );
            }(),
          ),
          AsyncError() => SliverToBoxAdapter(
            child: Padding(
              key: ValueKey('$p-failed'),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(child: Text(l10n.sectionUnavailable)),
                  TextButton(
                    onPressed: () => ref.invalidate(provider),
                    child: Text(l10n.checkoutCheckAgain),
                  ),
                ],
              ),
            ),
          ),
          _ => const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        },
        if (value != null && value.loadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        if (value != null && value.loadMoreFailure != null)
          SliverToBoxAdapter(
            child: Center(
              child: TextButton(
                key: ValueKey('$p-load-more-retry'),
                onPressed: notifier.loadMore,
                child: Text(l10n.checkoutCheckAgain),
              ),
            ),
          ),
      ],
    );
  }
}

/// 랭킹 탭 "다른 사람들도 많이 눌러 봤어요 · 최근 3시간 클릭이 많은 상품"(레퍼런스, 사용자 2026-11-26).
/// **클릭 순위 API 가 계약에 없다(BR-113)** — 목 모드에서만 목 데이터(인기순 앞 6개)로 3칸 × 2줄을 보인다.
/// 실서버에서는 자리를 비운다(지어낸 순위를 보이지 않는다).
class ClickedRankingSection extends ConsumerWidget {
  const ClickedRankingSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(envProvider) != PmartEnv.mock) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final items =
        ref
            .watch(
              productListProvider(const ProductQuery(sort: SortKey.popular)),
            )
            .value
            ?.items
            .take(6)
            .toList() ??
        const <ProductTile>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const ValueKey('ranking-clicked'),
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.rankingClickedTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.rankingClickedSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          for (var r = 0; r < (items.length / 3).ceil(); r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var c = 0; c < 3; c++) ...[
                    if (c > 0) const SizedBox(width: 8),
                    Expanded(
                      child: r * 3 + c < items.length
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${r * 3 + c + 1}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                ProductTileCard(
                                  rail: true,
                                  tile: items[r * 3 + c],
                                  onTap: () => context.push(
                                    '/products/${items[r * 3 + c].productId}',
                                    extra: items[r * 3 + c],
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
