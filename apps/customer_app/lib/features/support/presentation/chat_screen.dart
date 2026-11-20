import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:pmart_core/pmart_core.dart' show PmartEnv;
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers.dart';
import '../../checkout/presentation/checkout_controller.dart'
    show clockProvider;
import '../../address/presentation/address_screens.dart' show LoginRequired;
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/mock_chat_repository.dart';
import '../domain/chat.dart';
import '../domain/inquiry.dart' show InquiryOrigin;
import 'chat_controller.dart';
import 'inquiry_screens.dart' show InquiryFormArgs;

/// 고객센터 AI 상담. 답변·주문 상태는 서버가 준 문장 그대로 보인다(일반 텍스트).
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
    // 주문 건 문의면 질문마다 고른 주문을 붙인다.
    final orderId = switch (ref.read(chatTopicProvider)) {
      ChatTopicOrder(:final order) => order.orderId,
      _ => null,
    };
    await ref.read(chatProvider.notifier).ask(q, orderId: orderId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final member = ref.watch(sessionProvider) is MemberSession;
    final turns = ref.watch(chatProvider);
    final busy = turns.any((t) => t.status == ChatTurnStatus.sending);
    final mock = ref.watch(envProvider) == PmartEnv.mock;
    final topic = ref.watch(chatTopicProvider);
    final log = ref.watch(chatTopicLogProvider);
    // 종류를 고르기 전(또는 주문을 고르는 중)에는 입력을 막는다.
    final canType = topic is ChatTopicGeneral || topic is ChatTopicOrder;
    ref.listen(chatProvider, (_, _) => _toEnd());
    ref.listen(chatTopicProvider, (_, _) => _toEnd());
    return Scaffold(
      appBar: AppBar(title: Text(l10n.supportChat)),
      body: !member
          ? LoginRequired(message: l10n.chatLoginNeeded)
          : Column(
              children: [
                // 레퍼런스 2: 머리 아래 "상담센터 ··· ⟳ 상담종료" 줄
                Container(
                  key: const ValueKey('chat-header'),
                  padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 13,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: PmartLineIcon(
                          PmartLineIcons.headset,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.chatCenterName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        key: const ValueKey('chat-end'),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.onSurface,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: busy
                            ? null
                            : () async {
                                final ok = await showPmartConfirm(
                                  context,
                                  title: l10n.chatEndTitle,
                                  confirmLabel: l10n.chatEnd,
                                  cancelLabel: l10n.cancelConfirmNo,
                                  confirmKey: const ValueKey('chat-end-ok'),
                                );
                                if (ok ?? false) {
                                  ref.invalidate(chatProvider);
                                  // 고른 상담 종류 기록("일반 문의" 등)도 비운다 — 안 비우면 종료 뒤에도 남는다(사용자 2026-11-20).
                                  ref.invalidate(chatTopicLogProvider);
                                  ref.read(chatTopicProvider.notifier).reset();
                                }
                              },
                        icon: const PmartLineIcon(
                          PmartLineIcons.refresh,
                          size: 16,
                        ),
                        label: Text(l10n.chatEnd),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    children: [
                      // 레퍼런스 2: 가운데 날짜 줄 → "상담센터" 이름표 + 회색 인사 말풍선
                      Center(
                        child: Text(
                          DateFormat('y년 M월 d일', 'ko').format(
                            toSeoulWallClock(ref.watch(clockProvider)()),
                          ),
                          key: const ValueKey('chat-date'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.chatCenterName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 260),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            l10n.chatIntro,
                            key: const ValueKey('chat-intro'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                            ),
                          ),
                        ),
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
                      // 한 줄 시간순(사용자 2026-11-16): 고른 종류·주문은 고른 자리에 남고, 질문·답은 그 뒤에,
                      // 지금 고르는 선택지는 맨 끝에. (전에는 선택 칸이 맨 위 한 자리라 새 선택이 앞 대화보다 위에 나왔다.)
                      for (var i = 0; i <= turns.length; i++) ...[
                        for (final e in log)
                          if (e.at == i)
                            _TopicSection(
                              topic: e.topic,
                              fromChooser: e.fromChooser,
                            ),
                        if (i < turns.length) _Turn(turn: turns[i]),
                      ],
                      if (topic == null || topic is ChatTopicPickingOrder)
                        _TopicSection(topic: topic),
                    ],
                  ),
                ),
                if (topic case ChatTopicOrder(:final order))
                  Container(
                    key: const ValueKey('chat-topic-bar'),
                    width: double.infinity,
                    color: theme.colorScheme.surfaceContainer,
                    padding: const EdgeInsets.only(left: 16, right: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            // 시스템 주문 ID 는 보이지 않는다(주문 시각, 없으면 상태).
                            l10n.chatOrderTopicBar(switch (order.orderedAt) {
                              final at? => formatSeoulDateTime(at),
                              null => order.statusLabel,
                            }),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        TextButton(
                          key: const ValueKey('chat-topic-change'),
                          onPressed: busy
                              ? null
                              : ref.read(chatTopicProvider.notifier).reset,
                          child: Text(l10n.chatTopicChange),
                        ),
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
                            enabled: !busy && canType,
                            maxLength: chatQuestionMax,
                            minLines: 1,
                            maxLines: 4,
                            // 레퍼런스 2: 둥근 회색 칸(글자 수 숨김) + 동그란 ↑ 보내기
                            decoration: InputDecoration(
                              hintText: canType
                                  ? l10n.chatHint
                                  : l10n.chatChooseTopicHint,
                              counterText: '',
                              isDense: true,
                              filled: true,
                              fillColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainer,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 11,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(22),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          key: const ValueKey('chat-send'),
                          style: FilledButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: EdgeInsets.zero,
                            minimumSize: const Size.square(40),
                            fixedSize: const Size.square(40),
                          ),
                          onPressed:
                              busy || !canType || _input.text.trim().isEmpty
                              ? null
                              : _send,
                          child: Semantics(
                            label: l10n.chatSend,
                            child: const RotatedBox(
                              quarterTurns: 1,
                              child: PmartLineIcon(
                                PmartLineIcons.back,
                                size: 20,
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            ),
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

/// 상담 종류 고르기(레퍼런스 2-1·2-4): 처음엔 오른쪽에 "일반 문의"·"주문 건에 대한 문의" 버튼,
/// 고르면 내 말풍선으로 남는다. 주문 건이면 최근 주문(`GET /customer-assistant/recent-orders`)을 버튼으로 보인다.
class _TopicSection extends ConsumerWidget {
  const _TopicSection({required this.topic, this.fromChooser = true});

  final ChatTopic? topic;

  /// 주문을 "주문 건에 대한 문의"로 골랐는지(아니면 답 안의 주문 카드로 고른 것 — 그 말풍선은 없다).
  final bool fromChooser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final notifier = ref.read(chatTopicProvider.notifier);
    Widget mine(String text, Key key) => Align(
      alignment: Alignment.centerRight,
      child: _Bubble(
        key: key,
        color: scheme.primaryContainer,
        child: Text(text),
      ),
    );
    return switch (topic) {
      null => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _ChoiceButton(
            key: const ValueKey('chat-topic-general'),
            label: l10n.chatTopicGeneral,
            onTap: notifier.chooseGeneral,
          ),
          _ChoiceButton(
            key: const ValueKey('chat-topic-order'),
            label: l10n.chatTopicOrder,
            onTap: notifier.chooseOrder,
          ),
          const SizedBox(height: 8),
        ],
      ),
      ChatTopicGeneral() => mine(
        l10n.chatTopicGeneral,
        const ValueKey('chat-topic-general-chosen'),
      ),
      ChatTopicPickingOrder() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          mine(l10n.chatTopicOrder, const ValueKey('chat-topic-order-chosen')),
          const _RecentOrderPicker(),
        ],
      ),
      ChatTopicOrder(:final order) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (fromChooser)
            mine(
              l10n.chatTopicOrder,
              const ValueKey('chat-topic-order-chosen'),
            ),
          mine(
            _orderPickLabel(l10n, order),
            const ValueKey('chat-topic-order-picked'),
          ),
          // 고른 뒤 바로 응답한다(사용자 2026-11-16 "주문 고른 뒤 연결이 안 된다") — 고른 주문(서버 값) +
          // 무엇을 물으면 되는지 + 주문 상세(취소·반품 신청은 거기서, 서버 판정). 질문을 대신 보내지는 않는다.
          Align(
            alignment: Alignment.centerLeft,
            child: _Bubble(
              key: const ValueKey('chat-topic-order-ack'),
              color: scheme.surfaceContainer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _OrderCard(order: order),
                  Text(l10n.chatOrderPickedPrompt),
                  TextButton(
                    key: const ValueKey('chat-topic-order-detail'),
                    onPressed: () => context.push(
                      '/orders/${Uri.encodeComponent(order.orderId)}',
                    ),
                    child: Text(l10n.chatOrderDetail),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    };
  }
}

/// 주문 고르기 단추·고른 말풍선. 시스템 주문 ID 는 고객에게 보이지 않는다(계약 OrderBrief 에 화면용 주문번호가 없어
/// 주문 시각 · 상태로 구분한다).
String _orderPickLabel(AppLocalizations l10n, ChatOrder o) =>
    switch (o.orderedAt) {
      final DateTime t => l10n.chatOrderPick(
        formatSeoulDateTime(t),
        o.statusLabel,
      ),
      null => o.statusLabel,
    };

/// 도착 예정 시간대(서울 날짜·시각 문자열) → 다른 화면과 같은 "11월 15일 (일) 오후 2:00~3:00". 읽지 못하면 null.
String? _arrivalText(ChatOrder o) {
  final (d, s, e) = (o.arrivalDate, o.arrivalStart, o.arrivalEnd);
  if (d == null || s == null || e == null) return null;
  final start = DateTime.tryParse('${d}T$s:00+09:00');
  final end = DateTime.tryParse('${d}T$e:00+09:00');
  if (start == null || end == null) return null;
  return '${formatSeoulDate(start)} ${formatSeoulWindow(start, end)}';
}

class _RecentOrderPicker extends ConsumerWidget {
  const _RecentOrderPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final notifier = ref.read(chatTopicProvider.notifier);
    final orders = ref.watch(chatRecentOrdersProvider);
    final prompt = Align(
      alignment: Alignment.centerLeft,
      child: _Bubble(
        color: theme.colorScheme.surfaceContainer,
        child: Text(l10n.chatPickOrderPrompt),
      ),
    );
    return switch (orders) {
      AsyncData(:final value) when value.isEmpty => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _Bubble(
              key: const ValueKey('chat-recent-empty'),
              color: theme.colorScheme.surfaceContainer,
              child: Text(l10n.chatNoRecentOrders),
            ),
          ),
          _ChoiceButton(
            key: const ValueKey('chat-topic-general-instead'),
            label: l10n.chatAskGeneralInstead,
            onTap: notifier.chooseGeneral,
          ),
        ],
      ),
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          prompt,
          for (final o in value)
            _ChoiceButton(
              key: ValueKey('chat-recent-${o.orderId}'),
              label: _orderPickLabel(l10n, o),
              onTap: () => notifier.pickOrder(o),
            ),
          const SizedBox(height: 8),
        ],
      ),
      // 조회 실패는 "주문 없음"으로 보이지 않는다.
      AsyncError() => Align(
        alignment: Alignment.centerLeft,
        child: _Bubble(
          key: const ValueKey('chat-recent-error'),
          color: theme.colorScheme.errorContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.chatRecentOrdersFailed),
              TextButton(
                key: const ValueKey('chat-recent-retry'),
                onPressed: () => ref.invalidate(chatRecentOrdersProvider),
                child: Text(l10n.chatRetry),
              ),
            ],
          ),
        ),
      ),
      _ => const Padding(
        padding: EdgeInsets.all(8),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    };
  }
}

