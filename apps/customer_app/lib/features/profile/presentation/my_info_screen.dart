import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../auth/presentation/provider_badge.dart';
import '../../auth/domain/auth.dart' show MemberSession, SocialProvider;
import '../../auth/presentation/auth_controller.dart' show sessionProvider;
import '../domain/profile.dart';
import 'profile_avatar.dart';
import 'profile_photo.dart';
import 'profile_controller.dart';
import '../../../shared/notice.dart';
import '../../auth/presentation/signup_steps.dart';

/// 마이 목록에 보일 한 줄 요약(이름 · 가린 번호). 번호는 등록된 것이 있을 때만 붙인다
/// (연락처 등록은 서버가 아직 열지 않아 "번호 없음"을 따로 보이지 않는다, 2026-11-03 안내).
String myInfoSummary(AppLocalizations l10n, Profile p) {
  final name = p.nickname?.trim() ?? '';
  if (name.isEmpty && !p.hasPhone) return l10n.infoNotSet;
  return [
    name.isEmpty ? l10n.infoNameNotSet : name,
    if (p.hasPhone) p.phoneMasked!,
  ].join(' · ');
}

/// SCR-ACCOUNT 내 정보: 이름(닉네임). 회원가입 직후([signup])와 마이에서 같은 화면을 쓴다.
/// 저장은 서버 결과(APPLIED)로만 확정한다.
/// 휴대폰 번호는 서버가 연락처 변경을 아직 열지 않아(보내면 400, 2026-11-03 안내) 칸을 잠그고 보내지 않는다.
///
/// 가입 직후에는 저장할 때까지 닫지 않는다. 서버가 저장을 제공하지 않거나(501)
/// 결과를 확인하지 못했을 때만 "나중에 하기"를 연다(가입을 막지 않는다).
class MyInfoScreen extends ConsumerStatefulWidget {
  const MyInfoScreen({super.key, this.signup = false});

  final bool signup;

  @override
  ConsumerState<MyInfoScreen> createState() => _MyInfoScreenState();
}

