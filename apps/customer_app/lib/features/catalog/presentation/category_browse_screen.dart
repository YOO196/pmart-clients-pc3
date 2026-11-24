import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/cart_icon_button.dart';
import '../domain/catalog.dart';
import 'catalog_providers.dart';
import 'home_screen.dart' show BannerPager, openHomeBanner;
import 'product_list_view.dart';
import 'widgets/category_art.dart';
import 'widgets/product_tile_card.dart';
import '../../../shared/providers.dart'
    show imageOriginProvider, resolveImageUrl, withImageWidth;

/// 카테고리 화면을 연다 — 아래 탭 막대를 둔 채, 들어온 탭 안에서(사용자 2026-11-23 "1,2 하고"):
/// 홈 탭이면 `/category`, 카테고리 탭이면 `/categories/list`, 그 밖(전체 화면 위 등)은 `/products`(전체 화면).
void openCategoryBrowse(
  BuildContext context,
  String categoryId, {
  String? title,
}) {
  final here = GoRouter.of(context)
      .routerDelegate
      .currentConfiguration
      .uri
      .path;
  final path = switch (here) {
    '/' || '/category' => '/category',
    '/categories' || '/categories/list' => '/categories/list',
    _ => '/products',
  };
  context.push(
    Uri(
      path: path,
      queryParameters: {'categoryId': categoryId, 'title': ?title},
    ).toString(),
  );
}

/// 초안 15 B(사용자 확정 2026-11-23): 카테고리 → 하위 → 상품 목록 한 화면.
/// 같은 구획 상위 가로 탭(검정 밑줄) → 하위 동그라미 줄(맨 앞 "☰ 전체") → CATEGORY 배너 → "이 카테고리의 할인
/// 상품 전체 ›" 가로 줄 → 상품 수·정렬·필터·2열. 내려 보면(D) 동그라미 줄이 그림 든 알약 칩으로 바뀌어 탭 아래 붙는다.
/// 진입: 카테고리 탭 상위(시트 없이)·홈 카테고리 타일·카테고리 연결 배너 — [categoryId] 가 상위면 "전체",
/// 하위면 그 상위 탭 + 그 하위가 골라진 상태.
class CategoryBrowseScreen extends ConsumerStatefulWidget {
  const CategoryBrowseScreen({super.key, required this.categoryId, this.title});

  final String categoryId;

  /// 카테고리 트리를 못 읽었을 때 단독 목록의 제목.
  final String? title;

  @override
  ConsumerState<CategoryBrowseScreen> createState() =>
      _CategoryBrowseScreenState();
}

class _CategoryBrowseScreenState extends ConsumerState<CategoryBrowseScreen> {
  /// 사용자가 탭·하위를 바꾸면 여기(처음은 [CategoryBrowseScreen.categoryId]).
  String? _picked;
  bool _collapsed = false;

  /// 동그라미 줄 높이쯤 내려가면 알약 칩 줄로 바꾼다.
  static const _collapseAt = 92.0;

  /// 배너·할인 줄을 기다리는 가장 긴 시간. 넘으면 그 칸 없이 상품을 보인다(사용자 2026-11-24 C).
  static const _holdMax = Duration(milliseconds: 1000);

  /// 상품 격자를 보이기 시작한 목록(categoryId). 이 목록이 아니면 머리(배너·할인 줄)가 정해질 때까지
  /// 격자 자리에 뼈대를 둔다 — 머리가 늦게 끼어들어 상품이 아래로 밀리지 않게.
  String? _releasedFor;
  String? _holdFor;
  Timer? _hold;

  /// 놓을 때 이미 정해졌던 칸만 보인다. 늦게 온 칸은 이 목록을 보는 동안 숨긴다(밀림 없음).
  bool _showBanner = false;
  bool _showSale = false;

  void _pick(String id) => setState(() {
    _picked = id;
    _collapsed = false;
  });

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  static bool _settled(AsyncValue<Object?> v) => v.hasValue || v.hasError;

  static ProductQuery _saleQuery(String listId) =>
      ProductQuery(categoryId: listId, onSale: true);

  void _release(String listId) {
    _hold?.cancel();
    _hold = null;
    _holdFor = null;
    _releasedFor = listId;
    // 배너는 목록마다 같아 한 번 보이면 그대로 둔다.
    _showBanner = _showBanner || _settled(ref.read(categoryBannersProvider));
    _showSale = _settled(ref.read(productListProvider(_saleQuery(listId))));
  }

