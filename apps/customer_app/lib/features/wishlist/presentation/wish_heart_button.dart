import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/notice.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import 'wishlist_controller.dart';

/// 찜 하트(상품 상세·목록 카드·찜한 상품 목록 — customer 0.13.0, ADR-0081).
///
/// 서버가 반영한 뒤에만 채워지거나 비워진다. 비회원이 누르면 로그인 안내(서버에 비회원 찜이 없다).
/// 찜 정보를 아직 못 읽었으면 흐린 하트 — 찜했는지 모르는 채로 "안 찜함"이라고 하지 않는다.
class WishHeartButton extends ConsumerStatefulWidget {
  const WishHeartButton({
    super.key,
    required this.productId,
    this.size = 24,
    this.onImage = false,
    this.onChanged,
  });

  final String productId;
  final double size;

  /// 상품 사진 위에 얹는 모양(흰 동그라미 바탕).
  final bool onImage;

  /// 서버가 반영한 뒤(찜했으면 true, 뺐으면 false).
  final ValueChanged<bool>? onChanged;

  @override
  ConsumerState<WishHeartButton> createState() => _WishHeartButtonState();
}

class _WishHeartButtonState extends ConsumerState<WishHeartButton> {
  bool _busy = false;

  Future<void> _tap() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    if (ref.read(sessionProvider) is! MemberSession) {
      messenger.notice(
        l10n.wishLoginNeeded,
        action: SnackBarAction(
          label: l10n.wishLogin,
          onPressed: () => router.push('/login'),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    final outcome = await ref
        .read(wishlistIdsProvider.notifier)
        .toggle(widget.productId);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case WishAdded():
        widget.onChanged?.call(true);
        messenger.notice(l10n.wishAdded);
      case WishRemoved():
        widget.onChanged?.call(false);
        messenger.notice(l10n.wishRemoved);
      case WishLimitExceeded(:final limit):
        messenger.notice(
          limit == null ? l10n.wishLimitPlain : l10n.wishLimit(limit),
        );
      case WishNotAllowed():
        messenger.notice(l10n.wishNotAllowed);
      case WishUnavailable():
        // 못 읽은 찜 정보를 다시 읽는다.
        ref.invalidate(wishlistIdsProvider);
        messenger.notice(l10n.wishLoadFailed);
      case WishFailed():
        messenger.notice(l10n.wishFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final ids = ref.watch(wishlistIdsProvider);
    final member = ref.watch(sessionProvider) is MemberSession;
    // 회원인데 아직 모른다(읽는 중·실패) — 흐리게.
    final unknown = member && (ids.value == null || ids.hasError);
    final wished = ids.value?.contains(widget.productId) ?? false;
    final icon = PmartLineIcon(
      wished ? PmartLineIcons.heartFilled : PmartLineIcons.heart,
      size: widget.size,
      color: wished
          ? scheme.tertiary
          : unknown
          ? scheme.outlineVariant
          : scheme.onSurface,
    );
    final tooltip = wished ? l10n.wishTooltipRemove : l10n.wishTooltipAdd;
    if (widget.onImage) {
      return Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: scheme.surface.withValues(alpha: 0.92),
          shape: const CircleBorder(),
          elevation: 1,
          shadowColor: Colors.black26,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _busy ? null : _tap,
            child: Padding(padding: const EdgeInsets.all(5), child: icon),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: _busy ? null : _tap,
      icon: icon,
    );
  }
}
