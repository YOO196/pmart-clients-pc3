import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';

/// SCR-ACCOUNT-001(일부). 주문 내역·주소 관리·로그인/로그아웃 진입.
class MyScreen extends ConsumerWidget {
  const MyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final member = ref.watch(sessionProvider) is MemberSession;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navMy)),
      body: ListView(
        children: [
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
