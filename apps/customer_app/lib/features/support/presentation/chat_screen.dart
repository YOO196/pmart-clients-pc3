import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart' show PmartEnv;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers.dart';
import '../../address/presentation/address_screens.dart' show LoginRequired;
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/mock_chat_repository.dart';
import '../domain/chat.dart';
import '../domain/inquiry.dart' show InquiryOrigin;
import 'chat_controller.dart';
import 'inquiry_screens.dart' show InquiryFormArgs;

/// 고객센터 AI 상담. 답변·근거·주문 상태는 서버가 준 문장 그대로 보인다(일반 텍스트).
/// AI 상담은 취소·환불을 하지 않는다 — 답하지 못하면 "고객센터에 문의 남기기"로 잇는다.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final q = _input.text.trim();
    if (q.isEmpty) return;
    _input.clear();
    await ref.read(chatProvider.notifier).ask(q);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final member = ref.watch(sessionProvider) is MemberSession;
    final turns = ref.watch(chatProvider);
    final busy = turns.any((t) => t.status == ChatTurnStatus.sending);
    final mock = ref.watch(envProvider) == PmartEnv.mock;
    ref.listen(chatProvider, (_, _) => _toEnd());
    return Scaffold(
      appBar: AppBar(title: Text(l10n.supportChat)),
      body: !member
          ? LoginRequired(message: l10n.chatLoginNeeded)
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        l10n.chatIntro,
                        key: const ValueKey('chat-intro'),
                        style: theme.textTheme.bodySmall,
                      ),
                      if (mock)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            l10n.chatMockNote(
                              MockChatRepository.tags.keys.join(' '),
                            ),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      const SizedBox(height: 12),
                      for (final t in turns) _Turn(turn: t),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('chat-input'),
                            controller: _input,
                            enabled: !busy,
                            maxLength: chatQuestionMax,
                            minLines: 1,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: l10n.chatHint,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 22),
                          child: FilledButton(
                            key: const ValueKey('chat-send'),
                            onPressed: busy || _input.text.trim().isEmpty
                                ? null
                                : _send,
                            child: Text(l10n.chatSend),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Turn extends ConsumerWidget {
  const _Turn({required this.turn});

  final ChatTurn turn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      key: ValueKey('chat-turn-${turn.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: _Bubble(
            color: scheme.primaryContainer,
            child: Text(turn.question),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: switch (turn.status) {
            ChatTurnStatus.sending => _Bubble(
              color: scheme.surfaceContainer,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(l10n.chatSending),
                ],
              ),
            ),
            ChatTurnStatus.unknown => _Bubble(
              key: const ValueKey('chat-unknown'),
              color: scheme.surfaceContainer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.chatUnknown),
                  TextButton(
                    key: const ValueKey('chat-recheck'),
                    onPressed: () =>
                        ref.read(chatProvider.notifier).recheck(turn.id),
                    child: Text(l10n.chatRecheck),
                  ),
                ],
              ),
            ),
            ChatTurnStatus.rejected => _Bubble(
              key: const ValueKey('chat-rejected'),
              color: scheme.errorContainer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_rejectText(l10n, turn)),
                  // 요청 제한에 걸려도 문의는 남길 수 있다.
                  if (turn.rejectCode == ChatProblemCode.rateLimited)
                    _HandoffButton(
                      label: l10n.chatHandoff,
                      question: turn.question,
                      orderId: turn.orderId,
                    ),
                ],
              ),
            ),
            ChatTurnStatus.answered => _Answer(
              turn: turn,
              answer: turn.answer!,
            ),
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

String _rejectText(AppLocalizations l10n, ChatTurn t) => switch (t.rejectCode) {
  // 서버 안내 문장이 있으면 그대로(1분 5개·하루 50개를 서버가 구분해 준다).
  ChatProblemCode.rateLimited => switch (t.serverDetail?.trim()) {
    final String d when d.isNotEmpty => d,
    _ => l10n.chatRateLimited,
  },
  ChatProblemCode.orderNotFound => l10n.chatOrderNotFound,
  ChatProblemCode.configRequired => l10n.chatConfigRequired,
  _ when t.rejectStatus == 403 => l10n.chatLoginNeeded,
  _ => l10n.chatRejected,
};

