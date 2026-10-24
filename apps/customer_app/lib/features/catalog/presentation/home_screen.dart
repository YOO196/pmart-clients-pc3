import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers.dart';
import '../../../shared/ui_state_of.dart';
import '../domain/catalog.dart';
import 'catalog_providers.dart';
import 'widgets/product_tile_card.dart';

/// SCR-HOME-001. 영역별 부분 실패는 그 영역만 다시 불러온다.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mock = ref.watch(envProvider) == PmartEnv.mock;
    final state = uiStateOf(
      ref.watch(homeProvider),
      isEmpty: (h) => h.sections.isEmpty && h.banners.isEmpty,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeTitle),
        actions: [
          if (mock)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(label: Text(l10n.mockModeBadge)),
            ),
        ],
      ),
      body: UiStateView<HomeView>(
        state: state,
        onRetry: () => ref.invalidate(homeProvider),
        ready: (context, home) => RefreshIndicator(
          onRefresh: () => ref.refresh(homeProvider.future),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              for (final b in home.banners) _BannerCard(b),
              for (final s in home.sections)
                _SectionView(
                  key: ValueKey('section-${s.sectionId}'),
                  section: s,
                  layoutVersion: home.layoutVersion,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard(this.banner);

  final HomeBanner banner;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: SizedBox(
        height: 96,
        child: Center(
          child: Text(
            banner.altText ?? '',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
    ),
  );
}

class _SectionView extends ConsumerWidget {
  const _SectionView({
    super.key,
    required this.section,
    required this.layoutVersion,
  });

  final HomeSection section;
  final int layoutVersion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final retry = ref.watch(sectionRetryProvider(section.sectionId));
    final shown = switch (retry) {
      AsyncData(:final value) => value,
      _ => section,
    };
    final Widget body;
    if (shown.available) {
      body = shown.items.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.sectionEmpty),
            )
          : SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: shown.items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 4),
                itemBuilder: (context, i) => SizedBox(
                  width: 280,
                  child: ProductTileCard(
                    tile: shown.items[i],
                    onTap: () =>
                        context.push('/products/${shown.items[i].productId}'),
                  ),
                ),
              ),
            );
    } else {
      final loading = retry?.isLoading ?? false;
      body = Padding(
        key: ValueKey('section-unavailable-${section.sectionId}'),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            const Icon(Icons.error_outline),
            const SizedBox(width: 8),
            Expanded(child: Text(l10n.sectionUnavailable)),
            TextButton(
              onPressed: loading
                  ? null
                  : () => ref
                        .read(sectionRetryProvider(section.sectionId).notifier)
                        .retry(section, layoutVersion),
              child: loading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.sectionRetry),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              section.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          body,
        ],
      ),
    );
  }
}
