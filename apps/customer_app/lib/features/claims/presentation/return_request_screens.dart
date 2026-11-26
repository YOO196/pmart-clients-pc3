import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/notice.dart';
import '../../../shared/ui_state_of.dart';
import '../../catalog/presentation/widgets/product_tile_card.dart'
    show ProductImage;
import '../../orders/presentation/orders_providers.dart';
import '../../reviews/domain/reviews.dart' show ReviewPhotoFile;
import '../../reviews/presentation/reviews_controller.dart'
    show ReviewPhotoSource, reviewPhotoPickerProvider;
import '../../support/domain/inquiry.dart' show InquiryCategory;
import '../../support/presentation/inquiry_screens.dart' show InquiryFormArgs;
import '../domain/return_request.dart';
import 'claims_controller.dart';
import 'return_request_controller.dart';

// 반품·교환 신청(레퍼런스 12, 사용자 2026-11-24 A안 — 목 화면 + BR-95). 화면은 지금 앱의 카드·간격·버튼에 맞춘다.
// 실서버는 계약이 없어 신청 불가로 보이고 고객센터 문의로 잇는다. 접수는 승인이 아니다 — 처리 내역이 진행을 보인다.

String rrTypeText(AppLocalizations l10n, ReturnRequestType t) => switch (t) {
  ReturnRequestType.returnItems => l10n.rrTypeReturn,
  ReturnRequestType.exchange => l10n.rrTypeExchange,
};

/// 라우트 조각 ↔ 종류.
String rrTypeSlug(ReturnRequestType t) => switch (t) {
  ReturnRequestType.returnItems => 'return',
  ReturnRequestType.exchange => 'exchange',
};

ReturnRequestType? rrTypeOfSlug(String? s) => switch (s) {
  'return' => ReturnRequestType.returnItems,
  'exchange' => ReturnRequestType.exchange,
  _ => null,
};

String rrReasonText(AppLocalizations l10n, ReturnReason r) => switch (r) {
  ReturnReason.dislike => l10n.rrReasonDislike,
  ReturnReason.wrongOrder => l10n.rrReasonWrongOrder,
  ReturnReason.wrongAddress => l10n.rrReasonWrongAddress,
  ReturnReason.notAsDescribed => l10n.rrReasonNotAsDescribed,
  ReturnReason.malfunction => l10n.rrReasonMalfunction,
  ReturnReason.spoiled => l10n.rrReasonSpoiled,
  ReturnReason.foreignObject => l10n.rrReasonForeignObject,
  ReturnReason.expired => l10n.rrReasonExpired,
  ReturnReason.damaged => l10n.rrReasonDamaged,
  ReturnReason.partlyWrong => l10n.rrReasonPartlyWrong,
  ReturnReason.allWrong => l10n.rrReasonAllWrong,
  ReturnReason.partlyMissing => l10n.rrReasonPartlyMissing,
  ReturnReason.notArrived => l10n.rrReasonNotArrived,
};

String rrGroupText(AppLocalizations l10n, ReturnReasonGroup g) => switch (g) {
  ReturnReasonGroup.changeOfMind => l10n.rrGroupChangeOfMind,
  ReturnReasonGroup.product => l10n.rrGroupProduct,
  ReturnReasonGroup.delivery => l10n.rrGroupDelivery,
};

/// 환불 문의로(계약상 지금 유일한 접수 길).
void _toInquiry(BuildContext context, String orderId) => context.push(
  '/support/inquiries/new',
  extra: InquiryFormArgs(orderId: orderId, category: InquiryCategory.refund),
);

const _cardRadius = BorderRadius.all(Radius.circular(16));

/// 테두리 카드. 안의 줄(라디오·InkWell)이 누름 효과를 그리도록 Material 로 둔다.
Widget _card(ThemeData theme, Widget child) => Material(
  color: theme.colorScheme.surface,
  clipBehavior: Clip.antiAlias,
  shape: RoundedRectangleBorder(
    borderRadius: _cardRadius,
    side: BorderSide(color: theme.colorScheme.outlineVariant),
  ),
  child: child,
);

