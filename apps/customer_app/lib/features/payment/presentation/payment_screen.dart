import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_ui/pmart_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../auth/domain/auth.dart' show MemberSession;
import '../../auth/presentation/auth_controller.dart' show sessionProvider;
import '../../checkout/presentation/checkout_controller.dart';
import '../../orders/presentation/orders_providers.dart'
    show orderDetailProvider;
import '../../checkout/presentation/order_sheet_screen.dart'
    show checkoutFailureText;
import 'pg_widget_session.dart' show pgAmountMismatchCode;
import 'toss_payment_page.dart' show TossPgLauncher;
import '../domain/payment.dart';
import 'payment_controller.dart';
import 'order_done_motion.dart';

String paymentPhaseText(AppLocalizations l10n, PaymentFlowState s) =>
    switch (s.phase) {
      PaymentPhase.preparing => l10n.payPreparing,
      PaymentPhase.authenticating => l10n.payAuthenticating,
      PaymentPhase.confirming => l10n.payConfirming,
      PaymentPhase.done => l10n.payDone,
      PaymentPhase.failed => switch (s.failureCode) {
        'USER_CANCELLED' => l10n.payCancelled,
        TossPgLauncher.resultMismatch => l10n.payResultMismatch,
        TossPgLauncher.configMissing => l10n.payConfigRequired,
        pgAmountMismatchCode => l10n.payAmountMismatch,
        'PG_RENDER_FAILED' => l10n.payRenderFailed,
        final String code => checkoutFailureText(l10n, code),
        null => l10n.payFailed,
      },
      PaymentPhase.recovering => l10n.payRecovering,
      PaymentPhase.refunding => l10n.payRefunding,
    };

