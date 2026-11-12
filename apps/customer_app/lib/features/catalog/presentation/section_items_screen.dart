import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import 'catalog_providers.dart';
import 'home_providers.dart';
import 'product_list_view.dart' show ProductGrid;

/// 진열 영역 "전체보기". 같은 영역의 상품을 `GET /storefront/sections/{id}/items` 로 이어 받는다.
/// 홈 구성이 바뀌었으면(LAYOUT_VERSION_CHANGED) 오류로 보이고 홈을 다시 받는다.
class SectionItemsScreen extends ConsumerWidget {
  const SectionItemsScreen({super.key, required this.target});

  final SectionRef target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final provider = sectionItemsProvider(target);
    final value = ref.watch(provider);
    return Scaffold(
      appBar: AppBar(title: Text(target.section.title)),
      body: UiStateView<ProductListState>(
        state: uiStateOf(value, isEmpty: (s) => s.items.isEmpty),
        onRetry: () => ref.invalidate(provider),
        empty: (_) => Center(child: Text(l10n.sectionEmpty)),
        ready: (context, list) => ProductGrid(
          key: ValueKey('section-items-${target.section.sectionId}'),
          list: list,
          onLoadMore: () => ref.read(provider.notifier).loadMore(),
        ),
      ),
    );
  }
}
