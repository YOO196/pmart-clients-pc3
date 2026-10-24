import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers.dart';
import '../../../shared/ui_state_of.dart';
import '../data/mock_offer_repository.dart';
import '../data/offer_repository.dart';
import '../domain/offer_list.dart';

final offerRepositoryProvider = Provider<OfferRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockOfferRepository(),
    PmartEnv.local => ApiOfferRepository(ref.watch(dioProvider)),
  },
);

/// 한 번 조회. `pollAfterSec` 에 따른 폴링·즉시 조회 시점은 C2 에서 붙인다(rider-app.md).
final activeOffersProvider = FutureProvider<OfferList>(
  (ref) => ref.watch(offerRepositoryProvider).activeOffers(),
);

class OffersScreen extends ConsumerWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mock = ref.watch(envProvider) == PmartEnv.mock;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.offersTitle),
        actions: [
          if (mock)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(label: Text(l10n.mockModeBadge)),
            ),
        ],
      ),
      body: UiStateView<OfferList>(
        state: uiStateOf(
          ref.watch(activeOffersProvider),
          isEmpty: (l) => l.offers.isEmpty,
        ),
        onRetry: () => ref.invalidate(activeOffersProvider),
        empty: (_) => Center(child: Text(l10n.offersEmpty)),
        ready: (context, list) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (list.pollAfter == null)
              ListTile(
                leading: const Icon(Icons.pause_circle_outline),
                title: Text(l10n.pollingStopped),
              ),
            for (final offer in list.offers)
              Card(
                key: ValueKey('offer-${offer.offerId}'),
                child: ListTile(
                  title: Text(switch (offer.remainingSec) {
                    final int s => l10n.offerRemaining(s),
                    null => l10n.offerRemainingUnknown,
                  }),
                  subtitle: Text(
                    [
                      if (offer.dropAreaLabel case final label?)
                        l10n.offerDropArea(label),
                      if (offer.estimatedFee case final fee?)
                        l10n.offerFee(formatKrw(fee)),
                    ].join('\n'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
