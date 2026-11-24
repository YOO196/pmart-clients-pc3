import 'dart:math' as math;

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

/// `11.30(일)` — 서울 날짜.
String _md(DateTime instant) =>
    DateFormat('M.d(E)', 'ko').format(toSeoulWallClock(instant));

/// 서울 날짜로 센 남은 날 수(오늘 = 0). 표시만 — 쓸 수 있는지는 서버가 정한다.
int couponDaysLeft(DateTime until, DateTime now) {
  final u = toSeoulWallClock(until);
  final n = toSeoulWallClock(now);
  return DateTime.utc(
    u.year,
    u.month,
    u.day,
  ).difference(DateTime.utc(n.year, n.month, n.day)).inDays;
}

/// 만료 임박 기준(초안 10-C: 3일 안이면 분홍 칩).
const couponSoonDays = 3;

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

/// 최소 주문 조건 짧은 표기: "15,000원 이상" / "금액 조건 없음".
String _minText(AppLocalizations l10n, int min, {bool order = false}) =>
    min <= 0
    ? l10n.couponCondNoMin
    : (order
          ? l10n.couponCondMinOrder(formatKrw(min))
          : l10n.couponCondMin(formatKrw(min)));

/// 쿠폰 티켓 카드(초안 10-B·C·D): 왼쪽 연보라 칸에 할인(정률이면 아래 "최대 N원"), 점선 오른쪽에 이름·조건 줄·칩,
/// 오른쪽 끝 [trailing]. [dim] 은 회색 티켓(지난 쿠폰·마감), [stamp] 는 기울어진 도장("사용함"/"기간 만료").
class CouponTicket extends StatelessWidget {
  const CouponTicket({
    super.key,
    required this.discount,
    required this.name,
    required this.lines,
    this.chip,
    this.link,
    this.trailing,
    this.onTap,
    this.dim = false,
    this.stamp,
  });

  final CouponDiscount discount;
  final String name;

  /// 회색 작은 줄들(조건·기한).
  final List<String> lines;

  /// 줄 아래 작은 칩(만료 임박 분홍 / 날짜 회색).
  final Widget? chip;

  /// 줄 아래 보라 글자 링크(쓴 주문 보기 ›).
  final Widget? link;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dim;
  final String? stamp;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = scheme.surfaceContainer; // 티켓 파인 자리는 바탕색
    final leftBg = dim ? scheme.surfaceContainerHigh : scheme.primaryContainer;
    final leftFg = dim ? scheme.outline : scheme.onPrimaryContainer;
    final fg = dim ? scheme.outline : scheme.onSurface;
    final sub = dim ? scheme.outline : scheme.onSurfaceVariant;
    final rate = discount.type == CouponDiscountType.rate;
    final number = NumberFormat.decimalPattern('ko').format(discount.value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 96,
                  color: leftBg,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 14,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text.rich(
                        TextSpan(
                          text: number,
                          children: [
                            TextSpan(
                              text: rate
                                  ? l10n.couponPercentUnit
                                  : l10n.couponWonUnit,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          color: leftFg,
                        ),
                      ),
                      if (rate)
                        if (discount.maxAmount case final m?)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              l10n.couponMaxShort(formatKrw(m)),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                color: leftFg,
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
                // 점선 + 위·아래 파인 반원(바탕색).
                SizedBox(
                  width: 14,
                  child: CustomPaint(
                    painter: _TicketCut(
                      notch: bg,
                      dash: scheme.outlineVariant,
                      left: leftBg,
                    ),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 14, 12, 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: fg,
                                    ),
                                  ),
                                  for (final l in lines)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text(
                                        l,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              fontSize: 12.5,
                                              height: 1.4,
                                              color: sub,
                                            ),
                                      ),
                                    ),
                                  if (chip case final c?)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: c,
                                    ),
                                  if (link case final k?)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: k,
                                    ),
                                ],
                              ),
                            ),
                            if (trailing case final t?) ...[
                              const SizedBox(width: 8),
                              t,
                            ],
                          ],
                        ),
                      ),
                      if (stamp case final s?)
                        Positioned(
                          right: 12,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Transform.rotate(
                              angle: -0.18,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: scheme.outline,
                                    width: 1.4,
                                  ),
                                ),
                                child: Text(
                                  s,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.outline,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
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

/// 티켓 가운데 자르는 선: 세로 점선 + 위·아래 반원 홈.
class _TicketCut extends CustomPainter {
  _TicketCut({required this.notch, required this.dash, required this.left});

  final Color notch;
  final Color dash;
  final Color left;

  @override
  void paint(Canvas canvas, Size size) {
    // 왼쪽 반은 왼쪽 칸 색으로 이어 칠한다(홈이 칸 경계에 걸치게).
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width / 2, size.height),
      Paint()..color = left,
    );
    final p = Paint()
      ..color = dash
      ..strokeWidth = 1.4;
    final x = size.width / 2;
    for (var y = 10.0; y < size.height - 10; y += 7) {
      canvas.drawLine(Offset(x, y), Offset(x, y + 3.5), p);
    }
    final n = Paint()..color = notch;
    canvas.drawCircle(Offset(x, 0), 7, n);
    canvas.drawCircle(Offset(x, size.height), 7, n);
  }

  @override
  bool shouldRepaint(_TicketCut old) =>
      old.notch != notch || old.dash != dash || old.left != left;
}

