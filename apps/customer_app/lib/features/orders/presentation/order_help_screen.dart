import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/order_status.dart';
import '../../../shared/ui_state_of.dart';
import '../../support/domain/inquiry.dart' show DeliveryIssue;
import '../../support/presentation/inquiry_screens.dart'
    show InquiryFormArgs, deliveryIssueText;
import '../domain/orders.dart';
import 'orders_providers.dart';

/// 주문 상태에 맞는 배송 신고 종류. 서버가 최종 판정한다(지연은 진행 중만 — 아니면 422).
List<DeliveryIssue> deliveryIssuesFor(OrderStatus s) => switch (s) {
  OrderStatus.confirmed ||
  OrderStatus.preparing ||
  OrderStatus.partiallyHandedOver ||
  OrderStatus.inDelivery => const [DeliveryIssue.delayed],
  // 일부만 전달됐으면 남은 것이 늦을 수도, 전달된 것이 다른 곳에 갔을 수도 있다.
  OrderStatus.partiallyDelivered => const [
    DeliveryIssue.delayed,
    DeliveryIssue.misdelivered,
  ],
  OrderStatus.completed => const [
    DeliveryIssue.notReceived,
    DeliveryIssue.misdelivered,
  ],
  _ => const [],
};

/// 주문 "문의하기" — 무엇을 도와드릴까요?(레퍼런스 9-2 3-1). 배송 신고는 문의(case `deliveryIssue`)로 남는다.
/// 고르면 문의 남기기로 간다(종류 배송·주문 고정). 접수일 뿐 주문을 바꾸지 않는다.
class OrderHelpScreen extends ConsumerWidget {
  const OrderHelpScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final value = ref.watch(orderDetailProvider(orderId));
    return Scaffold(
      // 레퍼런스 9-2 3-1: 왼쪽 제목, 큰 굵은 질문, 줄마다 16sp + 회색 ›
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: pmartLeftTitleSpacing,
        title: Text(l10n.orderInquiry),
      ),
      body: UiStateView<OrderDetail>(
        state: uiStateOf(value),
        onRetry: () => ref.invalidate(orderDetailProvider(orderId)),
        ready: (context, o) {
          // 배송 ID 는 참고값(서버는 주문 소유만 확인) — 배송이 하나뿐일 때만 싣는다.
          final deliveryId = switch (o.shipments) {
            [final only] => only.deliveryId,
            _ => null,
          };
          Widget row(String text, Key key, VoidCallback onTap) => InkWell(
            key: key,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      text,
                      style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16),
                    ),
                  ),
                  PmartLineIcon(
                    PmartLineIcons.chevronRight,
                    size: 18,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
          );
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 26, 16, 18),
                child: Text(
                  l10n.orderHelpTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final issue in deliveryIssuesFor(o.status))
                row(
                  deliveryIssueText(l10n, issue),
                  ValueKey('order-help-${issue.name}'),
                  () {
                    void form() => context.pushReplacement(
                      '/support/inquiries/new',
                      extra: InquiryFormArgs(
                        orderId: o.orderId,
                        deliveryIssue: issue,
                        deliveryId: deliveryId,
                      ),
                    );
                    // 레퍼런스 9-1 5: 배달 늦어짐은 "진행 중인 주문을 확인해주세요" 안내를 먼저(사용자 결정 2026-11-20).
                    if (issue == DeliveryIssue.delayed) {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              _DelayedGuide(order: o, onInquiry: form),
                        ),
                      );
                    } else {
                      form();
                    }
                  },
                ),
              row(
                l10n.orderHelpOther,
                const ValueKey('order-help-other'),
                // 레퍼런스 9-1 5 "그 외": "다른 도움이 필요하신가요?" 안내 → 채팅 상담(우리는 AI 상담) 또는 문의 남기기
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _OtherHelpGuide(
                      onChat: () => context.push('/support/chat'),
                      onInquiry: () => context.pushReplacement(
                        '/support/inquiries/new',
                        extra: InquiryFormArgs(orderId: o.orderId),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// "진행 중인 주문을 확인해주세요"(레퍼런스 9-1 5 배달 늦어짐): 지금 상태·센터·주문 목록·수령 방법 카드,
/// 아래 [확인]. 그래도 남기고 싶으면 "문의 남기기", 취소할 수 있으면 "주문취소하기".
class _DelayedGuide extends StatelessWidget {
  const _DelayedGuide({required this.order, required this.onInquiry});

  final OrderDetail order;
  final VoidCallback onInquiry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final o = order;
    final mode = switch (o.deliveryMode) {
      'SINGLE' => l10n.modeSingle,
      'BUNDLED' => l10n.modeBundled,
      'SCHEDULED' => l10n.modeScheduled,
      _ => null,
    };
    Widget line(String label, Widget value) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );
    return Scaffold(
      key: const ValueKey('help-delayed-guide'),
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        children: [
          Text(
            l10n.helpDelayedTitle,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 21,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: DefaultTextStyle.merge(
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    orderStatusText(l10n, o.status),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (o.mfcName case final n?) line(l10n.helpCenter, Text(n)),
                  line(
                    l10n.helpItems,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final l in o.lines)
                          Text(
                            '• ${l.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (mode != null) line(l10n.helpMode, Text(mode)),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (canRequestCancel(o))
                    TextButton(
                      key: const ValueKey('help-guide-cancel'),
                      onPressed: () =>
                          context.push('/orders/${o.orderId}/cancel'),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.onSurfaceVariant,
                        textStyle: theme.textTheme.bodySmall?.copyWith(
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      child: Text(l10n.helpCancelOrder),
                    ),
                  TextButton(
                    key: const ValueKey('help-guide-inquiry'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      onInquiry();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.onSurfaceVariant,
                      textStyle: theme.textTheme.bodySmall?.copyWith(
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    child: Text(l10n.helpLeaveInquiry),
                  ),
                ],
              ),
              FilledButton(
                key: const ValueKey('help-guide-ok'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.actionConfirm),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "다른 도움이 필요하신가요?"(레퍼런스 9-1 5 그 외). 상담원 실시간 채팅은 없어(2026-11-09 결정) AI 상담으로,
/// 문의 남기기는 아래 글자 단추로.
class _OtherHelpGuide extends StatelessWidget {
  const _OtherHelpGuide({required this.onChat, required this.onInquiry});

  final VoidCallback onChat;
  final VoidCallback onInquiry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      key: const ValueKey('help-other-guide'),
      appBar: AppBar(),
      body: Column(
        children: [
          const SizedBox(height: 24),
          Text(
            l10n.helpOtherTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 21,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.helpOtherBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Expanded(
            child: Center(
              child: PmartLineIcon(
                PmartLineIcons.headset,
                size: 96,
                strokeWidth: 1.4,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                key: const ValueKey('help-guide-inquiry'),
                onPressed: () {
                  Navigator.of(context).pop();
                  onInquiry();
                },
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                  textStyle: theme.textTheme.bodySmall?.copyWith(
                    decoration: TextDecoration.underline,
                  ),
                ),
                child: Text(l10n.helpLeaveInquiry),
              ),
              FilledButton(
                key: const ValueKey('help-guide-chat'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  onChat();
                },
                child: Text(l10n.helpChat),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
