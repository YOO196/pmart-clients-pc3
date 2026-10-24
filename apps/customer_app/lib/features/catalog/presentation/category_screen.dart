import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../domain/catalog.dart';
import 'catalog_providers.dart';

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
          return ListView(
            children: [
              for (final root in roots)
                ExpansionTile(
                  key: ValueKey('category-${root.categoryId}'),
                  title: Text(root.name),
                  children: [
                    ListTile(
                      title: Text(l10n.categoryAll(root.name)),
                      onTap: () => _open(context, root),
                    ),
                    for (final child in nodes.where(
                      (n) => n.parentId == root.categoryId,
                    ))
                      ListTile(
                        key: ValueKey('category-${child.categoryId}'),
                        title: Text(child.name),
                        onTap: () => _open(context, child),
                      ),
                  ],
                ),
            ],
          );
        },
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
