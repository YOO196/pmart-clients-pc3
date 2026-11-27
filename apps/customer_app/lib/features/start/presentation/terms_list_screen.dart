import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../profile/data/consents_repository.dart' show ConsentWire;
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

/// 마이·고객센터 → 약관 및 정책(사용자 레퍼런스 2026-11-26 — 목록이 늘 보이게, 안 내용은 대충).
/// 고정 목록: 이용약관·위치기반·개인정보는 서버 약관 본문(`/consent-terms` 현행 버전)이 있으면 그것을 열고,
/// 못 읽었거나 없으면 아래 시연용 글을 연다. 나머지 항목은 시연용 글(법률 검토 전 — 화면에 그렇게 적는다).
class TermsListScreen extends ConsumerWidget {
  const TermsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final server = ref.watch(consentTermsProvider).value;
    String? serverVersion(String type) => server?.items
        .where((t) => t.type == type && t.hasDocument)
        .firstOrNull
        ?.latestVersion;
    final items = <(String key, String title, String? consentType)>[
      ('business', l10n.policyBusiness, null),
      ('terms', l10n.consentTerms, ConsentWire.terms),
      ('location', l10n.consentLocation, ConsentWire.location),
      ('finance', l10n.policyFinance, null),
      ('privacy', l10n.consentPrivacy, ConsentWire.privacy),
      ('review', l10n.policyReview, null),
      ('data', l10n.policyData, null),
      ('dispute', l10n.policyDispute, null),
      ('copyright', l10n.policyCopyright, null),
    ];
    return Scaffold(
      key: const ValueKey('terms-list'),
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          l10n.termsTitle,
          style: theme.appBarTheme.titleTextStyle?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
        itemBuilder: (context, i) {
          final (key, title, type) = items[i];
          final version = type == null ? null : serverVersion(type);
          return InkWell(
            key: ValueKey('terms-$key'),
            onTap: () => version != null
                ? context.push(StartRoutes.terms(type!, version))
                : Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          _SamplePolicyScreen(title: title, policyKey: key),
                    ),
                  ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(fontSize: 17),
                    ),
                  ),
                  PmartLineIcon(
                    PmartLineIcons.chevronRight,
                    size: 22,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 시연용 약관 글(사용자 "안에 내용은 대충 적어") — 맨 위에 시연용 초안임을 적는다.
class _SamplePolicyScreen extends StatelessWidget {
  const _SamplePolicyScreen({required this.title, required this.policyKey});

  final String title;
  final String policyKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      key: ValueKey('terms-sample-$policyKey'),
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              l10n.policySampleNotice,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.policySampleBody(title),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 15,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }
}
