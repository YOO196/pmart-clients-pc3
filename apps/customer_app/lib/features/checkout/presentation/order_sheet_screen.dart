import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart' show ProblemFailure;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../../address/presentation/address_controller.dart';
import '../../cart/domain/cart.dart' show Cart;
import '../../cart/presentation/cart_controller.dart';
import '../../coupons/presentation/coupon_controller.dart'
    show availableCouponsProvider;
import '../../coupons/presentation/coupon_screens.dart'
    show CouponPick, couponReasonText;
import '../../payment/domain/payment.dart';
import '../../payment/presentation/payment_controller.dart';
import '../../payment/presentation/payment_screen.dart' show paymentPhaseText;
import '../../payment/presentation/pg_widget_session.dart';
import '../domain/checkout.dart';
import 'checkout_controller.dart';
import '../../address/presentation/phone_number_formatter.dart';
import 'contact_sheet.dart';
import 'delivery_select_screen.dart'
    show modeLabel, saveOutOfStockPreference, slotDayLabel, windowText;
import '../../catalog/presentation/widgets/product_tile_card.dart'
    show ProductImage;
import 'shipping_address_view.dart';
import '../../../shared/big_button_text.dart';
import '../../../shared/notice.dart';

String _money(AppLocalizations l10n, int? amount) => switch (amount) {
  final int a => formatKrw(a),
  null => l10n.amountUnavailable,
};

/// 주문서 품목 제목. 초안에 고정된 상품명·옵션 사본(BR-35) → 장바구니 이름 → sku 순. 사본은 cartItemId, 없으면 sku 로 맞춘다.
String orderSheetLineTitle(OrderDraft draft, Cart? cart, DraftLine l) {
  final server =
      draft.lines.where((d) => d.cartItemId == l.cartItemId).firstOrNull ??
      draft.lines.where((d) => d.sku == l.sku).firstOrNull;
  return server?.title ??
      cart?.lines
          .where((c) => c.cartItemId == l.cartItemId)
          .firstOrNull
          ?.name ??
      l.sku;
}

String tipReasonText(AppLocalizations l10n, TipReason r) => switch (r) {
  TipReason.standard => l10n.tipStandard,
  TipReason.over30000 => l10n.tipOver30000,
  TipReason.firstPurchase => l10n.tipFirstPurchase,
  TipReason.none => l10n.tipNone,
  TipReason.unknown => l10n.tipUnknown,
};

String blockerText(AppLocalizations l10n, DraftBlocker b) => switch (b) {
  DraftBlocker.minOrderAmount => l10n.blockerMinOrder,
  DraftBlocker.deliveryModeUnavailable => l10n.blockerModeUnavailable,
  DraftBlocker.slotRequired => l10n.blockerSlotRequired,
  DraftBlocker.slotUnavailable => l10n.blockerSlotUnavailable,
  DraftBlocker.contactRequired => l10n.blockerContactRequired,
  DraftBlocker.couponNotApplicable => l10n.blockerCouponNotApplicable,
  DraftBlocker.unknown => l10n.blockerUnknown,
};

/// 최소주문 미달 안내. 부족액은 서버 값(minOrderShortfall)만 쓴다(BR-14).
String minOrderText(AppLocalizations l10n, Quote? q) =>
    switch (q?.minOrderShortfall) {
      final int n when n > 0 => l10n.minOrderShortfall(formatKrw(n)),
      _ => l10n.minOrderUnsatisfied,
    };

/// 결제 진입 실패 사유(초안 checkoutFailure.code·결제 흐름 실패 코드).
String checkoutFailureText(AppLocalizations l10n, String code) =>
    switch (code) {
      CheckoutProblemCode.insufficientStock => l10n.cfInsufficientStock,
      CheckoutProblemCode.skuNotHandled => l10n.cfSkuNotHandled,
      CheckoutProblemCode.capacityExceeded => l10n.cfCapacityExceeded,
      CheckoutProblemCode.slotNotSelectable => l10n.cfSlotNotSelectable,
      CheckoutProblemCode.configRequired => l10n.draftConfigRequired,
      CheckoutProblemCode.resourceExpired => l10n.cfResourceExpired,
      _ => l10n.payFailed,
    };

