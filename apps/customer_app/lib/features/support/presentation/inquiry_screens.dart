import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:pmart_core/pmart_core.dart'
    show IdempotencyKey, PmartFailure, ProblemFailure;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../orders/presentation/orders_providers.dart'
    show orderDetailProvider, orderListProvider, orderStatusText;
import '../../orders/domain/orders.dart'
    show OrderDetail, OrderLineView, OrderListQuery;
import '../../../shared/account_restriction.dart';
import '../../../shared/choice_sheet.dart';
import '../../catalog/presentation/widgets/product_tile_card.dart'
    show ProductImage;
import '../../reviews/presentation/reviews_controller.dart'
    show ReviewPhotoSource, reviewPhotoPickerProvider;
import '../../profile/presentation/profile_controller.dart'
    show profileProvider;
import '../domain/inquiry.dart';
import 'faq_screens.dart' show SupportFaqBlock;
import 'inquiry_controller.dart';
import '../../../shared/notice.dart';

String inquiryCategoryText(AppLocalizations l10n, InquiryCategory? c) =>
    switch (c) {
      InquiryCategory.order => l10n.inqCatOrder,
      InquiryCategory.delivery => l10n.inqCatDelivery,
      InquiryCategory.payment => l10n.inqCatPayment,
      InquiryCategory.refund => l10n.inqCatRefund,
      InquiryCategory.product => l10n.inqCatProduct,
      InquiryCategory.account => l10n.inqCatAccount,
      InquiryCategory.other => l10n.inqCatOther,
      null => l10n.inqCatUnknown,
    };

String inquiryStatusText(AppLocalizations l10n, InquiryStatus s) => switch (s) {
  InquiryStatus.received => l10n.inqStatusReceived,
  InquiryStatus.answered => l10n.inqStatusAnswered,
  InquiryStatus.closed => l10n.inqStatusClosed,
  InquiryStatus.unknown => l10n.inqStatusUnknown,
};

/// 문의 남기기 화면으로 넘기는 값(주문 상세·AI 상담에서 올 때).
@immutable
class InquiryFormArgs {
  const InquiryFormArgs({
    this.orderId,
    this.bodyDraft,
    this.origin = InquiryOrigin.inquiryPage,
    this.deliveryIssue,
    this.deliveryId,
    this.category,
  });

  final String? orderId;

  /// 처음 고를 종류(고객이 바꿀 수 있다). 주문상세 [반품·교환]은 환불(사용자 2026-11-21, 반품 접수는 고객센터만 — claim 0.2.0).
  final InquiryCategory? category;

  /// 본문 초안(AI 상담에서 넘어올 때 고객이 한 질문 — 고칠 수 있다).
  final String? bodyDraft;
  final InquiryOrigin origin;

  /// 배송 신고로 왔으면 그 종류(주문 도움말 화면에서). 종류는 배송·주문은 고정.
  final DeliveryIssue? deliveryIssue;
  final String? deliveryId;
}

String deliveryIssueText(AppLocalizations l10n, DeliveryIssue i) => switch (i) {
  DeliveryIssue.delayed => l10n.inqIssueDelayed,
  DeliveryIssue.notReceived => l10n.inqIssueNotReceived,
  DeliveryIssue.misdelivered => l10n.inqIssueMisdelivered,
};

/// 고객센터 메인. 레퍼런스 "문의하기"(큰 제목 + 화살표 줄) 모양을 따른다.
/// 상담사 실시간 연결은 없다(2026-11-09 결정) — 문의 남기기로 받는다.
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = ref.watch(profileProvider).value;
    final who = [p?.nickname, p?.name]
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .firstOrNull;
    return Scaffold(
      // 레퍼런스 1 고객센터: 가운데 제목
      appBar: AppBar(
        titleTextStyle: Theme.of(context).appBarTheme.titleTextStyle
            ?.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
        title: Text(l10n.supportTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 30, 16, 16),
        children: [
          // 레퍼런스 1 고객센터: 큰 제목 20sp 보통 굵기
          // 사용자 캡처(2026-11-20): "냥냥펀치님 / 무엇을 도와드릴까요?" — 이름은 굵게 + 형광펜 밑줄
          if (who != null)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: who,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      background: Paint()
                        ..color = theme.colorScheme.primaryContainer,
                    ),
                  ),
                  TextSpan(text: l10n.supportNameSuffix),
                ],
              ),
              key: const ValueKey('support-name'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w400,
              ),
            ),
          Text(
            l10n.supportHeadline,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 16),
          // 검색칸 · 자주 묻는 질문 · 분류 칩(회원만 — 레퍼런스 고객센터 메인).
          const SupportFaqBlock(),
          // 묶음 사이 8dp 회색 띠(화면 폭 — 목록 좌우 여백 16 을 넘어 그린다)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: _FullWidthGap(),
          ),
          SupportRow(
            key: const ValueKey('support-chat'),
            label: l10n.supportChat,
            description: l10n.supportChatDesc,
            onTap: () => context.push('/support/chat'),
          ),
          SupportRow(
            key: const ValueKey('support-new-inquiry'),
            label: l10n.supportNewInquiry,
            onTap: () => context.push('/support/inquiries/new'),
          ),
          SupportRow(
            key: const ValueKey('support-my-inquiries'),
            label: l10n.supportMyInquiries,
            onTap: () => context.push('/support/inquiries'),
          ),
        ],
      ),
    );
  }
}

/// 좌우 여백 16 인 목록 안에서 화면 폭 회색 띠.
class _FullWidthGap extends StatelessWidget {
  const _FullWidthGap();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 8,
    child: OverflowBox(
      maxWidth: MediaQuery.sizeOf(context).width,
      child: const PmartSectionGap(height: 8),
    ),
  );
}

