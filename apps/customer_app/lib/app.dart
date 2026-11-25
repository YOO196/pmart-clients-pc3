import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:pmart_core/pmart_core.dart' show PmartEnv;

import 'features/auth/domain/auth.dart' show MemberSession;
import 'features/address/presentation/logout_flow.dart'
    show carryGuestAddressOnLogin;
import 'features/auth/presentation/auth_controller.dart';
import 'features/cart/presentation/cart_controller.dart'
    show cartControllerProvider;
import 'features/cart/presentation/guest_cart_carry.dart';
import 'features/catalog/presentation/catalog_providers.dart'
    show categoriesProvider;
import 'features/start/presentation/start_controller.dart'
    show
        StartStep,
        startFlagsProvider,
        startPrefetchProvider,
        startStepProvider;
import 'features/push/presentation/push_controller.dart'
    show pendingPushRouteProvider, pushRegistrationProvider;
import 'l10n/gen/app_localizations.dart';
import 'router.dart';
import 'shared/notice.dart';
import 'shared/providers.dart';

/// 화면 어디서든 세션 안내(스낵바)를 띄우기 위한 루트 메신저.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class CustomerApp extends ConsumerWidget {
  const CustomerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 저장된 세션 확인(한 번). 결과는 sessionProvider 로 퍼진다.
    ref.watch(sessionRestoreProvider);
    // 휴대폰 푸시: 회원이 되면 알림 권한·토큰 등록, 비회원이 되면 단말 토큰을 버린다.
    ref.watch(pushRegistrationProvider);
    // 카테고리 트리를 앱이 뜰 때 미리 읽어 둔다 — 홈 타일·배너·알림으로 카테고리 화면에 바로 들어가도
    // 위 탭·하위 줄이 늦게 끼어들지 않게(사용자 2026-11-24). listen 이라 결과가 와도 앱 전체를 다시 그리지 않는다.
    ref.listen(categoriesProvider, (_, _) {});
    // 로딩 화면이 떠 있는 동안 주소록·홈을 미리 읽는다(차례로 기다리지 않게 — 로딩 S4).
    ref.listen(startPrefetchProvider, (_, _) {});
    // 한 번이라도 회원이 되면(로그인·세션 복원) 첫 로그인/둘러보기 화면은 본 것으로 둔다 — 로그아웃할 때 그 화면이
    // 다시 뜨던 것(사용자 2026-11-25). 전에는 그 화면에서 로그인한 경우만 기록했다(마이페이지 로그인은 빠짐).
    // 비회원 장바구니 ID 를 기억해 둔다(품목이 있을 때) — 로그인하면 옮긴다.
    ref.listen(cartControllerProvider, (_, next) {
      final cart = next.value?.cart;
      if (cart != null && !cart.isMember && cart.lines.isNotEmpty) {
        ref.read(lastGuestCartIdProvider.notifier).set(cart.cartId);
      }
    });
    // 시작 화면이 끝나면 기다리던 푸시 목적지(배송 현황 등)를 연다.
    ref.listen(startStepProvider, (_, step) {
      final route = ref.read(pendingPushRouteProvider);
      if (step == StartStep.ready && route != null) {
        ref.read(pendingPushRouteProvider.notifier).set(null);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => ref.read(routerProvider).push(route),
        );
      }
    });
    ref.listen(sessionProvider, (prev, next) {
      if (next is MemberSession) {
        ref.read(startFlagsProvider.notifier).completeEntry();
        // 비회원 → 회원(로그인·가입)일 때 쓰던 주소를 옮긴다(세션 복원은 비회원 기록이 없어 할 일 없음).
        if (prev is! MemberSession) {
          final container = ProviderScope.containerOf(context);
          carryGuestAddressOnLogin(container);
          // 비회원 장바구니도 옮긴다([주문하기] 로그인은 그 흐름의 병합 화면이 한다).
          carryGuestCartOnLogin(container);
        }
      }
    });
    // 세션이 끝났을 때 한 번 알린다: 조용히 이어졌으면 짧게, 안 됐으면 "다시 로그인" 버튼과 함께.
    ref.listen(sessionNoticeProvider, (_, notice) {
      if (notice == null) return;
      ref.read(sessionNoticeProvider.notifier).clear();
      final messenger = rootScaffoldMessengerKey.currentState;
      final ctx = rootScaffoldMessengerKey.currentContext;
      if (messenger == null || ctx == null) return;
      final l10n = AppLocalizations.of(ctx);
      // 다시 로그인·다시 시도는 놓치면 안 되는 안내라 다른 알림보다 조금 길게 둔다(그래도 스스로 닫힌다).
      const long = Duration(seconds: 5);
      switch (notice) {
        case SessionNotice.renewed:
          messenger.notice(
            l10n.sessionRenewed,
            key: const ValueKey('session-renewed'),
          );
        case SessionNotice.expired:
          messenger.notice(
            l10n.sessionExpiredNotice,
            key: const ValueKey('session-expired'),
            duration: long,
            action: SnackBarAction(
              label: l10n.sessionExpiredLogin,
              // 로그인은 현재 화면 위에 열리고, 끝나면 그 화면으로 돌아온다(입력값 유지).
              onPressed: () => ref.read(routerProvider).push('/login'),
            ),
          );
        case SessionNotice.unreachable:
          messenger.notice(
            l10n.sessionUnreachableNotice,
            key: const ValueKey('session-unreachable'),
            duration: long,
            action: SnackBarAction(
              label: l10n.sessionRetry,
              onPressed: () =>
                  ref.read(sessionProvider.notifier).retryRestore(),
            ),
          );
      }
    });
    return _app(ref);
  }

  Widget _app(WidgetRef ref) => MaterialApp.router(
    scaffoldMessengerKey: rootScaffoldMessengerKey,
    onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
    theme: PmartCustomerTheme.light(fontFamily: 'Pretendard'),
    darkTheme: PmartCustomerTheme.dark(fontFamily: 'Pretendard'),
    locale: const Locale('ko'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      PmartUiLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    routerConfig: ref.watch(routerProvider),
    // 목 모드는 화면 모서리에 띠를 둔다(실서버와 헷갈리지 않게: 목 로그인은 Google 창 없이 항상 성공한다).
    builder: (context, child) => _RestoreOnResume(
      child: AboveSystemNavBar(
        child: ref.watch(envProvider) == PmartEnv.mock
            ? Banner(
                message: AppLocalizations.of(context).mockBanner,
                location: BannerLocation.topStart,
                child: child ?? const SizedBox.shrink(),
              )
            : child ?? const SizedBox.shrink(),
      ),
    ),
  );
}