/// 초안 생성 거절(422·409) 사유와 고객이 갈 곳. 모르는 코드는 null(일반 오류 화면).
({String text, String? route, String? action})? draftRejection(
  AppLocalizations l10n,
  Object? error,
) {
  if (error is! ProblemFailure) return null;
  return switch (error.problem.code) {
    CheckoutProblemCode.accountNotPurchasable => (
      text: l10n.draftAccountNotPurchasable,
      route: null,
      action: null,
    ),
    CheckoutProblemCode.outOfServiceArea => (
      text: l10n.addressNotServiceable,
      route: '/addresses',
      action: l10n.goAddresses,
    ),
    // 판정 불명은 배송 불가가 아니다.
    CheckoutProblemCode.serviceabilityUnknown => (
      text: l10n.draftServiceabilityUnknown,
      route: '/addresses',
      action: l10n.goAddresses,
    ),
    CheckoutProblemCode.mfcChanged => (
      text: l10n.draftMfcChanged,
      route: '/cart',
      action: l10n.cartGoToCart,
    ),
    CheckoutProblemCode.skuNotSaleable => (
      text: l10n.draftSkuNotSaleable,
      route: '/cart',
      action: l10n.cartGoToCart,
    ),
    CheckoutProblemCode.quantityLimitExceeded => (
      text: l10n.draftQuantityLimit,
      route: '/cart',
      action: l10n.cartGoToCart,
    ),
    // 초안 생성 422(order 0.8.0). 결제 단계 자원 확보 실패(checkoutFailure)의 같은 코드와는 다른 자리다.
    CheckoutProblemCode.insufficientStock => (
      text: l10n.draftInsufficientStock,
      route: '/cart',
      action: l10n.cartGoToCart,
    ),
    CheckoutProblemCode.priceNotSet => (
      text: l10n.draftPriceNotSet,
      route: '/cart',
      action: l10n.cartGoToCart,
    ),
    CheckoutProblemCode.weightUnsplittable => (
      text: l10n.draftWeightUnsplittable,
      route: '/cart',
      action: l10n.cartGoToCart,
    ),
    CheckoutProblemCode.configRequired => (
      text: l10n.draftConfigRequired,
      route: null,
      action: null,
    ),
    _ => null,
  };
}

String _left(Duration d) {
  final s = d.inSeconds.clamp(0, 359999);
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

String blockedText(AppLocalizations l10n, CheckoutBlockReason r) => switch (r) {
  CheckoutBlockReason.notMember => l10n.blockedNotMember,
  CheckoutBlockReason.noShoppingAddress => l10n.blockedNoAddress,
  CheckoutBlockReason.noSelectedItems => l10n.blockedNoItems,
  CheckoutBlockReason.setupIncomplete => l10n.blockedSetup,
};

/// SCR-CHECKOUT-001. 금액·기한·자격은 서버 값만 보인다. 결제 버튼은 서버가 PAY 를 줬을 때만 열린다.
class OrderSheetScreen extends ConsumerStatefulWidget {
  const OrderSheetScreen({super.key});

  @override
  ConsumerState<OrderSheetScreen> createState() => _OrderSheetScreenState();
}

class _OrderSheetScreenState extends ConsumerState<OrderSheetScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(draftControllerProvider.notifier).enter());
    // 남은 시간 표시만 갱신한다. 앱 타이머로 확보를 풀거나 상태를 바꾸지 않는다.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(draftControllerProvider);
    final blocked = switch (value) {
      AsyncError(error: final CheckoutBlocked b) => b.reason,
      _ => null,
    };
    final rejection = switch (value) {
      AsyncError(:final error) => draftRejection(l10n, error),
      _ => null,
    };
    final surfaces = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: surfaces.surfaceContainer,
      appBar: AppBar(
        titleTextStyle: Theme.of(context).appBarTheme.titleTextStyle
            ?.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
        title: Text(l10n.checkoutTitle),
        centerTitle: true,
        // 레퍼런스 6-0: 뒤로 가면 "주문을 취소할까요?"
        leading: BackButton(
          onPressed: () async {
            final ok = await showPmartConfirm(
              context,
              // 레퍼런스 6-0: 굵은 제목 없이 보통 글씨 본문 한 덩어리(약 17sp, 검정).
              content: Text(
                l10n.checkoutLeaveBody,
                key: const ValueKey('checkout-leave-body'),
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(fontSize: 17, height: 1.25),
              ),
              confirmLabel: l10n.checkoutLeaveOk,
              cancelLabel: l10n.checkoutLeaveCancel,
              confirmKey: const ValueKey('checkout-leave-ok'),
            );
            if ((ok ?? false) && context.mounted) context.pop();
          },
        ),
        backgroundColor: surfaces.surfaceContainer,
      ),
      body: blocked != null
          ? Center(child: Text(blockedText(l10n, blocked)))
          : rejection != null
          ? Center(
              key: const ValueKey('draft-rejected'),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(rejection.text, textAlign: TextAlign.center),
                    if (rejection case (
                      route: final String route,
                      action: final String action,
                      text: _,
                    )) ...[
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => context.go(route),
                        child: Text(action),
                      ),
                    ],
                  ],
                ),
              ),
            )
          : switch (value) {
              AsyncData(value: null) => const Center(
                child: CircularProgressIndicator(),
              ),
              _ => UiStateView<DraftState?>(
                state: uiStateOf(value),
                onRetry: () =>
                    ref.read(draftControllerProvider.notifier).recreate(),
                ready: (context, s) => _Sheet(state: s!),
              ),
            },
    );
  }
}

/// 주문서 본문. 주문서형 결제위젯(BR-34): 결제수단·약관 위젯을 여기 그리고, "결제하기"는 결제 진입 →
/// 결제창 → 결과 확인까지 이 화면 위에서 진행한다. 완료·결과 불명·복구·환불일 때만 결제 화면으로 넘긴다.
/// 결제창 실패·취소는 여기 배너로 보이고, 새 키로 다시 결제 진입할 수 있다.
class _Sheet extends ConsumerStatefulWidget {
  const _Sheet({required this.state});

