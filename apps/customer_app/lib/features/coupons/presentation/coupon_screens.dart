import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/notice.dart';
import '../../../shared/ui_state_of.dart';
import '../../address/presentation/address_screens.dart' show LoginRequired;
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../checkout/presentation/checkout_controller.dart'
    show clockProvider;
import '../domain/coupon.dart';
import 'coupon_controller.dart';

/// 할인 크기 `7,000원` / `10%` (계약 Discount 그대로 — 할인액 계산 아님).
String couponDiscountText(AppLocalizations l10n, CouponDiscount d) =>
    switch (d.type) {
      CouponDiscountType.amount => formatKrw(d.value),
      CouponDiscountType.rate => l10n.couponRate(d.value),
    };

String _ymd(DateTime instant) =>
    DateFormat('yyyy.MM.dd').format(toSeoulWallClock(instant));

/// `5일 후 만료 (2026.10.15)` — 서울 날짜로 센 날 수(표시만, 쓸 수 있는지는 서버가 정한다).
String couponExpiryText(AppLocalizations l10n, DateTime until, DateTime now) {
  final u = toSeoulWallClock(until);
  final n = toSeoulWallClock(now);
  final days = DateTime.utc(
    u.year,
    u.month,
    u.day,
  ).difference(DateTime.utc(n.year, n.month, n.day)).inDays;
  final date = _ymd(until);
  return days <= 0
      ? l10n.couponExpireToday(date)
      : l10n.couponExpireIn(days, date);
}

/// 쓸 수 없는 쿠폰 사유(서버 `coupon.reason`·차단 detail). 모르는 값은 일반 문구.
String couponReasonText(AppLocalizations l10n, String? reason) =>
    switch (reason) {
      'NOT_FOUND' || 'NOT_OWNER' => l10n.couponReasonNotFound,
      'EXPIRED' => l10n.couponReasonExpired,
      'NOT_STARTED' => l10n.couponReasonNotStarted,
      'HELD' => l10n.couponReasonHeld,
      'USED' => l10n.couponReasonUsed,
      'MIN_ORDER_NOT_MET' => l10n.couponReasonMinOrder,
      _ => l10n.couponReasonUnknown,
    };

/// 쿠폰 카드(레퍼런스 6-5 "할인쿠폰"): 큰 할인 크기 / 이름 / 만료 / 최소주문금액, 오른쪽 고르기 동그라미.
class CouponCard extends StatelessWidget {
  const CouponCard({
    super.key,
    required this.discount,
    required this.name,
    required this.lines,
    this.trailing,
    this.onTap,
    this.dim = false,
    this.note,
  });

  final CouponDiscount discount;
  final String name;

  /// 회색 작은 줄들(만료·최소주문금액 등).
  final List<String> lines;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// 쓸 수 없는 쿠폰(사용·만료) — 흐리게.
  final bool dim;

  /// 빨간 안내 한 줄.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = dim ? scheme.outline : scheme.onSurface;
    final sub = dim ? scheme.outlineVariant : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 18, 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          text: couponDiscountText(l10n, discount),
                          children: [
                            if (discount.type == CouponDiscountType.rate)
                              if (discount.maxAmount case final m?)
                                TextSpan(
                                  text:
                                      '  ${l10n.couponMaxAmount(formatKrw(m))}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: sub,
                                  ),
                                ),
                          ],
                        ),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: fg,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontSize: 18,
                          color: fg,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final l in lines)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            l,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              color: sub,
                            ),
                          ),
                        ),
                      if (note case final n?)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            n,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              color: scheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing case final t?) ...[const SizedBox(width: 12), t],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 고르기 동그라미(고르면 채운 원 + ✓).
class _PickMark extends StatelessWidget {
  const _PickMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 23,
      height: 23,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? scheme.primary : null,
        border: selected
            ? null
            : Border.all(color: scheme.outlineVariant, width: 1.5),
      ),
      child: selected
          ? PmartLineIcon(
              PmartLineIcons.check,
              size: 15,
              color: scheme.onPrimary,
            )
          : null,
    );
  }
}

/// 주문서 → 할인쿠폰 고르기의 결과. 닫기(X)는 null(바꾸지 않음), 고른 것이 없으면 [couponId] = null(쿠폰 빼기).
typedef CouponPick = ({String? couponId});

