import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/cart_icon_button.dart';
import '../../../shared/ui_state_of.dart';
import '../domain/catalog.dart';
import 'catalog_providers.dart';
import 'home_screen.dart' show BannerPager, openHomeBanner;
import 'widgets/category_art.dart';

/// SCR-CATEGORY-001. 상위 → 하위 카테고리. 고르면 같은 조건의 상품 목록으로 간다.
class CategoryScreen extends ConsumerWidget {
  const CategoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      // 레퍼런스 3-3: ← 제목 + 오른쪽 홈·검색·장바구니
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: pmartLeftTitleSpacing,
        title: Text(l10n.categoryTitle),
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
      ),
      body: UiStateView<List<CategoryNode>>(
        loading: (_) =>
            const PmartListSkeleton(thumb: true, thumbSize: 44, rows: 8),
        state: uiStateOf(
          ref.watch(categoriesProvider),
          isEmpty: (n) => n.isEmpty,
        ),
        onRetry: () => ref.invalidate(categoriesProvider),
        ready: (context, nodes) {
          final roots = nodes.where((n) => n.depth == 1).toList();
          // 서버 순서를 지키며 section 별로 묶는다(처음 나온 순서). section 이 없으면 제목 없는 한 묶음.
          final groups = <String?, List<CategoryNode>>{};
          for (final r in roots) {
            (groups[r.section] ??= []).add(r);
          }
          final theme = Theme.of(context);
          // 레퍼런스(사용자 제공 카테고리 그림 2026-11-20): 줄 간격 약 46dp, 그림 32dp, 글자 15sp
          final rowHeight = MediaQuery.textScalerOf(context).scale(20) + 30;
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              // 레퍼런스 3-3 맨 위 배너(placement=CATEGORY). 없으면 자리를 비운다.
              const _CategoryBanners(),
              for (final (i, MapEntry(key: section, value: items))
                  in groups.entries.indexed) ...[
                if (i > 0) const PmartSectionGap(height: 8),
                if (section != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(15, 22, 15, 6),
                    // 레퍼런스 3-3: 구역 제목("맛있는것")은 굵지 않은 조금 큰 글자(사용자 2026-11-21 "레퍼런스 참고").
                    child: Text(
                      section,
                      key: ValueKey('category-section-$section'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisExtent: rowHeight,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, j) {
                    final root = items[j];
                    return InkWell(
                      key: ValueKey('category-${root.categoryId}'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _showChildren(context, l10n, root, nodes),
                      child: Row(
                        children: [
                          // 레퍼런스 3-3: 동그란 그림 칸.
                          CategoryArt(name: root.name, size: 34, radius: 17),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              root.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
              // 레퍼런스 3-3 아래: "B마트 추천" 타일 4개 + 고객센터 상자(사용자 2026-11-22 "7, 8 다 추가").
              const PmartSectionGap(height: 8),
              const _Picks(),
              const _SupportBox(),
            ],
          );
        },
      ),
    );
  }

  /// 상위 카테고리를 누르면 "전체" + 하위 카테고리를 아래 시트로 보인다.
  void _showChildren(
    BuildContext context,
    AppLocalizations l10n,
    CategoryNode root,
    List<CategoryNode> nodes,
  ) {
    final children = nodes.where((n) => n.parentId == root.categoryId).toList();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                root.name,
                style: Theme.of(sheet).textTheme.titleLarge,
              ),
            ),
            ListTile(
              title: Text(l10n.categoryAll(root.name)),
              trailing: const PmartLineIcon(
                PmartLineIcons.chevronRight,
                size: 18,
              ),
              onTap: () {
                Navigator.of(sheet).pop();
                _open(context, root);
              },
            ),
            for (final child in children)
              ListTile(
                key: ValueKey('category-${child.categoryId}'),
                title: Text(child.name),
                trailing: const PmartLineIcon(
                  PmartLineIcons.chevronRight,
                  size: 18,
                ),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _open(context, child);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, CategoryNode node) => context.push(
    Uri(
      path: '/products',
      queryParameters: {'categoryId': node.categoryId, 'title': node.name},
    ).toString(),
  );
}

class _CategoryBanners extends ConsumerWidget {
  const _CategoryBanners();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banners = ref.watch(categoryBannersProvider).value;
    if (banners == null || banners.isEmpty) return const SizedBox.shrink();
    return BannerPager(
      key: const ValueKey('category-banners'),
      banners: banners,
      onOpen: (b) => openHomeBanner(context, b, ref.read(homeProvider).value),
    );
  }
}

/// 추천 타일 4개(레퍼런스 "B마트 추천" — 할인·기획전·인기·신상). 갈 곳(사용자 2026-11-22):
/// 할인 = 할인 상품 목록(search 0.8.0 onSale, BR-82), 기획전 = 홈의 지금 MD 탭(없으면 홈),
/// 인기 = 홈 랭킹 탭, 신상 = 홈 신상품 탭(서버가 그 탭을 주지 않으면 홈).
class _Picks extends ConsumerWidget {
  const _Picks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    void openHome({HomeTab? tab, bool firstCustom = false}) {
      ref
          .read(homeTabRequestProvider.notifier)
          .open(tab: tab, firstCustom: firstCustom);
      context.go('/');
    }

    Widget tile({
      required String key,
      required PmartLineIcons icon,
      required String label,
      required Color background,
      required Color color,
      required VoidCallback onTap,
    }) => Expanded(
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey(key),
          onTap: onTap,
          child: SizedBox(
            height: 74,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PmartLineIcon(icon, size: 24, color: color),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 22, 15, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.categoryPicksTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 15.5,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              tile(
                key: 'category-pick-discount',
                icon: PmartLineIcons.percent,
                label: l10n.categoryPickDiscount,
                background: scheme.tertiaryContainer,
                color: scheme.tertiary,
                onTap: () => context.push(
                  Uri(
                    path: '/products',
                    queryParameters: {
                      'onSale': 'true',
                      'title': l10n.categoryPickDiscountTitle,
                    },
                  ).toString(),
                ),
              ),
              const SizedBox(width: 8),
              tile(
                key: 'category-pick-event',
                icon: PmartLineIcons.tag,
                label: l10n.categoryPickEvent,
                background: scheme.primaryContainer,
                color: scheme.primary,
                onTap: () => openHome(firstCustom: true),
              ),
              const SizedBox(width: 8),
              tile(
                key: 'category-pick-popular',
                icon: PmartLineIcons.trophy,
                label: l10n.categoryPickPopular,
                background: scheme.secondaryContainer,
                color: scheme.secondary,
                onTap: () => openHome(tab: HomeTab.ranking),
              ),
              const SizedBox(width: 8),
              tile(
                key: 'category-pick-new',
                icon: PmartLineIcons.sparkle,
                label: l10n.categoryPickNew,
                background: PmartBrand.lavenderMist,
                color: scheme.primary,
                onTap: () => openHome(tab: HomeTab.isNew),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 고객센터 상자(레퍼런스 3-3 맨 아래). 전화번호·운영시간은 업무 문서·계약에 없어 넣지 않고 앱 고객센터로
/// 보낸다(사용자 2026-11-22 "앱 고객센터 바로가기").
class _SupportBox extends StatelessWidget {
  const _SupportBox();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sub = theme.textTheme.bodySmall?.copyWith(
      fontSize: 12.5,
      color: scheme.onSurfaceVariant,
    );
    return ColoredBox(
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 16, 15, 24),
        child: Material(
          color: scheme.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('category-support'),
            onTap: () => context.push('/support'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.categorySupportTitle, style: sub),
                  const SizedBox(height: 4),
                  Text(l10n.categorySupportBody, style: sub),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(l10n.categorySupportGo, style: sub),
                      PmartLineIcon(
                        PmartLineIcons.chevronRight,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
