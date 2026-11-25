import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../address/presentation/logout_flow.dart'
    show prepareKeepAddressAsGuest;
import '../../start/presentation/start_controller.dart'
    show logoutKeepingAddressProvider;
import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/notice.dart';
import '../../../shared/providers.dart';
import '../../../shared/ui_state_of.dart';
import '../../auth/data/auth_repository.dart' show SocialProviderDown;
import '../../auth/data/google_token_source.dart'
    show SocialProviderMisconfigured;
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../orders/presentation/my_screen.dart' show providerName;
import '../../profile/data/mock_profile_repository.dart';
import '../../profile/presentation/profile_controller.dart';
import '../data/withdrawal_repository.dart';
import '../domain/withdrawal.dart';

final withdrawalRepositoryProvider = Provider<WithdrawalRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockWithdrawalRepository(),
    PmartEnv.local => ApiWithdrawalRepository(ref.watch(dioProvider)),
  },
);

/// 내 탈퇴 기록(최근 것부터). 비회원이면 null — 부르지 않는다.
final myWithdrawalsProvider = FutureProvider.autoDispose<List<Withdrawal>?>((
  ref,
) async {
  if (ref.watch(sessionProvider) is! MemberSession) return null;
  return ref.watch(withdrawalRepositoryProvider).list();
});

/// 회원 탈퇴(customer 0.12.0, ADR-0077 — 백엔드 요청 2026-11-20 customer-withdrawal).
///
/// 안내 → 사유(선택) → **같은 소셜로 다시 로그인**(재인증) → 접수. 서버가 확정한 상태만 보인다:
/// 완료면 이 기기의 로그인 정보를 지우고 홈으로, 진행 중 주문·환불이 있으면 "탈퇴 처리 대기",
/// 서버가 아직 모르면 "확인 중". 대기 중에는 같은 재인증으로 철회할 수 있다.
class WithdrawalScreen extends ConsumerStatefulWidget {
  const WithdrawalScreen({super.key});

  @override
  ConsumerState<WithdrawalScreen> createState() => _WithdrawalScreenState();
}

class _WithdrawalScreenState extends ConsumerState<WithdrawalScreen> {
  final _text = TextEditingController();
  WithdrawalReason? _reason;
  bool _agreed = false;
  bool _busy = false;
  String? _error;

  /// 결과를 모르는 접수·철회 — 같은 키·같은 토큰으로 다시 보낸다(두 번 접수되지 않게). 메모리에만.
  IdempotencyKey? _key;
  String? _token;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// 재인증할 소셜: 서버가 아는 가입 제공자가 먼저, 없으면 이번에 로그인한 제공자.
  SocialProvider? _provider() =>
      ref.read(profileProvider).value?.socialProvider ??
      switch (ref.read(sessionProvider)) {
        MemberSession(:final provider) => provider,
        _ => null,
      };

  /// 재인증해 받은 토큰으로 [send] 를 보낸다. 고객이 로그인 화면을 닫으면 아무 일도 없다(null).
  /// 구글 탈퇴 재인증 때 받은 접근 토큰(BR-105) — 같은 탈퇴 재전송에 같이 쓴다. 로그 금지.
  String? _accessToken;

  Future<Withdrawal?> _reauthAndSend(
    Future<Withdrawal> Function(
      SocialProvider provider,
      String token,
      IdempotencyKey key,
    )
    send,
  ) async {
    final l10n = AppLocalizations.of(context);
    final provider = _provider();
    if (provider == null) {
      setState(() => _error = l10n.wdNoProvider);
      return null;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_token == null) {
        final credential = await ref
            .read(socialTokenSourceProvider)
            // 네이버는 서버가 교환 뒤 앱 연결을 끊는다(auth 0.11.0, BR-74).
            .obtain(provider, withdrawal: true);
        _token = credential?.token;
        // 구글은 접근 토큰도 — 서버가 연결을 끊는다(BR-105). 없으면 없이.
        _accessToken = credential?.accessToken;
      }
      final token = _token;
      if (token == null) return null; // 로그인 화면을 닫음
      final key = _key ??= IdempotencyKey.generate();
      Withdrawal w;
      try {
        w = await send(provider, token, key);
      } on UnknownResultFailure {
        w = await send(provider, token, key);
      }
      _key = null;
      _token = null;
      _accessToken = null;
      return w;
    } on SocialProviderDown {
      _error = l10n.wdReauthFailed;
    } on SocialProviderMisconfigured {
      _error = l10n.wdReauthFailed;
    } on ProblemFailure catch (f) {
      // 서버가 답했다 — 다음 시도는 새 키·새 토큰으로.
      _key = null;
      _token = null;
      _accessToken = null;
      switch (f.problem.code) {
        case WithdrawalProblemCode.providerRejected:
          _error = l10n.wdReauthRejected;
        case WithdrawalProblemCode.reauthenticationMismatch:
          _error = l10n.wdReauthMismatch(providerName(l10n, provider));
        case WithdrawalProblemCode.invalidState:
          // 이미 신청했거나 이미 끝났다 — 서버 상태를 다시 읽어 보인다.
          ref.invalidate(myWithdrawalsProvider);
          _error = l10n.wdStateChanged;
        default:
          _error = l10n.wdFailed;
      }
    } on PmartFailure {
      // 결과를 모른다(연결·시간 초과·5xx) — 접수됐다고도 안 됐다고도 하지 않는다. 같은 키로 다시 누를 수 있다.
      _error = l10n.wdTryLater;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return null;
  }