class _MyInfoScreenState extends ConsumerState<MyInfoScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  bool _filled = false;
  ProfileChangeOutcome? _last;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canSkip =>
      _last is ProfileChangeUnsupported || _last is ProfileChangeUnknown;

  Future<void> _save(Profile? current) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = _name.text.trim();
    // 바뀐 항목만 보낸다. 번호는 서버가 아직 받지 않으므로 보내지 않는다.
    final nameChanged = name != (current?.nickname?.trim() ?? '');
    if (!nameChanged) {
      messenger.notice(l10n.infoNothingChanged);
      return;
    }
    final outcome = await ref
        .read(profileProvider.notifier)
        .changeProfile(name: name);
    if (!mounted) return;
    setState(() => _last = outcome);
    if (outcome is ProfileChangeApplied) {
      messenger.notice(l10n.infoSaved);
      context.pop(true);
    }
  }

  String? _message(AppLocalizations l10n) => switch (_last) {
    null || ProfileChangeApplied() => null,
    ProfileChangePending() => l10n.infoPending,
    ProfileChangeUnsupported() => l10n.infoUnsupported,
    ProfileChangeRejected() => l10n.infoRejected,
    ProfileChangeUnknown() => l10n.infoUnknown,
  };

  @override
  Widget build(BuildContext context) {
    // 마이 > 내 정보는 F안 목록 화면. 가입 직후 "내 정보 등록"만 아래 입력 폼(이름을 꼭 받아야 해서).
    if (!widget.signup) return const _MyInfoView();
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(profileProvider);
    final profile = value.value;
    // 서버 값으로 한 번만 채운다(입력 중에 덮어쓰지 않는다).
    if (!_filled && profile != null) {
      _filled = true;
      _name.text = profile.nickname ?? '';
    }
    final hasPhone = profile?.hasPhone ?? false;
    final message = _message(l10n);
    return PopScope(
      canPop: !widget.signup || _canSkip,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.signup ? l10n.infoSignupTitle : l10n.infoTitle),
          automaticallyImplyLeading: !widget.signup,
          actions: [if (widget.signup) const SignupStepCount(step: 3)],
        ),
        body: switch (value) {
          AsyncError() when profile == null => Center(
            child: Text(l10n.infoLoadFailed),
          ),
          _ when profile == null => const Center(
            child: CircularProgressIndicator(),
          ),
          _ => Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 새 가입 마지막 단계 3/3(사용자 2026-11-21).
                if (widget.signup) const SignupSteps(step: 3),
                _ProviderProfile(profile: profile),
                const SizedBox(height: 16),
                Text(widget.signup ? l10n.infoSignupGuide : l10n.infoGuide),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('info-name'),
                  controller: _name,
                  maxLength: NameInput.maxLength,
                  decoration: InputDecoration(labelText: l10n.infoName),
                  validator: (v) =>
                      NameInput.valid(v ?? '') ? null : l10n.infoNameInvalid,
                ),
                const SizedBox(height: 8),
                // 휴대폰 번호는 "번호 확인"(OCTOMO) 화면에서 넣고 확인한다(customer 0.9.0). 여기서는 보이기만.
                TextFormField(
                  key: ValueKey('info-phone-${profile.phoneMasked}'),
                  enabled: false,
                  initialValue: hasPhone ? profile.phoneMasked : '',
                  decoration: InputDecoration(
                    labelText: l10n.infoPhone,
                    helperText: !hasPhone
                        ? null
                        : profile.phoneVerified
                        ? l10n.infoPhoneVerified
                        : l10n.infoPhoneUnverified,
                  ),
                ),
                if (!profile.phoneVerified)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const ValueKey('info-phone-verify'),
                      onPressed: () => context.push('/me/phone-verification'),
                      child: Text(l10n.infoPhoneVerify),
                    ),
                  ),
                if (message != null) ...[
                  const SizedBox(height: 8),
                  Text(message, key: const ValueKey('info-message')),
                ],
                const SizedBox(height: 16),
                CommandButton(
                  key: const ValueKey('info-save'),
                  label: l10n.infoSave,
                  onPressed: () => _save(profile),
                ),
                if (widget.signup && _canSkip)
                  TextButton(
                    key: const ValueKey('info-later'),
                    onPressed: () => context.pop(false),
                    child: Text(l10n.infoLater),
                  ),
              ],
            ),
          ),
        },
      ),
    );
  }
}

