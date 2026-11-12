import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
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
      appBar: AppBar(title: Text(l10n.categoryTitle)),
      body: UiStateView<List<CategoryNode>>(
        state: uiStateOf(
          ref.watch(categoriesProvider),
          isEmpty: (n) => n.isEmpty,
        ),
        onRetry: () => ref.invalidate(categoriesProvider),
        ready: (context, nodes) {
          final roots = nodes.where((n) => n.depth == 1).toList();
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(15, 10, 15, 24),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisExtent: MediaQuery.textScalerOf(context).scale(19) + 30,
            ),
            itemCount: roots.length,
            itemBuilder: (context, i) {
              final root = roots[i];
              final theme = Theme.of(context);
              return InkWell(
                key: ValueKey('category-${root.categoryId}'),
                borderRadius: BorderRadius.circular(14),
                onTap: () => _showChildren(context, l10n, root, nodes),
                child: Row(
                  children: [
                    CategoryArt(name: root.name, size: 36, radius: 11),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        root.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              );
            },
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
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(sheet).pop();
                _open(context, root);
              },
            ),
            for (final child in children)
              ListTile(
                key: ValueKey('category-${child.categoryId}'),
                title: Text(child.name),
                trailing: const Icon(Icons.chevron_right),
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