/// 오른쪽 정렬 테두리 버튼(레퍼런스의 선택지 모양).
class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.75,
      ),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          side: BorderSide(color: Theme.of(context).colorScheme.onSurface),
          // 레퍼런스(2-1·2-4): 얇은 테두리, 모서리 4dp, 보통 굵기, 높이 약 38dp.
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: const Size(0, 38),
          alignment: Alignment.centerLeft,
          textStyle: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(fontWeight: FontWeight.w400),
        ),
        child: Text(label, textAlign: TextAlign.start),
      ),
    ),
  );
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
                  // 같은 질문을 주문과 함께 새 키로 다시 보낸다. 다음 질문도 이 주문으로 묻는다.
                  onTap: () {
                    ref.read(chatTopicProvider.notifier).pickOrder(o);
                    ref
                        .read(chatProvider.notifier)
                        .ask(turn.question, orderId: o.orderId);
                  },
                ),
          ],
          // 취소·환불 같은 실행 요청: 답 바로 아래에 최근 주문(누르면 주문 상세) + 주문 내역.
          if (answer.state == ChatAnswerState.outOfScope) ...[
            const SizedBox(height: 8),
            const _ActionOrders(),
            TextButton(
              key: const ValueKey('chat-go-orders'),
              onPressed: () => context.push('/orders'),
              child: Text(l10n.ordersTitle),
            ),
          ],
          // 근거(citations)는 받더라도 고객에게 보이지 않는다(사용자 2026-11-16 — 개발 단계에서도).
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
        ],
      ),
    );
  }
}