/// 작은 칩(만료 임박 분홍 / 그 밖 회색).
Widget _expiryChip(
  BuildContext context,
  AppLocalizations l10n,
  DateTime until,
  DateTime now,
) {
  final scheme = Theme.of(context).colorScheme;
  final days = couponDaysLeft(until, now);
  final soon = days <= couponSoonDays;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: soon ? scheme.tertiaryContainer : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      soon
          ? (days <= 0 ? l10n.couponExpiresToday : l10n.couponDaysLeft(days))
          : l10n.couponValidUntil(_md(until)),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: soon ? scheme.onTertiaryContainer : scheme.onSurfaceVariant,
      ),
    ),
  );
}

/// 목록 위 머리: "받을 수 있는 쿠폰 2장"(수는 보라 굵게) + 오른쪽 [action].
class _ListHead extends StatelessWidget {
  const _ListHead({required this.label, required this.count, this.action});

  final String label;
  final int count;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 0, 12),
      child: Row(
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '$label '),
                TextSpan(
                  text: l10n.couponCountUnit(count),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          ?action,
        ],
      ),
    );
  }
}

/// 빈 상태(초안 10-D): 연보라 동그라미 티켓 + 제목 + 안내 + 버튼(있으면).
class _CouponEmpty extends StatelessWidget {
  const _CouponEmpty({
    super.key,
    required this.title,
    this.body,
    this.action,
    this.onAction,
  });