  final DraftState state;

  @override
  ConsumerState<_Sheet> createState() => _SheetState();
}

class _SheetState extends ConsumerState<_Sheet> {
  PgWidgetSession? _session;
  String? _sessionKey;
  bool _navigated = false;

  /// 이 화면에서 "결제하기"로 시작한 결제 흐름이 진행 중인지. 흐름 상태의 초기값(preparing)과 구분한다.
  bool _flowStarted = false;

  /// dispose 에서는 ref 를 쓸 수 없어 세션을 등록할 때 받아 둔다.
  ActivePgLauncher? _active;

  DraftState get state => widget.state;

  @override
  void dispose() {
    final s = _session;
    if (s != null) {
      _active?.clear(s);
      s.dispose();
    }
    super.dispose();
  }

  /// 결제위젯 설정이 있으면 세션을 만들어 결제 흐름이 쓰게 등록한다. 설정(계정)이 바뀌면 새로 만든다.
  PgWidgetSession? _ensureSession(PaymentWidgetConfig? cfg) {
    if (cfg == null) return null;
    final key = '${cfg.clientKey}|${cfg.customerKey}';
    if (_session != null && _sessionKey == key) return _session;
    _session?.dispose();
    final s = ref.read(pgWidgetSessionFactoryProvider)(cfg);
    final active = ref.read(activePgLauncherProvider);
    _session = s;
    _sessionKey = key;
    _active = active;
    active.set(s);
    return s;
  }

  bool _working(PaymentFlowState f) =>
      _flowStarted &&
      switch (f.phase) {
        PaymentPhase.preparing ||
        PaymentPhase.authenticating ||
        PaymentPhase.confirming => !f.stillChecking,
        _ => false,
      };

  /// 결제 화면으로 넘길 상태: 완료·복구·환불, 또는 확인이 오래 걸려 "다시 확인"이 필요할 때.
  bool _handoff(PaymentFlowState f) => switch (f.phase) {
    PaymentPhase.done ||
    PaymentPhase.recovering ||
    PaymentPhase.refunding => true,
    _ => f.stillChecking,
  };

  void _onFlow(PaymentFlowState? prev, PaymentFlowState next, String draftId) {
    if (!_flowStarted) return;
    if (next.phase == PaymentPhase.failed &&
        prev?.phase != PaymentPhase.failed) {
      // 이번 결제 시도는 끝났다. 초안을 다시 읽어 결제 버튼을 새 키로 다시 연다.
      setState(() => _flowStarted = false);
      ref.read(draftControllerProvider.notifier).refreshUntilPayable();
      return;
    }
    if (_handoff(next) && !_navigated) {
      _navigated = true;
      setState(() => _flowStarted = false);
      context.push('/payments/$draftId');
    }
  }

