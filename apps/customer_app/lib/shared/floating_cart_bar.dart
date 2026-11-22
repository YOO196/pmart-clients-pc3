import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../features/cart/presentation/cart_controller.dart'
    show cartControllerProvider;
import '../features/cart/domain/cart.dart' show Cart;
import '../l10n/gen/app_localizations.dart';
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
    final short = cart.minOrderShortfall;
    return Material(
      key: const ValueKey('home-cart-bar'),
      color: scheme.surface,
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (cart.selectedItemAmount case final a?)
                    Text(
                      formatKrw(a),
                      key: const ValueKey('home-cart-amount'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _message != null
                        ? Text(
                            _message!,
                            key: const ValueKey('home-cart-pulse'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 13,
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
                              fontSize: 13,
                              color: short != null && short > 0
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            FilledButton(
              key: const ValueKey('home-cart-go'),
              onPressed: () => context.push('/cart'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 46),
                padding: const EdgeInsets.fromLTRB(10, 0, 18, 0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
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
                          CurvedAnimation(parent: _bump, curve: Curves.easeOut),
                        ),
                    child: Container(
                      key: const ValueKey('home-cart-count'),
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${cart.lines.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.cartTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
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
