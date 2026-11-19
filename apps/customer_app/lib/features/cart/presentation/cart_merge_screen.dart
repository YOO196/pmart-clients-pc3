import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers.dart';
import '../data/cart_merge_repository.dart';
import '../data/mock_cart_repository.dart';
import '../domain/cart.dart';
import '../domain/cart_merge.dart';
import 'cart_controller.dart';

final cartMergeRepositoryProvider = Provider<CartMergeRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockCartMergeRepository(
      member: switch (ref.read(cartRepositoryProvider)) {
        final MockCartRepository m => m,
        _ => null,
      },
    ),
    PmartEnv.local => ApiCartMergeRepository(
      memberDio: ref.watch(dioProvider),
      guestDio: ref.watch(guestDioProvider),
      guestTokens: ref.watch(guestTokenStoreProvider),
      refreshGuest: authRefresher(
        baseUrl: ref.watch(apiBaseUrlProvider),
        deviceId: ref.watch(deviceIdProvider),
      ),
    ),
  },
);

/// 병합을 거절한 이유. 수량·상한 값은 결과에 없어서 숫자 없는 문구를 쓴다.
String mergeReasonText(AppLocalizations l10n, String? code) => switch (code) {
  CartProblemCode.quantityLimitExceeded => l10n.cartRejectLimitUnknown,
  CartProblemCode.insufficientAvailableQuantity =>
    l10n.cartRejectAvailableUnknown,
  CartProblemCode.skuNotSaleable => l10n.cartRejectNotSaleable,
  MergeProblemCode.sourceItemChanged => l10n.mergeRejectChanged,
  _ => l10n.cartRejectOther,
};

/// SCR-CART-MERGE-001 주문서 로그인 뒤 병합 확인(BR-50 회신). 로그인 전 비회원 장바구니를 읽어
/// 품목이 없으면 바로 주문을 이어 가고(true 로 닫힘), 있으면 고객이 고른 항목만 회원 장바구니로 옮긴다.
/// 닫힐 때 true = 주문 계속, null = 그만(장바구니로).
class CartMergeScreen extends ConsumerStatefulWidget {
  const CartMergeScreen({super.key, required this.guestCartId});

  final String guestCartId;

  @override
  ConsumerState<CartMergeScreen> createState() => _CartMergeScreenState();
}

class _CartMergeScreenState extends ConsumerState<CartMergeScreen> {
  Cart? _guest;
  PmartFailure? _loadError;
  final _selected = <String>{};

  /// 옮길 수량(항목별). 1 ~ 비회원 장바구니 수량 — 서버는 원래 수량보다 많으면 SOURCE_ITEM_CHANGED 로 거절하고,
  /// 적게 옮기면 나머지를 비회원 장바구니에 남긴다(SCR-CART-MERGE-001.ADJUST).
  final _qty = <String, int>{};

  /// 직전 병합에서 거절된 항목의 이유(수량을 바꿔 다시 담을 때 줄 아래에 보인다).
  Map<String, String?> _reasons = const {};
  bool _busy = false;
  String? _error;
  CartMergeResult? _result;
  bool _unknown = false;

  /// 이 선택으로 보낼 키. 결과를 모르면 같은 키로만 다시 확인하고, 고른 것이 바뀌면 새 키.
  IdempotencyKey? _key;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// [only] 가 있으면 그 항목만 골라 둔다(못 담은 상품 다시 고르기).
  Future<void> _load({Set<String>? only}) async {
    setState(() {
      _loadError = null;
      _guest = null;
    });
    try {
      final guest = await ref
          .read(cartMergeRepositoryProvider)
          .guestCart(widget.guestCartId);
      if (!mounted) return;
      if (guest.lines.isEmpty) {
        // 옮길 것이 없다 — 바로 주문서로.
        context.pop(true);
        return;
      }
      setState(() {
        _guest = guest;
        _key = null;
        _qty
          ..clear()
          ..addEntries(
            guest.lines.map((l) => MapEntry(l.cartItemId, l.quantity)),
          );
        _selected
          ..clear()
          ..addAll(
            guest.lines
                .map((l) => l.cartItemId)
                .where((id) => only == null || only.contains(id)),
          );
      });
    } on PmartFailure catch (f) {
      if (mounted) setState(() => _loadError = f);
    }
  }

  void _setQty(String id, int q) => setState(() {
    _qty[id] = q;
    _key = null;
    _error = null;
  });