/// 주문서 "할인쿠폰" 고르기(레퍼런스 6-5). 지금 쓸 수 있는 내 쿠폰만 보인다. 한 장만 고른다(다시 누르면 빼기).
/// 할인 금액·쓸 수 있는지는 고른 뒤 다시 만든 주문서 견적(서버)으로만 보인다 — 여기서 계산하지 않는다.
class CouponPickScreen extends ConsumerStatefulWidget {
  const CouponPickScreen({super.key, this.selected});

  final String? selected;

  @override
  ConsumerState<CouponPickScreen> createState() => _CouponPickScreenState();
}

class _CouponPickScreenState extends ConsumerState<CouponPickScreen> {
  late String? _picked = widget.selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider)();
    final value = ref.watch(availableCouponsProvider);
    return Scaffold(
      key: const ValueKey('coupon-pick'),
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('coupon-pick-close'),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const PmartLineIcon(PmartLineIcons.close),
          onPressed: () => context.pop(),
        ),
        title: Text(l10n.couponTitle),
        centerTitle: true,
        titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      body: UiStateView<List<Coupon>?>(
        state: uiStateOf(value, isEmpty: (l) => l == null || l.isEmpty),
        onRetry: () => ref.invalidate(availableCouponsProvider),
        loading: (_) => const PmartListSkeleton(rows: 3),
        empty: (_) => Center(
          key: const ValueKey('coupon-pick-empty'),
          child: Text(l10n.couponNoneAvailable),
        ),
        ready: (context, list) => ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          children: [
            for (final c in list!)
              CouponCard(
                key: ValueKey('coupon-${c.couponId}'),
                discount: c.discount,
                name: c.name,
                lines: [
                  couponExpiryText(l10n, c.validUntil, now),
                  l10n.couponMinOrder(formatKrw(c.minOrderAmount)),
                ],
                trailing: _PickMark(selected: _picked == c.couponId),
                onTap: () => setState(
                  () => _picked = _picked == c.couponId ? null : c.couponId,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                l10n.couponPickHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Material(
        color: theme.colorScheme.surface,
        elevation: 12,
        shadowColor: Colors.black26,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 16, 10, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(9, 0, 9, 14),
                  child: Text(
                    _picked == null
                        ? l10n.couponUseNone
                        : l10n.couponUseCount(1),
                    key: const ValueKey('coupon-pick-count'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(
                  height: 47,
                  child: FilledButton(
                    key: const ValueKey('coupon-pick-use'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: value.hasValue
                        ? () => context.pop<CouponPick>((couponId: _picked))
                        : null,
                    child: Text(l10n.couponUse),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 마이 → 쿠폰함: 쿠폰 받기 / 사용 가능 / 지난 쿠폰. 비회원은 조회하지 않고 로그인 안내만.
class CouponBoxScreen extends ConsumerWidget {
  const CouponBoxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final member = ref.watch(sessionProvider) is MemberSession;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        key: const ValueKey('coupon-box'),
        appBar: AppBar(
          title: Text(l10n.couponBoxTitle),
          bottom: member
              ? TabBar(
                  tabs: [
                    Tab(
                      key: const ValueKey('coupon-tab-download'),
                      text: l10n.couponTabDownload,
                    ),
                    Tab(
                      key: const ValueKey('coupon-tab-available'),
                      text: l10n.couponTabAvailable,
                    ),
                    Tab(
                      key: const ValueKey('coupon-tab-past'),
                      text: l10n.couponTabPast,
                    ),
                  ],
                )
              : null,
        ),
        body: !member
            ? LoginRequired(message: l10n.couponLoginNeeded)
            : const TabBarView(
                children: [
                  _CampaignList(),
                  _MyCouponList(past: false),
                  _MyCouponList(past: true),
                ],
              ),
      ),
    );
  }
}

class _CampaignList extends ConsumerStatefulWidget {
  const _CampaignList();

  @override
  ConsumerState<_CampaignList> createState() => _CampaignListState();
}

class _CampaignListState extends ConsumerState<_CampaignList> {
  /// 받는 중인 행사(버튼 잠금).
  final _busy = <String>{};

  Future<void> _download(String promotionId) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy.add(promotionId));
    final r = await downloadCoupon(ref, promotionId);
    if (!mounted) return;
    setState(() => _busy.remove(promotionId));
    showNotice(context, switch (r) {
      CouponDownloaded() => l10n.couponDownloadDone,
      CouponDownloadRejected(:final code) => switch (code) {
        CouponProblemCode.limitReached => l10n.couponDownloadLimit,
        CouponProblemCode.soldOut => l10n.couponDownloadSoldOut,
        CouponProblemCode.notActive ||
        CouponProblemCode.unsupported => l10n.couponDownloadNotActive,
        _ => l10n.couponDownloadFailed,
      },
      CouponDownloadUnknown() => l10n.couponDownloadUnknown,
      CouponDownloadFailed() => l10n.couponDownloadFailed,
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(couponCampaignsProvider);
    return UiStateView<List<CouponCampaign>?>(
      state: uiStateOf(value, isEmpty: (l) => l == null || l.isEmpty),
      onRetry: () => ref.invalidate(couponCampaignsProvider),
      loading: (_) => const PmartListSkeleton(rows: 3),
      empty: (_) => Center(
        key: const ValueKey('coupon-campaigns-empty'),
        child: Text(l10n.couponCampaignsEmpty),
      ),
      ready: (context, list) => RefreshIndicator(
        onRefresh: () => ref.refresh(couponCampaignsProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          children: [
            for (final c in list!)
              CouponCard(
                key: ValueKey('campaign-${c.promotionId}'),
                discount: c.discount,
                name: c.name,
                dim: c.soldOut,
                lines: [
                  l10n.couponMinOrder(formatKrw(c.minOrderAmount)),
                  switch ((c.useDays, c.useUntil)) {
                    (final int d, _) => l10n.couponUseDays(d),
                    (null, final DateTime u) => l10n.couponUseUntil(_ymd(u)),
                    _ => '',
                  },
                  l10n.couponDownloadUntil(_ymd(c.endsAt)),
                  if (c.remaining case final r? when r > 0)
                    l10n.couponRemaining(r),
                ].where((s) => s.isNotEmpty).toList(),
                trailing: _DownloadButton(
                  key: ValueKey('campaign-download-${c.promotionId}'),
                  label: c.reachedLimit
                      ? l10n.couponDownloaded
                      : c.soldOut
                      ? l10n.couponSoldOut
                      : l10n.couponDownload,
                  busy: _busy.contains(c.promotionId),
                  onPressed: c.reachedLimit || c.soldOut
                      ? null
                      : () => _download(c.promotionId),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DownloadButton extends StatelessWidget {
  const _DownloadButton({
    super.key,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 36,
    child: OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    ),
  );
}

class _MyCouponList extends ConsumerWidget {
  const _MyCouponList({required this.past});

  final bool past;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final now = ref.watch(clockProvider)();
    final provider = past ? pastCouponsProvider : availableCouponsProvider;
    final value = ref.watch(provider);
    return UiStateView<List<Coupon>?>(
      state: uiStateOf(value, isEmpty: (l) => l == null || l.isEmpty),
      onRetry: () => ref.invalidate(provider),
      loading: (_) => const PmartListSkeleton(rows: 3),
      empty: (_) => Center(
        key: ValueKey(past ? 'coupon-past-empty' : 'coupon-available-empty'),
        child: Text(past ? l10n.couponPastEmpty : l10n.couponNoneAvailable),
      ),
      ready: (context, list) => RefreshIndicator(
        onRefresh: () => ref.refresh(provider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          children: [
            for (final c in list!)
              CouponCard(
                key: ValueKey('my-coupon-${c.couponId}'),
                discount: c.discount,
                name: c.name,
                dim: past,
                lines: [
                  switch (c.status) {
                    CouponStatus.available => couponExpiryText(
                      l10n,
                      c.validUntil,
                      now,
                    ),
                    CouponStatus.used => l10n.couponStatusUsed,
                    CouponStatus.expired => l10n.couponStatusExpired,
                    CouponStatus.unknown => l10n.couponValidUntil(
                      _ymd(c.validUntil),
                    ),
                  },
                  l10n.couponMinOrder(formatKrw(c.minOrderAmount)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
