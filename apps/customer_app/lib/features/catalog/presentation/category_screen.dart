import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/cart_icon_button.dart';
import '../../../shared/ui_state_of.dart';
import '../domain/catalog.dart';
import 'category_browse_screen.dart' show openCategoryBrowse;
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
        // 아래 탭으로 열면 ← 가 없어 제목이 왼쪽 끝에 붙는다 — 아래 구획 제목·홈과 같은 16 을 띄운다(사용자 2026-11-24).
        titleSpacing: context.canPop() ? pmartLeftTitleSpacing : 16,
        // 레퍼런스 상단바(태블릿 나란히 보기 2026-11-26): 제목 굵게, 아이콘 크고 선 굵게(사용자 "너무 얇아").
        title: Text(
          l10n.categoryTitle,
          style: Theme.of(context).appBarTheme.titleTextStyle
              ?.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: l10n.navHome,
            icon: const PmartLineIcon(
              PmartLineIcons.home,
              size: 25,
              strokeWidth: 2.3,
            ),
            onPressed: () => context.go('/'),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: l10n.searchTitle,
            icon: const PmartLineIcon(
              PmartLineIcons.search,
              size: 25,
              strokeWidth: 2.3,
            ),
            onPressed: () => context.push('/search'),
          ),
          const CartIconButton(size: 25, strokeWidth: 2.3),
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
          // 사용자 폰 캡처(2026-11-26, 1080px = 411dp): 줄 간격 52, 그림 36(둥근 네모), 글자 14, 두 칸 사이 12.2.
          final rowHeight = MediaQuery.textScalerOf(context).scale(20) + 32;
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
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12.2,
                    mainAxisExtent: rowHeight,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, j) {
                    final root = items[j];
                    return InkWell(
                      key: ValueKey('category-${root.categoryId}'),
                      borderRadius: BorderRadius.circular(14),
                      // 초안 15 B: 시트 없이 바로 카테고리 화면(전체).
                      onTap: () => _open(context, root),
                      child: Row(
                        children: [
                          CategoryArt(name: root.name, size: 36, radius: 10),
                          const SizedBox(width: 10.8),
                          Expanded(
                            child: Text(
                              root.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: theme.colorScheme.onSurface,
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

  void _open(BuildContext context, CategoryNode node) =>
      openCategoryBrowse(context, node.categoryId, title: node.name);
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
    void openHome({HomeTab? tab, bool firstCustom = false, bool sale = false}) {
      ref
          .read(homeTabRequestProvider.notifier)
          .open(tab: tab, firstCustom: firstCustom, sale: sale);
      context.go('/');
    }

    // 사용자 폰 캡처(2026-11-26): 타일 83.7×69.6(모서리 12, 사이 6.5, 가로로 넘김), 그림 약 24(위 12),
    // 글 14 굵게(위 47). 그림은 캡처에서 자른 것.
    Widget tile({
      required String key,
      required String art,
      required String label,
      required Color background,
      required Color color,
      required VoidCallback onTap,
    }) => Padding(
      padding: const EdgeInsets.only(right: 6.5),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey(key),
          onTap: onTap,
          child: SizedBox(
            width: 83.7,
            height: 69.6,
            child: Column(
              children: [
                const SizedBox(height: 10.5),
                Image.asset(
                  'assets/images/category_picks/$art.png',
                  height: 25,
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              l10n.categoryPicksTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                tile(
                  key: 'category-pick-discount',
                  art: 'discount',
                  label: l10n.categoryPickDiscount,
                  background: const Color(0xFFFEEEEF),
                  color: const Color(0xFF5A2221),
                  onTap: () => openHome(sale: true),
                ),
                tile(
                  key: 'category-pick-event',
                  art: 'event',
                  label: l10n.categoryPickEvent,
                  background: const Color(0xFFEEF0FF),
                  color: const Color(0xFF140B40),
                  onTap: () => openHome(firstCustom: true),
                ),
                tile(
                  key: 'category-pick-popular',
                  art: 'popular',
                  label: l10n.categoryPickPopular,
                  background: const Color(0xFFFFF3E5),
                  color: const Color(0xFF643501),
                  onTap: () => openHome(tab: HomeTab.ranking),
                ),
                tile(
                  key: 'category-pick-new',
                  art: 'new',
                  label: l10n.categoryPickNew,
                  background: const Color(0xFFFFF9E6),
                  color: const Color(0xFF654E00),
                  onTap: () => openHome(tab: HomeTab.isNew),
                ),
              ],
            ),
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
    // 사용자 폰 캡처(2026-11-26): 회색 바탕(#F4F5F7) 안 테두리 상자(#E5E6E8, 좌우 15), 글 13.5 회색(#7E7F81)
    // 줄 간격 18.3, 안쪽 12.
    final sub = theme.textTheme.bodySmall?.copyWith(
      fontSize: 13.5,
      height: 1.35,
      color: const Color(0xFF7E7F81),
    );
    return ColoredBox(
      color: const Color(0xFFF4F5F7),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 20, 15, 32),
        child: Material(
          color: const Color(0xFFF4F5F7),
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFFE5E6E8)),
            borderRadius: BorderRadius.circular(4),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('category-support'),
            onTap: () => context.push('/support'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
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
                      const PmartLineIcon(
                        PmartLineIcons.chevronRight,
                        size: 14,
                        color: Color(0xFF7E7F81),
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