/// ① 어떤 처리를 원하세요?(레퍼런스 12-1). 자격이 없는 칸은 흐리게 + 고객센터 안내.
class ReturnExchangeEntryScreen extends ConsumerWidget {
  const ReturnExchangeEntryScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final provider = returnEligibilityProvider(orderId);
    return Scaffold(
      appBar: AppBar(
        titleTextStyle: Theme.of(context).appBarTheme.titleTextStyle
            ?.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
        title: Text(l10n.rrTitle),
      ),
      body: UiStateView<ReturnEligibility>(
        state: uiStateOf(ref.watch(provider)),
        onRetry: () => ref.invalidate(provider),
        ready: (context, e) {
          Future<void> open(ReturnRequestType t) async {
            final claimId = await context.push<String>(
              '/orders/$orderId/return-exchange/${rrTypeSlug(t)}',
            );
            if (claimId == null || !context.mounted) return;
            context.pushReplacement('/claims/$claimId');
          }

          Widget choice(ReturnRequestType t, bool allowed) {
            final type = rrTypeText(l10n, t);
            final title = InkWell(
              key: ValueKey('rr-go-${rrTypeSlug(t)}'),
              borderRadius: _cardRadius,
              onTap: allowed ? () => open(t) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 22, 16, 22),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.rrGo(type),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: allowed ? null : theme.colorScheme.outline,
                        ),
                      ),
                    ),
                    PmartLineIcon(
                      PmartLineIcons.chevronRight,
                      size: 20,
                      color: allowed
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.outline,
                    ),
                  ],
                ),
              ),
            );
            return _card(
              theme,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  title,
                  if (!allowed) ...[
                    Divider(height: 1, color: theme.colorScheme.outlineVariant),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                      child: Text(
                        // 반품은 고객센터로만(백엔드 회신 2026-11-25 BR-95 — 사용자 결정).
                        t == ReturnRequestType.returnItems
                            ? l10n.rrReturnViaCenter
                            : l10n.rrNotAllowed(type),
                        key: ValueKey('rr-not-allowed-${rrTypeSlug(t)}'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: ValueKey('rr-inquiry-${rrTypeSlug(t)}'),
                        onPressed: () => _toInquiry(context, orderId),
                        child: Text(l10n.rrInquiry),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ],
              ),
            );
          }

          Widget bullet(String text, {bool strong = false}) => Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: theme.textTheme.bodyMedium),
                Expanded(
                  child: Text(
                    text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: strong ? FontWeight.w700 : null,
                    ),
                  ),
                ),
              ],
            ),
          );

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              Text(
                l10n.rrEntryQuestion,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.rrEntryLead,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),
              // 반품은 늘 흐리게 — 고객 앱 접수는 교환만(BR-95 회신 2026-11-25, 반품 고객 토큰 422 UNSUPPORTED_ACTION).
              choice(ReturnRequestType.returnItems, false),
              const SizedBox(height: 12),
              choice(ReturnRequestType.exchange, e.exchangeAllowed),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainer,
                  borderRadius: _cardRadius,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.rrGuideTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    bullet(l10n.rrGuide1),
                    bullet(l10n.rrGuide2),
                    bullet(l10n.rrGuide3, strong: true),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// ② 반품·교환 신청서(레퍼런스 12-3~7). 접수되면 클레임 ID 를 돌려주며 닫힌다(진입 화면이 처리 내역으로 보낸다).
class ReturnRequestFormScreen extends ConsumerStatefulWidget {
  const ReturnRequestFormScreen({
    super.key,
    required this.orderId,
    required this.type,
  });

  final String orderId;
  final ReturnRequestType type;

  @override
  ConsumerState<ReturnRequestFormScreen> createState() =>
      _ReturnRequestFormScreenState();
}