  /// [listId] 목록의 격자를 지금 보여도 되는지. 머리 두 칸이 정해졌거나 [_holdMax] 가 지났으면 놓는다.
  bool _gridReleased(String listId) {
    if (_releasedFor == listId) return true;
    final banner = ref.watch(categoryBannersProvider);
    final sale = ref.watch(productListProvider(_saleQuery(listId)));
    if ((_showBanner || _settled(banner)) && _settled(sale)) {
      _release(listId);
      return true;
    }
    if (_holdFor != listId) {
      _hold?.cancel();
      _holdFor = listId;
      _hold = Timer(_holdMax, () {
        if (!mounted || _holdFor != listId) return;
        setState(() => _release(listId));
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tree = ref.watch(categoriesProvider);
    final nodes = tree.value;
    final current = _picked ?? widget.categoryId;
    final byId = {
      for (final n in nodes ?? const <CategoryNode>[]) n.categoryId: n,
    };
    // 상위(depth 1)와 그 바로 아래 하위(depth 2)를 찾는다. 더 깊으면 위로 올라간다.
    CategoryNode? root;
    CategoryNode? child;
    var n = byId[current];
    while (n != null) {
      if (n.depth == 1) {
        root = n;
        break;
      }
      if (n.depth == 2) child = n;
      n = n.parentId == null ? null : byId[n.parentId];
    }
    final appBar = AppBar(
      title: root == null ? Text(widget.title ?? '') : null,
      actions: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: l10n.navHome,
          icon: const PmartLineIcon(PmartLineIcons.home, size: 23),
          onPressed: () => context.go('/'),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: l10n.searchTitle,
          icon: const PmartLineIcon(PmartLineIcons.search, size: 23),
          onPressed: () => context.go('/search'),
        ),
        const CartIconButton(),
        const SizedBox(width: 6),
      ],
    );
    // 트리를 읽는 중이면 위 탭·하위 줄 자리를 같은 높이의 뼈대로 먼저 잡는다 — 다 읽은 뒤 두 줄이 끼어들어
    // 화면이 밀리지 않게(사용자 2026-11-24 A).
    if (nodes == null && tree.isLoading) {
      return Scaffold(
        appBar: appBar,
        body: const _BrowseSkeleton(key: ValueKey('category-browse-skeleton')),
      );
    }
    // 트리를 못 읽었거나 없는 id 면 그 카테고리 단독 목록(지금까지의 모습).
    if (root == null) {
      return Scaffold(
        appBar: appBar,
        body: ProductListView(baseQuery: ProductQuery(categoryId: current)),
      );
    }
    final all = nodes!;
    final tabs = all
        .where((c) => c.depth == 1 && c.section == root!.section)
        .toList();
    final children = all.where((c) => c.parentId == root!.categoryId).toList();
    final listId = child?.categoryId ?? root.categoryId;
    final released = _gridReleased(listId);
    return Scaffold(
      appBar: appBar,
      body: Column(
        children: [
          _RootTabs(tabs: tabs, selected: root.categoryId, onPick: _pick),
          if (_collapsed && children.isNotEmpty)
            _ChildPills(
              rootId: root.categoryId,
              children: children,
              selected: child?.categoryId,
              onPick: _pick,
            ),
          Expanded(
            child: NotificationListener<ScrollUpdateNotification>(
              onNotification: (e) {
                if (e.depth != 0 || e.metrics.axis != Axis.vertical) {
                  return false;
                }
                final c = e.metrics.pixels > _collapseAt;
                if (c != _collapsed) setState(() => _collapsed = c);
                return false;
              },
              child: ProductListView(
                key: ValueKey('category-list-$listId'),
                baseQuery: ProductQuery(categoryId: listId),
                holdList: !released,
                header: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (children.isNotEmpty)
                      _ChildCircles(
                        rootId: root.categoryId,
                        children: children,
                        selected: child?.categoryId,
                        onPick: _pick,
                      ),
                    if (released && _showBanner) const _CategoryBannerSlot(),
                    if (released && _showSale)
                      _CategorySaleRow(categoryId: listId),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 같은 구획 상위 가로 탭 — 고른 탭은 굵게 + 검정 밑줄.
class _RootTabs extends StatefulWidget {
  const _RootTabs({
    required this.tabs,
    required this.selected,
    required this.onPick,
  });

  final List<CategoryNode> tabs;
  final String selected;
  final ValueChanged<String> onPick;

  @override
  State<_RootTabs> createState() => _RootTabsState();
}

class _RootTabsState extends State<_RootTabs> {
  final _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(_RootTabs old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) _reveal();
  }

  /// 고른 탭이 화면 밖이면 보이게 굴린다.
  void _reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final c = _selectedKey.currentContext;
    if (c != null && c.mounted) {
      Scrollable.ensureVisible(c, alignment: 0.3);
    }
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: ListView(
        key: const ValueKey('category-tabs'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (final t in widget.tabs)
            InkWell(
              key: t.categoryId == widget.selected
                  ? _selectedKey
                  : ValueKey('category-tab-${t.categoryId}'),
              onTap: t.categoryId == widget.selected
                  ? null
                  : () => widget.onPick(t.categoryId),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 2,
                      color: t.categoryId == widget.selected
                          ? scheme.onSurface
                          : Colors.transparent,
                    ),
                  ),
                ),
                child: Text(
                  t.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 15,
                    fontWeight: t.categoryId == widget.selected
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: t.categoryId == widget.selected
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "☰" 세 줄(라인 아이콘에 없어 선 셋으로 그린다).
class _MenuGlyph extends StatelessWidget {
  const _MenuGlyph({required this.color, this.width = 18});

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < 3; i++)
        Container(
          width: width,
          height: 1.6,
          margin: EdgeInsets.only(top: i == 0 ? 0 : width * 0.24),
          color: color,
        ),
    ],
  );
}

/// 하위 동그라미 줄(B) — 맨 앞 "☰ 전체", 고른 것 검정 테두리·굵은 이름. 그림은 앱 그림(이름 키워드).
class _ChildCircles extends StatelessWidget {
  const _ChildCircles({
    required this.rootId,
    required this.children,
    required this.selected,
    required this.onPick,
  });

  final String rootId;
  final List<CategoryNode> children;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget item({
      required Key key,
      required bool on,
      required Widget art,
      required String label,
      required VoidCallback onTap,
    }) => InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 66,
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.surfaceContainer,
                border: Border.all(
                  width: on ? 1.6 : 1,
                  color: on ? scheme.onSurface : scheme.outlineVariant,
                ),
              ),
              alignment: Alignment.center,
              child: art,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                color: on ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 96,
          child: ListView(
            key: const ValueKey('category-children'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
            children: [
              item(
                key: const ValueKey('category-child-all'),
                on: selected == null,
                art: _MenuGlyph(color: scheme.onSurface),
                label: l10n.categoryAllShort,
                onTap: () => onPick(rootId),
              ),
              for (final c in children)
                item(
                  key: ValueKey('category-child-${c.categoryId}'),
                  on: selected == c.categoryId,
                  art: _CategoryPhoto(node: c, size: 56),
                  label: c.name,
                  onTap: () => onPick(c.categoryId),
                ),
            ],
          ),
        ),
        Container(height: 8, color: scheme.surfaceContainer),
      ],
    );
  }
}

/// 내려 볼 때(D) 탭 아래 붙는 알약 칩 줄 — "☰ 전체"(고르면 검정) + 그림 든 하위 칩, 아래 연보라 선.
class _ChildPills extends StatelessWidget {
  const _ChildPills({
    required this.rootId,
    required this.children,
    required this.selected,
    required this.onPick,
  });

  final String rootId;
  final List<CategoryNode> children;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget pill({
      required Key key,
      required bool on,
      required Widget lead,
      required String label,
      required VoidCallback onTap,
    }) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: on ? scheme.onSurface : scheme.surface,
        shape: StadiumBorder(
          side: BorderSide(
            color: on ? scheme.onSurface : scheme.outlineVariant,
          ),
        ),
        child: InkWell(
          key: key,
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(5, 4, 12, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                lead,
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 13,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                    color: on ? scheme.surface : scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Container(
      key: const ValueKey('category-pills'),
      height: 48,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(width: 3, color: scheme.primaryContainer),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
        children: [
          pill(
            key: const ValueKey('category-pill-all'),
            on: selected == null,
            lead: SizedBox(
              width: 22,
              height: 22,
              child: Center(
                child: _MenuGlyph(
                  width: 12,
                  color: selected == null ? scheme.surface : scheme.onSurface,
                ),
              ),
            ),
            label: l10n.categoryAllShort,
            onTap: () => onPick(rootId),
          ),
          for (final c in children)
            pill(
              key: ValueKey('category-pill-${c.categoryId}'),
              on: selected == c.categoryId,
              lead: _CategoryPhoto(node: c, size: 24),
              label: c.name,
              onTap: () => onPick(c.categoryId),
            ),
        ],
      ),
    );
  }
}

/// CATEGORY 배너(편성, BR-82) — 없거나 실패면 칸을 통째로 숨긴다(E-2).
class _CategoryBannerSlot extends ConsumerWidget {
  const _CategoryBannerSlot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banners = ref.watch(categoryBannersProvider).value;
    if (banners == null || banners.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: BannerPager(
        key: const ValueKey('category-list-banners'),
        banners: banners,
        onOpen: (b) => openHomeBanner(context, b, ref.read(homeProvider).value),
      ),
    );
  }
}

/// "이 카테고리의 할인 상품 전체 ›" 가로 줄(search onSale + categoryId, BR-83). 0개·읽는 중·실패면 숨김(E-2).
class _CategorySaleRow extends ConsumerWidget {
  const _CategorySaleRow({required this.categoryId});

  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items =
        ref
            .watch(
              productListProvider(
                ProductQuery(categoryId: categoryId, onSale: true),
              ),
            )
            .value
            ?.items
            .take(10)
            .toList() ??
        const <ProductTile>[];
    if (items.isEmpty) return const SizedBox.shrink();
    final width = ProductTileCard.railWidthOf(context);
    return Column(
      key: const ValueKey('category-sale'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.categorySaleTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('category-sale-all'),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onSurfaceVariant,
                  textStyle: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
                ),
                onPressed: () => context.push(
                  Uri(
                    path: '/products',
                    queryParameters: {
                      'categoryId': categoryId,
                      'onSale': 'true',
                      'title': l10n.categorySaleTitle,
                    },
                  ).toString(),
                ),
                child: Text(l10n.searchKeywordSaleAll),
              ),
            ],
          ),
        ),
        SizedBox(
          height: ProductTileCard.heightFor(context, width),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => SizedBox(
              width: width,
              child: ProductTileCard(
                rail: true,
                tile: items[i],
                onTap: () => context.push(
                  '/products/${items[i].productId}',
                  extra: items[i],
                ),
              ),
            ),
          ),
        ),
        Container(height: 8, color: scheme.surfaceContainer),
      ],
    );
  }
}