/// SCR-PAYMENT-001. 뒤로가기·재진입·앱 재시작은 같은 결제 시도를 조회한다.
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key, required this.draftId});

  final String draftId;

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(paymentFlowProvider(widget.draftId).notifier).run(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = paymentFlowProvider(widget.draftId);
    final s = ref.watch(provider);
    final ctl = ref.read(provider.notifier);
    // 결제 중 세션이 끝났다가 다시 로그인되면 결제 결과부터 확인한다(결제를 다시 시작하지 않는다).
    ref.listen(sessionProvider, (prev, next) {
      if (prev is! MemberSession && next is MemberSession) ctl.checkAgain();
    });
    final working = switch (s.phase) {
      PaymentPhase.preparing ||
      PaymentPhase.authenticating ||
      PaymentPhase.confirming => !s.stillChecking,
      _ => false,
    };
    // 서버가 결제·주문을 확정한 뒤에만(done) 완료 화면.
    if (s.phase == PaymentPhase.done) {
      return _PaymentDoneView(orderId: s.orderId!);
    }
    return Scaffold(
      appBar: AppBar(
        // 레퍼런스 7-4: 끝나면 제목 "주문완료"(뒤로 없음)
        title: Text(
          s.phase == PaymentPhase.done ? l10n.payDoneTitle : l10n.payTitle,
        ),
        automaticallyImplyLeading: s.phase != PaymentPhase.done,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 레퍼런스 7-3·7-4: 가운데 작은 원형 로딩
              if (working)
                const SizedBox.square(
                  dimension: 30,
                  child: CircularProgressIndicator(strokeWidth: 3.5),
                ),
              const SizedBox(height: 16),
              Text(
                paymentPhaseText(l10n, s),
                key: const ValueKey('pay-phase'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (s.stillChecking) ...[
                const SizedBox(height: 8),
                Text(l10n.payStillChecking, textAlign: TextAlign.center),
              ],
              if (s.phase == PaymentPhase.confirming ||
                  s.phase == PaymentPhase.recovering ||
                  s.phase == PaymentPhase.refunding) ...[
                const SizedBox(height: 8),
                // 결과를 모르는 동안 다시 결제하지 않게 안내한다.
                Text(l10n.payDoNotRetry, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 24),
              // 이번 결제 시도는 끝났다. 주문서로 돌아가 새로 결제 진입한다(같은 결제창을 다시 열지 않는다).
              if (s.canRetryPayment)
                FilledButton(
                  key: const ValueKey('pay-retry'),
                  onPressed: () {
                    ref.read(draftControllerProvider.notifier).refresh();
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/checkout');
                    }
                  },
                  child: Text(l10n.payBackToOrderSheet),
                ),
              if (!working &&
                  !s.canRetryPayment &&
                  s.phase != PaymentPhase.done)
                OutlinedButton(
                  key: const ValueKey('pay-check-again'),
                  onPressed: ctl.checkAgain,
                  child: Text(l10n.checkoutCheckAgain),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 주문 완료(사용자 레퍼런스 2026-11-25 — 실패 화면 두 장의 배치를 성공으로): 위 X·가운데 "주문완료",
/// 큰 굵은 제목, 회색 굵은 주문번호, 한 줄 안내(굵은 낱말), 아래쪽 큰 캐릭터, 맨 아래 꽉 찬 버튼.
/// 캐릭터는 사용자 제작 라이더(브랜드색).
class _PaymentDoneView extends ConsumerWidget {
  const _PaymentDoneView({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // 화면용 주문번호(order 0.11.0)는 주문 조회에만 있다. 읽는 동안은 비워 두고, 없거나 못 읽으면 orderId.
    final number = switch (ref.watch(orderDetailProvider(orderId))) {
      AsyncLoading() => null,
      AsyncData(:final value) => value.displayNumber,
      _ => orderId,
    };
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        centerTitle: true,
        automaticallyImplyLeading: false,
        leading: IconButton(
          key: const ValueKey('pay-done-close'),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const PmartLineIcon(PmartLineIcons.close, size: 22),
          onPressed: () => context.go('/'),
        ),
        title: Text(
          l10n.payDoneTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: scheme.outlineVariant),
        ),
      ),
      body: SafeArea(
        top: false,
        child: OrderDoneMotion(
          builder: (context, t) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 사용자 지시(2026-11-25): "주문이 완료됐어요" 굵고 크게, 내려서 가운데 — 위 빈자리의 가운데에 글 묶음.
              Expanded(
                flex: 6,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: DoneCheckBadge(t: t, size: 84)),
                      DoneRise(
                        t: t,
                        a: 0.32,
                        b: 0.55,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            l10n.payDone,
                            key: const ValueKey('pay-phase'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DoneRise(
                        t: t,
                        a: 0.42,
                        b: 0.65,
                        child: SizedBox(
                          height: 24,
                          child: number == null
                              ? null
                              : Text(
                                  l10n.payOrderNumber(number),
                                  key: const ValueKey('order-id'),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF7B7D80),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      DoneRise(
                        t: t,
                        a: 0.48,
                        b: 0.7,
                        child: Text(
                          l10n.payDoneCheer,
                          key: const ValueKey('pay-done-cheer'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      DoneRise(
                        t: t,
                        a: 0.54,
                        b: 0.78,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: l10n.payDoneGuideBefore),
                                TextSpan(
                                  text: l10n.payDoneGuideBold,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(text: l10n.payDoneGuideAfter),
                              ],
                            ),
                            key: const ValueKey('pay-done-guide'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontSize: 15.5,
                              height: 1.6,
                              color: const Color(0xFF4B4D4F),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 캐릭터는 남는 자리의 아래쪽(레퍼런스: 화면 아래 3분의 1 즈음).
              Expanded(
                flex: 4,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: LayoutBuilder(
                    builder: (context, c) => DoneRiderDriveIn(
                      t: t,
                      width: (c.maxHeight * 0.85 / (284 / 329)).clamp(
                        120.0,
                        240.0,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: SizedBox(
                  height: 52,
                  child: FilledButton(
                    key: const ValueKey('go-order'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      textStyle: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () => context.go('/orders/$orderId'),
                    child: Text(l10n.payGoOrder),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