  final String title;
  final String? body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 64),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: PmartBrand.lavender,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: PmartLineIcon(
                PmartLineIcons.ticket,
                size: 32,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (body case final b?) ...[
              const SizedBox(height: 6),
              Text(
                b,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (action case final a?) ...[
              const SizedBox(height: 18),
              OutlinedButton(
                key: const ValueKey('coupon-empty-action'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  foregroundColor: scheme.onSurface,
                  side: BorderSide(color: scheme.outlineVariant),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: onAction,
                child: Text(a),
              ),
            ],
          ],
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
/// 카드는 쿠폰함과 같은 티켓(초안 10 — 오른쪽 끝이 고르기 동그라미).
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
      backgroundColor: theme.colorScheme.surfaceContainer,
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
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          children: [
            for (final c in _byExpiry(list!))
              CouponTicket(
                key: ValueKey('coupon-${c.couponId}'),
                discount: c.discount,
                name: c.name,
                lines: [_minText(l10n, c.minOrderAmount, order: true)],
                chip: _expiryChip(context, l10n, c.validUntil, now),
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

/// 만료 가까운 순(초안 10-C). 서버가 준 목록 안에서만 다시 줄 세운다(같은 날이면 서버 순서 그대로).
List<Coupon> _byExpiry(List<Coupon> list) {
  final indexed = list.indexed.toList()
    ..sort((a, b) {
      final c = a.$2.validUntil.compareTo(b.$2.validUntil);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return [for (final (_, c) in indexed) c];
}

/// 마이 → 쿠폰함: 쿠폰 받기 / 사용 가능(장수) / 지난 쿠폰. 비회원은 조회하지 않고 로그인 안내만.
class CouponBoxScreen extends ConsumerWidget {
  const CouponBoxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final member = ref.watch(sessionProvider) is MemberSession;
    // 탭 장수: 사용 가능 목록 길이(서버 값). 못 읽었으면 수 없이.
    final available = member ? ref.watch(availableCouponsProvider).value : null;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        key: const ValueKey('coupon-box'),
        backgroundColor: member ? scheme.surfaceContainer : null,
        appBar: AppBar(
          title: Text(l10n.couponBoxTitle),
          bottom: member
              ? TabBar(
                  // 초안 10: 고른 탭은 검정 굵게 + 검정 밑줄, 나머지 회색.
                  labelColor: scheme.onSurface,
                  unselectedLabelColor: scheme.onSurfaceVariant,
                  indicatorColor: scheme.onSurface,
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelStyle: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                  unselectedLabelStyle: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w400),
                  tabs: [
                    Tab(
                      key: const ValueKey('coupon-tab-download'),
                      text: l10n.couponTabDownload,
                    ),
                    Tab(
                      key: const ValueKey('coupon-tab-available'),
                      child: Text.rich(
                        TextSpan(
                          text: l10n.couponTabAvailable,
                          children: [
                            if (available case final a? when a.isNotEmpty)
                              TextSpan(
                                text: ' ${a.length}',
                                style: TextStyle(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ),
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

/// 쿠폰 받기 버튼 상태·하나 받기·한번에 받기(쿠폰함 "받을 수 있는 쿠폰"과 홈 쿠폰 시트가 같이 쓴다).
mixin _CampaignDownloads<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// 받는 중인 행사(버튼 잠금).
  final _busy = <String>{};
  bool _allBusy = false;

  String _resultText(AppLocalizations l10n, CouponDownloadResult r) =>
      switch (r) {
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
      };

  Future<void> _download(String promotionId) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy.add(promotionId));
    final r = await downloadCoupon(ref, promotionId);
    if (!mounted) return;
    setState(() => _busy.remove(promotionId));
    showNotice(context, _resultText(l10n, r));
  }

  /// 초안 10-B [모두 받기]: 묶음 API 가 없어 받을 수 있는 행사를 하나씩 차례로 받는다(누르는 동안 잠금).
  /// 끝나면 받은 수/못 받은 수로 한 번에 알린다. 받았는지 모르는 것이 있으면 확인 안내.
  Future<void> _downloadAll(List<CouponCampaign> targets) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _allBusy = true;
      _busy.addAll(targets.map((c) => c.promotionId));
    });
    var ok = 0;
    var failed = 0;
    var unknown = 0;
    for (final c in targets) {
      final r = await downloadCoupon(ref, c.promotionId);
      if (!mounted) return;
      setState(() => _busy.remove(c.promotionId));
      switch (r) {
        case CouponDownloaded():
          ok++;
        case CouponDownloadUnknown():
          unknown++;
        case CouponDownloadRejected() || CouponDownloadFailed():
          failed++;
      }
    }
    setState(() => _allBusy = false);
    showNotice(
      context,
      unknown > 0
          ? l10n.couponDownloadUnknown
          : failed == 0
          ? l10n.couponAllDone(ok)
          : ok == 0
          ? l10n.couponDownloadFailed
          : l10n.couponAllPartial(ok, failed),
    );
  }
}

/// 행사 한 장(쿠폰함·홈 쿠폰 시트 공통). 조건은 서버 값만.
Widget _campaignTicket(
  AppLocalizations l10n,
  CouponCampaign c, {
  required bool busy,
  required VoidCallback onPressed,
}) => CouponTicket(
  key: ValueKey('campaign-${c.promotionId}'),
  discount: c.discount,
  name: c.name,
  dim: c.soldOut,
  lines: [
    [
      _minText(l10n, c.minOrderAmount),
      switch ((c.useDays, c.useUntil)) {
        (final int d, _) => l10n.couponCondDays(d),
        // 초안: 조건 줄은 요일 없이 짧게("11.30까지 사용").
        (null, final DateTime u) => l10n.couponCondUntil(
          DateFormat('M.d', 'ko').format(toSeoulWallClock(u)),
        ),
        _ => null,
      },
    ].nonNulls.join(' · '),
    [
      l10n.couponCondDownloadBy(_md(c.endsAt)),
      if (c.remaining case final r? when r > 0) l10n.couponCondRemaining(r),
    ].join(' · '),
  ],
  trailing: _DownloadButton(
    key: ValueKey('campaign-download-${c.promotionId}'),
    state: c.reachedLimit
        ? _DownloadState.done
        : c.soldOut
        ? _DownloadState.closed
        : _DownloadState.open,
    busy: busy,
    onPressed: onPressed,
  ),
);

/// 홈 쿠폰 줄을 누르면 뜨는 "할인받고 주문해요" 시트(사용자 새 UI 2026-11-24): 모든 쿠폰 + 아래 [한번에 받기].
/// 묶음 받기 API 가 없어 하나씩 차례로 받는다(쿠폰함 [모두 받기]와 같음).
/// 크기는 사용자 폰 캡처 실측(1080px = 411dp, 1dp = 2.625px): 제목 18 굵게(왼쪽 20), 카드 좌우 16·모서리 14·받기 칸 51, 글 14/13.
class CouponCampaignSheet extends ConsumerStatefulWidget {
  const CouponCampaignSheet({super.key});

  @override
  ConsumerState<CouponCampaignSheet> createState() =>
      _CouponCampaignSheetState();
}

class _CouponCampaignSheetState extends ConsumerState<CouponCampaignSheet>
    with _CampaignDownloads<CouponCampaignSheet> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final value = ref.watch(couponCampaignsProvider);
    final now = ref.watch(clockProvider)();
    final list = value.value ?? const <CouponCampaign>[];
    final open = [
      for (final c in list)
        if (!c.reachedLimit && !c.soldOut) c,
    ];
    final title18 = theme.textTheme.titleMedium?.copyWith(
      fontSize: 18,
      height: 1.3,
      fontWeight: FontWeight.w700,
    );
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.9,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(19.8, 9, 7, 0),
              child: Row(
                children: [
                  Expanded(child: Text(l10n.couponSheetTitle, style: title18)),
                  IconButton(
                    key: const ValueKey('coupon-sheet-close'),
                    tooltip: MaterialLocalizations.of(context)
                        .closeButtonTooltip,
                    icon: const PmartLineIcon(
                      PmartLineIcons.close,
                      size: 24,
                      strokeWidth: 2,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: UiStateView<List<CouponCampaign>?>(
                state: uiStateOf(value, isEmpty: (l) => l == null || l.isEmpty),
                onRetry: () => ref.invalidate(couponCampaignsProvider),
                loading: (_) => const PmartListSkeleton(rows: 3),
                empty: (_) => _CouponEmpty(
                  key: const ValueKey('coupon-sheet-empty'),
                  title: l10n.couponCampaignsEmpty,
                ),
                ready: (context, list) => ListView(
                  padding: const EdgeInsets.fromLTRB(16, 26, 16, 16),
                  children: [
                    Text(l10n.couponSheetAll, style: title18),
                    const SizedBox(height: 17.6),
                    for (final c in list!)
                      _SheetCouponCard(
                        key: ValueKey('campaign-${c.promotionId}'),
                        campaign: c,
                        now: now,
                        busy: _busy.contains(c.promotionId),
                        onDownload: () => _download(c.promotionId),
                      ),
                  ],
                ),
              ),
            ),
            PmartBottomBar(
              padding: const EdgeInsets.fromLTRB(12.2, 11, 12.2, 11),
              child: SizedBox(
                height: 49,
                child: FilledButton(
                  key: const ValueKey('coupon-sheet-all'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: _allBusy || open.isEmpty
                      ? null
                      : () => _downloadAll(open),
                  child: _allBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.couponSheetDownloadAll),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 시트의 쿠폰 한 장: 흰 카드(회색 테두리) · 왼쪽 "{할인} {이름}"(할인은 주 색) / "{최소}부터 사용 가능" /
/// 받기 남은 날(임박이면 빨강), 오른쪽 점선 너머 받기 칸(보라 동그라미 ↓ / 받음 ✓ / 마감). 값은 서버 값만.
class _SheetCouponCard extends StatelessWidget {
  const _SheetCouponCard({
    super.key,
    required this.campaign,
    required this.now,
    required this.busy,
    required this.onDownload,
  });

  final CouponCampaign campaign;
  final DateTime now;
  final bool busy;
  final VoidCallback onDownload;

  static const _stub = 51.4;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = campaign;
    final amount = switch (c.discount.type) {
      CouponDiscountType.amount => formatKrw(c.discount.value),
      CouponDiscountType.rate => '${c.discount.value}%',
    };
    final days = couponDaysLeft(c.endsAt, now);
    final soon = days <= couponSoonDays;
    // 회색 줄은 레퍼런스처럼 진한 회색(본문 80%).
    final line = theme.textTheme.bodySmall?.copyWith(
      fontSize: 13,
      height: 1.3,
      color: scheme.onSurface.withValues(alpha: 0.8),
    );
    final stub = c.reachedLimit
        ? Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: PmartBrand.lavender,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: PmartLineIcon(
              PmartLineIcons.check,
              size: 14,
              strokeWidth: 2.4,
              color: scheme.primary,
            ),
          )
        : c.soldOut
        ? Text(
            l10n.couponSoldOut,
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
          )
        : Material(
            key: ValueKey('campaign-download-${c.promotionId}'),
            color: scheme.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: busy ? null : onDownload,
              child: SizedBox.square(
                dimension: 32,
                child: Center(
                  child: busy
                      ? SizedBox.square(
                          dimension: 13,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onPrimary,
                          ),
                        )
                      : PmartLineIcon(
                          PmartLineIcons.download,
                          size: 17,
                          strokeWidth: 2.4,
                          color: scheme.onPrimary,
                        ),
                ),
              ),
            ),
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 13.3),
      child: Opacity(
        opacity: c.soldOut ? 0.5 : 1,
        child: CustomPaint(
          painter: _StubBorderPainter(
            stubWidth: _stub,
            border: scheme.outlineVariant,
            fill: scheme.surface,
          ),
          // "모든 쿠폰" 카드 실측(1080px = 411dp): 높이 127, 왼쪽 16 에 바로픽 아이콘 36(모서리 7), 글까지 10.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 126.9),
            child: Row(
              children: [
                const SizedBox(width: 15.6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image.asset(
                    'assets/images/app_icon.png',
                    key: const ValueKey('campaign-brand'),
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 10.3),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 16, 8, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: amount,
                                style: TextStyle(color: scheme.primary),
                              ),
                              TextSpan(text: ' ${c.name}'),
                            ],
                          ),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontSize: 14,
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3.75),
                        Text(
                          c.minOrderAmount <= 0
                              ? l10n.couponCondNoMin
                              : l10n.couponFromMin(formatKrw(c.minOrderAmount)),
                          style: line,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          days <= 0
                              ? l10n.couponDownloadToday
                              : l10n.couponDaysLeft(days),
                          key: ValueKey('campaign-left-${c.promotionId}'),
                          style: line?.copyWith(
                            color: soon ? scheme.error : null,
                          ),
                        ),
                        const SizedBox(height: 1),
                        // 장바구니 쿠폰은 주문 1건에 1장(ADR-0082).
                        Text(l10n.couponPerOrderOne, style: line),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: _stub,
                  child: Center(child: stub),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 흰 카드 테두리 + 오른쪽 받기 칸 점선, 점선 위아래 파인 반원.
class _StubBorderPainter extends CustomPainter {
  _StubBorderPainter({
    required this.stubWidth,
    required this.border,
    required this.fill,
  });

  final double stubWidth;
  final Color border;
  final Color fill;

  static const _radius = 13.7;
  static const _notch = 4.6;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final r = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.5),
      const Radius.circular(_radius),
    );
    canvas
      ..drawRRect(r, Paint()..color = fill)
      ..drawRRect(r, line);
    final x = size.width - stubWidth;
    for (final y in [0.5, size.height - 0.5]) {
      final c = Offset(x, y);
      canvas
        ..drawCircle(c, _notch, Paint()..color = fill)
        ..drawArc(
          Rect.fromCircle(center: c, radius: _notch),
          y < 1 ? 0 : math.pi,
          math.pi,
          false,
          line,
        );
    }
    const dash = 3.0;
    for (var y = _notch + 3; y < size.height - _notch - 3; y += dash * 2) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, math.min(y + dash, size.height - _notch - 3)),
        line,
      );
    }
  }

  @override
  bool shouldRepaint(_StubBorderPainter old) =>
      old.stubWidth != stubWidth || old.border != border || old.fill != fill;
}

class _CampaignList extends ConsumerStatefulWidget {
  const _CampaignList();

  @override
  ConsumerState<_CampaignList> createState() => _CampaignListState();
}

class _CampaignListState extends ConsumerState<_CampaignList>
    with _CampaignDownloads<_CampaignList> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = ref.watch(couponCampaignsProvider);
    return UiStateView<List<CouponCampaign>?>(
      state: uiStateOf(value, isEmpty: (l) => l == null || l.isEmpty),
      onRetry: () => ref.invalidate(couponCampaignsProvider),
      loading: (_) => const PmartListSkeleton(rows: 3),
      empty: (_) => _CouponEmpty(
        key: const ValueKey('coupon-campaigns-empty'),
        title: l10n.couponCampaignsEmpty,
      ),
      ready: (context, list) {
        final open = [
          for (final c in list!)
            if (!c.reachedLimit && !c.soldOut) c,
        ];
        return RefreshIndicator(
          onRefresh: () => ref.refresh(couponCampaignsProvider.future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            children: [
              _ListHead(
                label: l10n.couponCanDownload,
                count: open.length,
                action: open.isEmpty
                    ? null
                    : FilledButton.icon(
                        key: const ValueKey('coupon-download-all'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: const StadiumBorder(),
                          textStyle: theme.textTheme.labelLarge?.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: _allBusy ? null : () => _downloadAll(open),
                        icon: _allBusy
                            ? const SizedBox.square(
                                dimension: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : PmartLineIcon(
                                PmartLineIcons.download,
                                size: 15,
                                strokeWidth: 2,
                                color: scheme.onPrimary,
                              ),
                        label: Text(l10n.couponDownloadAll),
                      ),
              ),
              for (final c in list)
                _campaignTicket(
                  l10n,
                  c,
                  busy: _busy.contains(c.promotionId),
                  onPressed: () => _download(c.promotionId),
                ),
            ],
          ),
        );
      },
    );
  }
}

enum _DownloadState { open, done, closed }

/// 초안 10-B 받기 동그라미: 보라 ↓ / 받음 연보라 ✓ + "받음" / 마감 회색 "마감".
class _DownloadButton extends StatelessWidget {
  const _DownloadButton({
    super.key,
    required this.state,
    required this.busy,
    required this.onPressed,
  });

  final _DownloadState state;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final circle = switch (state) {
      _DownloadState.open => Material(
        color: scheme.primary,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: busy ? null : onPressed,
          child: SizedBox.square(
            dimension: 40,
            child: Center(
              child: busy
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onPrimary,
                      ),
                    )
                  : PmartLineIcon(
                      PmartLineIcons.download,
                      size: 20,
                      strokeWidth: 2.2,
                      color: scheme.onPrimary,
                    ),
            ),
          ),
        ),
      ),
      _DownloadState.done => Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: PmartBrand.lavender,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: PmartLineIcon(
          PmartLineIcons.check,
          size: 18,
          strokeWidth: 2.2,
          color: scheme.primary,
        ),
      ),
      _DownloadState.closed => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          l10n.couponSoldOut,
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 11,
            color: scheme.outline,
          ),
        ),
      ),
    };
    return Semantics(
      button: state == _DownloadState.open,
      label: switch (state) {
        _DownloadState.open => l10n.couponDownload,
        _DownloadState.done => l10n.couponDownloaded,
        _DownloadState.closed => l10n.couponSoldOut,
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          circle,
          if (state == _DownloadState.done)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                l10n.couponDownloaded,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MyCouponList extends ConsumerWidget {
  const _MyCouponList({required this.past});

  final bool past;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = ref.watch(clockProvider)();
    final provider = past ? pastCouponsProvider : availableCouponsProvider;
    final value = ref.watch(provider);
    return UiStateView<List<Coupon>?>(
      state: uiStateOf(value, isEmpty: (l) => l == null || l.isEmpty),
      onRetry: () => ref.invalidate(provider),
      loading: (_) => const PmartListSkeleton(rows: 3),
      empty: (_) => past
          ? _CouponEmpty(
              key: const ValueKey('coupon-past-empty'),
              title: l10n.couponPastEmpty,
            )
          : _CouponEmpty(
              key: const ValueKey('coupon-available-empty'),
              title: l10n.couponNoneAvailable,
              body: l10n.couponNoneAvailableGuide,
              action: l10n.couponGoDownload,
              onAction: () => DefaultTabController.of(context).animateTo(0),
            ),
      ready: (context, list) => RefreshIndicator(
        onRefresh: () => ref.refresh(provider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          children: [
            if (!past) _ListHead(label: l10n.couponCanUse, count: list!.length),
            for (final c in past ? list! : _byExpiry(list!))
              CouponTicket(
                key: ValueKey('my-coupon-${c.couponId}'),
                discount: c.discount,
                name: c.name,
                dim: past,
                stamp: switch (c.status) {
                  CouponStatus.used => l10n.couponStatusUsed,
                  CouponStatus.expired => l10n.couponStatusExpired,
                  _ => null,
                },
                lines: [
                  if (past)
                    switch (c.status) {
                      CouponStatus.expired => l10n.couponExpiredOn(
                        _md(c.validUntil),
                      ),
                      // BR-85: 쓴 날(서버 usedAt)이 있으면 "11.8(토)에 사용"(초안 10-D).
                      CouponStatus.used when c.usedAt != null =>
                        l10n.couponUsedOn(_md(c.usedAt!)),
                      _ => _minText(l10n, c.minOrderAmount, order: true),
                    }
                  else
                    _minText(l10n, c.minOrderAmount, order: true),
                ],
                chip: past
                    ? null
                    : _expiryChip(context, l10n, c.validUntil, now),
                // 쓴 쿠폰은 쓴 주문으로(서버의 쓴 주문 ID → 주문 상세).
                link: past && c.status == CouponStatus.used
                    ? switch (c.usedOrderId) {
                        final id? => InkWell(
                          key: ValueKey('coupon-used-order-${c.couponId}'),
                          onTap: () => context.push(
                            '/orders/${Uri.encodeComponent(id)}',
                          ),
                          child: Text(
                            l10n.couponSeeOrder,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                        null => null,
                      }
                    : null,
              ),
            if (!past)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: PmartLineIcon(
                        PmartLineIcons.info,
                        size: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.couponUseGuide,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12.5,
                          height: 1.5,
                          color: scheme.onSurfaceVariant,
                        ),
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
