import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../start/presentation/start_controller.dart' show StartRoutes;
import '../../../shared/providers.dart';
import '../../../shared/ui_state_of.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/consents_repository.dart';
import '../../../shared/notice.dart';

final consentsRepositoryProvider = Provider<ConsentsRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockConsentsRepository(),
    PmartEnv.local => ApiConsentsRepository(ref.watch(dioProvider)),
  },
);

/// 내 동의. 비회원이면 null. 실패는 실패로 남는다.
final myConsentsProvider = FutureProvider.autoDispose<MyConsents?>((ref) async {
  if (ref.watch(sessionProvider) is! MemberSession) return null;
  return ref.watch(consentsRepositoryProvider).list();
});

String consentTypeLabel(AppLocalizations l10n, String type) => switch (type) {
  ConsentWire.terms => l10n.consentTerms,
  ConsentWire.privacy => l10n.consentPrivacy,
  ConsentWire.age14 => l10n.consentAge14,
  ConsentWire.marketing => l10n.consentMarketing,
  ConsentWire.location => l10n.consentLocation,
  // 모르는 항목은 서버 코드 그대로(지어내지 않는다)
  _ => type,
};

/// 동의를 바꾼다. 결과를 모르면 같은 키로 한 번 더 보낸다(계약: 같은 키는 같은 결과).
Future<CommandStatus> sendConsentChanges(
  ConsentsRepository repo,
  List<ConsentChange> changes,
) async {
  final key = IdempotencyKey.generate();
  try {
    return await repo.change(changes, key: key);
  } on UnknownResultFailure {
    return repo.change(changes, key: key);
  }
}

/// 주문 전 확인(백엔드 알림 2026-11-17 consents §3): 로그인해 있는 고객의 필수 동의가 지금 버전이 아니면
/// 같은 동의 화면을 보이고 `POST /me/consent-changes` 로 받는다. 동의했으면(또는 확인할 필요가 없으면) true.
/// 조회 실패는 막지 않는다 — 서버가 최종 판정한다(구매 불가면 초안이 422 ACCOUNT_NOT_PURCHASABLE).
Future<bool> ensureCurrentConsents(BuildContext context, WidgetRef ref) async {
  final MyConsents consents;
  try {
    consents = await ref.read(consentsRepositoryProvider).list();
  } on PmartFailure {
    return true;
  }
  if (!consents.requiredOutdated || !context.mounted) return true;
  final ok = await context.push<bool>('/me/consents/reconsent');
  return ok == true;
}

/// 재동의 화면(SCR-CONSENT-001, 로그인 동의 화면과 같은 모양). 필수는 모두 체크해야 버튼이 켜진다.
/// 선택(마케팅)은 지금 값에서 시작하고 끈 것도 false 로 보낸다.
class ReconsentScreen extends ConsumerStatefulWidget {
  const ReconsentScreen({super.key});

  @override
  ConsumerState<ReconsentScreen> createState() => _ReconsentScreenState();
}