/// 앱 화면을 폰 아래 시스템 막대(홈·뒤로 버튼) **위까지만** 그린다(사용자 2026-11-20).
///
/// 안드로이드 15 이상은 앱이 시스템 막대 밑까지 그려지게 한다(edge-to-edge 강제) — 그 높이만큼 아래를 비우고
/// 앱 바탕색으로 칠한다. 안쪽 화면들은 아래 여백이 없는 것으로 보게 해(이중 여백 없음) 키보드 높이도 그만큼 줄여 준다.
class AboveSystemNavBar extends StatelessWidget {
  const AboveSystemNavBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bar = media.viewPadding.bottom;
    if (bar <= 0) return child;
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: EdgeInsets.only(bottom: bar),
        child: MediaQuery(
          data: media.copyWith(
            padding: media.padding.copyWith(bottom: 0),
            viewPadding: media.viewPadding.copyWith(bottom: 0),
            // 키보드는 화면 맨 아래부터 잰 높이라, 비운 막대 높이만큼 빼야 겹치지 않는다.
            viewInsets: media.viewInsets.copyWith(
              bottom: (media.viewInsets.bottom - bar).clamp(0, double.infinity),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 저장된 세션을 확인하지 못한 채라면(연결 안 됨) 앱이 다시 앞으로 올 때 다시 확인한다.
class _RestoreOnResume extends ConsumerStatefulWidget {
  const _RestoreOnResume({required this.child});

  final Widget child;

  @override
  ConsumerState<_RestoreOnResume> createState() => _RestoreOnResumeState();
}

class _RestoreOnResumeState extends ConsumerState<_RestoreOnResume> {
  AppLifecycleListener? _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onResume: () => ref.read(sessionProvider.notifier).retryRestore(),
    );
  }

  @override
  void dispose() {
    _listener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