  Future<void> _request() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final text = _text.text.trim();
    final provider = _provider();
    final container = ProviderScope.containerOf(context, listen: false);
    // 탈퇴 뒤에도 지금 주소로 둘러보게 — 회원 토큰이 있을 때 주소를 읽어 둔다(탈퇴가 끝나면 읽을 수 없다).
    final keepAddress = await prepareKeepAddressAsGuest(context, ref);
    if (!mounted) return;
    final w = await _reauthAndSend(
      (provider, token, key) => ref
          .read(withdrawalRepositoryProvider)
          .request(
            provider: provider,
            providerToken: token,
            reasonCode: _reason?.code,
            reasonText: text.isEmpty ? null : text,
            key: key,
            providerAccessToken: _accessToken,
          ),
    );
    if (w == null || !mounted) return;
    // 서버가 탈퇴를 받아들였다 — 로그인 제공자와의 앱 연결(동의)을 끊어 다시 가입할 때 동의 화면이 다시 뜨게
    // (백엔드 요청 2026-11-21: 동의는 처음 가입 때만, 카카오·네이버는 서버가 끊고 구글만 앱이). 실패·취소면 여기까지 오지 않는다.
    // 끊기 실패는 탈퇴 흐름을 막지 않는다(forget 은 던지지 않는다).
    if (provider != null && w.state != WithdrawalState.revoked) {
      await ref.read(socialTokenSourceProvider).forget(provider, revoke: true);
      if (!mounted) return;
    }
    if (w.state.done) {
      // 서버가 세션을 끊었다 — 이 기기의 로그인 정보만 지운다(서버에 더 묻지 않는다).
      // 주소 옮기기가 끝날 때까지 주소 입력 화면으로 보내지 않는다(로그아웃과 같다).
      final hold = container.read(logoutKeepingAddressProvider.notifier)
        ..set(true);
      try {
        await ref.read(sessionProvider.notifier).forgetLocalSession();
        await keepAddress?.call();
      } finally {
        hold.set(false);
      }
      router.go('/');
      messenger.notice(l10n.wdCompleted);
      return;
    }
    syncMockWithdrawPending(ref, pending: true);
    _refresh();
  }

  Future<void> _revoke(Withdrawal current) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final w = await _reauthAndSend(
      (provider, token, key) => ref
          .read(withdrawalRepositoryProvider)
          .revoke(
            current.withdrawalId,
            provider: provider,
            providerToken: token,
            key: key,
          ),
    );
    if (w == null || !mounted) return;
    if (w.state == WithdrawalState.revoked) {
      syncMockWithdrawPending(ref, pending: false);
      messenger.notice(l10n.wdRevoked);
    }
    _refresh();
  }

  void _refresh() {
    ref.invalidate(myWithdrawalsProvider);
    // 계정 상태(탈퇴 대기 띠)도 서버 기준으로 다시 읽는다.
    ref.invalidate(profileProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(myWithdrawalsProvider);
    return Scaffold(
      key: const ValueKey('withdrawal'),
      appBar: AppBar(title: Text(l10n.wdTitle)),
      body: UiStateView<List<Withdrawal>?>(
        state: uiStateOf(value),
        onRetry: () => ref.invalidate(myWithdrawalsProvider),
        ready: (context, list) {
          // 끝나지 않은 접수가 있으면 그 상태를, 없으면 탈퇴 안내를 보인다.
          final current = list?.where((w) => w.state.waiting).firstOrNull;
          return current == null ? _form(l10n) : _status(l10n, current);
        },
      ),
    );
  }

  Widget _section(String title, List<String> lines) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '• $line',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _errorText() {
    final e = _error;
    if (e == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        e,
        key: const ValueKey('wd-error'),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }

  Widget _form(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final provider = _provider();
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('wd-form'),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            children: [
              Text(
                l10n.wdHeadline,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 22),
              _section(l10n.wdErasedTitle, [l10n.wdErased1, l10n.wdErased2]),
              _section(l10n.wdKeptTitle, [l10n.wdKept1]),
              _section(l10n.wdNoteTitle, [
                l10n.wdNote1,
                l10n.wdNote2,
                l10n.wdNote3,
              ]),
              const Divider(height: 24),
              Text(
                l10n.wdReasonTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in WithdrawalReason.values)
                    ChoiceChip(
                      key: ValueKey('wd-reason-${r.name}'),
                      label: Text(_reasonText(l10n, r)),
                      selected: _reason == r,
                      onSelected: _busy
                          ? null
                          : (on) => setState(() {
                              _reason = on ? r : null;
                              // 고른 값이 바뀌면 새 요청이다.
                              _key = null;
                            }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('wd-reason-text'),
                controller: _text,
                enabled: !_busy,
                maxLength: withdrawalReasonTextMax,
                maxLines: 3,
                onChanged: (_) => _key = null,
                decoration: InputDecoration(
                  hintText: l10n.wdReasonHint,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              InkWell(
                key: const ValueKey('wd-agree'),
                onTap: _busy ? null : () => setState(() => _agreed = !_agreed),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _agreed,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _agreed = v ?? false),
                      ),
                      Expanded(child: Text(l10n.wdAgree)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _errorText(),
                FilledButton(
                  key: const ValueKey('wd-submit'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  onPressed: (_agreed && !_busy) ? _request : null,
                  child: Text(
                    provider == null
                        ? l10n.wdSubmit
                        : l10n.wdSubmitWith(providerName(l10n, provider)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _status(AppLocalizations l10n, Withdrawal w) {
    final theme = Theme.of(context);
    final blocked = w.state == WithdrawalState.blockedByObligations;
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('wd-status'),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            children: [
              Text(
                blocked ? l10n.wdBlockedTitle : l10n.wdCheckingTitle,
                key: const ValueKey('wd-status-title'),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                blocked ? l10n.wdBlockedBody : l10n.wdCheckingBody,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              if (w.lastCheckedAt case final t?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.wdLastChecked(formatSeoulDateTime(t)),
                    key: const ValueKey('wd-last-checked'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              // 탈퇴를 막고 있는 일 — 서버가 준 것만. 누르면 그 주문·처리 내역으로.
              for (final (i, o) in w.obligations.indexed)
                ListTile(
                  key: ValueKey('wd-obligation-$i'),
                  contentPadding: EdgeInsets.zero,
                  leading: const PmartLineIcon(PmartLineIcons.alert),
                  title: Text(_obligationText(l10n, o.kind)),
                  trailing: switch (o) {
                    WithdrawalObligation(ref: _?, :final kind)
                        when kind.refersToOrder || kind.refersToClaim =>
                      const PmartLineIcon(
                        PmartLineIcons.chevronRight,
                        size: 18,
                      ),
                    _ => null,
                  },
                  onTap: switch (o) {
                    WithdrawalObligation(:final ref?, :final kind)
                        when kind.refersToOrder =>
                      () => context.push('/orders/$ref'),
                    WithdrawalObligation(:final ref?, :final kind)
                        when kind.refersToClaim =>
                      () => context.push('/claims/$ref'),
                    _ => null,
                  },
                ),
              const Divider(height: 28),
              _section(l10n.wdWaitingTitle, [
                l10n.wdWaiting1,
                l10n.wdWaiting2,
                l10n.wdWaiting3,
              ]),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _errorText(),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('wd-refresh'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: _busy ? null : _refresh,
                        child: Text(l10n.wdRefresh),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('wd-revoke'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: _busy ? null : () => _revoke(w),
                        child: Text(l10n.wdRevoke),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _reasonText(AppLocalizations l10n, WithdrawalReason r) => switch (r) {
  WithdrawalReason.rarelyUse => l10n.wdReasonRarelyUse,
  WithdrawalReason.delivery => l10n.wdReasonDelivery,
  WithdrawalReason.products => l10n.wdReasonProducts,
  WithdrawalReason.price => l10n.wdReasonPrice,
  WithdrawalReason.privacy => l10n.wdReasonPrivacy,
  WithdrawalReason.other => l10n.wdReasonOther,
};

String _obligationText(AppLocalizations l10n, ObligationKind k) => switch (k) {
  ObligationKind.orderInProgress => l10n.wdObligationOrder,
  ObligationKind.paymentUnknown => l10n.wdObligationPayment,
  ObligationKind.claimInProgress => l10n.wdObligationClaim,
  ObligationKind.refundInProgress => l10n.wdObligationRefund,
  ObligationKind.other => l10n.wdObligationOther,
};

/// 목 모드: 탈퇴 대기·철회에 맞춰 목 프로필의 계정 상태를 바꾼다(실서버는 `GET /me` 가 알려 준다).
void syncMockWithdrawPending(WidgetRef ref, {required bool pending}) {
  if (ref.read(profileRepositoryProvider) case final MockProfileRepository m) {
    m.withdrawPending = pending;
  }
}