  Future<void> _pay(BuildContext context, AppLocalizations l10n) async {
    final ctl = ref.read(draftControllerProvider.notifier);
    final session = _session;
    if (session != null && !await session.requiredTermsAgreed()) {
      if (!context.mounted) return;
      showNotice(context, l10n.tossAgreementRequired);
      return;
    }
    final draftId = state.draft.draftId;
    final start = await ctl.pay();
    // 사가가 시작됐을 뿐이다. 결제 흐름이 PAY 를 기다렸다가 이 화면의 위젯으로 결제창을 연다.
    if (start is CheckoutAccepted && mounted) {
      setState(() {
        _flowStarted = true;
        _navigated = false;
      });
      unawaited(ref.read(paymentFlowProvider(draftId).notifier).run());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ctl = ref.read(draftControllerProvider.notifier);
    final draft = state.draft;
    final quote = state.agreedQuote ?? draft.quote;
    final now = ref.watch(clockProvider)();
    final cart = ref.watch(cartControllerProvider).value?.cart;
    final address = ref.watch(addressBookProvider).value?.shoppingAddress;
    final req = state.request;
    final config = ref.watch(paymentWidgetConfigProvider);
    final session = _ensureSession(config.value);
    final flowProvider = paymentFlowProvider(draft.draftId);
    final flow = ref.watch(flowProvider);
    ref.listen(
      flowProvider,
      (prev, next) => _onFlow(prev, next, draft.draftId),
    );

    final banners = <Widget>[
      // 결제창 실패·취소(이번 시도 끝). 서버가 확보분을 풀었고, 새 키로 다시 결제할 수 있다.
      if (flow.phase == PaymentPhase.failed &&
          flow.failureCode != draft.checkoutFailure?.code)
        _Banner(
          key: const ValueKey('pg-failed'),
          icon: PmartLineIcons.alert,
          text: paymentPhaseText(l10n, flow),
        ),
      if (draft.next == DraftNext.wait)
        _Banner(
          key: const ValueKey('draft-waiting'),
          icon: PmartLineIcons.refresh,
          text: l10n.checkoutPreparing,
          action: TextButton(
            onPressed: ctl.refresh,
            child: Text(l10n.checkoutCheckAgain),
          ),
        ),
      if (draft.expired)
        _Banner(
          key: const ValueKey('draft-expired'),
          icon: PmartLineIcons.clock,
          text: l10n.draftExpired,
          action: TextButton(
            onPressed: ctl.recreate,
            child: Text(l10n.draftRecreate),
          ),
        ),
      if (draft.quote?.minOrderSatisfied == false ||
          draft.blockers.contains(DraftBlocker.minOrderAmount))
        _Banner(
          key: const ValueKey('min-order'),
          icon: PmartLineIcons.info,
          text: minOrderText(l10n, draft.quote),
          action: TextButton(
            onPressed: () => context.go('/cart'),
            child: Text(l10n.cartGoToCart),
          ),
        ),
      // 최소주문 밖의 막는 사유도 모두 보인다(서버 순서).
      for (final b in draft.blockers)
        if (b != DraftBlocker.minOrderAmount)
          _Banner(
            key: ValueKey('blocker-${b.name}'),
            icon: PmartLineIcons.alert,
            text: blockerText(l10n, b),
            action: b == DraftBlocker.couponNotApplicable
                ? TextButton(
                    key: const ValueKey('coupon-remove-blocker'),
                    onPressed: () => ctl.changeCoupon(null),
                    child: Text(l10n.couponRemove),
                  )
                : b == DraftBlocker.contactRequired
                ? TextButton(
                    key: const ValueKey('contact-enter'),
                    onPressed: () => editMyContact(context, ref),
                    child: Text(l10n.contactEnter),
                  )
                : TextButton(
                    onPressed: () => context.push('/checkout/delivery'),
                    child: Text(l10n.checkoutChange),
                  ),
          ),
      if (state.checkoutUnknown)
        _Banner(
          key: const ValueKey('checkout-unknown'),
          icon: PmartLineIcons.refresh,
          text: l10n.checkoutUnknown,
          action: TextButton(
            onPressed: ctl.refresh,
            child: Text(l10n.checkoutCheckAgain),
          ),
        ),
      // 결제창을 닫았거나 실패했으면(이번 시도 끝) "준비하고 있어요"를 같이 보이지 않는다.
      if (state.lastStart is CheckoutAccepted &&
          flow.phase != PaymentPhase.failed)
        _Banner(
          key: const ValueKey('checkout-accepted'),
          icon: PmartLineIcons.receipt,
          text: l10n.checkoutAccepted,
        ),
      // 지난 결제 진입이 자원 확보·결제에서 실패했다. 서버가 확보분을 풀었고, 견적이 유효하면 다시 결제할 수 있다.
      if (draft.checkoutFailure case final f?
          when state.lastStart is! CheckoutAccepted)
        _Banner(
          key: const ValueKey('checkout-failure'),
          icon: PmartLineIcons.alert,
          text: checkoutFailureText(l10n, f.code),
        ),
      if (state.lastStart case CheckoutRejected(:final code))
        _Banner(
          key: const ValueKey('checkout-rejected'),
          icon: PmartLineIcons.alert,
          text: switch (code) {
            CheckoutProblemCode.unsupported => l10n.checkoutNotYetSupported,
            CheckoutProblemCode.checkoutBlocked => l10n.checkoutBlocked,
            // 초안 뒤 계정이 구매 불가로 바뀜(결제 진입 때 다시 확인, BR-37 회신 4).
            CheckoutProblemCode.accountNotPurchasable =>
              l10n.draftAccountNotPurchasable,
            // 결제 진입 때 쿠폰 점유 실패(order 0.18.0) — 쿠폰을 빼고 주문서를 다시 만든다.
            CheckoutProblemCode.couponNotApplicable =>
              l10n.checkoutCouponRejected,
            _ => l10n.checkoutRejected,
          },
          action: code == CheckoutProblemCode.couponNotApplicable
              ? TextButton(
                  key: const ValueKey('coupon-remove-rejected'),
                  onPressed: () => ctl.changeCoupon(null),
                  child: Text(l10n.couponRemove),
                )
              : null,
        ),
      if (state.needsReconsent) _ReQuoteCard(state: state),
    ];

    final expiry = draft.earliestExpiry;
    final body = Column(
      children: [
        Expanded(
          // ListView 는 화면 밖 항목을 늦게 만든다 — 맨 아래 결제수단(토스 위젯)이 스크롤이 닿을 때에야
          // 로딩을 시작해 늦게 떴다. 주문서는 길지 않아 한 번에 만든다.
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 레퍼런스 6-1: 맨 위(카드 밖) "알뜰배달로 받을게요" + ⏰ 시간 — 누르면 배송 방식 다시 고르기
                InkWell(
                  key: const ValueKey('change-delivery'),
                  onTap: () => context.pop(),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.checkoutReceiveBy(modeLabel(l10n, req.mode)),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (req.window case final w?)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                const PmartLineIcon(
                                  PmartLineIcons.clock,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  l10n.checkoutWindowReserved(
                                    slotDayLabel(l10n, w.date, now: now),
                                    windowText(w),
                                  ),
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        if ((quote?.plannedShipments ?? 1) > 1)
                          Text(l10n.splitShipment(quote!.plannedShipments!)),
                      ],
                    ),
                  ),
                ),
                ...banners,
                if (expiry != null && draft.awaitingCheckout)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 10, 6, 2),
                    child: Row(
                      children: [
                        PmartLineIcon(
                          PmartLineIcons.clock,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            expiry.isAfter(now)
                                ? l10n.payWithin(_left(expiry.difference(now)))
                                : l10n.holdExpired,
                            key: const ValueKey('pay-within'),
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                // 담은 상품: 사진 가로 줄 + "총 N건 상품 자세히 보기 ⌄"
                _Section(
                  title: l10n.checkoutItems,
                  children: [
                    _ItemsPreview(draft: draft, cart: cart, lines: req.lines),
                  ],
                ),
                // 배달주소 / 라이더 요청사항(한 카드, 줄 사이 선)
                _Card(
                  children: [
                    _Row(
                      title: l10n.checkoutAddress,
                      child: switch (draft.shippingAddress) {
                        // 초안에 고정된 배송지 사본(BR-37). 사본이 없는 옛 초안만 초안을 만든 현재 쇼핑 주소를 보인다.
                        final a? => ShippingAddressView(
                          address: a,
                          showPhone: false,
                        ),
                        null when address != null => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(address.label ?? address.roadAddress),
                            Text(
                              '${address.roadAddress} ${address.detailAddress}',
                            ),
                          ],
                        ),
                        _ => null,
                      },
                    ),
                    _Row(
                      key: const ValueKey('change-note'),
                      title: l10n.deliveryNoteTitle,
                      onTap: () => _editNote(context, ref),
                      child: Text(
                        req.deliveryNote ?? l10n.deliveryNoteEmpty,
                        style: req.deliveryNote == null
                            ? TextStyle(color: theme.colorScheme.outline)
                            : null,
                      ),
                    ),
                  ],
                ),
                // 레퍼런스 6-3 "내 연락처" — 초안 사본의 연락처(서버 값). 바꾸면 프로필에 저장하고 초안을 다시 만든다(BR-60 R3).
                _Card(
                  children: [
                    _Row(
                      key: const ValueKey('contact-change'),
                      title: l10n.contactTitle,
                      onTap: () => editMyContact(context, ref),
                      child: Text(
                        switch (draft.shippingAddress?.receiverPhone) {
                          final p? => PhoneNumberFormatter.format(p),
                          null => l10n.contactNone,
                        },
                        key: const ValueKey('contact-phone'),
                      ),
                    ),
                  ],
                ),
                // 품절 시 요청사항: 드롭다운 모양 상자(바꾸기는 배송 방식 화면에서)
                _Section(
                  title: l10n.oosTitle,
                  children: [
                    InkWell(
                      key: const ValueKey('change-oos'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _editOutOfStock(context, ref),
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                switch (req.outOfStock) {
                                  OutOfStockPreference.cancelOutOfStockOnly =>
                                    l10n.oosOnly,
                                  OutOfStockPreference.cancelAll => l10n.oosAll,
                                },
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const PmartLineIcon(
                              PmartLineIcons.chevronDown,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                _Section(
                  title: l10n.payMethods,
                  children: [
                    _PaymentWidgetArea(
                      config: config,
                      session: session,
                      amount: quote?.totalAmount,
                    ),
                  ],
                ),
                // 할인쿠폰(레퍼런스 6-1 결제수단 아래): N개 보유 / 적용된 할인(서버 견적) — 누르면 고르기
                _CouponSection(draft: draft),
                // 금액(레퍼런스 6-1 아래): 상품금액·배달팁·봉투값 / 굵은 선 / 결제금액
                _Card(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                  divided: false,
                  children: [
                    _AmountRow(
                      l10n.amountItems,
                      _money(l10n, quote?.listItemAmount),
                    ),
                    _AmountRow(
                      '${l10n.amountTip} (${tipReasonText(l10n, quote?.tipReason ?? TipReason.unknown)})',
                      _money(l10n, quote?.deliveryTip),
                    ),
                    if (quote?.firstPurchase case final f
                        when f == FirstPurchaseBenefit.expected ||
                            f == FirstPurchaseBenefit.checkingOtherOrder)
                      Text(
                        f == FirstPurchaseBenefit.expected
                            ? l10n.firstPurchaseExpected
                            : l10n.firstPurchaseChecking,
                        key: const ValueKey('first-purchase'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    _AmountRow(l10n.amountBag, _money(l10n, quote?.bagFee)),
                    // 할인(order 0.18.0 — 서버 값만, 0 이면 줄을 두지 않는다)
                    if (quote?.promotionDiscount case final d? when d > 0)
                      _AmountRow(
                        l10n.amountPromotion,
                        formatKrw(d, negative: true),
                        key: const ValueKey('amount-promotion'),
                        discount: true,
                      ),
                    if (quote?.couponDiscount case final d? when d > 0)
                      _AmountRow(
                        quote?.coupon?.name ?? l10n.amountCoupon,
                        formatKrw(d, negative: true),
                        key: const ValueKey('amount-coupon'),
                        discount: true,
                      ),
                    const SizedBox(height: 10),
                    Divider(
                      height: 2,
                      thickness: 1.6,
                      color: theme.colorScheme.onSurface,
                    ),
                    _AmountRow(
                      l10n.amountTotal,
                      _money(l10n, quote?.totalAmount),
                      key: const ValueKey('amount-total'),
                      strong: true,
                    ),
                    if (quote?.expiresAt case final e?)
                      Text(
                        e.isAfter(now)
                            ? l10n.priceHoldLeft(_left(e.difference(now)))
                            : l10n.holdExpired,
                        key: const ValueKey('price-hold'),
                        style: theme.textTheme.bodySmall,
                      ),
                    if (draft.resources?.reservationExpiresAt case final e?)
                      Text(
                        e.isAfter(now)
                            ? l10n.stockHoldLeft(_left(e.difference(now)))
                            : l10n.holdExpired,
                        key: const ValueKey('stock-hold'),
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Material(
          color: theme.colorScheme.surface,
          elevation: 12,
          shadowColor: Colors.black26,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 58,
                child: ValueListenableBuilder<bool>(
                  valueListenable: session?.ready ?? _neverReady,
                  builder: (context, widgetReady, _) => BigButtonText(
                    child: CommandButton(
                      key: const ValueKey('pay'),
                      busy: state.paying || _working(flow),
                      // 막는 사유가 있으면 주버튼에 첫 사유를 쓴다(DraftBlocker 설명의 순서).
                      label: switch ((
                        draft.blockers.firstOrNull,
                        quote?.totalAmount,
                      )) {
                        (final DraftBlocker b, _) => blockerText(l10n, b),
                        (null, final int t) => l10n.payButton(formatKrw(t)),
                        (null, null) => l10n.payButtonNoAmount,
                      },
                      // 결제위젯이 그려져야 연다(설정 실패·비회원이면 열지 않는다).
                      onPressed: state.canPay && widgetReady
                          ? () => _pay(context, l10n)
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    // 요청사항을 바꿔 새 초안을 받는 중이면 주문서는 그대로 두고(다시 그리지 않게 같은 자리에 둔다) 위에 얇은 진행 막대만,
    // 누르기는 막는다. 결제 진행 중(진입 대기·결제창·결과 확인)이면 이 화면 위에서 진행하고, 뒤로가기·재탭을 막는다.
    final renewing = ref.watch(draftRenewingProvider);
    final working = _working(flow);
    return Stack(
      fit: StackFit.expand,
      children: [
        AbsorbPointer(absorbing: renewing, child: body),
        if (renewing)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(key: ValueKey('draft-renewing')),
          ),
        if (working) ...[
          const ModalBarrier(dismissible: false, color: Colors.black38),
          Center(
            child: Card(
              key: const ValueKey('pay-progress'),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      paymentPhaseText(l10n, flow),
                      key: const ValueKey('pay-phase-inline'),
                      style: theme.textTheme.titleMedium,
                    ),
                    if (flow.phase == PaymentPhase.confirming) ...[
                      const SizedBox(height: 8),
                      Text(l10n.payDoNotRetry, textAlign: TextAlign.center),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 주문서 "할인쿠폰"(레퍼런스 6-1): 제목 + 오른쪽 "N개 보유", 아래 상자 — 적용된 할인(서버 견적 couponDiscount)·
/// 쓸 수 없는 사유(견적 coupon.reason)·"쿠폰 선택". 누르면 고르기 화면, 고른 결과로 주문서를 다시 만든다(order 0.18.0).
class _CouponSection extends ConsumerWidget {
  const _CouponSection({required this.draft});

  final OrderDraft draft;

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final current = ref.read(checkoutSetupProvider).couponId;
    final pick = await context.push<CouponPick>(
      '/checkout/coupons',
      extra: current,
    );
    if (pick == null) return;
    await ref
        .read(draftControllerProvider.notifier)
        .changeCoupon(pick.couponId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chosen = ref.watch(checkoutSetupProvider.select((s) => s.couponId));
    final owned = ref.watch(availableCouponsProvider);
    final quote = draft.quote;
    final result = quote?.coupon;
    // 고른 쿠폰이 이 초안에 반영된 결과만 보인다(다시 만드는 중이면 "확인 중").
    final applied = chosen != null && result?.couponId == chosen
        ? result
        : null;
    final Widget label = switch ((chosen, applied)) {
      (null, _) => Text(
        owned.value?.isEmpty ?? false
            ? l10n.couponNoneAvailable
            : l10n.couponSelect,
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      (_, null) => Text(
        l10n.couponCheckingDiscount,
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      (_, final QuoteCoupon c) when c.applicable => Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: formatKrw(quote?.couponDiscount ?? 0),
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: l10n.couponAppliedSuffix),
          ],
        ),
      ),
      (_, final QuoteCoupon c) => Text(
        couponReasonText(l10n, c.reason),
        key: const ValueKey('coupon-reason'),
        style: TextStyle(color: scheme.error),
      ),
    };
    return Container(
      key: const ValueKey('coupon-section'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.couponTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                // 보유 수 — 조회 실패·읽는 중이면 0 으로 보이지 않고 비운다.
                if (owned.value case final list?)
                  Text(
                    l10n.couponOwned(list.length),
                    key: const ValueKey('coupon-owned'),
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            key: const ValueKey('coupon-open'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => _pick(context, ref),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: DefaultTextStyle.merge(
                      style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16),
                      child: label,
                    ),
                  ),
                  const PmartLineIcon(PmartLineIcons.chevronRight, size: 20),
                ],
              ),
            ),
          ),
          if (applied case final c? when !c.applicable)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey('coupon-remove'),
                onPressed: () => ref
                    .read(draftControllerProvider.notifier)
                    .changeCoupon(null),
                child: Text(l10n.couponRemove),
              ),
            ),
        ],
      ),
    );
  }
}

/// 결제위젯 세션이 없을 때(비회원·설정 실패) 결제 버튼을 닫아 두는 값.
final _neverReady = ValueNotifier<bool>(false);

/// 결제수단·약관 위젯 영역. 설정 조회 중·실패·비회원은 위젯을 그리지 않는다(결제 버튼도 닫힌다).
class _PaymentWidgetArea extends ConsumerWidget {
  const _PaymentWidgetArea({
    required this.config,
    required this.session,
    required this.amount,
  });

  final AsyncValue<PaymentWidgetConfig?> config;
  final PgWidgetSession? session;
  final int? amount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return switch (config) {
      AsyncLoading() => Row(
        key: const ValueKey('pg-config-loading'),
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(l10n.payMethodsLoading),
        ],
      ),
      // 422 CONFIG_REQUIRED(서버에 키 없음)·조회 실패 모두 결제를 열지 않는다. 다시 받을 수 있다.
      AsyncError() => _Banner(
        key: const ValueKey('pg-config-failed'),
        icon: PmartLineIcons.alert,
        text: l10n.payConfigRequired,
        action: TextButton(
          onPressed: () => ref.invalidate(paymentWidgetConfigProvider),
          child: Text(l10n.payConfigRetry),
        ),
      ),
      _ => switch ((session, amount)) {
        (final PgWidgetSession s, final int a) => s.build(context, amount: a),
        _ => const SizedBox.shrink(),
      },
    };
  }
}

class _ReQuoteCard extends ConsumerWidget {
  const _ReQuoteCard({required this.state});

  final DraftState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final before = state.previousQuote!;
    final after = state.draft.quote;
    return Card(
      key: const ValueKey('re-quote'),
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.reQuoteTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(l10n.reQuoteBefore(_money(l10n, before.totalAmount))),
            Text(
              l10n.reQuoteAfter(_money(l10n, after?.totalAmount)),
              key: const ValueKey('re-quote-after'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey('re-quote-agree'),
              onPressed: () =>
                  ref.read(draftControllerProvider.notifier).agreeToNewQuote(),
              child: Text(l10n.reQuoteAgree),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.icon,
    required this.text,
    this.action,
  });

  final PmartLineIcons icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      color: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: PmartLineIcon(icon, color: scheme.primary),
        title: Text(text),
        trailing: action,
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          // 오른쪽 동작(변경 등)이 있어도 없어도 제목 줄 높이가 같게
          constraints: const BoxConstraints(minHeight: 32),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        ...children,
      ],
    ),
  );
}

class _AmountRow extends StatelessWidget {
  const _AmountRow(
    this.label,
    this.value, {
    super.key,
    this.strong = false,
    this.discount = false,
  });

  final String label;
  final String value;
  final bool strong;

  /// 할인 줄(브랜드색).
  final bool discount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: strong ? 8 : 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: strong
                  ? theme.textTheme.titleMedium?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    )
                  : theme.textTheme.bodyMedium?.copyWith(
                      color: discount
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
            ),
          ),
          Text(
            value,
            style: strong
                ? theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  )
                // 레퍼런스 6-1 금액 줄 오른쪽은 보통 굵기(결제금액만 굵게).
                : theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w400,
                    color: discount ? theme.colorScheme.primary : null,
                  ),
          ),
        ],
      ),
    );
  }
}

/// 흰 둥근 카드 — 줄 여럿이면 사이에 선(레퍼런스 6-1 "배달주소 / 라이더 요청사항").
class _Card extends StatelessWidget {
  const _Card({
    required this.children,
    this.padding = EdgeInsets.zero,
    this.divided = true,
  });

