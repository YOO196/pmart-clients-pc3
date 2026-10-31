import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../profile/presentation/my_info_screen.dart' show myInfoSummary;
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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navMy)),
      body: ListView(
        children: [
          if (session is MemberSession)
            ListTile(
              key: const ValueKey('my-account'),
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(switch (session.provider) {
                final SocialProvider p => l10n.myLoggedInWith(
                  providerName(l10n, p),
                ),
                null => l10n.myLoggedIn,
              }),
              subtitle: Text(session.accountLabel ?? l10n.myAccountUnknown),
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
          else
            ListTile(
              key: const ValueKey('my-login'),
              leading: const Icon(Icons.login),
              title: Text(l10n.loginTitle),
              onTap: () => context.push('/login'),
            ),
        ],
      ),
    );
  }
}