/// 하위 카테고리 동그라미 그림: 서버 대표 사진(BR-89 — 그 카테고리 인기 1위 상품, 회색 동그라미 안 contain)이
/// 있으면 그것, 없거나 읽는 중·실패면 앱 그림(이름 키워드).
class _CategoryPhoto extends ConsumerWidget {
  const _CategoryPhoto({required this.node, required this.size});

  final CategoryNode node;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final art = CategoryArt(name: node.name, size: size, radius: size / 2);
    final path = ref.watch(categoryImagesProvider).value?[node.categoryId];
    final px = size * MediaQuery.devicePixelRatioOf(context);
    final url = resolveImageUrl(
      withImageWidth(path, px),
      ref.watch(imageOriginProvider),
    );
    if (url == null) return art;
    return Container(
      key: ValueKey('category-photo-${node.categoryId}'),
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(size * 0.1),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surfaceContainer,
      ),
      child: Image.network(
        url,
        fit: BoxFit.contain,
        cacheWidth: px.round(),
        errorBuilder: (_, _, _) => art,
      ),
    );
  }
}

/// 카테고리 트리를 읽는 동안의 자리 표시 — 위 탭(46)·하위 동그라미 줄(96 + 회색 8)·상품 격자를 같은 높이로
/// 잡아 다 읽은 뒤 화면이 밀리지 않게 한다. 반짝임은 위 두 줄 하나, 격자 하나.
class _BrowseSkeleton extends StatelessWidget {
  const _BrowseSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PmartShimmer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: scheme.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < 5; i++) ...[
                      if (i > 0) const SizedBox(width: 18),
                      const PmartBone(width: 44, height: 15),
                    ],
                  ],
                ),
              ),
              SizedBox(
                height: 96,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    maxWidth: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < 6; i++)
                            const SizedBox(
                              width: 66,
                              child: Column(
                                children: [
                                  PmartBone(height: 56, circle: true),
                                  SizedBox(height: 8),
                                  PmartBone(width: 40, height: 12),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(height: 8, color: scheme.surfaceContainer),
        const Expanded(child: PmartGridSkeleton()),
      ],
    );
  }
}