/// 로그인 제공자(Google) 프로필: 사진·이름·이메일. 서버가 로그인마다 최신으로 바꾸고 여기서는 바꿀 수 없다(ADR-0024).
/// 값이 없으면 "정보 없음"으로 둔다(빈칸을 다른 값으로 채우지 않는다).
class _ProviderProfile extends StatelessWidget {
  const _ProviderProfile({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final emailLine = profile.hasEmail
        ? switch (profile.emailVerified) {
            true => l10n.infoEmailVerified(profile.email!.trim()),
            _ => profile.email!.trim(),
          }
        : l10n.infoGoogleEmailNotSet;
    return Card(
      key: const ValueKey('info-google'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ProfileAvatar(profile: profile, radius: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.hasProviderName
                        ? profile.name!.trim()
                        : l10n.infoGoogleNameNotSet,
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(emailLine, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    l10n.infoGoogleNote,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 마이 > 내 정보 — 초안 `../고객앱 ui/02_내정보/my_info_v2.html` F안(사용자 2026-11-21 선택, 색은 앱 팔레트):
/// 가운데 프로필 사진(로그인 계정 사진 — 사진 바꾸기는 서버 기능이 없어 넣지 않음, BR-80), 번호 미확인이면 분홍 안내 띠
/// [확인하기 ›], 카드 목록(이름 › 시트에서 수정 / 휴대폰 번호 + 확인 칩 › 번호 확인 화면 / 이메일 읽기만), 로그인 계정 카드,
/// 안내 한 줄, 맨 아래 회원 탈퇴(로그아웃은 마이페이지에만 — 사용자). 값은 서버 값만, 저장은 서버 확정(APPLIED)으로만.
class _MyInfoView extends ConsumerWidget {
  const _MyInfoView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = ref.watch(profileProvider);
    final profile = value.value;
    Widget card(List<Widget> rows) => Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          for (final (i, r) in rows.indexed) ...[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
            r,
          ],
        ],
      ),
    );
    final label = theme.textTheme.titleSmall?.copyWith(
      fontSize: 15.5,
      fontWeight: FontWeight.w700,
    );
    final valueStyle = theme.textTheme.bodyLarge?.copyWith(
      fontSize: 15,
      color: scheme.onSurfaceVariant,
    );
    Widget row({
      required Key key,
      required String title,
      required Widget trailing,
      VoidCallback? onTap,
    }) => InkWell(
      key: key,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 18, onTap == null ? 20 : 14, 18),
        child: Row(
          children: [
            Text(title, style: label),
            const SizedBox(width: 16),
            Expanded(
              child: Align(alignment: Alignment.centerRight, child: trailing),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              PmartLineIcon(
                PmartLineIcons.chevronRight,
                size: 16,
                color: scheme.outline,
              ),
            ],
          ],
        ),
      ),
    );
    // 서버 프로필의 로그인 제공자, 없으면 이 기기 세션의 제공자.
    final signupProvider =
        profile?.socialProvider ??
        switch (ref.watch(sessionProvider)) {
          MemberSession(:final provider) => provider,
          _ => null,
        };
    final providerLabel = switch (signupProvider) {
      SocialProvider.kakao => l10n.loginKakaoShort,
      SocialProvider.naver => l10n.loginNaverShort,
      SocialProvider.apple => l10n.loginAppleShort,
      SocialProvider.google => l10n.loginGoogleShort,
      null => null,
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.infoTitle)),
      body: switch (value) {
        AsyncError() when profile == null => Center(
          child: Text(l10n.infoLoadFailed),
        ),
        _ when profile == null => const Center(
          child: CircularProgressIndicator(),
        ),
        _ => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            // 사진 + 카메라 표시 → 사진 바꾸기 시트(G안, customer 0.15.0 BR-80).
            Center(
              child: ProfilePhotoEditor(
                profile: profile,
                providerLabel: providerLabel,
              ),
            ),
            const SizedBox(height: 20),
            // 번호 확인 전이면 분홍 안내 띠(D안에서 가져옴).
            if (!profile.phoneVerified) ...[
              Material(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const ValueKey('info-phone-verify'),
                  onTap: () => context.push('/me/phone-verification'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        PmartLineIcon(
                          PmartLineIcons.info,
                          size: 18,
                          color: scheme.onTertiaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.infoPhoneVerifyBand,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                        Text(
                          l10n.infoPhoneVerifyGo,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onTertiaryContainer,
                          ),
                        ),
                        PmartLineIcon(
                          PmartLineIcons.chevronRight,
                          size: 15,
                          color: scheme.onTertiaryContainer,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            card([
              row(
                key: const ValueKey('info-name-row'),
                title: l10n.infoName,
                // 앱에서 정한 이름(nickname)이 없으면 로그인 계정 이름(서버 `name` — 네이버·카카오·Google 이
                // 준 회원 이름). 둘 다 없을 때만 "이름 없음"(사용자 2026-11-25 네이버 로그인인데 이름 없음).
                trailing: Text(
                  switch ((profile.nickname?.trim(), profile.name?.trim())) {
                    (final n?, _) when n.isNotEmpty => n,
                    (_, final n?) when n.isNotEmpty => n,
                    _ => l10n.infoNameNotSet,
                  },
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: valueStyle,
                ),
                onTap: () => _editName(context, profile),
              ),
              row(
                key: const ValueKey('info-phone-row'),
                title: l10n.infoPhone,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        profile.hasPhone
                            ? profile.phoneMasked!
                            : l10n.infoPhoneNotSet,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: valueStyle,
                      ),
                    ),
                    if (profile.hasPhone) ...[
                      const SizedBox(width: 6),
                      _VerifyChip(verified: profile.phoneVerified),
                    ],
                  ],
                ),
                onTap: () => context.push('/me/phone-verification'),
              ),
              row(
                key: const ValueKey('info-email-row'),
                title: l10n.infoEmail,
                trailing: Text(
                  profile.hasEmail
                      ? profile.email!.trim()
                      : l10n.infoGoogleEmailNotSet,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: valueStyle,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            // 로그인 계정 — 읽기만(바꾸는 기능 없음). 브랜드 로고 대신 이름 글자.
            Container(
              key: const ValueKey('info-google'),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.infoLoginAccount, style: label),
                        const SizedBox(height: 4),
                        Text(
                          l10n.infoLoginAccountNote,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 서버 프로필의 로그인 제공자, 없으면 이 기기 세션의 제공자.
                  // 마이 화면 이메일 옆과 같은 배지(백엔드 요청 2026-11-25).
                  if (signupProvider case final p?)
                    ProviderBadge(
                      provider: p,
                      textKey: const ValueKey('info-login-provider'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
              child: Text(
                l10n.infoOrdersUnchanged,
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 28),
            // 회원 탈퇴(customer 0.12.0). 탈퇴 대기 중이면 "탈퇴 처리 대기".
            Center(
              child: TextButton(
                key: const ValueKey('info-withdraw'),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onSurfaceVariant,
                  textStyle: theme.textTheme.bodySmall?.copyWith(fontSize: 14),
                ),
                onPressed: () => context.push('/me/withdrawal'),
                child: Text(
                  profile.withdrawPending ? l10n.wdPendingBand : l10n.wdTitle,
                ),
              ),
            ),
          ],
        ),
      },
    );
  }

  Future<void> _editName(BuildContext context, Profile profile) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _NameSheet(profile: profile),
      );
}

/// 번호 확인 칩: 확인됨 = 연보라 바탕·주 색, 확인 안 됨 = 분홍 바탕(서버 값).
class _VerifyChip extends StatelessWidget {
  const _VerifyChip({required this.verified});
  final bool verified;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: ValueKey(verified ? 'info-phone-verified' : 'info-phone-unverified'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: verified ? scheme.primaryContainer : scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        verified ? l10n.infoPhoneVerified : l10n.infoPhoneUnverified,
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: verified ? scheme.primary : scheme.onTertiaryContainer,
        ),
      ),
    );
  }
}

