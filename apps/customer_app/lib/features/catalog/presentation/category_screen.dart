import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/cart_icon_button.dart';
import '../../../shared/ui_state_of.dart';
import '../domain/catalog.dart';
import 'catalog_providers.dart';
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
          final rowHeight = MediaQuery.textScalerOf(context).scale(20) + 26;
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (final (i, MapEntry(key: section, value: items))
                  in groups.entries.indexed) ...[
                if (i > 0) const PmartSectionGap(height: 8),
                if (section != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(15, 18, 15, 4),
                    child: Text(
                      section,
                      key: ValueKey('category-section-$section'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
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
                          CategoryArt(name: root.name, size: 32, radius: 10),
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