class _ReturnRequestFormScreenState
    extends ConsumerState<ReturnRequestFormScreen> {
  /// 고른 품목 → 수량.
  final _picked = <String, int>{};
  ReturnReasonGroup _group = ReturnReasonGroup.changeOfMind;
  ReturnReason? _reason;
  bool _detailOpen = true;
  bool _unavailableOpen = false;
  late final _detail = TextEditingController()..addListener(_changed);
  final _photos = <ReviewPhotoFile>[];
  String? _pickupNote;
  String? _redeliveryNote;

  late final _requester = ReturnRequester(
    ref.read(returnRequestRepositoryProvider),
  );

  /// 접수 결과를 모른다 — 입력을 잠그고 같은 키로만 다시 확인한다.
  bool _unknown = false;
  bool _done = false;
  String? _message;

  void _changed() => setState(() {});

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _picked.isNotEmpty ||
      _reason != null ||
      _detail.text.isNotEmpty ||
      _photos.isNotEmpty;

  bool get _locked => _unknown;

  String get _typeText => rrTypeText(AppLocalizations.of(context), widget.type);

  Future<bool> _confirmLeave() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showPmartConfirm(
      context,
      title: l10n.rrLeaveTitle(_typeText),
      body: l10n.rrLeaveBody,
      confirmLabel: l10n.rrLeaveYes,
      cancelLabel: l10n.rrLeaveNo,
      confirmKey: const ValueKey('rr-leave-yes'),
      cancelKey: const ValueKey('rr-leave-no'),
    );
    return ok ?? false;
  }

  Future<void> _addPhotos() async {
    final room = returnPhotosMax - _photos.length;
    if (room <= 0 || _locked) return;
    final files = await ref.read(reviewPhotoPickerProvider)(
      ReviewPhotoSource.gallery,
      room,
    );
    if (!mounted || files.isEmpty) return;
    setState(() => _photos.addAll(files.take(room)));
  }

  Future<void> _pickNote({required bool pickup}) async {
    final l10n = AppLocalizations.of(context);
    final options = pickup
        ? [l10n.rrPickupFrontDoor, l10n.rrPickupHandOver, l10n.rrPickupCallMe]
        : [
            l10n.rrRedeliverBell,
            l10n.rrRedeliverKnock,
            l10n.rrRedeliverQuiet,
            l10n.rrRedeliverInPerson,
            l10n.rrRedeliverCallMe,
          ];
    final current = pickup ? _pickupNote : _redeliveryNote;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RiderNoteSheet(
        title: l10n.rrNoteSheetTitle(
          pickup ? l10n.rrWhenPickup : l10n.rrWhenRedeliver,
        ),
        options: options,
        current: current ?? options.first,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (pickup) {
        _pickupNote = picked;
      } else {
        _redeliveryNote = picked;
      }
    });
  }

  Future<void> _submit(ReturnEligibility e, List<ReturnableLine> picked) async {
    final l10n = AppLocalizations.of(context);
    final reason = _reason;
    if (reason == null) return;
    final exchange = widget.type == ReturnRequestType.exchange;
    setState(() => _message = null);
    final outcome = await _requester.submit(
      ReturnRequestDraft(
        orderId: widget.orderId,
        type: widget.type,
        lines: [
          for (final l in picked)
            (orderLineId: l.orderLineId, qty: _picked[l.orderLineId]!),
        ],
        reason: reason,
        detail: _detail.text.trim().isEmpty ? null : _detail.text.trim(),
        photos: [for (final p in _photos) p.bytes],
        pickupNote: _pickupNote ?? l10n.rrPickupFrontDoor,
        redeliveryNote: exchange
            ? (_redeliveryNote ?? l10n.rrRedeliverBell)
            : null,
      ),
    );
    if (!mounted) return;
    switch (outcome) {
      case CommandDone(:final value):
        _done = true;
        ref
          ..invalidate(orderClaimsProvider(widget.orderId))
          ..invalidate(orderDetailProvider(widget.orderId))
          ..invalidate(returnEligibilityProvider(widget.orderId));
        ScaffoldMessenger.of(context).notice(l10n.rrSubmitted(_typeText));
        context.pop(value.claimId);
      case CommandRejected():
        setState(() {
          _unknown = false;
          _message = l10n.rrRejected;
        });
      case CommandUnknown():
        setState(() {
          _unknown = true;
          _message = l10n.rrUnknown;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = returnEligibilityProvider(widget.orderId);
    return PopScope<Object?>(
      canPop: _done || !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          setState(() => _done = true);
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleTextStyle: Theme.of(context).appBarTheme.titleTextStyle
              ?.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
          title: Text(l10n.rrFormTitle(_typeText)),
        ),
        body: UiStateView<ReturnEligibility>(
          state: uiStateOf(ref.watch(provider)),
          onRetry: () => ref.invalidate(provider),
          ready: (context, e) => _form(context, e),
        ),
      ),
    );
  }

  Widget _form(BuildContext context, ReturnEligibility e) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final type = _typeText;
    final allowed = switch (widget.type) {
      ReturnRequestType.returnItems => e.returnAllowed,
      ReturnRequestType.exchange => e.exchangeAllowed,
    };
    if (!allowed) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            l10n.rrNotAllowed(type),
            key: const ValueKey('rr-form-not-allowed'),
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => _toInquiry(context, widget.orderId),
            child: Text(l10n.rrInquiry),
          ),
        ],
      );
    }
    final picked = [
      for (final l in e.lines)
        if (_picked.containsKey(l.orderLineId)) l,
    ];
    final problems = returnDraftProblems(
      picked: picked,
      reason: _reason,
      detail: _detail.text,
      photos: _photos.length,
    );
    final group = _reason?.group ?? _group;
    final changeOfMind = group == ReturnReasonGroup.changeOfMind;
    final exchange = widget.type == ReturnRequestType.exchange;

    Widget heading(String text, {String? sub}) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(
              sub,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );

    Widget card(List<Widget> children, {Key? key}) => Padding(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _card(
        theme,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );

    final allPicked =
        e.lines.isNotEmpty &&
        e.lines.every((l) => _picked.containsKey(l.orderLineId));

    // 변심 불가 품목을 변심 사유로 고르면 왜 막혔는지 알린다(나머지는 버튼이 흐린 것으로 충분).
    final problemText =
        problems.contains(ReturnDraftProblem.changeOfMindRestricted)
        ? l10n.rrProblemRestricted(type)
        : null;

    return Column(
      children: [
        Expanded(
          child: AbsorbPointer(
            absorbing: _locked,
            child: ListView(
              key: const ValueKey('rr-form'),
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                // ── 상품 선택
                heading(l10n.rrPickTitle(type)),
                card([
                  InkWell(
                    key: const ValueKey('rr-select-all'),
                    onTap: () => setState(() {
                      if (allPicked) {
                        _picked.clear();
                      } else {
                        for (final l in e.lines) {
                          _picked.putIfAbsent(
                            l.orderLineId,
                            () => l.requestableQty,
                          );
                        }
                      }
                    }),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
                      child: Row(
                        children: [
                          _Check(value: allPicked),
                          const SizedBox(width: 8),
                          Text(
                            l10n.rrSelectAll,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Divider(height: 1, color: theme.colorScheme.outlineVariant),
                  for (final (i, l) in e.lines.indexed) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: theme.colorScheme.outlineVariant,
                      ),
                    _LineRow(
                      line: l,
                      type: type,
                      qty: _picked[l.orderLineId],
                      onToggle: () => setState(() {
                        if (_picked.remove(l.orderLineId) == null) {
                          _picked[l.orderLineId] = l.requestableQty;
                        }
                      }),
                      onQty: (q) => setState(() => _picked[l.orderLineId] = q),
                    ),
                  ],
                ]),
                if (e.unavailable.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  card([
                    InkWell(
                      key: const ValueKey('rr-unavailable'),
                      onTap: () =>
                          setState(() => _unavailableOpen = !_unavailableOpen),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.rrUnavailableTitle(type),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            PmartLineIcon(
                              _unavailableOpen
                                  ? PmartLineIcons.chevronUp
                                  : PmartLineIcons.chevronDown,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_unavailableOpen) ...[
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          l10n.rrUnavailableNote,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      for (final u in e.unavailable)
                        Padding(
                          key: ValueKey('rr-unavailable-${u.orderLineId}'),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: Opacity(
                            opacity: 0.4,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        u.title,
                                        style: theme.textTheme.bodyLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      Text(
                                        l10n.rrUnavailableQty(u.qty),
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ProductImage(url: u.imageUrl, size: 48),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ]),
                ],

                // ── 이유 선택
                heading(l10n.rrReasonTitle(type)),
                card([
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: _GroupTabs(
                      selected: _group,
                      onChanged: (g) => setState(() => _group = g),
                    ),
                  ),
                  RadioGroup<ReturnReason>(
                    groupValue: _reason,
                    onChanged: (r) => setState(() => _reason = r),
                    child: Column(
                      children: [
                        for (final r in ReturnReason.values)
                          if (r.group == _group &&
                              (widget.type != ReturnRequestType.exchange ||
                                  r.exchangeable))
                            RadioListTile<ReturnReason>(
                              key: ValueKey('rr-reason-${r.name}'),
                              value: r,
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              title: Text(
                                rrReasonText(l10n, r),
                                style: theme.textTheme.bodyLarge,
                              ),
                            ),
                      ],
                    ),
                  ),
                  if (problemText != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        problemText,
                        key: const ValueKey('rr-problem'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  Divider(height: 1, color: theme.colorScheme.outlineVariant),
                  _detailBlock(context, group),
                ]),

                // ── 방법 선택
                heading(
                  l10n.rrMethodTitle(type),
                  sub: changeOfMind
                      ? l10n.rrMethodNoteFee(type)
                      : l10n.rrMethodNoteFree(type),
                ),
                card([
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.radio_button_checked,
                              color: theme.colorScheme.onSurface,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                exchange
                                    ? l10n.rrMethodPickupRedeliver
                                    : l10n.rrMethodPickup,
                                style: theme.textTheme.bodyLarge,
                              ),
                            ),
                            Text(key: const ValueKey('rr-fee'), switch ((
                              changeOfMind,
                              e.changeOfMindFee,
                            )) {
                              (true, final fee?) => l10n.rrFee(formatKrw(fee)),
                              (true, null) => '',
                              (false, _) => l10n.rrFeeFree,
                            }, style: theme.textTheme.bodyMedium),
                          ],
                        ),
                        if (e.pickupAddress case final a?) ...[
                          const SizedBox(height: 16),
                          Text(
                            l10n.rrPickupInfo,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${a.roadAddress} ${a.detailAddress}'.trim(),
                            style: theme.textTheme.bodyMedium,
                          ),
                          if ([a.receiverName, a.receiverPhone].nonNulls
                              case final who when who.isNotEmpty)
                            Text(
                              who.join(' · '),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                        const SizedBox(height: 18),
                        Text(
                          l10n.rrRiderNote,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _NoteField(
                          key: const ValueKey('rr-note-pickup'),
                          label: l10n.rrWhenPickup,
                          value: _pickupNote ?? l10n.rrPickupFrontDoor,
                          onTap: () => _pickNote(pickup: true),
                        ),
                        if (exchange) ...[
                          const SizedBox(height: 14),
                          _NoteField(
                            key: const ValueKey('rr-note-redeliver'),
                            label: l10n.rrWhenRedeliver,
                            value: _redeliveryNote ?? l10n.rrRedeliverBell,
                            onTap: () => _pickNote(pickup: false),
                          ),
                        ],
                      ],
                    ),
                  ),
                ]),

                // ── 결제 금액 정보(금액은 서버 값만)
                heading(
                  l10n.rrPayTitle,
                  sub: picked.isEmpty
                      ? l10n.rrPayPickFirst(type)
                      : changeOfMind
                      ? l10n.rrPayFeeLater
                      : l10n.rrPayNothing,
                ),
                const SizedBox(height: 12),
                ColoredBox(
                  color: theme.colorScheme.surfaceContainer,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.rrFooterTitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '•  ${l10n.rrFooterNote}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        PmartBottomBar(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_message case final m?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    m,
                    key: const ValueKey('rr-message'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              SizedBox(
                height: 52,
                child: CommandButton(
                  key: const ValueKey('rr-submit'),
                  label: _unknown ? l10n.rrCheckAgain : l10n.rrSubmit(type),
                  onPressed: problems.isEmpty || _unknown
                      ? () => _submit(e, picked)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailBlock(BuildContext context, ReturnReasonGroup group) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final required = group != ReturnReasonGroup.changeOfMind;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const ValueKey('rr-detail-toggle'),
            onTap: () => setState(() => _detailOpen = !_detailOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Text(
                    l10n.rrDetailTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: required
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      required ? l10n.rrRequired : l10n.rrOptional,
                      key: const ValueKey('rr-detail-badge'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: required
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const Spacer(),
                  PmartLineIcon(
                    _detailOpen
                        ? PmartLineIcons.chevronUp
                        : PmartLineIcons.chevronDown,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_detailOpen) ...[
            if (required)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  group == ReturnReasonGroup.product
                      ? l10n.rrDetailNeedProduct
                      : l10n.rrDetailNeedDelivery,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            TextField(
              key: const ValueKey('rr-detail'),
              controller: _detail,
              maxLength: returnDetailMax,
              minLines: 5,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: l10n.rrDetailHint,
                counterText: l10n.rrDetailCount(
                  _detail.text.characters.length,
                  returnDetailMax,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_photos.length < returnPhotosMax)
                  InkWell(
                    key: const ValueKey('rr-photo-add'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: _addPhotos,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const PmartLineIcon(PmartLineIcons.camera, size: 22),
                          const SizedBox(height: 4),
                          Text(
                            l10n.rrPhotoAdd(_photos.length, returnPhotosMax),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                for (final (i, p) in _photos.indexed)
                  Stack(
                    key: ValueKey('rr-photo-$i'),
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          p.bytes,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 72,
                            height: 72,
                            color: theme.colorScheme.surfaceContainer,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IconButton(
                          tooltip: l10n.rrPhotoRemove,
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => _photos.removeAt(i)),
                          icon: const PmartLineIcon(
                            PmartLineIcons.clearCircle,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.rrPhotoNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 둥근 네모 체크(레퍼런스 12-4).
class _Check extends StatelessWidget {
  const _Check({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Checkbox(
      value: value,
      onChanged: (_) {},
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
  );
}

/// 품목 한 줄: 체크 · 이름 · 옵션 줄 · 금액 · 꼬리표 · 수량 조절(2개 이상일 때).
class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    required this.type,
    required this.qty,
    required this.onToggle,
    required this.onQty,
  });

  final ReturnableLine line;
  final String type;
  final int? qty;
  final VoidCallback onToggle;
  final ValueChanged<int> onQty;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final l = line;
    final checked = qty != null;
    final shownQty = qty ?? l.requestableQty;
    Widget tag(String text, Color bg, Color fg, String note) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              text,
              style: theme.textTheme.labelSmall?.copyWith(color: fg),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(note, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
    return InkWell(
      key: ValueKey('rr-line-${l.orderLineId}'),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Check(value: checked),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  Text(
                    l.title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '• ${switch (l.unitPrice) {
                      final p? => l10n.rrLineSub(l.title, l.orderedQty, formatKrw(p)),
                      null => l10n.rrLineSubNoPrice(l.title, l.orderedQty),
                    }}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (l.lineAmount case final a?)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        formatKrw(a),
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  if (l.freshGuarantee)
                    tag(
                      l10n.rrFreshTag,
                      const Color(0xFF0B5B34),
                      Colors.white,
                      l10n.rrFreshText(type),
                    ),
                  if (l.needsAgentApproval)
                    tag(
                      l10n.rrApprovalTag,
                      theme.colorScheme.secondaryContainer,
                      theme.colorScheme.onSecondaryContainer,
                      l10n.rrApprovalText(type),
                    ),
                  if (!l.changeOfMindAllowed)
                    tag(
                      l10n.rrRestrictTag(type),
                      theme.colorScheme.errorContainer,
                      theme.colorScheme.error,
                      l10n.rrRestrictText(type),
                    ),
                  if (l.requestableQty > 1)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: _Stepper(
                          key: ValueKey('rr-qty-${l.orderLineId}'),
                          value: shownQty,
                          max: l.requestableQty,
                          enabled: checked,
                          onChanged: onQty,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: ProductImage(url: l.imageUrl, size: 48),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    super.key,
    required this.value,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final int max;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final faint = theme.colorScheme.outline;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: l10n.rrQtyMinus,
            visualDensity: VisualDensity.compact,
            onPressed: enabled && value > 1 ? () => onChanged(value - 1) : null,
            icon: PmartLineIcon(
              PmartLineIcons.minus,
              size: 18,
              color: enabled && value > 1 ? null : faint,
            ),
          ),
          SizedBox(
            width: 24,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: enabled ? null : faint,
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.rrQtyPlus,
            visualDensity: VisualDensity.compact,
            onPressed: enabled && value < max
                ? () => onChanged(value + 1)
                : null,
            icon: PmartLineIcon(
              PmartLineIcons.plus,
              size: 18,
              color: enabled && value < max ? null : faint,
            ),
          ),
        ],
      ),
    );
  }
}

/// [변심·실수] [상품문제] [배달문제] — 회색 바탕에 고른 칸만 흰 상자(레퍼런스 12-5).
class _GroupTabs extends StatelessWidget {
  const _GroupTabs({required this.selected, required this.onChanged});

  final ReturnReasonGroup selected;
  final ValueChanged<ReturnReasonGroup> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      height: 46,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (final g in ReturnReasonGroup.values)
            Expanded(
              child: GestureDetector(
                key: ValueKey('rr-group-${g.name}'),
                onTap: () => onChanged(g),
                child: Container(
                  alignment: Alignment.center,
                  decoration: g == selected
                      ? BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        )
                      : null,
                  child: Text(
                    rrGroupText(l10n, g),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: g == selected ? FontWeight.w700 : null,
                      color: g == selected
                          ? null
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 라이더 요청사항 칸 — 테두리 위 작은 이름표 + 고른 문구 + ⌄. 누르면 시트.
class _NoteField extends StatelessWidget {
  const _NoteField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          border: const OutlineInputBorder(),
          suffixIcon: const PmartLineIcon(PmartLineIcons.chevronDown, size: 18),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 44,
            minHeight: 24,
          ),
        ),
        child: Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge,
        ),
      ),
    );
  }
}

/// 라이더 요청사항 시트(레퍼런스 12-7): 라디오 줄 + 직접 입력 + [완료].
class _RiderNoteSheet extends StatefulWidget {
  const _RiderNoteSheet({
    required this.title,
    required this.options,
    required this.current,
  });

  final String title;
  final List<String> options;
  final String current;

  @override
  State<_RiderNoteSheet> createState() => _RiderNoteSheetState();
}

class _RiderNoteSheetState extends State<_RiderNoteSheet> {
  static const _custom = '\u0000custom';
  late String _value = widget.options.contains(widget.current)
      ? widget.current
      : _custom;
  late final _text = TextEditingController(
    text: widget.options.contains(widget.current) ? '' : widget.current,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final custom = _value == _custom;
    final result = custom ? _text.text.trim() : _value;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                      icon: const PmartLineIcon(PmartLineIcons.close, size: 24),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              RadioGroup<String>(
                groupValue: _value,
                onChanged: (v) => setState(() => _value = v ?? _value),
                child: Column(
                  children: [
                    for (final (i, o) in widget.options.indexed)
                      RadioListTile<String>(
                        key: ValueKey('rr-note-option-$i'),
                        value: o,
                        title: Text(o, style: theme.textTheme.bodyLarge),
                      ),
                    RadioListTile<String>(
                      key: const ValueKey('rr-note-option-custom'),
                      value: _custom,
                      title: Text(
                        l10n.rrNoteCustom,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
              ),
              if (custom)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: TextField(
                    key: const ValueKey('rr-note-custom'),
                    controller: _text,
                    maxLength: 50,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: l10n.rrNoteCustomHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: SizedBox(
                  height: 52,
                  child: FilledButton(
                    key: const ValueKey('rr-note-done'),
                    onPressed: result.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(result),
                    child: Text(l10n.rrNoteDone),
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