/// 이름 바꾸기 시트(F-2): 입력칸(30자) + [저장]. 서버가 확정(APPLIED)해야 닫힌다. 그 밖의 결과는 시트에 안내.
class _NameSheet extends ConsumerStatefulWidget {
  const _NameSheet({required this.profile});
  final Profile profile;
  @override
  ConsumerState<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends ConsumerState<_NameSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.nickname ?? '');
  ProfileChangeOutcome? _last;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = _name.text.trim();
    if (name == (widget.profile.nickname?.trim() ?? '')) {
      Navigator.of(context).pop();
      messenger.notice(l10n.infoNothingChanged);
      return;
    }
    final outcome = await ref
        .read(profileProvider.notifier)
        .changeProfile(name: name);
    if (!mounted) return;
    setState(() => _last = outcome);
    if (outcome is ProfileChangeApplied) {
      Navigator.of(context).pop();
      messenger.notice(l10n.infoSaved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final message = switch (_last) {
      null || ProfileChangeApplied() => null,
      ProfileChangePending() => l10n.infoPending,
      ProfileChangeUnsupported() => l10n.infoUnsupported,
      ProfileChangeRejected() => l10n.infoRejected,
      ProfileChangeUnknown() => l10n.infoUnknown,
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.infoNameSheetTitle,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('info-name-close'),
                  tooltip: l10n.actionClose,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const PmartLineIcon(PmartLineIcons.close, size: 22),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.infoNameSheetBody,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('info-name'),
              controller: _name,
              autofocus: true,
              maxLength: NameInput.maxLength,
              decoration: InputDecoration(labelText: l10n.infoName),
              validator: (v) =>
                  NameInput.valid(v ?? '') ? null : l10n.infoNameInvalid,
            ),
            if (message != null) ...[
              const SizedBox(height: 4),
              Text(message, key: const ValueKey('info-message')),
            ],
            const SizedBox(height: 12),
            CommandButton(
              key: const ValueKey('info-save'),
              label: l10n.infoSave,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
