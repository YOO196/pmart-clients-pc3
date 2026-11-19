import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../../address/presentation/address_screens.dart' show LoginRequired;
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../orders/presentation/orders_providers.dart'
    show orderDetailProvider, orderListProvider, orderStatusText;
import '../../orders/domain/orders.dart' show OrderListQuery;
import '../domain/inquiry.dart';
import 'faq_screens.dart' show SupportFaqBlock;
import 'inquiry_controller.dart';

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
  });

  final String? orderId;

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
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.supportTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
        children: [
          Text(
            l10n.supportHeadline,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          // 검색칸 · 자주 묻는 질문 · 분류 칩(회원만 — 레퍼런스 고객센터 메인).
          const SupportFaqBlock(),
          SupportRow(
            key: const ValueKey('support-chat'),
            label: l10n.supportChat,
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

/// 레퍼런스의 화살표 줄(글자 17, 세로 여백 넉넉히, 오른쪽 회색 화살표).
class SupportRow extends StatelessWidget {
  const SupportRow({super.key, required this.label, required this.onTap});

  final String label;
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
              child: Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(fontSize: 17),
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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.inqDetailTitle)),
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
              const SizedBox(height: 16),
              Text(l10n.inqDetailNote, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
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

  bool get _canSend =>
      !_busy && _category != null && _body.text.trim().isNotEmpty;

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
      ),
    );
    if (!mounted) return;
    switch (outcome) {
      case InquirySubmitted(:final inquiry):
        ref.invalidate(inquiryListProvider);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.inqSubmitted)));
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