  final List<Widget> children;
  final EdgeInsets padding;
  final bool divided;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: padding,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, c) in children.indexed) ...[
          if (divided && i > 0) const Divider(height: 1),
          c,
        ],
      ],
    ),
  );
}

/// 카드 안 한 줄: 굵은 제목 + 아래 내용, 누를 수 있으면 오른쪽 ›.
class _Row extends StatelessWidget {
  const _Row({super.key, required this.title, this.child, this.onTap});

  final String title;
  final Widget? child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (child case final c?) ...[
                    const SizedBox(height: 4),
                    DefaultTextStyle.merge(
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                      child: c,
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              const PmartLineIcon(PmartLineIcons.chevronRight, size: 20),
          ],
        ),
      ),
    );
  }
}

/// 담은 상품: 사진 가로 줄 + 회색 알약 "총 N건 상품 자세히 보기 ⌄"(누르면 이름·수량 목록을 펼친다).
class _ItemsPreview extends StatefulWidget {
  const _ItemsPreview({
    required this.draft,
    required this.cart,
    required this.lines,
  });

  final OrderDraft draft;
  final Cart? cart;
  final List<DraftLine> lines;

  @override
  State<_ItemsPreview> createState() => _ItemsPreviewState();
}

class _ItemsPreviewState extends State<_ItemsPreview> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cart = widget.cart;
    String? imageOf(String sku) =>
        cart?.lines.where((c) => c.sku == sku).firstOrNull?.imageUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 58,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: widget.lines.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => ProductImage(
              url: imageOf(widget.lines[i].sku),
              size: 58,
              radius: 8,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Material(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            key: const ValueKey('checkout-items-toggle'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    l10n.checkoutItemsMore(widget.lines.length),
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                  ),
                  const SizedBox(width: 2),
                  PmartLineIcon(
                    _open
                        ? PmartLineIcons.chevronUp
                        : PmartLineIcons.chevronDown,
                    size: 15,
                  ),
                ],
              ),
            ),
          ),
        ),
        // 목록은 펼치지 않아도 화면에 있어야 한다(접힌 동안은 0 높이). 시험·화면 낭독기가 읽을 수 있게 Offstage 대신 높이만 줄인다.
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final l in widget.lines)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '${orderSheetLineTitle(widget.draft, cart, l)} · ${l10n.cartLineQuantity(l.quantity)}',
                          ),
                        ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// 라이더 요청사항 바꾸기(아래 시트). 바꾸면 새 주문 의도로 초안을 다시 만든다(같은 의도는 예전 초안이 돌아온다).
