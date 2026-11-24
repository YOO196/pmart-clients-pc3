import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../features/cart/presentation/cart_controller.dart'
    show cartControllerProvider;
import '../features/cart/domain/cart.dart' show Cart;
import '../l10n/gen/app_localizations.dart';
import 'cart_bar_sheet.dart' show showCartBarSheet;
import 'notice.dart';

/// 막대에 잠깐 띄울 담기 결과 한 줄. [seq] 가 바뀔 때마다 한 번 보인다.
typedef CartBarPulse = ({int seq, String text});

/// 상품 카드 `+` 로 담은 결과를 막대가 대신 알린다(사용자 2026-11-22 — 알림이 목록을 가려서).
final cartBarPulseProvider =
    NotifierProvider<CartBarPulseNotifier, CartBarPulse?>(
      CartBarPulseNotifier.new,
    );

class CartBarPulseNotifier extends Notifier<CartBarPulse?> {
  @override
  CartBarPulse? build() => null;

  void pulse(String text) => state = (seq: (state?.seq ?? 0) + 1, text: text);
}

/// 홈·검색 결과·카테고리 목록 아래 떠 있는 장바구니 막대(사용자 캡처 2026-11-20 "24,138원 주문 가능 [2 장바구니]").
/// 서버가 확정한 장바구니에 품목이 있을 때만. 금액은 서버 선택 합계 그대로(없으면 금액 없이).
///
/// 담기 성공은 알림 대신 이 막대가 보인다(레퍼런스처럼): 개수 동그라미가 통통 튀고, 아래 줄이
/// [pulseDuration] 동안 "장바구니에 담았어요"로 바뀐다. 실패는 그대로 알림.
class FloatingCartBar extends ConsumerStatefulWidget {
  const FloatingCartBar({super.key});

  static const pulseDuration = Duration(milliseconds: 1500);

  static final _hosts = <_FloatingCartBarState>{};

  /// 지금 보이는 화면(다른 탭·아래 깔린 화면 제외)에 막대 자리가 있는지. 장바구니가 비어 막대가 아직
  /// 안 보여도 자리가 있으면 true — 처음 담으면 막대가 나타나며 알린다.
  static bool hostedOnScreen() => _hosts.any((s) => s._onScreen());

  @override
  ConsumerState<FloatingCartBar> createState() => _FloatingCartBarState();
}

class _FloatingCartBarState extends ConsumerState<FloatingCartBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bump = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );
  String? _message;
  Timer? _clear;

  bool _onScreen() {
    if (!mounted) return false;
    if (!TickerMode.valuesOf(context).enabled) return false;
    return ModalRoute.of(context)?.isCurrent ?? true;
  }

  @override
  void initState() {
    super.initState();
    FloatingCartBar._hosts.add(this);
  }

  @override
  void dispose() {
    FloatingCartBar._hosts.remove(this);
    _clear?.cancel();
    _bump.dispose();
    super.dispose();
  }

  void _show(String text) {
    _clear?.cancel();
    setState(() => _message = text);
    _bump.forward(from: 0);
    _clear = Timer(FloatingCartBar.pulseDuration, () {
      if (mounted) setState(() => _message = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(cartBarPulseProvider, (prev, next) {
      if (next != null && next.seq != prev?.seq && _onScreen()) {
        _show(next.text);
      }
    });
    final l10n = AppLocalizations.of(context);
    final cart = ref.watch(cartControllerProvider).value?.cart;
    if (cart == null || cart.lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      // 알림(스낵바)이 이 막대를 덮지 않게 위로 띄운다.
      child: NoticeClearance(child: _bar(context, l10n, cart)),
    );
  }

  Widget _bar(BuildContext context, AppLocalizations l10n, Cart cart) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      key: const ValueKey('home-cart-bar'),
      color: scheme.surface,
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(21),
      child: CartBarBody(
        cart: cart,
        open: false,
        message: _message,
        bump: _bump,
        onToggle: () => showCartBarSheet(context),
      ),
    );
  }
}

/// 장바구니 막대 내용(금액·할인 전 금액·^/⌄·주문 가능/부족액 · [장바구니] · 최소 주문 줄). 닫힌 막대와 펼친 시트가 같이 쓴다.
class CartBarBody extends StatelessWidget {
  const CartBarBody({
    super.key,
    required this.cart,
    required this.open,
    this.message,
    this.bump,
    this.onToggle,
    this.rowPadding = const EdgeInsets.fromLTRB(16.4, 8.8, 10, 8.8),
    this.progressPadding = const EdgeInsets.fromLTRB(10.3, 0, 10, 7.6),
  });

  final Cart cart;

  /// 펼친 시트 안이면 true(동그라미가 ⌄).
  final bool open;

  /// 담기 결과 한 줄(닫힌 막대만).
  final String? message;