/// 취소·환불 같은 실행 요청(`OUT_OF_SCOPE`)의 답 아래: 최근 주문(`GET /customer-assistant/recent-orders`, 최대 5개).
/// 누르면 그 주문 상세로 간다 — 취소는 거기서(가능 여부는 서버 판정). AI 가 취소하지 않는다(사용자 2026-11-16).
/// 조회 실패는 실패 + 다시 시도(빈 목록으로 바꾸지 않는다).
class _ActionOrders extends ConsumerWidget {
  const _ActionOrders();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return switch (ref.watch(chatRecentOrdersProvider)) {
      AsyncData(value: final orders) when orders.isEmpty => Text(
        l10n.chatNoRecentOrders,
        key: const ValueKey('chat-action-orders-empty'),
        style: theme.textTheme.bodySmall,
      ),
      AsyncData(value: final orders) => Column(
        key: const ValueKey('chat-action-orders'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.chatActionOrdersHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          for (final o in orders)
            _OrderCard(
              order: o,
              onTap: () =>
                  context.push('/orders/${Uri.encodeComponent(o.orderId)}'),
            ),
        ],
      ),
      AsyncError() => Row(
        key: const ValueKey('chat-action-orders-error'),
        children: [
          Expanded(
            child: Text(
              l10n.chatRecentOrdersFailed,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
          TextButton(
            onPressed: () => ref.invalidate(chatRecentOrdersProvider),
            child: Text(l10n.chatRetry),
          ),
        ],
      ),
      _ => const LinearProgressIndicator(),
    };
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
    final arrival = switch (_arrivalText(order)) {
      final w? => l10n.chatOrderArrival(w),
      null => null,
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
