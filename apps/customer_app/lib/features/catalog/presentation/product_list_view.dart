import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/choice_sheet.dart';
import '../../../shared/floating_cart_bar.dart';
import '../../cart/presentation/cart_controller.dart'
    show cartControllerProvider;
import '../../../shared/ui_state_of.dart';
import '../domain/catalog.dart';
import 'catalog_providers.dart';
import 'widgets/product_tile_card.dart';

String sortLabel(AppLocalizations l10n, SortKey s) => switch (s) {
  SortKey.relevance => l10n.sortRelevance,
  SortKey.popular => l10n.sortPopular,
  SortKey.newest => l10n.sortNewest,
  SortKey.priceAsc => l10n.sortPriceAsc,
  SortKey.priceDesc => l10n.sortPriceDesc,
  SortKey.rating => l10n.sortRating,
  SortKey.reviewCount => l10n.sortReviewCount,
  SortKey.discountRate => l10n.sortDiscountRate,
};

/// SCR-LIST-001 본문. 정렬·필터는 이 위젯이 들고, 결과는 조건별 provider 에서 읽는다.
///
/// 상세로 갔다 돌아오면(push) 이 위젯이 살아 있으므로 조건·스크롤이 그대로다.
class ProductListView extends ConsumerStatefulWidget {
  const ProductListView({super.key, required this.baseQuery, this.onKeyword});

  /// 검색어·카테고리. 정렬·필터는 여기서 바꾼다.
  final ProductQuery baseQuery;

  /// 오타 교정 띠에서 다른 검색어로(제안어) 또는 원래 검색어로(교정 없이) 다시 찾을 때. 검색 화면만 준다.
  final void Function(String keyword, {bool noCorrection})? onKeyword;

  @override
  ConsumerState<ProductListView> createState() => _ProductListViewState();
}

class _ProductListViewState extends ConsumerState<ProductListView> {
  SortKey _sort = SortKey.relevance;
  Set<String> _filters = const {};

  ProductQuery get _query =>
      widget.baseQuery.copyWith(sort: _sort, filters: _filters);

  @override
  void didUpdateWidget(ProductListView old) {
    super.didUpdateWidget(old);
    // 검색어·카테고리가 바뀌면 이전 조건의 필터는 의미가 없다. 정렬은 유지한다.
    if (old.baseQuery != widget.baseQuery) _filters = const {};
  }