  /// 개수 동그라미 통통(닫힌 막대만).
  final Animation<double>? bump;
  final VoidCallback? onToggle;
  final EdgeInsets rowPadding;
  final EdgeInsets progressPadding;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final short = cart.minOrderShortfall;
    final fill = minOrderFill(cart);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: rowPadding.copyWith(
            bottom: fill == null ? rowPadding.top : 8.4,
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  key: const ValueKey('home-cart-toggle-area'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggle,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (cart.selectedItemAmount case final a?)
                        // 금액 · 할인 전 금액 · ^ 를 가운데로 맞춘다(레퍼런스: 동그라미가 숫자 가운데 높이).
                        Row(
                          children: [
                            Text(
                              formatKrw(a),
                              key: const ValueKey('home-cart-amount'),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            // 할인 전 금액(줄 긋기, 사용자 지시 2026-11-24) — 서버 할인 전 합계(cart 0.5.0, BR-97)를
                            // 보이기만 한다. 결제 금액은 주문서 견적.
                            if (cartListPrice(cart) case final before?) ...[
                              const SizedBox(width: 5),
                              Text(
                                formatKrw(before),
                                key: const ValueKey('home-cart-before'),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 13,
                                  color: scheme.outline,
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor: scheme.outline,
                                ),
                              ),
                            ],
                            // ^ / ⌄ 검은 동그라미(실측 12.2dp, 앞 글과 4.6dp) — 누르면 추천 시트를 열고 닫는다.
                            if (onToggle != null) ...[
                              const SizedBox(width: 4.6),
                              _ToggleDot(open: open),
                            ],
                          ],
                        ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: message != null
                            ? Text(
                                message!,
                                key: const ValueKey('home-cart-pulse'),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.primary,
                                ),
                              )
                            : Text(
                                switch (short) {
                                  final int s when s > 0 =>
                                    l10n.cartMinOrderShortfall(formatKrw(s)),
                                  _ => l10n.homeCartOrderable,
                                },
                                key: const ValueKey('home-cart-sub'),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: short != null && short > 0
                                      ? scheme.primary
                                      : scheme.onSurface,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              FilledButton(
                key: const ValueKey('home-cart-go'),
                onPressed: () => context.push('/cart'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 37.3),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.fromLTRB(12.6, 0, 12, 0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 담을 때 1 → 1.3 → 1 로 통통.
                    ScaleTransition(
                      scale:
                          TweenSequence<double>([
                            TweenSequenceItem(
                              tween: Tween(begin: 1, end: 1.3),
                              weight: 1,
                            ),
                            TweenSequenceItem(
                              tween: Tween(begin: 1.3, end: 1),
                              weight: 1,
                            ),
                          ]).animate(
                            CurvedAnimation(
                              parent: bump ?? kAlwaysDismissedAnimation,
                              curve: Curves.easeOut,
                            ),
                          ),
                      child: Container(
                        key: const ValueKey('home-cart-count'),
                        width: 21.7,
                        height: 21.7,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Colors.black,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${cart.lines.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      l10n.cartTitle,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (fill != null)
          Padding(
            padding: progressPadding,
            child: _MinOrderProgress(fill: fill),
          ),
      ],
    );
  }
}

class _ToggleDot extends StatelessWidget {
  const _ToggleDot({required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey(open ? 'home-cart-collapse' : 'home-cart-expand'),
    width: 12.2,
    height: 12.2,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: Colors.black,
      shape: BoxShape.circle,
    ),
    child: PmartLineIcon(
      open ? PmartLineIcons.chevronDown : PmartLineIcons.chevronUp,
      size: 8,
      strokeWidth: 3,
      color: Colors.white,
    ),
  );
}

/// 장바구니 막대의 할인 전 금액(줄 긋기). 서버 기간 할인 합계가 0 보다 클 때만 — 둘 중 하나라도 없으면 null.
/// 서버 할인 전 합계(cart 0.5.0 `selectedListAmount`, BR-97) — 앱이 더하지 않는다.
int? cartListPrice(Cart cart) =>
    switch ((cart.selectedListAmount, cart.selectedDiscountAmount)) {
      (final int list, final int d) when d > 0 => list,
      _ => null,
    };

/// 최소 주문 금액까지 얼마나 찼는지(레퍼런스 장바구니 막대 아래 줄). 서버 값으로만 —
/// 모자람 0 이면 가득, 모자람·최소 금액을 다 알 때만 그 비율. 하나라도 모르면 줄을 그리지 않는다(0 으로 꾸미지 않는다).
double? minOrderFill(Cart cart) {
  final short = cart.minOrderShortfall;
  if (short == null) return null;
  if (short <= 0) return 1;
  final min = cart.minOrderAmount;
  if (min == null || min <= 0) return null;
  return ((min - short) / min).clamp(0.0, 1.0);
}

class _MinOrderProgress extends StatelessWidget {
  const _MinOrderProgress({required this.fill});

  final double fill;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      key: const ValueKey('home-cart-progress'),
      borderRadius: BorderRadius.circular(2.1),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: fill),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        builder: (_, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: 4.2,
          color: scheme.primary,
          backgroundColor: scheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}