class _ReconsentScreenState extends ConsumerState<ReconsentScreen> {
  final _agreed = <String>{};
  bool _seeded = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit(MyConsents c) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final changes = [
      // 기능 필수(위치 약관)는 이 화면에서 묻지 않는다 — 보내지도 않는다.
      for (final i in c.items.where((i) => i.requiredFor == null))
        if (i.required)
          ConsentChange(i.type, i.latestVersion, agreed: true)
        else
          ConsentChange(
            i.type,
            i.latestVersion,
            agreed: _agreed.contains(i.type),
          ),
    ];
    String? error;
    var done = false;
    try {
      final status = await sendConsentChanges(
        ref.read(consentsRepositoryProvider),
        changes,
      );
      if (status == CommandStatus.applied) {
        done = true;
      } else {
        // 접수만 됐거나 거절 — 서버 상태를 다시 읽어 판단한다.
        final again = await ref.read(consentsRepositoryProvider).list();
        done = !again.requiredOutdated;
        if (!done) error = l10n.consentUnknown;
      }
    } on ProblemFailure catch (f) {
      if (f.problem.code == ConsentProblemCode.versionOutdated) {
        // 그 사이 약관 버전이 바뀌었다 — 새 목록으로 다시 묻는다.
        ref.invalidate(myConsentsProvider);
        _seeded = false;
        error = l10n.consentVersionChanged;
      } else {
        error = l10n.loginRejected;
      }
    } on PmartFailure {
      error = l10n.consentUnknown;
    }
    if (!mounted) return;
    ref.invalidate(myConsentsProvider);
    if (done) {
      context.canPop() ? context.pop(true) : context.go('/');
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final value = ref.watch(myConsentsProvider);
    // 레퍼런스 13-9(약관 시트): 굵은 2줄 제목 + ✕, 묶음 제목, 줄마다 [보기], 아래 [전체 동의하고 계속하기].
    // 필수는 하나씩 체크하지 않고 아래 단추 한 번으로 모두 동의한다(사용자 결정 2026-11-20). 선택은 체크로 고른다.
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: UiStateView<MyConsents?>(
          state: uiStateOf(value),
          onRetry: () => ref.invalidate(myConsentsProvider),
          ready: (context, c) {
            if (c == null) return const SizedBox.shrink();
            if (!_seeded) {
              _seeded = true;
              _agreed
                ..clear()
                ..addAll([
                  for (final i in c.items)
                    if (!i.required && i.current) i.type,
                ]);
            }
            final required = c.items.where((i) => i.required).toList();
            final optional = c.items
                .where((i) => !i.required && i.requiredFor == null)
                .toList();
            Widget view(MyConsent i) => ActionChip(
              key: ValueKey('reconsent-view-${i.type}'),
              label: Text(l10n.consentView),
              labelStyle: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
              backgroundColor: theme.colorScheme.surfaceContainer,
              side: BorderSide.none,
              shape: const StadiumBorder(),
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  context.push(StartRoutes.terms(i.type, i.latestVersion)),
            );
            Widget row(MyConsent i, String title, {Widget? lead}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  lead ??
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 10, 0),
                        child: Container(
                          width: 4,
                          height: 4,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 15,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  view(i),
                ],
              ),
            );
            Widget group(String text) => Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 6),
              child: Text(
                text,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
            return SingleChildScrollView(
              key: const ValueKey('reconsent-sheet'),
              padding: const EdgeInsets.fromLTRB(20, 22, 12, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          l10n.consentReconsentTitle,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 20,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('reconsent-close'),
                        tooltip: l10n.actionClose,
                        icon: const PmartLineIcon(
                          PmartLineIcons.close,
                          size: 24,
                        ),
                        onPressed: _busy
                            ? null
                            // 바로 열린 경우(뒤에 화면 없음)는 홈으로.
                            : () => context.canPop()
                                  ? context.pop(false)
                                  : context.go('/'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.consentReconsentBody,
                    key: const ValueKey('reconsent-body'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (required.isNotEmpty) group(l10n.consentGroupRequired),
                  for (final i in required)
                    KeyedSubtree(
                      key: ValueKey('reconsent-${i.type}'),
                      child: row(
                        i,
                        l10n.consentRequired(consentTypeLabel(l10n, i.type)),
                      ),
                    ),
                  if (optional.isNotEmpty) group(l10n.consentGroupOptional),
                  for (final i in optional)
                    row(
                      i,
                      l10n.consentOptional(consentTypeLabel(l10n, i.type)),
                      lead: SizedBox(
                        width: 32,
                        child: Checkbox(
                          key: ValueKey('reconsent-${i.type}'),
                          value: _agreed.contains(i.type),
                          visualDensity: VisualDensity.compact,
                          onChanged: _busy
                              ? null
                              : (v) => setState(
                                  () => (v ?? false)
                                      ? _agreed.add(i.type)
                                      : _agreed.remove(i.type),
                                ),
                        ),
                      ),
                    ),
                  if (_error case final e?) ...[
                    const SizedBox(height: 8),
                    Text(
                      e,
                      key: const ValueKey('reconsent-error'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton(
                      key: const ValueKey('reconsent-submit'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _busy ? null : () => _submit(c),
                      child: Text(l10n.consentAgreeAllContinue),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 설정의 "마케팅 정보 수신 동의" 켜고 끄기(customer 0.3.0 — notification 의 marketingConsent 는 아직 UNKNOWN).
/// 서버가 APPLIED 로 답한 뒤에만 바뀐 값으로 보인다.
class MarketingConsentTile extends ConsumerStatefulWidget {
  const MarketingConsentTile({super.key});

  @override
  ConsumerState<MarketingConsentTile> createState() =>
      _MarketingConsentTileState();
}

class _MarketingConsentTileState extends ConsumerState<MarketingConsentTile> {
  bool _busy = false;

  Future<void> _toggle(MyConsent m, bool on) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    String? message;
    try {
      final status = await sendConsentChanges(
        ref.read(consentsRepositoryProvider),
        [ConsentChange(m.type, m.latestVersion, agreed: on)],
      );
      if (status != CommandStatus.applied) message = l10n.consentUnknown;
    } on PmartFailure {
      message = l10n.marketingConsentFailed;
    }
    if (!mounted) return;
    // 서버 값이 정본이다. 바꿨든 못 했든 다시 읽는다.
    ref.invalidate(myConsentsProvider);
    setState(() => _busy = false);
    if (message != null) {
      showNotice(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(myConsentsProvider);
    final marketing = value.value?.marketing;
    return SwitchListTile(
      key: const ValueKey('settings-marketing-consent'),
      title: Text(l10n.noticeMarketingConsent),
      // 못 읽었으면 꺼짐으로 보이지 않는다 — 스위치를 막고 안내한다.
      subtitle: switch (value) {
        AsyncError() => Text(l10n.marketingConsentLoadFailed),
        AsyncLoading() => Text(l10n.noticeValueUnknown),
        _ => null,
      },
      value: marketing?.current ?? false,
      onChanged: (marketing == null || _busy)
          ? null
          : (on) => _toggle(marketing, on),
    );
  }
}