  /// 정렬 고르기: 아래 시트(지금 정렬에 ✓).
  Future<void> _pickSort() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showChoiceSheet<SortKey>(
      context,
      title: l10n.sortTitle,
      closeKey: const ValueKey('sort-close'),
      selected: _sort,
      options: [
        // 할인율순은 할인 목록에서만(BR-83 — 서버가 onSale 과 함께만 받는다).
        for (final s in SortKey.values)
          if (s != SortKey.discountRate || widget.baseQuery.onSale)
            (s, sortLabel(l10n, s), ValueKey('sort-${s.name}')),
      ],
    );
    if (picked != null && mounted) setState(() => _sort = picked);
  }

  /// 목록 위 속성 줄에서 바로 고르기 — 시트와 같은 규칙(단일 선택 속성은 같은 속성의 다른 값을 지운다).
  void _toggleAttribute(FilterAttribute a, FilterValue v) {
    final token = a.token(v);
    setState(() {
      _filters = _filters.contains(token)
          ? ({..._filters}..remove(token))
          : {
              if (a.multiSelect)
                ..._filters
              else
                ..._filters.where((t) => !t.startsWith('${a.key}.')),
              token,
            };
    });
  }

  Future<void> _openFilters() async {
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FilterSheet(query: widget.baseQuery, initial: _filters),
    );
    // 닫기(null)는 기존 조건 유지.
    if (picked != null && mounted) setState(() => _filters = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = _query;
    final provider = productListProvider(query);
    final value = ref.watch(provider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final list = value.value;
    // 레퍼런스 3-4: 회색 띠 "○○을 찾으시는 것 같아요." — 교정 결과면 원래 검색어로 다시 찾기
    final keyword = widget.baseQuery.keyword;
    final Widget? correction = switch ((
      list?.correctedQuery,
      list?.suggestedQuery,
    )) {
      (final c?, _) when keyword != null => _CorrectionBand(
        key: const ValueKey('search-corrected'),
        // 요청(2026-11-20 search-correction-text): "'순두부' 검색 결과예요" + "'순두뷰'로 검색하기"
        lead: "'$c'",
        text: l10n.searchCorrected,
        action: l10n.searchUseOriginal(keyword),
        onAction: widget.onKeyword == null
            ? null
            : () => widget.onKeyword!(keyword, noCorrection: true),
      ),
      (_, final s?) => _CorrectionBand(
        key: const ValueKey('search-suggested'),
        // "혹시 '순두부'를 찾으셨나요?" — 누르면 그 검색어로 새로 찾는다
        prefix: l10n.searchSuggestedPrefix,
        lead: "'$s'",
        text: l10n.searchSuggested,
        onTap: widget.onKeyword == null ? null : () => widget.onKeyword!(s),
      ),
      _ => null,
    };
    // 정렬·필터는 회색 테두리 알약(레퍼런스 3-4 "⇅ 기본순"·"필터")
    Widget pill({
      required Key key,
      required PmartLineIcons icon,
      required String label,
      required VoidCallback onPressed,
    }) => OutlinedButton.icon(
      key: key,
      onPressed: onPressed,
      icon: PmartLineIcon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        side: BorderSide(color: scheme.outlineVariant),
        foregroundColor: scheme.onSurface,
        textStyle: theme.textTheme.bodyMedium?.copyWith(fontSize: 10.5),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
    final hasCart =
        ref.watch(cartControllerProvider).value?.cart.lines.isNotEmpty ?? false;
    return Column(
      children: [
        ?correction,
        _AttributeRows(
          query: widget.baseQuery,
          picked: _filters,
          onToggle: _toggleAttribute,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  switch (list?.total) {
                    final int total => l10n.searchResultCount(total),
                    null => '',
                  },
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              pill(
                key: const ValueKey('sort'),
                icon: PmartLineIcons.sort,
                label: sortLabel(l10n, _sort),
                onPressed: _pickSort,
              ),
              const SizedBox(width: 6),
              // 고른 필터 수는 알약 오른쪽 위 작은 동그라미(레퍼런스).
              Badge(
                key: const ValueKey('filter-count'),
                isLabelVisible: _filters.isNotEmpty,
                label: Text('${_filters.length}'),
                backgroundColor: scheme.onSurface,
                textColor: scheme.surface,
                offset: const Offset(-2, -4),
                child: pill(
                  key: const ValueKey('open-filters'),
                  icon: PmartLineIcons.filter,
                  label: l10n.filterTitle,
                  onPressed: _openFilters,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          // 레퍼런스: 목록 위에 떠 있는 장바구니 막대(담긴 게 있을 때만).
          child: Stack(
            children: [
              Positioned.fill(
                child: UiStateView<ProductListState>(
                  loading: (_) => const PmartGridSkeleton(),
                  state: uiStateOf(value, isEmpty: (s) => s.items.isEmpty),
                  onRetry: () => ref.invalidate(provider),
                  empty: (_) => Center(
                    child: Text(
                      widget.baseQuery.onSale
                          ? l10n.listNoSaleProducts
                          : widget.baseQuery.keyword == null
                          ? l10n.listNoProducts
                          : l10n.searchNoResult,
                    ),
                  ),
                  ready: (context, list) => ProductGrid(
                    key: const PageStorageKey('product-list'),
                    list: list,
                    onLoadMore: () => ref.read(provider.notifier).loadMore(),
                    autoLoadMore: true,
                    bottomInset: hasCart ? 90 : 0,
                  ),
                ),
              ),
              const Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: FloatingCartBar(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 오타 교정 띠(레퍼런스 3-4): 회색 바탕 가운데 "[굵게 검색어]을 찾으시는 것 같아요." 교정 결과면 오른쪽 아래 원래 검색어 링크.
class _CorrectionBand extends StatelessWidget {
  const _CorrectionBand({
    super.key,
    required this.lead,
    required this.text,
    this.prefix,
    this.action,
    this.onAction,
    this.onTap,
  });

  final String? prefix;
  final String lead;
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Column(
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    if (prefix case final p?) TextSpan(text: p),
                    TextSpan(
                      text: lead,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: text),
                  ],
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15),
              ),
              if (action case final a?)
                TextButton(
                  key: const ValueKey('search-use-original'),
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: scheme.onSurfaceVariant,
                    textStyle: theme.textTheme.bodySmall?.copyWith(
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  child: Text(a),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 상품 2칸 격자 + 목록 끝의 "더 보기". 검색·카테고리·전체보기가 같이 쓴다.
class ProductGrid extends StatelessWidget {
  const ProductGrid({
    super.key,
    required this.list,
    required this.onLoadMore,
    this.autoLoadMore = false,
    this.bottomInset = 0,
  });

  /// 아래 떠 있는 막대에 가리지 않게 끝에 더 띄운다.
  final double bottomInset;

  final ProductListState list;
  final VoidCallback onLoadMore;

  /// 남은 카드가 [autoLoadAhead] 개쯤일 때 다음 묶음을 미리 부른다(검색·카테고리, 한 묶음 20개).
  /// 실패하면 멈추고 "더 보기"로 다시 받는다.
  final bool autoLoadMore;
  static const autoLoadAhead = 6;

  @override
  Widget build(BuildContext context) {
    final width = ProductTileCard.gridWidthOf(context);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
              mainAxisExtent: ProductTileCard.heightFor(context, width),
            ),
            itemCount: list.items.length,
            itemBuilder: (context, i) {
              if (autoLoadMore &&
                  i >= list.items.length - autoLoadAhead &&
                  list.hasMore &&
                  !list.loadingMore &&
                  list.loadMoreFailure == null) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => onLoadMore(),
                );
              }
              final tile = list.items[i];
              return ProductTileCard(
                rail: true,
                tile: tile,
                onTap: () =>
                    context.push('/products/${tile.productId}', extra: tile),
              );
            },
          ),
        ),
        if (list.hasMore)
          SliverToBoxAdapter(
            child: LoadMoreFooter(list: list, onLoadMore: onLoadMore),
          ),
        SliverToBoxAdapter(child: SizedBox(height: 16 + bottomInset)),
      ],
    );
  }
}

/// 목록 끝의 "더 보기"·다음 묶음 실패 안내(받은 목록은 그대로 둔다).
class LoadMoreFooter extends StatelessWidget {
  const LoadMoreFooter({
    super.key,
    required this.list,
    required this.onLoadMore,
  });

  final ProductListState list;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (list.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          if (list.loadMoreFailure != null) Text(l10n.loadMoreFailed),
          OutlinedButton(
            key: const ValueKey('load-more'),
            onPressed: onLoadMore,
            child: Text(l10n.loadMore),
          ),
        ],
      ),
    );
  }
}

/// SCR-FILTER-001. 고른 값은 임시 선택이다. 적용해야 반영되고, 닫기는 기존 조건을 유지한다.
class FilterSheet extends ConsumerStatefulWidget {
  const FilterSheet({super.key, required this.query, required this.initial});

  final ProductQuery query;
  final Set<String> initial;

  @override
  ConsumerState<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<FilterSheet> {
  late Set<String> _picked = {...widget.initial};

  void _toggle(FilterAttribute a, FilterValue v) {
    final token = a.token(v);
    setState(() {
      if (_picked.contains(token)) {
        _picked = {..._picked}..remove(token);
      } else {
        _picked = {
          // 단일 선택 속성은 같은 속성의 다른 값을 지운다.
          if (a.multiSelect)
            ..._picked
          else
            ..._picked.where((t) => !t.startsWith('${a.key}.')),
          token,
        };
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final provider = filtersProvider(
      ProductQuery(
        keyword: widget.query.keyword,
        categoryId: widget.query.categoryId,
        onSale: widget.query.onSale,
      ),
    );
    final value = ref.watch(provider);
    final state = uiStateOf(value, isEmpty: (a) => a.isEmpty);
    final attributes = value.value ?? const <FilterAttribute>[];
    // 고른 값의 이름(아래 "작은공기 ✕" 줄) — 속성 목록에서 찾는다.
    final pickedLabels = [
      for (final a in attributes)
        for (final v in a.values)
          if (_picked.contains(a.token(v))) (a, v),
    ];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.filterTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('filter-close'),
                    tooltip: l10n.filterClose,
                    icon: const PmartLineIcon(PmartLineIcons.close, size: 24),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: UiStateView<List<FilterAttribute>>(
                state: state,
                onRetry: () => ref.invalidate(provider),
                ready: (context, attributes) => ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  children: [
                    for (final a in attributes) ...[
                      Text(
                        a.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final v in a.values)
                            _FilterPill(
                              key: ValueKey('filter-${a.token(v)}'),
                              label: v.label,
                              selected: _picked.contains(a.token(v)),
                              // 현재 조건에서 결과가 0개인 값은 고를 수 없다(이미 고른 값은 해제 가능).
                              enabled:
                                  v.count != 0 || _picked.contains(a.token(v)),
                              onTap: () => _toggle(a, v),
                            ),
                        ],
                      ),
                      const SizedBox(height: 28),
                    ],
                  ],
                ),
              ),
            ),
            if (pickedLabels.isNotEmpty) ...[
              const Divider(height: 1),
              SizedBox(
                height: 52,
                child: ListView(
                  key: const ValueKey('filter-picked'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
                  children: [
                    for (final (a, v) in pickedLabels)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InputChip(
                          key: ValueKey('filter-picked-${a.token(v)}'),
                          label: Text(v.label),
                          labelStyle: theme.textTheme.bodyMedium,
                          backgroundColor: scheme.surfaceContainer,
                          side: BorderSide.none,
                          shape: const StadiumBorder(),
                          deleteIcon: const PmartLineIcon(
                            PmartLineIcons.close,
                            size: 16,
                          ),
                          onDeleted: () => _toggle(a, v),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 16, 8),
              child: Row(
                children: [
                  InkWell(
                    key: const ValueKey('filter-reset'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _picked = {}),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const PmartLineIcon(PmartLineIcons.refresh, size: 24),
                          Text(
                            l10n.filterReset,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('filter-apply'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        // 테마 글꼴을 잃지 않게 테마 글자 모양에서 바꾼다.
                        textStyle: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(_picked),
                      child: Text(l10n.filterApply),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 필터 값 알약(레퍼런스): 테두리 알약, 고르면 채움, 고를 수 없으면 흐리게.
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const StadiumBorder(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: ShapeDecoration(
            shape: StadiumBorder(
              side: BorderSide(
                color: selected
                    ? scheme.primary
                    : scheme.outlineVariant.withValues(
                        alpha: enabled ? 1 : 0.5,
                      ),
              ),
            ),
            color: selected ? scheme.primary : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected
                  ? scheme.onPrimary
                  : enabled
                  ? scheme.onSurface
                  : scheme.outline.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

/// 목록 위 속성 줄(레퍼런스 "즉석밥 크기 | 작은공기 중간공기 큰공기"): 앞 2개 속성을 바로 고른다.
/// 고르면 곧바로 필터에 반영(시트의 적용과 같은 결과). 결과 0개 값은 흐리게·못 고름.
class _AttributeRows extends ConsumerWidget {
  const _AttributeRows({
    required this.query,
    required this.picked,
    required this.onToggle,
  });

  final ProductQuery query;
  final Set<String> picked;
  final void Function(FilterAttribute, FilterValue) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final attributes = ref
        .watch(
          filtersProvider(
            ProductQuery(
              keyword: query.keyword,
              categoryId: query.categoryId,
              onSale: query.onSale,
            ),
          ),
        )
        .value;
    // 읽는 중·실패면 줄을 두지 않는다(필터 버튼에서 다시 시도·실패 표시).
    if (attributes == null || attributes.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      key: const ValueKey('attribute-rows'),
      children: [
        for (final a in attributes.take(2)) ...[
          SizedBox(
            height: 52,
            child: Row(
              children: [
                SizedBox(
                  width: 112,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text(
                      a.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(right: 12),
                    children: [
                      for (final v in a.values)
                        if (v.count != 0 || picked.contains(a.token(v)))
                          InkWell(
                            key: ValueKey('attr-${a.token(v)}'),
                            onTap: () => onToggle(a, v),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Center(
                                child: Text(
                                  v.label,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: picked.contains(a.token(v))
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color: picked.contains(a.token(v))
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
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
          ),
          const Divider(height: 1),
        ],
        Container(height: 8, color: scheme.surfaceContainer),
      ],
    );
  }
}