  /// 결과에서 "못 담은 상품 다시 고르기" — 비회원 장바구니를 다시 읽어(옮긴 것은 빠져 있다) 거절된 항목만 골라 둔다.
  Future<void> _adjust(CartMergeResult r) async {
    final rejected = {
      for (final i in r.items)
        if (i.result == MergeItemResult.rejected && i.sourceItemId != null)
          i.sourceItemId!: i.reasonCode,
    };
    setState(() {
      _result = null;
      _reasons = rejected;
      _error = null;
    });
    await _load(only: rejected.keys.toSet());
  }

  void _toggle(String id, bool on) => setState(() {
    on ? _selected.add(id) : _selected.remove(id);
    _key = null;
    _error = null;
  });

  Future<void> _merge() async {
    final guest = _guest;
    if (guest == null || _selected.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final key = _key ??= IdempotencyKey.generate();
    String? error;
    try {
      final member = (await ref.read(cartControllerProvider.future)).cart;
      final outcome = await ref
          .read(cartMergeRepositoryProvider)
          .merge(
            memberCartId: member.cartId,
            memberCartVersion: member.version,
            guest: guest,
            items: [
              for (final l in guest.lines)
                if (_selected.contains(l.cartItemId))
                  MergeItemRequest(
                    sourceItemId: l.cartItemId,
                    sku: l.sku,
                    quantity: (_qty[l.cartItemId] ?? l.quantity).clamp(
                      1,
                      l.quantity,
                    ),
                  ),
            ],
            key: key,
          );
      switch (outcome) {
        case MergeAnswered(:final result):
          _result = result;
          _unknown = false;
          // 회원 장바구니를 다시 읽는다 — 그 센터 기준 품절·미취급이 보인다.
          ref.invalidate(cartControllerProvider);
        case MergeVersionConflict():
          _key = null;
          ref.invalidate(cartControllerProvider);
          error = l10n.mergeConflict;
        case MergeUnknown():
          _unknown = true;
      }
    } on ProblemFailure catch (f) {
      error = f.problem.code == MergeProblemCode.forbiddenOwner
          ? l10n.mergeForbidden
          : l10n.mergeFailed;
    } on PmartFailure {
      error = l10n.mergeFailed;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final guest = _guest;
    final result = _result;
    final Widget body;
    final Widget? bottom;
    if (_loadError != null) {
      // 읽지 못한 것을 "비회원 장바구니 없음"으로 보지 않는다 — 다시 읽거나, 고객이 알고 건너뛴다.
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.mergeLoadFailed,
                key: const ValueKey('merge-load-error'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const ValueKey('merge-reload'),
                onPressed: _load,
                child: Text(l10n.mergeRetry),
              ),
            ],
          ),
        ),
      );
      bottom = _skipButton(l10n);
    } else if (guest == null) {
      body = const Center(child: CircularProgressIndicator());
      bottom = null;
    } else if (result != null) {
      body = _resultList(l10n, theme, guest, result);
      final anyRejected = result.items.any(
        (i) => i.result == MergeItemResult.rejected,
      );
      bottom = _bar(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              key: const ValueKey('merge-continue'),
              style: _primaryStyle(),
              onPressed: () => context.pop(true),
              child: Text(l10n.mergeContinue),
            ),
            if (anyRejected)
              TextButton(
                key: const ValueKey('merge-adjust'),
                onPressed: () => _adjust(result),
                child: Text(l10n.mergeAdjust),
              ),
          ],
        ),
      );
    } else {
      body = _chooseList(l10n, theme, guest);
      bottom = _bar(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_unknown)
              FilledButton(
                key: const ValueKey('merge-check-again'),
                style: _primaryStyle(),
                onPressed: _busy ? null : _merge,
                child: Text(l10n.mergeCheckAgain),
              )
            else
              FilledButton(
                key: const ValueKey('merge-confirm'),
                style: _primaryStyle(),
                onPressed: (_busy || _selected.isEmpty) ? null : _merge,
                child: Text(l10n.mergeConfirm(_selected.length)),
              ),
            if (!_unknown)
              TextButton(
                key: const ValueKey('merge-skip'),
                onPressed: _busy ? null : () => context.pop(true),
                child: Text(l10n.mergeSkip),
              ),
          ],
        ),
      );
    }
    return Scaffold(
      key: const ValueKey('cart-merge'),
      appBar: AppBar(title: Text(l10n.mergeTitle)),
      body: body,
      bottomNavigationBar: bottom,
    );
  }

  ButtonStyle _primaryStyle() => FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(50),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );

  Widget _bar(Widget child) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: child,
    ),
  );

  Widget _skipButton(AppLocalizations l10n) => _bar(
    TextButton(
      key: const ValueKey('merge-skip'),
      onPressed: () => context.pop(true),
      child: Text(l10n.mergeSkip),
    ),
  );

  Widget _lineText(ThemeData theme, CartLine l) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        l.name ?? l.sku,
        style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15),
      ),
      const SizedBox(height: 2),
      Text(
        [
          ?l.optionLabel,
          AppLocalizations.of(context).mergeQuantity(l.quantity),
        ].join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(
          fontSize: 13,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );

  /// 옮길 수량 ±(1 ~ 비회원 장바구니 수량).
  Widget _stepper(AppLocalizations l10n, ThemeData theme, CartLine l) {
    final q = (_qty[l.cartItemId] ?? l.quantity).clamp(1, l.quantity);
    final locked = _busy || _unknown;
    Widget button(String k, PmartLineIcons icon, VoidCallback? onTap) =>
        InkResponse(
          key: ValueKey('merge-$k-${l.cartItemId}'),
          onTap: onTap,
          radius: 18,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: PmartLineIcon(
              icon,
              size: 18,
              color: onTap == null
                  ? theme.colorScheme.outlineVariant
                  : theme.colorScheme.onSurface,
            ),
          ),
        );
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            'minus',
            PmartLineIcons.minus,
            locked || q <= 1 ? null : () => _setQty(l.cartItemId, q - 1),
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$q',
              key: ValueKey('merge-qty-${l.cartItemId}'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15),
            ),
          ),
          button(
            'plus',
            PmartLineIcons.plus,
            locked || q >= l.quantity
                ? null
                : () => _setQty(l.cartItemId, q + 1),
          ),
        ],
      ),
    );
  }

  Widget _chooseList(AppLocalizations l10n, ThemeData theme, Cart guest) =>
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        children: [
          Text(
            l10n.mergeHeadline,
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 20,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.mergeBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          for (final l in guest.lines)
            InkWell(
              key: ValueKey('merge-item-${l.cartItemId}'),
              onTap: _busy || _unknown
                  ? null
                  : () => _toggle(
                      l.cartItemId,
                      !_selected.contains(l.cartItemId),
                    ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Checkbox(
                      value: _selected.contains(l.cartItemId),
                      onChanged: _busy || _unknown
                          ? null
                          : (v) => _toggle(l.cartItemId, v ?? false),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _lineText(theme, l),
                          if (_reasons.containsKey(l.cartItemId))
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                mergeReasonText(l10n, _reasons[l.cartItemId]),
                                key: ValueKey('merge-reason-${l.cartItemId}'),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 12.5,
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_selected.contains(l.cartItemId) && l.quantity > 1)
                      _stepper(l10n, theme, l),
                  ],
                ),
              ),
            ),
          if (_unknown) ...[
            const SizedBox(height: 12),
            Text(
              l10n.mergeUnknown,
              key: const ValueKey('merge-unknown'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          if (_error case final e?) ...[
            const SizedBox(height: 12),
            Text(
              e,
              key: const ValueKey('merge-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
        ],
      );

  Widget _resultList(
    AppLocalizations l10n,
    ThemeData theme,
    Cart guest,
    CartMergeResult r,
  ) {
    CartLine? lineOf(MergeItem i) =>
        guest.lines.where((l) => l.cartItemId == i.sourceItemId).firstOrNull;
    return ListView(
      key: const ValueKey('merge-result'),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      children: [
        Text(
          switch (r.state) {
            MergeState.confirmed => l10n.mergeResultAll(r.mergedCount),
            MergeState.partial => l10n.mergeResultPartial(r.mergedCount),
            MergeState.rejected => l10n.mergeResultNone,
            MergeState.pending => l10n.mergeResultPending(r.mergedCount),
            MergeState.unknown => l10n.mergeUnknown,
          },
          key: const ValueKey('merge-result-title'),
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 20,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (r.state == MergeState.partial ||
            r.state == MergeState.rejected) ...[
          const SizedBox(height: 6),
          Text(
            l10n.mergeResultKept,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),
        for (final i in r.items)
          Padding(
            key: ValueKey('merge-result-${i.sourceItemId}'),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: switch (lineOf(i)) {
                    final l? => _lineText(theme, l),
                    null => Text(i.sku ?? ''),
                  },
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    switch (i.result) {
                      MergeItemResult.merged => l10n.mergeItemMerged,
                      MergeItemResult.rejected => mergeReasonText(
                        l10n,
                        i.reasonCode,
                      ),
                      MergeItemResult.unknown => l10n.mergeItemUnknown,
                    },
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 13,
                      color: i.result == MergeItemResult.merged
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            PmartLineIcon(
              PmartLineIcons.cart,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.mergeResultNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