Future<void> _editNote(BuildContext context, WidgetRef ref) async {
  final initial = ref.read(checkoutSetupProvider).deliveryNote;
  final saved = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    // 입력칸은 시트가 가지고 시트와 함께 정리한다(닫히는 동안에도 쓰인다 — 먼저 정리하면 오류).
    builder: (context) => _NoteSheet(initial: initial),
  );
  if (saved == null || !context.mounted) return;
  ref.read(checkoutSetupProvider.notifier)
    ..setNote(saved)
    ..renewIntent();
  await ref.read(draftControllerProvider.notifier).renewInPlace();
}

class _NoteSheet extends StatefulWidget {
  const _NoteSheet({required this.initial});

  final String initial;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  late final ctl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        key: const ValueKey('note-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.deliveryNoteTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('note-input'),
            controller: ctl,
            autofocus: true,
            maxLength: 200,
            decoration: InputDecoration(
              hintText: l10n.deliveryNote,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const ValueKey('note-done'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: () => Navigator.of(context).pop(ctl.text.trim()),
            child: Text(l10n.contactDone),
          ),
        ],
      ),
    );
  }
}

/// 품절 시 요청사항 바꾸기(레퍼런스 6-4 시트: 라디오 둘 + 다음에도 적용 + [완료]).
Future<void> _editOutOfStock(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final setup = ref.read(checkoutSetupProvider);
  var pick = setup.outOfStock;
  var remember = setup.rememberOutOfStock;
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
            child: Column(
              key: const ValueKey('oos-sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 8),
                  child: Text(
                    l10n.oosTitle,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                RadioGroup<OutOfStockPreference>(
                  groupValue: pick,
                  onChanged: (p) => setSheet(() => pick = p ?? pick),
                  child: Column(
                    children: [
                      RadioListTile(
                        key: const ValueKey('oos-sheet-only'),
                        value: OutOfStockPreference.cancelOutOfStockOnly,
                        title: Text(l10n.oosOnly),
                      ),
                      RadioListTile(
                        key: const ValueKey('oos-sheet-all'),
                        value: OutOfStockPreference.cancelAll,
                        title: Text(l10n.oosAll),
                      ),
                    ],
                  ),
                ),
                CheckboxListTile(
                  key: const ValueKey('oos-remember'),
                  value: remember,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(l10n.oosRemember),
                  onChanged: (v) => setSheet(() => remember = v ?? false),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  key: const ValueKey('oos-done'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(l10n.contactDone),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  if (done != true || !context.mounted) return;
  final setupCtl = ref.read(checkoutSetupProvider.notifier)
    ..setOutOfStock(pick)
    ..setRememberOutOfStock(remember);
  if (remember) await saveOutOfStockPreference(context, ref, pick);
  if (!context.mounted) return;
  setupCtl.renewIntent();
  await ref.read(draftControllerProvider.notifier).renewInPlace();
}