class _Bubble extends StatelessWidget {
  const _Bubble({super.key, required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    constraints: BoxConstraints(
      maxWidth: MediaQuery.sizeOf(context).width * 0.82,
    ),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );
}

class _Answer extends ConsumerWidget {
  const _Answer({required this.turn, required this.answer});

  final ChatTurn turn;
  final ChatAnswer answer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final handoff = answer.handoff;
    return _Bubble(
      key: ValueKey('chat-answer-${answer.state.name}'),
      color: scheme.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (answer.answer.trim().isNotEmpty) Text(answer.answer),
          if (answer.order case final order?) ...[
            const SizedBox(height: 8),
            _OrderCard(order: order),
          ],
          if (answer.state == ChatAnswerState.realtimeDataRequired) ...[
            const SizedBox(height: 8),
            if (answer.recentOrders.isEmpty)
              Text(l10n.chatNoRecentOrders, style: theme.textTheme.bodySmall)
            else
              for (final o in answer.recentOrders)
                _OrderCard(
                  order: o,
                  // 같은 질문을 주문과 함께 새 키로 다시 보낸다.
                  onTap: () => ref
                      .read(chatProvider.notifier)
                      .ask(turn.question, orderId: o.orderId),
                ),
          ],
          if (answer.citations.isNotEmpty)
            _Citations(citations: answer.citations),
          if (handoff != null) ...[
            const SizedBox(height: 4),
            Text(handoff.message, style: theme.textTheme.bodySmall),
            _HandoffButton(
              label: switch (handoff.buttonLabel?.trim()) {
                final String b when b.isNotEmpty => b,
                _ => l10n.chatHandoff,
              },
              question: turn.question,
              orderId: handoff.orderId ?? turn.orderId,
            ),
          ],
          if (answer.state == ChatAnswerState.outOfScope)
            TextButton(
              key: const ValueKey('chat-go-orders'),
              onPressed: () => context.push('/orders'),
              child: Text(l10n.ordersTitle),
            ),
        ],
      ),
    );
  }
}

class _HandoffButton extends StatelessWidget {
  const _HandoffButton({
    required this.label,
    required this.question,
    this.orderId,
  });

  final String label;
  final String question;
  final String? orderId;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    key: const ValueKey('chat-handoff'),
    // 질문은 서버에 남지 않는다 — 문의 본문 초안으로 넣어 준다(고객이 고칠 수 있다).
    onPressed: () => context.push(
      '/support/inquiries/new',
      extra: InquiryFormArgs(
        orderId: orderId,
        bodyDraft: question,
        origin: InquiryOrigin.assistantHandoff,
      ),
    ),
    child: Text(label),
  );
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, this.onTap});

  final ChatOrder order;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final parts = [
      if (order.orderedAt case final t?) formatSeoulDateTime(t),
      if (order.itemCount case final n?) l10n.chatOrderItems(n),
      if (order.totalAmount case final a?) formatKrw(a),
    ];
    final arrival = switch ((
      order.arrivalDate,
      order.arrivalStart,
      order.arrivalEnd,
    )) {
      (final String d, final String s, final String e) => l10n.chatOrderArrival(
        '$d $s~$e',
      ),
      _ => null,
    };
    return Card(
      key: ValueKey('chat-order-${order.orderId}'),
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                order.statusLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (parts.isNotEmpty)
                Text(parts.join(' · '), style: theme.textTheme.bodySmall),
              if (arrival != null)
                Text(arrival, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// "근거 보기" — 눌러서 펼친다. (말풍선 배경 위라 ExpansionTile 을 쓰지 않는다.)
class _Citations extends StatefulWidget {
  const _Citations({required this.citations});

  final List<ChatCitation> citations;

  @override
  State<_Citations> createState() => _CitationsState();
}

class _CitationsState extends State<_Citations> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          key: const ValueKey('chat-citations'),
          onPressed: () => setState(() => _open = !_open),
          icon: PmartLineIcon(
            _open ? PmartLineIcons.chevronUp : PmartLineIcons.chevronDown,
            size: 14,
          ),
          label: Text(l10n.chatCitations),
        ),
        if (_open)
          for (final c in widget.citations)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.section == null ? c.title : '${c.title} · ${c.section}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(c.excerpt, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
      ],
    );
  }
}
