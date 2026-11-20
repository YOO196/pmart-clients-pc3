import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../../profile/data/consents_repository.dart' show ConsentWire;
import '../data/device_consents_repository.dart';
import 'start_controller.dart';

/// 약관 이름(서버 항목 코드 → 화면 이름). 모르는 항목은 서버 코드 그대로(지어내지 않는다).
String consentTermTitle(AppLocalizations l10n, String type) => switch (type) {
  ConsentWire.terms => l10n.consentTerms,
  ConsentWire.privacy => l10n.consentPrivacy,
  ConsentWire.age14 => l10n.consentAge14,
  ConsentWire.marketing => l10n.consentMarketing,
  ConsentWire.location => l10n.consentLocation,
  _ => type,
};

/// 마이 → 약관 및 정책(사용자 2026-11-20 "약관 볼 수 있게"). 로그인하지 않아도 본다.
/// 목록은 서버 약관 목록(`GET /consent-terms` — 현행 버전), 누르면 본문(`/consent-terms/{항목}/{버전}`).
/// 본문이 없는 항목은 누를 수 없다. 조회 실패는 빈 목록이 아니라 실패 + 다시 시도.
class TermsListScreen extends ConsumerWidget {
  const TermsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final value = ref.watch(consentTermsProvider);
    return Scaffold(
      key: const ValueKey('terms-list'),
      appBar: AppBar(title: Text(l10n.termsTitle)),
      body: UiStateView<ConsentTerms>(
        state: uiStateOf(value, isEmpty: (t) => t.items.isEmpty),
        onRetry: () => ref.invalidate(consentTermsProvider),
        empty: (_) => Center(child: Text(l10n.termsEmpty)),
        ready: (context, terms) => ListView(
          children: [
            for (final t in terms.items)
              ListTile(
                key: ValueKey('terms-${t.type}'),
                title: Text(consentTermTitle(l10n, t.type)),
                subtitle: Text(
                  l10n.termsVersion(t.latestVersion),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: t.hasDocument
                    ? const PmartLineIcon(PmartLineIcons.chevronRight, size: 18)
                    : null,
                enabled: t.hasDocument,
                onTap: t.hasDocument
                    ? () => context.push(
                        StartRoutes.terms(t.type, t.latestVersion),
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}
