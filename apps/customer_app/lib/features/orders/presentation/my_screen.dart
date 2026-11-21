import 'package:flutter/material.dart';
import 'package:pmart_ui/pmart_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../address/presentation/logout_flow.dart';
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // 레퍼런스(사용자 캡처 2026-11-20 "마이배민"): 회색 바탕, 왼쪽 큰 제목 + 오른쪽 고객센터·설정 아이콘,
    // 가운데 큰 프로필 사진 + 이름(연필), 흰 둥근 카드, 아래 작은 선 아이콘 줄 목록.
    // 쿠폰·포인트·선물함·찜·배민클럽 같은 1차 제외 기능은 넣지 않는다.
    Widget row(
      String text, {
      Key? key,
      required PmartLineIcons icon,
      VoidCallback? onTap,
      String? sub,
      Widget? trailing,
    }) => InkWell(
      key: key,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        child: Row(
          children: [
            PmartLineIcon(icon, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (sub != null)
                    Text(
                      sub,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            trailing ??
                (onTap == null
                    ? const SizedBox.shrink()
                    : PmartLineIcon(
                        PmartLineIcons.chevronRight,
                        size: 16,
                        color: scheme.outline,
                      )),
          ],
        ),
      ),
    );
    Widget card(List<Widget> children) => Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: children),
    );
    return Scaffold(
      backgroundColor: scheme.surfaceContainer,
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 18,
        backgroundColor: scheme.surfaceContainer,
        title: Text(
          l10n.navMy,
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            key: const ValueKey('my-top-support'),
            tooltip: l10n.supportTitle,
            icon: const PmartLineIcon(PmartLineIcons.headset, size: 24),
            onPressed: () => context.push('/support'),
          ),
          IconButton(
            key: const ValueKey('my-top-settings'),
            tooltip: l10n.noticeSettingsTitle,
            icon: const PmartLineIcon(PmartLineIcons.settings, size: 24),
            onPressed: () => context.push('/notifications/settings'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // 탈퇴 처리 대기(계정 상태 WITHDRAW_PENDING — customer 0.12.0): 맨 위 띠, 누르면 상태 화면.
          if (member && (profile?.withdrawPending ?? false))
            Material(
              color: scheme.errorContainer,
              child: InkWell(
                key: const ValueKey('my-withdraw-pending'),
                onTap: () => context.push('/me/withdrawal'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.wdPendingBandBody,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      ),
                      PmartLineIcon(
                        PmartLineIcons.chevronRight,
                        size: 18,
                        color: scheme.onErrorContainer,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // 프로필: 가운데 큰 사진 + 이름(연필 = 내 정보)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Column(
              key: member ? const ValueKey('my-account') : null,
              children: [
                if (session is MemberSession) ...[
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => context.push('/me/info'),
                    // Google 프로필(이름·이메일·사진)은 서버가 로그인마다 최신으로 바꾼다(ADR-0024). 없으면 제공자 SDK 계정 표시.
                    child: SizedBox.square(
                      dimension: 96,
                      child: FittedBox(child: ProfileAvatar(profile: profile)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    key: const ValueKey('my-info'),
                    onTap: () => context.push('/me/info'),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          switch (ref.watch(profileProvider)) {
                            AsyncData(value: final p?) => myInfoSummary(
                              l10n,
                              p,
                            ),
                            AsyncError() => l10n.infoLoadFailed,
                            _ => l10n.infoLoading,
                          },
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        PmartLineIcon(
                          PmartLineIcons.pencil,
                          size: 15,
                          color: scheme.outline,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  // 로그인 제공자 · 계정(따로 두 줄 — 시험·화면 낭독기가 따로 읽는다)
                  Column(
                    children: [
                      Text(
                        switch (session.provider) {
                          final SocialProvider p => l10n.myLoggedInWith(
                            providerName(l10n, p),
                          ),
                          null => l10n.myLoggedIn,
                        },
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        providerAccountText(profile) ??
                            session.accountLabel ??
                            l10n.myAccountUnknown,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  // 저장된 로그인을 서버에 확인하지 못했다(연결 안 됨). 로그아웃된 게 아니다.
                  if (ref.watch(sessionUnverifiedProvider))
                    ListTile(
                      key: const ValueKey('my-session-unverified'),
                      leading: const PmartLineIcon(PmartLineIcons.alert),
                      title: Text(l10n.sessionUnreachableNotice),
                      trailing: TextButton(
                        onPressed: () =>
                            ref.read(sessionProvider.notifier).retryRestore(),
                        child: Text(l10n.sessionRetry),
                      ),
                    ),
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const ValueKey('my-login'),
                    onPressed: () => context.push('/login'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(l10n.loginTitle),
                  ),
                ],
              ],
            ),
          ),
          card([
            row(
              l10n.ordersTitle,
              key: const ValueKey('my-orders'),
              icon: PmartLineIcons.receipt,
              onTap: () => context.push('/my/orders'),
            ),
            // 취소·반품 목록은 회원 본인 것만 서버가 준다(claim 0.6.0).
            if (member)
              row(
                l10n.myClaimsTitle,
                key: const ValueKey('my-claims'),
                icon: PmartLineIcons.refresh,
                onTap: () => context.push('/claims'),
              ),
            row(
              l10n.wishTitle,
              key: const ValueKey('my-wishlist'),
              icon: PmartLineIcons.heart,
              onTap: () => context.push('/me/wishlist'),
            ),
            // 쿠폰함은 회원만(promotion 0.2.0 고객 경로).
            if (member)
              row(
                l10n.couponBoxTitle,
                key: const ValueKey('my-coupons'),
                icon: PmartLineIcons.receipt,
                onTap: () => context.push('/me/coupons'),
              ),
            row(
              l10n.reviewManageTitle,
              key: const ValueKey('my-reviews'),
              icon: PmartLineIcons.pencil,
              onTap: () => context.push('/reviews'),
            ),
            row(
              l10n.addressTitle,
              icon: PmartLineIcons.pin,
              onTap: () => context.push('/addresses'),
            ),
            row(
              l10n.noticeTitle,
              key: const ValueKey('my-notifications'),
              icon: PmartLineIcons.bell,
              onTap: () => context.push('/notifications'),
            ),
          ]),
          card([
            row(
              l10n.supportTitle,
              key: const ValueKey('my-support'),
              icon: PmartLineIcons.headset,
              onTap: () => context.push('/support'),
            ),
            row(
              l10n.faqTitle,
              key: const ValueKey('my-faqs'),
              icon: PmartLineIcons.info,
              onTap: () => context.push('/support/faqs'),
            ),
            row(
              l10n.termsTitle,
              key: const ValueKey('my-terms'),
              icon: PmartLineIcons.receipt,
              onTap: () => context.push('/me/terms'),
            ),
            row(
              l10n.noticeSettingsTitle,
              key: const ValueKey('my-notification-settings'),
              icon: PmartLineIcons.settings,
              onTap: () => context.push('/notifications/settings'),
            ),
            if (member)
              // 로그아웃 API(`POST /auth/logouts`)는 아직 붙이지 않았다. 기기의 토큰만 지운다.
              row(
                l10n.logout,
                key: const ValueKey('logout'),
                icon: PmartLineIcons.back,
                // 쇼핑 주소가 있으면 "지금 주소로 계속 둘러볼까요?"(customer 0.14.0)
                onTap: () => logoutKeepingAddress(context, ref),
              ),
          ]),
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
