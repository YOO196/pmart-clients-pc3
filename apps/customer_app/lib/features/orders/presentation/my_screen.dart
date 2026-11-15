import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../profile/domain/profile.dart';
import '../../profile/presentation/my_info_screen.dart' show myInfoSummary;
import '../../profile/presentation/profile_avatar.dart';
import '../../profile/presentation/profile_controller.dart';

/// SCR-ACCOUNT-001(일부). 주문 내역·주소 관리·로그인/로그아웃 진입.
String providerName(AppLocalizations l10n, SocialProvider p) => switch (p) {
  SocialProvider.kakao => l10n.providerKakao,
  SocialProvider.naver => l10n.providerNaver,
  SocialProvider.apple => l10n.providerApple,
  SocialProvider.google => l10n.providerGoogle,
};

class MyScreen extends ConsumerWidget {
  const MyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(sessionProvider);
    final member = session is MemberSession;
    final profile = ref.watch(profileProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navMy)),
      body: ListView(
        children: [
          if (session is MemberSession)
            ListTile(
              key: const ValueKey('my-account'),
              // Google 프로필(이름·이메일·사진)은 서버가 로그인마다 최신으로 바꾼다(ADR-0024). 없으면 제공자 SDK 계정 표시.
              leading: ProfileAvatar(profile: profile),
              title: Text(switch (session.provider) {
                final SocialProvider p => l10n.myLoggedInWith(
                  providerName(l10n, p),
                ),
                null => l10n.myLoggedIn,
              }),
              subtitle: Text(
                providerAccountText(profile) ??
                    session.accountLabel ??
                    l10n.myAccountUnknown,
              ),
            ),
          if (member)
            ListTile(
              key: const ValueKey('my-info'),
              leading: const Icon(Icons.badge_outlined),
              title: Text(l10n.infoTitle),
              subtitle: Text(switch (ref.watch(profileProvider)) {
                AsyncData(value: final p?) => myInfoSummary(l10n, p),
                AsyncError() => l10n.infoLoadFailed,
                _ => l10n.infoLoading,
              }),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/me/info'),
            ),
          ListTile(
            key: const ValueKey('my-orders'),
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(l10n.ordersTitle),
            onTap: () => context.push('/orders'),
          ),
          ListTile(
            key: const ValueKey('my-reviews'),
            leading: const Icon(Icons.rate_review_outlined),
            title: Text(l10n.reviewManageTitle),
            onTap: () => context.push('/reviews'),
          ),
          ListTile(
            key: const ValueKey('my-notifications'),
            leading: const Icon(Icons.notifications_none),
            title: Text(l10n.noticeTitle),
            onTap: () => context.push('/notifications'),
          ),
          ListTile(
            key: const ValueKey('my-notification-settings'),
            leading: const Icon(Icons.tune),
            title: Text(l10n.noticeSettingsTitle),
            onTap: () => context.push('/notifications/settings'),
          ),
          ListTile(
            key: const ValueKey('my-support'),
            leading: const Icon(Icons.headset_mic_outlined),
            title: Text(l10n.supportTitle),
            onTap: () => context.push('/support'),
          ),
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(l10n.addressTitle),
            onTap: () => context.push('/addresses'),
          ),
          const Divider(),
          if (member)
            ListTile(
              key: const ValueKey('logout'),
              leading: const Icon(Icons.logout),
              title: Text(l10n.logout),
              // 로그아웃 API(`POST /auth/logouts`)는 아직 붙이지 않았다. 기기의 토큰만 지운다.
              onTap: () => ref.read(sessionProvider.notifier).signOut(),
            )
          else ...[
            // 저장된 로그인을 서버에 확인하지 못했다(연결 안 됨). 로그아웃된 게 아니다.
            if (ref.watch(sessionUnverifiedProvider))
              ListTile(
                key: const ValueKey('my-session-unverified'),
                leading: const Icon(Icons.cloud_off_outlined),
                title: Text(l10n.sessionUnreachableNotice),
                trailing: TextButton(
                  onPressed: () =>
                      ref.read(sessionProvider.notifier).retryRestore(),
                  child: Text(l10n.sessionRetry),
                ),
              ),
            ListTile(
              key: const ValueKey('my-login'),
              leading: const Icon(Icons.login),
              title: Text(l10n.loginTitle),
              onTap: () => context.push('/login'),
            ),
          ],
        ],
      ),
    );
  }
}

/// 계정 줄에 보일 Google 프로필 "이름 · 이메일". 둘 다 없으면 null(제공자 SDK 계정 표시로 대신한다).
String? providerAccountText(Profile? p) {
  if (p == null) return null;
  final parts = [
    if (p.hasProviderName) p.name!.trim(),
    if (p.hasEmail) p.email!.trim(),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}
