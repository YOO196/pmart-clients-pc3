import 'dart:async';

import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart'
    show IdempotencyKey, PmartFailure, ProblemFailure;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../../address/presentation/address_screens.dart' show LoginRequired;
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../orders/presentation/orders_providers.dart'
    show orderDetailProvider, orderListProvider, orderStatusText;
import '../../orders/domain/orders.dart' show OrderListQuery;
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

/// 내 문의 목록(본인만, 최근 순). 답변 알림이 없어 당겨서 새로 고친다.
class InquiryListScreen extends ConsumerWidget {
  const InquiryListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(inquiryListProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.supportMyInquiries)),
      floatingActionButton: value.value == null
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('inquiry-new'),
              onPressed: () => context.push('/support/inquiries/new'),
              label: Text(l10n.supportNewInquiry),
            ),
      body: switch (value) {
        AsyncData(value: null) => LoginRequired(message: l10n.inqLoginNeeded),
        _ => UiStateView<InquiryListState?>(
          loading: (_) => const PmartListSkeleton(),
          state: uiStateOf(value, isEmpty: (s) => s!.items.isEmpty),
          onRetry: () => ref.invalidate(inquiryListProvider),
          empty: (_) => Center(
            key: const ValueKey('inquiries-empty'),
            child: Text(l10n.inqEmpty),
          ),
          ready: (context, s) => RefreshIndicator(
            onRefresh: () => ref.refresh(inquiryListProvider.future),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    l10n.inqListNote,
                    style: Theme.of(context).textTheme.bodySmall,
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

class _InquiryTile extends StatelessWidget {
  const _InquiryTile({required this.item});

  final InquirySummary item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final answered = item.status == InquiryStatus.answered;
    return ListTile(
      key: ValueKey('inquiry-${item.inquiryId}'),
      title: Text(
        item.title ?? inquiryCategoryText(l10n, item.category),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${inquiryCategoryText(l10n, item.category)} · ${formatSeoulDateTime(item.createdAt)}',
      ),
      trailing: Text(
        inquiryStatusText(l10n, item.status),
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: answered
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
        ),
      ),
      onTap: () => context.push('/support/inquiries/${item.inquiryId}'),
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

/// 문의 상세 + 답변. 고객이 이어 쓰는 기능은 없다(새 문의로).
class InquiryDetailScreen extends ConsumerWidget {
  const InquiryDetailScreen({super.key, required this.inquiryId});

  final String inquiryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final provider = inquiryProvider(inquiryId);
    final loaded = ref.watch(provider).value;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.inqDetailTitle),
        actions: [
          if (loaded != null && !loaded.closed)
            _CloseButton(inquiryId: inquiryId),
        ],
      ),
      body: UiStateView<InquiryDetail>(
        state: uiStateOf(ref.watch(provider)),
        onRetry: () => ref.invalidate(provider),
        ready: (context, d) => RefreshIndicator(
          onRefresh: () => ref.refresh(provider.future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      inquiryCategoryText(l10n, d.summary.category),
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  Text(
                    inquiryStatusText(l10n, d.summary.status),
                    key: const ValueKey('inquiry-status'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                formatSeoulDateTime(d.summary.createdAt),
                style: theme.textTheme.bodySmall,
              ),
              if (d.summary.orderId case final orderId?)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const ValueKey('inquiry-order'),
                    onPressed: () => context.push('/orders/$orderId'),
                    child: Text(l10n.inqOrderLink),
                  ),
                ),
              const SizedBox(height: 12),
              if (d.summary.title case final title?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              Text(d.body, key: const ValueKey('inquiry-body')),
              if (d.photoIds.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in d.photoIds) _InquiryPhotoThumb(photoId: p),
                  ],
                ),
              ],
              const Divider(height: 32),
              Text(
                l10n.inqRepliesTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              if (d.replies.isEmpty)
                Text(
                  d.summary.status == InquiryStatus.received
                      ? l10n.inqNoReplyYet
                      : l10n.inqNoReply,
                  key: const ValueKey('inquiry-no-reply'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                )
              else
                for (final r in d.replies)
                  Container(
                    key: ValueKey('inquiry-reply-${r.replyId}'),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.body),
                        if (r.createdAt case final t?)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              formatSeoulDateTime(t),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
              if (d.satisfaction case final s?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    [
                      l10n.inqRated(rateLabel(l10n, s.score)),
                      ?s.comment,
                    ].join(' · '),
                    key: const ValueKey('inquiry-rated'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else if (d.canRate)
                _RateBox(inquiryId: inquiryId),
              const SizedBox(height: 16),
              Text(
                d.closed ? l10n.inqClosedNote : l10n.inqDetailNote,
                key: d.closed ? const ValueKey('inquiry-closed-note') : null,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
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
    return Container(
      key: const ValueKey('inquiry-rate'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.inqRateTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(l10n.inqRateSubtitle, style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          // 레퍼런스(고객센터 2-2-2 만족도 조사): 얼굴 + 문구 5줄. 위에서부터 5점 → 1점.
          for (final s in const [5, 4, 3, 2, 1])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: _score == s
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: _score == s
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
                child: InkWell(
                  key: ValueKey('inquiry-rate-$s'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: _busy ? null : () => setState(() => _score = s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        // 레퍼런스 2-2-2: 색 채운 동그라미 얼굴(16dp)
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: _rateColor(s),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            _rateIcon(s),
                            size: 15,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(rateLabel(l10n, s)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 4),
          TextField(
            key: const ValueKey('inquiry-rate-comment'),
            controller: _comment,
            enabled: !_busy,
            maxLength: inquiryCommentMax,
            decoration: InputDecoration(labelText: l10n.inqRateComment),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const ValueKey('inquiry-rate-send'),
              onPressed: _busy || _score == null ? null : _send,
              child: Text(l10n.inqRateSubmit),
            ),
          ),
        ],
      ),
    );
  }
}

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
    return TextButton(
      key: const ValueKey('inquiry-close'),
      onPressed: _busy ? null : _close,
      child: Text(l10n.inqClose),
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
      case InquirySubmitted(:final inquiry):
        ref.invalidate(inquiryListProvider);
        showNotice(context, l10n.inqSubmitted);
        context.pushReplacement(
          '/support/inquiries/${inquiry.summary.inquiryId}',
        );
      case InquiryRejected(:final code, :final status):
        setState(() {
          _busy = false;
          _unknown = false;
          _message = switch (code) {
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
    final member = ref.watch(sessionProvider) is MemberSession;
    final locked = _busy || _unknown;
    final issue = widget.args.deliveryIssue;
    // 배송 신고는 종류(배송)·주문을 바꾸지 않는다 — 서버가 DELIVERY + 주문을 요구한다.
    final fixed = locked || issue != null;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.supportNewInquiry)),
      body: !member
          ? LoginRequired(message: l10n.inqLoginNeeded)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (issue != null) ...[
                  Text(
                    deliveryIssueText(l10n, issue),
                    key: const ValueKey('inq-issue'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  l10n.inqCategoryLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final c in InquiryCategory.values)
                      ChoiceChip(
                        key: ValueKey('inq-cat-${c.name}'),
                        label: Text(inquiryCategoryText(l10n, c)),
                        selected: _category == c,
                        onSelected: fixed
                            ? null
                            : (_) => setState(() => _category = c),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_orderId case final orderId?)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InputChip(
                      key: const ValueKey('inq-order'),
                      // 시스템 주문 ID(ORD-…)는 보이지 않는다 — 화면용 8자리 주문번호, 없으면 "선택한 주문".
                      label: Text(switch (ref
                          .watch(orderDetailProvider(orderId))
                          .value
                          ?.orderNumber) {
                        final n? => l10n.inqOrderChosen(n),
                        null => l10n.inqOrderChosenNoNumber,
                      }),
                      onDeleted: fixed
                          ? null
                          : () => setState(() => _orderId = null),
                    ),
                  )
                else
                  // 주문은 선택. 본인 주문 목록(`GET /orders`)에서 고른다 — 서버가 본인 주문인지 다시 확인한다(422 ORDER_NOT_FOUND).
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const ValueKey('inq-pick-order'),
                      onPressed: locked ? null : _pickOrder,
                      icon: const PmartLineIcon(
                        PmartLineIcons.chevronRight,
                        size: 14,
                      ),
                      iconAlignment: IconAlignment.end,
                      label: Text(l10n.inqPickOrder),
                    ),
                  ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('inq-title'),
                  controller: _title,
                  enabled: !locked,
                  maxLength: inquiryTitleMax,
                  decoration: InputDecoration(labelText: l10n.inqTitleLabel),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('inq-body'),
                  controller: _body,
                  enabled: !locked,
                  maxLength: inquiryBodyMax,
                  minLines: 5,
                  maxLines: 10,
                  decoration: InputDecoration(
                    labelText: l10n.inqBodyLabel,
                    hintText: l10n.inqBodyHint,
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.inqPhotosLabel(inquiryPhotosMax),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (i, p) in _photos.indexed)
                      _PhotoSlotView(
                        key: ValueKey('inq-photo-$i'),
                        slot: p,
                        onRemove: locked
                            ? null
                            : () => setState(() => _photos.remove(p)),
                        onRetry: locked || !p.failed ? null : () => _upload(p),
                      ),
                    if (_photos.length < inquiryPhotosMax)
                      OutlinedButton.icon(
                        key: const ValueKey('inq-photo-add'),
                        onPressed: locked ? null : _addPhotos,
                        icon: const PmartLineIcon(
                          PmartLineIcons.camera,
                          size: 18,
                        ),
                        label: Text(l10n.inqPhotoAdd),
                      ),
                  ],
                ),
                if (_photoMessage case final m?)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      m,
                      key: const ValueKey('inq-photo-message'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                if (!_photosReady && !_photos.any((p) => p.uploading))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      l10n.inqPhotosPending,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 12),
                Text(l10n.inqFormNote, style: theme.textTheme.bodySmall),
                if (_message case final message?)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      message,
                      key: const ValueKey('inq-message'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('inq-submit'),
                  onPressed: _unknown
                      ? (_busy ? null : _submit)
                      : (_canSend ? _submit : null),
                  child: Text(_unknown ? l10n.inqCheckAgain : l10n.inqSubmit),
                ),
              ],
            ),
    );
  }
}