/// 레퍼런스의 화살표 줄(글자 17, 세로 여백 넉넉히, 오른쪽 회색 화살표).
class SupportRow extends StatelessWidget {
  const SupportRow({
    super.key,
    required this.label,
    required this.onTap,
    this.description,
    this.bold = false,
  });

  final bool bold;

  final String label;

  /// 굵은 이름 아래 회색 설명(레퍼런스 "채팅 상담").
  final String? description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 16,
                      fontWeight: description == null && !bold
                          ? null
                          : FontWeight.w700,
                    ),
                  ),
                  if (description case final d?)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        d,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            PmartLineIcon(
              PmartLineIcons.chevronRight,
              size: 22,
              color: theme.colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }
}

/// 내 문의 목록(본인만, 최근 순) — 초안 18 B 카드형. 답변 알림이 없어 당겨서 새로 고친다.
class InquiryListScreen extends ConsumerWidget {
  const InquiryListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = ref.watch(inquiryListProvider);
    final member = ref.watch(sessionProvider) is MemberSession;
    final list = value.value;
    return Scaffold(
      backgroundColor: member ? scheme.surfaceContainer : null,
      appBar: AppBar(
        title: Text(l10n.supportMyInquiries),
        backgroundColor: scheme.surface,
      ),
      // 아래 고정 [새 문의 남기기](떠 있는 버튼 대신). 빈 목록은 가운데 버튼이 있어 두지 않는다.
      bottomNavigationBar: list == null || list.items.isEmpty
          ? null
          : SafeArea(
              child: Container(
                color: scheme.surface,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  key: const ValueKey('inquiry-new'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: () => context.push('/support/inquiries/new'),
                  child: Text(l10n.inqNewInquiry),
                ),
              ),
            ),
      body: switch (value) {
        AsyncData(value: null) => const _InquiryGuest(),
        _ => UiStateView<InquiryListState?>(
          loading: (_) => const PmartListSkeleton(),
          state: uiStateOf(value, isEmpty: (s) => s!.items.isEmpty),
          onRetry: () => ref.invalidate(inquiryListProvider),
          empty: (_) => const _InquiriesEmpty(),
          ready: (context, s) => RefreshIndicator(
            onRefresh: () => ref.refresh(inquiryListProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
                  child: Text(
                    l10n.inqListNote,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final i in s!.items) _InquiryTile(item: i),
                _MoreFooter(state: s),
              ],
            ),
          ),
        ),
      },
    );
  }
}

/// 상태 알약 — 답변 대기 회색 · 답변 완료 연보라 · 종료 흐림 · 모름 "확인 중"(초안 18).
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final InquiryStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (bg, fg, dot) = switch (status) {
      InquiryStatus.answered => (scheme.primaryContainer, scheme.primary, true),
      InquiryStatus.closed => (scheme.surfaceContainer, scheme.outline, false),
      _ => (scheme.surfaceContainer, scheme.onSurfaceVariant, true),
    };
    return Container(
      key: const ValueKey('inquiry-status'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            inquiryStatusText(l10n, status),
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 문의 제목 — 없으면 "{종류} 문의".
String inquiryTitleOf(AppLocalizations l10n, InquirySummary s) =>
    s.title ?? l10n.inqTitleOfKind(inquiryCategoryText(l10n, s.category));

/// 시스템 주문 ID 는 보이지 않는다 — 화면용 주문번호(주문 상세에서), 못 읽으면 줄을 두지 않는다.
class _OrderNumberLine extends ConsumerWidget {
  const _OrderNumberLine({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final n = ref.watch(orderDetailProvider(orderId)).value?.orderNumber;
    if (n == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        l10n.inqOrderChosen(n),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

String _shortWhen(DateTime t) =>
    DateFormat('M. d. HH:mm', 'ko').format(toSeoulWallClock(t));

class _InquiryTile extends StatelessWidget {
  const _InquiryTile({required this.item});

  final InquirySummary item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final closed = item.status == InquiryStatus.closed;
    final answered = item.status == InquiryStatus.answered;
    final grey = scheme.onSurfaceVariant;
    final card = Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: ValueKey('inquiry-${item.inquiryId}'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/support/inquiries/${item.inquiryId}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StatusPill(status: item.status),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      inquiryCategoryText(l10n, item.category),
                      style: theme.textTheme.bodySmall?.copyWith(color: grey),
                    ),
                  ),
                  Text(
                    _shortWhen(item.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(color: grey),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                inquiryTitleOf(l10n, item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (item.orderId case final id?) _OrderNumberLine(orderId: id),
              if (answered) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.inqReplyArrived,
                        key: ValueKey('inquiry-replied-${item.inquiryId}'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (item.answeredAt case final at?)
                      Text(
                        '${DateFormat('M/d HH:mm', 'ko').format(toSeoulWallClock(at))} ›',
                        style: theme.textTheme.bodySmall?.copyWith(color: grey),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      // 종료는 카드도 흐리게.
      child: closed ? Opacity(opacity: 0.6, child: card) : card,
    );
  }
}

/// 초안 18 H 빈 목록: 회색 원 + "남긴 문의가 없어요" + 안내 + [자주 묻는 질문] [문의 남기기].
class _InquiriesEmpty extends StatelessWidget {
  const _InquiriesEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      key: const ValueKey('inquiries-empty'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: scheme.surface,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: PmartLineIcon(
                  PmartLineIcons.questionBubble,
                  size: 28,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.inqEmpty,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.inqEmptyHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('inquiries-empty-faq'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: scheme.surface,
                    ),
                    onPressed: () => context.push('/support/faqs'),
                    child: Text(l10n.faqTitle),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('inquiry-new'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () => context.push('/support/inquiries/new'),
                    child: Text(l10n.supportNewInquiry),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreFooter extends ConsumerWidget {
  const _MoreFooter({required this.state});

  final InquiryListState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final more = ref.read(inquiryListProvider.notifier).loadMore;
    final Widget child;
    if (state.loadingMore) {
      child = const CircularProgressIndicator();
    } else if (state.moreFailed) {
      child = Column(
        key: const ValueKey('inquiries-more-failed'),
        children: [
          Text(l10n.inqMoreFailed),
          TextButton(onPressed: more, child: Text(l10n.loadMore)),
        ],
      );
    } else if (state.nextCursor != null) {
      child = OutlinedButton(
        key: const ValueKey('inquiries-more'),
        onPressed: more,
        child: Text(l10n.loadMore),
      );
    } else {
      return const SizedBox(height: 16);
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(child: child),
    );
  }
}

/// 문의 상세 — 초안 18 타임라인: 문의를 남겼어요 → 답변이 왔어요(답변마다) / 답변을 기다리고 있어요 → 만족도 →
/// 문의를 닫았어요. 고객이 이어 쓰는 기능은 없다(새 문의로).
class InquiryDetailScreen extends ConsumerWidget {
  const InquiryDetailScreen({super.key, required this.inquiryId});

  final String inquiryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final provider = inquiryProvider(inquiryId);
    final loaded = ref.watch(provider).value;
    final grey = scheme.onSurfaceVariant;
    TextStyle? meta() => theme.textTheme.bodySmall?.copyWith(color: grey);
    BoxDecoration box(Color c, {Color? border}) => BoxDecoration(
      color: c,
      borderRadius: BorderRadius.circular(12),
      border: border == null ? null : Border.all(color: border),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.inqDetailTitle)),
      // ④ 종료: 닫기 없이 아래 고정 [새 문의 남기기].
      bottomNavigationBar: loaded?.closed ?? false
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: OutlinedButton(
                  key: const ValueKey('inquiry-new-after-close'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: () => context.push('/support/inquiries/new'),
                  child: Text(l10n.inqNewInquiry),
                ),
              ),
            )
          : null,
      body: UiStateView<InquiryDetail>(
        state: uiStateOf(ref.watch(provider)),
        onRetry: () => ref.invalidate(provider),
        ready: (context, d) {
          final s = d.summary;
          return RefreshIndicator(
            onRefresh: () => ref.refresh(provider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Row(
                  children: [
                    _StatusPill(status: s.status),
                    const SizedBox(width: 8),
                    Text(inquiryCategoryText(l10n, s.category), style: meta()),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  inquiryTitleOf(l10n, s),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (s.orderId case final orderId?) ...[
                  const SizedBox(height: 12),
                  _InquiryOrderCard(orderId: orderId),
                ],
                const SizedBox(height: 16),
                // ● 문의를 남겼어요
                _TimelineStep(
                  dot: _Dot.ring,
                  title: l10n.inqStepAsked,
                  meta: formatSeoulDateTime(s.createdAt),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: box(scheme.surfaceContainer),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.body, key: const ValueKey('inquiry-body')),
                        if (d.photoIds.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final p in d.photoIds)
                                _InquiryPhotoThumb(photoId: p),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // ● 답변이 왔어요(답변마다) — 없으면 ○ 답변을 기다리고 있어요
                if (d.replies.isEmpty && !d.closed)
                  _TimelineStep(
                    dot: _Dot.dashed,
                    title: l10n.inqStepWaiting,
                    last: true,
                    child: Text(
                      l10n.inqStepWaitingNote,
                      key: const ValueKey('inquiry-no-reply'),
                      style: meta(),
                    ),
                  )
                else
                  for (final (i, r) in d.replies.indexed)
                    _TimelineStep(
                      dot: _Dot.ring,
                      title: l10n.inqReplyArrived,
                      meta: [
                        if (r.createdAt case final t?) formatSeoulTime(t),
                        l10n.inqReplyFrom,
                      ].join(' · '),
                      last:
                          i == d.replies.length - 1 &&
                          !d.closed &&
                          !d.canRate &&
                          d.satisfaction == null,
                      child: Container(
                        key: ValueKey('inquiry-reply-${r.replyId}'),
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: box(
                          PmartBrand.lavenderMist,
                          border: PmartBrand.lavender,
                        ),
                        child: Text(r.body),
                      ),
                    ),
                // ● 만족도(답변 뒤 한 번) / 평가를 남겼어요
                if (d.satisfaction case final sat?)
                  _TimelineStep(
                    dot: _Dot.filled,
                    title: l10n.inqStepRated,
                    last: !d.closed,
                    child: Container(
                      key: const ValueKey('inquiry-rated'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: box(scheme.surfaceContainer),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _RateFace(score: sat.score, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  rateLabel(l10n, sat.score),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (sat.comment case final c?)
                                  Text('"$c"', style: meta()),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (d.canRate && !d.closed)
                  _TimelineStep(
                    dot: _Dot.filled,
                    title: l10n.inqStepRate,
                    last: true,
                    child: _RateBox(inquiryId: inquiryId),
                  ),
                // ● 문의를 닫았어요(회색)
                if (d.closed)
                  _TimelineStep(
                    dot: _Dot.grey,
                    title: l10n.inqStepClosed,
                    meta: d.closedAt == null
                        ? null
                        : formatSeoulDateTime(d.closedAt!),
                    last: true,
                    child: Text(
                      l10n.inqClosedNote,
                      key: const ValueKey('inquiry-closed-note'),
                      style: meta(),
                    ),
                  ),
                // 아래 작은 밑줄 [문의 닫기](· [새 문의 남기기] — 평가를 남겼으면).
                if (!d.closed)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _CloseButton(inquiryId: inquiryId),
                        if (d.satisfaction != null)
                          _UnderlineLink(
                            key: const ValueKey('inquiry-new-link'),
                            label: l10n.inqNewInquiry,
                            onTap: () => context.push('/support/inquiries/new'),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 작은 회색 밑줄 글자 버튼(초안 18 "문의 닫기 · 새 문의 남기기").
class _UnderlineLink extends StatelessWidget {
  const _UnderlineLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: theme.colorScheme.onSurfaceVariant,
        textStyle: theme.textTheme.bodySmall?.copyWith(
          fontSize: 13,
          decoration: TextDecoration.underline,
        ),
      ),
      child: Text(label),
    );
  }
}

/// 문의한 주문 칸(회색) — 대표 사진 · "이름 외 N개" · 주문번호 ›. 누르면 주문 상세.
class _InquiryOrderCard extends ConsumerWidget {
  const _InquiryOrderCard({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final o = ref.watch(orderDetailProvider(orderId)).value;
    final names = <String>[
      for (final l in o?.lines ?? const <OrderLineView>[]) ?l.productName,
    ];
    final goods = switch (names) {
      [] => l10n.inqOrderLink,
      [final one] => one,
      [final first, ...] => l10n.ordersRepresentative(first, names.length - 1),
    };
    final image = o?.lines.firstOrNull?.imageUrl;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: const ValueKey('inquiry-order'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/orders/$orderId'),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ProductImage(url: image, size: 40, radius: 8),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goods,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (o?.orderNumber case final n?)
                      Text(
                        l10n.inqOrderChosen(n),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              PmartLineIcon(
                PmartLineIcons.chevronRight,
                size: 16,
                color: scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Dot { ring, dashed, filled, grey }

/// 타임라인 한 칸: 왼쪽 점 + 아래로 이어지는 세로 선, 오른쪽 제목·시각 + 내용.
class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.dot,
    required this.title,
    required this.child,
    this.meta,
    this.last = false,
  });

  final _Dot dot;
  final String title;
  final String? meta;
  final Widget child;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dotWidget = switch (dot) {
      _Dot.ring => Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surface,
          border: Border.all(color: scheme.primary, width: 2),
        ),
      ),
      _Dot.dashed => CustomPaint(
        size: const Size.square(14),
        painter: _DashedCirclePainter(scheme.outline),
      ),
      _Dot.filled => Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.primary,
        ),
      ),
      _Dot.grey => Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.outline,
        ),
      ),
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                const SizedBox(height: 3),
                dotWidget,
                if (!last)
                  Expanded(
                    child: Container(width: 1.5, color: scheme.outlineVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (meta case final m?)
                          TextSpan(
                            text: '  $m',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  child,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  _DashedCirclePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final r = size.width / 2 - 1;
    const n = 10;
    for (var i = 0; i < n; i++) {
      final a = i * 2 * math.pi / n;
      canvas.drawArc(
        Rect.fromCircle(center: size.center(Offset.zero), radius: r),
        a,
        math.pi / n,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter old) => old.color != color;
}

/// 붙은 사진 한 장(본인 토큰으로 받은 바이트). 실패는 "불러오지 못했어요" 칸.
class _InquiryPhotoThumb extends ConsumerWidget {
  const _InquiryPhotoThumb({required this.photoId});

  final String photoId;

  static const size = 88.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final value = ref.watch(inquiryPhotoProvider(photoId));
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ClipRRect(
      key: ValueKey('inquiry-photo-$photoId'),
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.square(
        dimension: size,
        child: switch (value) {
          AsyncData(:final value) => Image.memory(
            value,
            fit: BoxFit.cover,
            cacheWidth: (size * dpr).round(),
          ),
          AsyncError() => InkWell(
            onTap: () => ref.invalidate(inquiryPhotoProvider(photoId)),
            child: ColoredBox(
              color: theme.colorScheme.surfaceContainer,
              child: Center(
                child: Text(
                  l10n.inqPhotoLoadFailed,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ),
          ),
          _ => ColoredBox(color: theme.colorScheme.surfaceContainer),
        },
      ),
    );
  }
}

/// 만족도 점수(1~5)의 문구(레퍼런스 고객센터 2-2-2).
String rateLabel(AppLocalizations l10n, int score) => switch (score) {
  5 => l10n.inqRate5,
  4 => l10n.inqRate4,
  3 => l10n.inqRate3,
  2 => l10n.inqRate2,
  _ => l10n.inqRate1,
};

IconData _rateIcon(int s) => switch (s) {
  5 => Icons.sentiment_very_satisfied,
  4 => Icons.sentiment_satisfied,
  3 => Icons.sentiment_neutral,
  2 => Icons.sentiment_dissatisfied,
  _ => Icons.sentiment_very_dissatisfied,
};

Color _rateColor(int s) => switch (s) {
  5 => const Color(0xFF12B76A),
  4 => const Color(0xFF66C61C),
  3 => const Color(0xFFF5B800),
  2 => const Color(0xFFF79009),
  _ => const Color(0xFFF04438),
};

/// 답변 뒤 만족도(1~5점 + 한 줄, 한 번). 서버가 받은 뒤 상세를 다시 읽어 보인다.
class _RateBox extends ConsumerStatefulWidget {
  const _RateBox({required this.inquiryId});

  final String inquiryId;

  @override
  ConsumerState<_RateBox> createState() => _RateBoxState();
}

class _RateBoxState extends ConsumerState<_RateBox> {
  int? _score;
  final _comment = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final score = _score;
    if (score == null) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final comment = _comment.text.trim();
    setState(() => _busy = true);
    String message;
    try {
      final d = await runInquiryCommand(
        ref,
        widget.inquiryId,
        (key) => ref
            .read(inquiriesRepositoryProvider)
            .rate(
              widget.inquiryId,
              score: score,
              comment: comment.isEmpty ? null : comment,
              key: key,
            ),
        applied: (d) => d.satisfaction != null,
      );
      message = d == null ? l10n.inqRateFailed : l10n.inqRateDone;
    } on ProblemFailure catch (f) {
      // 이미 남김·답변 전은 최신 상세로 다시 보인다.
      ref.invalidate(inquiryProvider(widget.inquiryId));
      message = f.problem.code == InquiryProblemCode.alreadyRated
          ? l10n.inqRateDone
          : l10n.inqRateFailed;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.notice(message);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const ValueKey('inquiry-rate'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.inqRateTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.inqRateSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          // 초안 18: 지금 앱 얼굴을 가로 한 줄(왼쪽 1 → 오른쪽 5). 고르기 전엔 모두 흐리게, 고르면 그 얼굴만 크게·선명 + 연보라.
          Row(
            children: [
              for (final s in const [1, 2, 3, 4, 5])
                Expanded(
                  child: InkWell(
                    key: ValueKey('inquiry-rate-$s'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: _busy ? null : () => setState(() => _score = s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _score == s ? scheme.primaryContainer : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Opacity(
                            opacity: _score == s ? 1 : 0.45,
                            child: _RateFace(
                              score: s,
                              size: _score == s ? 32 : 24,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            rateShort(l10n, s),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: _score == s
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                              fontWeight: _score == s
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_score case final s?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                rateLabel(l10n, s),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('inquiry-rate-comment'),
            controller: _comment,
            enabled: !_busy,
            maxLength: inquiryCommentMax,
            // 초안 18: 회색 채운 한 줄 칸(테두리 없음).
            decoration: InputDecoration(
              hintText: l10n.inqRateComment,
              counterText: '',
              filled: true,
              fillColor: scheme.surfaceContainer,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            key: const ValueKey('inquiry-rate-send'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
            onPressed: _busy || _score == null ? null : _send,
            child: Text(l10n.inqRateSubmit),
          ),
        ],
      ),
    );
  }
}

/// 만족도 얼굴(색 채운 동그라미 + 흰 얼굴) — 레퍼런스 2-2-2, 색은 사용자 "기존 이모지 사용"으로 팔레트 밖 그대로.
class _RateFace extends StatelessWidget {
  const _RateFace({required this.score, required this.size});

  final int score;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: _rateColor(score), shape: BoxShape.circle),
    alignment: Alignment.center,
    child: Icon(_rateIcon(score), size: size * 0.84, color: Colors.white),
  );
}

/// 얼굴 아래 짧은 말(초안 18): 매우 아쉬워요 / 아쉬워요 / 그럭저럭 / 도움 됐어요 / 많은 도움.
String rateShort(AppLocalizations l10n, int score) => switch (score) {
  5 => l10n.inqRateShort5,
  4 => l10n.inqRateShort4,
  3 => l10n.inqRateShort3,
  2 => l10n.inqRateShort2,
  _ => l10n.inqRateShort1,
};

/// 문의 닫기(확인 뒤). 닫힌 문의는 다시 열 수 없다.
class _CloseButton extends ConsumerStatefulWidget {
  const _CloseButton({required this.inquiryId});

  final String inquiryId;

  @override
  ConsumerState<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends ConsumerState<_CloseButton> {
  bool _busy = false;

  Future<void> _close() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.inqCloseConfirmTitle),
        content: Text(l10n.inqCloseConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.inqCloseCancel),
          ),
          TextButton(
            key: const ValueKey('inquiry-close-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.inqClose),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    String message;
    try {
      final d = await runInquiryCommand(
        ref,
        widget.inquiryId,
        (key) => ref
            .read(inquiriesRepositoryProvider)
            .close(widget.inquiryId, key: key),
        applied: (d) => d.closed,
      );
      message = d == null ? l10n.inqCloseFailed : l10n.inqClosed;
    } on ProblemFailure catch (f) {
      ref.invalidate(inquiryProvider(widget.inquiryId));
      message = f.problem.code == InquiryProblemCode.inquiryClosed
          ? l10n.inqClosed
          : l10n.inqCloseFailed;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.notice(message);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 초안 18: 앱바 대신 아래 작은 밑줄 글자(확인 대화는 그대로).
    return _UnderlineLink(
      key: const ValueKey('inquiry-close'),
      label: l10n.inqClose,
      onTap: _busy ? null : _close,
    );
  }
}

/// 작성 화면의 사진 한 칸.
class _PhotoSlot {
  _PhotoSlot(this.bytes, this.name, this.key);

  final Uint8List bytes;
  final String name;

  /// 이 칸의 올리기 키. 다시 올리기도 같은 키(같은 photoId).
  final IdempotencyKey key;
  String? photoId;
  bool uploading = false;
  bool failed = false;
}

class _PhotoSlotView extends StatelessWidget {
  const _PhotoSlotView({
    super.key,
    required this.slot,
    required this.onRemove,
    required this.onRetry,
  });

  final _PhotoSlot slot;
  final VoidCallback? onRemove;
  final VoidCallback? onRetry;

  static const size = 72.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              slot.bytes,
              fit: BoxFit.cover,
              cacheWidth: (size * dpr).round(),
            ),
          ),
          if (slot.uploading)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (slot.failed)
            Material(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: onRetry,
                child: Center(
                  child: Text(
                    l10n.inqPhotoRetry,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ),
            ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              tooltip: l10n.inqPhotoRemove,
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0x99000000),
                foregroundColor: Colors.white,
                minimumSize: const Size(24, 24),
                padding: EdgeInsets.zero,
                // 72dp 칸 가운데 "다시 올리기"를 가리지 않게 누르는 영역을 버튼 크기로.
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
              onPressed: onRemove,
              icon: const PmartLineIcon(PmartLineIcons.close),
            ),
          ),
        ],
      ),
    );
  }
}

/// 문의에 붙일 주문 고르기 — 본인 주문 목록 첫 쪽(최근 순). 실패는 오류로(빈 목록 아님).
class _OrderPickerSheet extends ConsumerWidget {
  const _OrderPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final page = ref.watch(orderListProvider(const OrderListQuery()));
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                l10n.inqPickOrderTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Flexible(
              child: switch (page) {
                AsyncData(:final value)
                    when (value?.items ?? const []).isEmpty =>
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      l10n.inqPickOrderEmpty,
                      key: const ValueKey('inq-pick-empty'),
                    ),
                  ),
                AsyncData(:final value) => ListView(
                  shrinkWrap: true,
                  children: [
                    for (final o in value!.items)
                      ListTile(
                        key: ValueKey('inq-pick-${o.orderId}'),
                        title: Text(
                          o.orderedAt == null
                              ? o.orderId
                              : formatSeoulDateTime(o.orderedAt!),
                        ),
                        subtitle: Text(
                          '${orderStatusText(l10n, o.status)} · ${o.orderId}',
                        ),
                        onTap: () => Navigator.of(context).pop(o.orderId),
                      ),
                  ],
                ),
                AsyncError() => Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.inqPickOrderFailed,
                        key: const ValueKey('inq-pick-error'),
                      ),
                      TextButton(
                        onPressed: () => ref.invalidate(
                          orderListProvider(const OrderListQuery()),
                        ),
                        child: Text(l10n.chatRetry),
                      ),
                    ],
                  ),
                ),
                _ => const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 문의 남기기. 접수일 뿐 취소·환불을 실행하지 않는다. 사진 첨부·답변 알림은 없다(1차).
class InquiryFormScreen extends ConsumerStatefulWidget {
  const InquiryFormScreen({super.key, this.args = const InquiryFormArgs()});

  final InquiryFormArgs args;

  @override
  ConsumerState<InquiryFormScreen> createState() => _InquiryFormScreenState();
}

class _InquiryFormScreenState extends ConsumerState<InquiryFormScreen> {
  late final _title = TextEditingController();
  late final _body = TextEditingController(text: widget.args.bodyDraft ?? '');
  InquiryCategory? _category;
  late String? _orderId = widget.args.orderId;
  bool _busy = false;

  /// 이 화면이 사는 동안 하나만 둔다 — 결과 불명일 때의 키·본문을 들고 있다.
  late final _submitter = InquirySubmitter(
    ref.read(inquiriesRepositoryProvider),
  );

  /// 접수 결과를 모른다 — 본문을 잠그고 같은 키로만 다시 확인한다.
  bool _unknown = false;

  /// 서버가 접수를 확정했다 — 완료 화면(초안 17 D). 사진 수는 보낸 것.
  ({InquiryCategory category, int photos})? _done;
  String? _message;

  @override
  void initState() {
    super.initState();
    // 주문에서 들어오면 종류를 비워 두지 않는다(고객이 바꿀 수 있다). 배송 신고는 배송으로 고정한다(계약).
    if (widget.args.deliveryIssue != null) {
      _category = InquiryCategory.delivery;
    } else if (widget.args.category case final c?) {
      _category = c;
    } else if (_orderId != null) {
      _category = InquiryCategory.order;
    }
    _body.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  /// 고른 사진 칸. 고르면 바로 올린다(칸마다 자기 키 — 다시 올리기도 같은 키).
  final _photos = <_PhotoSlot>[];
  String? _photoMessage;

  bool get _photosReady => _photos.every((p) => p.photoId != null);

  bool get _canSend =>
      !_busy &&
      _category != null &&
      _body.text.trim().isNotEmpty &&
      _photosReady;

  Future<void> _addPhotos() async {
    final room = inquiryPhotosMax - _photos.length;
    if (room <= 0) return;
    final files = await ref.read(reviewPhotoPickerProvider)(
      ReviewPhotoSource.gallery,
      room,
    );
    if (!mounted || files.isEmpty) return;
    final slots = [
      for (final f in files.take(room))
        _PhotoSlot(f.bytes, f.name, IdempotencyKey.generate()),
    ];
    setState(() {
      _photos.addAll(slots);
      _photoMessage = null;
    });
    for (final s in slots) {
      unawaited(_upload(s));
    }
  }

  Future<void> _upload(_PhotoSlot s) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      s.uploading = true;
      s.failed = false;
    });
    try {
      final id = await ref
          .read(inquiriesRepositoryProvider)
          .uploadPhoto(s.bytes, name: s.name, key: s.key);
      if (!mounted) return;
      setState(() {
        s.photoId = id;
        s.uploading = false;
      });
    } on PmartFailure catch (f) {
      if (!mounted) return;
      setState(() {
        s.uploading = false;
        s.failed = true;
        _photoMessage = switch (f) {
          ProblemFailure(:final problem)
              when problem.code == InquiryProblemCode.photoInvalid =>
            l10n.inqPhotoInvalid,
          ProblemFailure(:final problem) when problem.status == 503 =>
            l10n.inqPhotoUnavailable,
          _ => l10n.inqPhotoFailed,
        };
      });
    }
  }

  /// 종류 고르기 — 아래 시트(초안 17 I).
  Future<void> _pickCategory() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showChoiceSheet<InquiryCategory?>(
      context,
      title: l10n.inqCategoryLabel,
      closeKey: const ValueKey('inq-cat-close'),
      selected: _category,
      options: [
        for (final c in InquiryCategory.values)
          (c, inquiryCategoryText(l10n, c), ValueKey('inq-cat-${c.name}')),
      ],
    );
    if (picked != null && mounted) setState(() => _category = picked);
  }

  Future<void> _pickOrder() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _OrderPickerSheet(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _orderId = picked;
      _category ??= InquiryCategory.order;
    });
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final category = _category;
    if (category == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final title = _title.text.trim();
    final outcome = await _submitter.submit(
      InquiryDraft(
        category: category,
        body: _body.text.trim(),
        orderId: _orderId,
        title: title.isEmpty ? null : title,
        origin: widget.args.origin,
        deliveryIssue: widget.args.deliveryIssue,
        deliveryId: widget.args.deliveryIssue == null
            ? null
            : widget.args.deliveryId,
        photoIds: [for (final p in _photos) ?p.photoId],
      ),
    );
    if (!mounted) return;
    switch (outcome) {
      case InquirySubmitted():
        ref.invalidate(inquiryListProvider);
        // 초안 17 D: 알림 한 줄 뒤 닫히지 않고 접수 완료 화면(서버가 확정한 뒤에만).
        setState(() {
          _busy = false;
          _done = (category: category, photos: _photos.length);
        });
      case InquiryRejected(:final code, :final status, :final until):
        // 이용제한·정지면 내 정보(제한 상태)를 다시 읽어 화면도 막는다.
        if (code == AccountRestrictionCode.restricted) {
          ref.invalidate(profileProvider);
        }
        setState(() {
          _busy = false;
          _unknown = false;
          _message = switch (code) {
            AccountRestrictionCode.restricted => restrictedText(l10n, until),
            InquiryProblemCode.orderNotFound => l10n.inqOrderNotFound,
            InquiryProblemCode.orderNotInProgress => l10n.inqOrderNotInProgress,
            InquiryProblemCode.photoNotFound => l10n.inqPhotoNotFound,
            _ when status == 403 => l10n.inqLoginNeeded,
            _ => l10n.inqRejected,
          };
        });
      case InquiryUnknown():
        setState(() {
          _busy = false;
          _unknown = true;
          _message = l10n.inqUnknown;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final member = ref.watch(sessionProvider) is MemberSession;
    final locked = _busy || _unknown;
    final issue = widget.args.deliveryIssue;
    // 배송 신고는 종류(배송)·주문을 바꾸지 않는다 — 서버가 DELIVERY + 주문을 요구한다.
    final fixed = issue != null;
    if (!member) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.supportNewInquiry)),
        body: const _InquiryGuest(),
      );
    }
    if (_done case final done?) {
      return _InquiryDone(
        category: done.category,
        orderId: _orderId,
        photos: done.photos,
      );
    }
    final order = switch (_orderId) {
      final id? => ref.watch(orderDetailProvider(id)).value,
      null => null,
    };
    final orderText = switch ((_orderId, order)) {
      (null, _) => null,
      (_, final o?) => _orderSummary(l10n, o),
      _ => l10n.inqOrderChosenNoNumber,
    };
    // 이용제한·정지 중이면 미리 막는다(customer 0.16.0 CU-7 — 서버가 최종 판정, 기한이 지나면 풀림).
    final profile = ref.watch(profileProvider).value;
    final blocked = profile?.writingBlockedAt(DateTime.now()) ?? false;
    // 못 누를 때 이유 한 줄(초안 17 I).
    final reason = _unknown || _busy
        ? null
        : blocked
        ? restrictedText(l10n, profile?.restrictedUntil)
        : _category == null
        ? l10n.inqReasonCategory
        : _body.text.trim().isEmpty
        ? l10n.inqReasonBody
        : !_photosReady
        ? l10n.inqReasonPhotos
        : null;
    final hint = scheme.onSurfaceVariant;
    Widget row({
      required Key key,
      Key? valueKey,
      required String label,
      required String? value,
      required VoidCallback? onTap,
    }) => InkWell(
      key: key,
      onTap: fixed || locked ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(color: hint),
              ),
            ),
            Expanded(
              child: Text(
                value ?? l10n.inqNotChosen,
                key: value == null ? null : valueKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: value == null ? FontWeight.w400 : FontWeight.w700,
                  color: value == null ? scheme.outline : scheme.onSurface,
                ),
              ),
            ),
            if (fixed)
              Text(
                l10n.inqFixed,
                style: theme.textTheme.bodySmall?.copyWith(color: hint),
              )
            else
              PmartLineIcon(
                PmartLineIcons.chevronRight,
                size: 18,
                color: scheme.outline,
              ),
          ],
        ),
      ),
    );
    BoxDecoration card() => BoxDecoration(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(14),
    );
    const plain = InputDecoration(
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      filled: false,
      counterText: '',
    );
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ① 종류 · 주문
        Container(
          decoration: card(),
          child: Column(
            children: [
              row(
                key: const ValueKey('inq-kind'),
                valueKey: const ValueKey('inq-kind-value'),
                label: l10n.inqKindLabel,
                value: _category == null
                    ? null
                    : inquiryCategoryText(l10n, _category),
                onTap: _pickCategory,
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              row(
                key: const ValueKey('inq-pick-order'),
                valueKey: const ValueKey('inq-order'),
                label: l10n.inqOrderLabel,
                value: orderText,
                onTap: _pickOrder,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // ② 제목 · 내용 · 사진
        Container(
          decoration: card(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('inq-title'),
                controller: _title,
                enabled: !locked,
                maxLength: inquiryTitleMax,
                decoration: plain.copyWith(hintText: l10n.inqTitleLabel),
              ),
              const Divider(height: 1),
              TextField(
                key: const ValueKey('inq-body'),
                controller: _body,
                enabled: !locked,
                maxLength: inquiryBodyMax,
                minLines: 4,
                maxLines: 12,
                decoration: plain.copyWith(hintText: l10n.inqBodyHint),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  l10n.inqBodyCount(
                    NumberFormat.decimalPattern('ko')
                        .format(_body.text.characters.length),
                    NumberFormat.decimalPattern('ko').format(inquiryBodyMax),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(color: hint),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_photos.length < inquiryPhotosMax)
                    _DashedAddBox(
                      key: const ValueKey('inq-photo-add'),
                      count: _photos.length,
                      max: inquiryPhotosMax,
                      onTap: locked ? null : _addPhotos,
                    ),
                  for (final (i, p) in _photos.indexed)
                    _PhotoSlotView(
                      key: ValueKey('inq-photo-$i'),
                      slot: p,
                      onRemove: locked
                          ? null
                          : () => setState(() => _photos.remove(p)),
                      onRetry: locked || !p.failed ? null : () => _upload(p),
                    ),
                ],
              ),
              if (_photoMessage case final m?)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    m,
                    key: const ValueKey('inq-photo-message'),
                    style: TextStyle(color: scheme.error),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            l10n.inqFormNote,
            style: theme.textTheme.bodySmall?.copyWith(color: hint),
          ),
        ),
      ],
    );
    return Scaffold(
      backgroundColor: scheme.surfaceContainer,
      appBar: AppBar(
        title: Text(l10n.supportNewInquiry),
        backgroundColor: scheme.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          // 초안 17 F: 배송 신고로 왔으면 카드 위 연보라 신고 머리.
          if (issue != null) ...[
            Container(
              key: const ValueKey('inq-issue-head'),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.inqIssueHead,
                    style: theme.textTheme.bodySmall?.copyWith(color: hint),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    deliveryIssueText(l10n, issue),
                    key: const ValueKey('inq-issue'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          // 초안 17 E: 결과 모름이면 카드를 흐리게 잠근다.
          if (_unknown)
            Opacity(opacity: 0.45, child: IgnorePointer(child: form))
          else
            form,
          if (_message case final message?)
            Container(
              key: const ValueKey('inq-message'),
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _unknown ? scheme.tertiaryContainer : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                message,
                style: TextStyle(
                  color: _unknown ? scheme.onTertiaryContainer : scheme.error,
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          color: scheme.surface,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (reason != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    reason,
                    key: const ValueKey('inq-reason'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: hint),
                  ),
                ),
              FilledButton(
                key: const ValueKey('inq-submit'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _unknown
                    ? (_busy ? null : _submit)
                    : (_canSend && !blocked ? _submit : null),
                child: Text(_unknown ? l10n.inqCheckAgain : l10n.inqSubmit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "국산 햇감자 1kg 외 2개 · 20481135"(초안 17 I 주문 줄). 상품명이 없으면 주문번호만, 그것도 없으면 "선택한 주문".
String _orderSummary(AppLocalizations l10n, OrderDetail o) {
  final names = [for (final l in o.lines) ?l.productName];
  final goods = switch (names) {
    [] => null,
    [final one] => one,
    [final first, ...] => l10n.ordersRepresentative(first, names.length - 1),
  };
  return switch ((goods, o.orderNumber)) {
    (final g?, final n?) => '$g · $n',
    (final g?, null) => g,
    (null, final n?) => l10n.inqOrderChosen(n),
    _ => l10n.inqOrderChosenNoNumber,
  };
}

/// 사진 더하기 점선 칸 — 카메라 + "n/5"(초안 17 I).
class _DashedAddBox extends StatelessWidget {
  const _DashedAddBox({
    super.key,
    required this.count,
    required this.max,
    required this.onTap,
  });

  final int count;
  final int max;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: l10n.inqPhotoAdd,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: CustomPaint(
          painter: _DashedRectPainter(scheme.outline),
          child: SizedBox.square(
            dimension: _PhotoSlotView.size,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PmartLineIcon(
                  PmartLineIcons.camera,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(height: 4),
                Text(
                  '$count/$max',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
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

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      );
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 7) {
        canvas.drawPath(m.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) => old.color != color;
}

/// 초안 17 D 접수 완료 — 연보라 체크 + 두 문장 + 요약(종류·주문·사진) + [내 문의 내역] [확인].
class _InquiryDone extends ConsumerWidget {
  const _InquiryDone({
    required this.category,
    required this.orderId,
    required this.photos,
  });

  final InquiryCategory category;
  final String? orderId;
  final int photos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final order = switch (orderId) {
      final id? => ref.watch(orderDetailProvider(id)).value,
      null => null,
    };
    Widget line(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              k,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(v, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
    return Scaffold(
      key: const ValueKey('inq-done'),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: l10n.inqDoneOk,
          icon: const PmartLineIcon(PmartLineIcons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: PmartLineIcon(
                  PmartLineIcons.check,
                  size: 32,
                  color: scheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.inqSubmitted,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.inqDoneBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            key: const ValueKey('inq-done-summary'),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                line(l10n.inqKindLabel, inquiryCategoryText(l10n, category)),
                if (orderId != null)
                  line(
                    l10n.inqOrderLabel,
                    order == null
                        ? l10n.inqOrderChosenNoNumber
                        : _orderSummary(l10n, order),
                  ),
                if (photos > 0)
                  line(l10n.inqPhotoLabel, l10n.inqPhotoCount(photos)),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('inq-done-list'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: () =>
                      context.pushReplacement('/support/inquiries'),
                  child: Text(l10n.inqMyInquiries),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('inq-done-ok'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: () => context.pop(),
                  child: Text(l10n.inqDoneOk),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 초안 17 G-1 비회원: 회색 사람 원 + "문의는 로그인한 뒤에 남길 수 있어요" + [로그인] + [자주 묻는 질문 보기].
class _InquiryGuest extends StatelessWidget {
  const _InquiryGuest();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          key: const ValueKey('inq-guest'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: PmartLineIcon(
                    PmartLineIcons.user,
                    size: 28,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.inqLoginNeeded,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const ValueKey('inq-guest-login'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => context.push('/login'),
              child: Text(l10n.loginTitle),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('inq-guest-faq'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => context.push('/support/faqs'),
              child: Text(l10n.inqSeeFaq),
            ),
          ],
        ),
      ),
    );
  }
}
