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
      appBar: AppBar(title: Text(l10n.orderInquiry)),
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
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
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Text(
                  l10n.orderHelpTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              for (final issue in deliveryIssuesFor(o.status))
                row(
                  deliveryIssueText(l10n, issue),
                  ValueKey('order-help-${issue.name}'),
                  () => context.pushReplacement(
                    '/support/inquiries/new',
                    extra: InquiryFormArgs(
                      orderId: o.orderId,
                      deliveryIssue: issue,
                      deliveryId: deliveryId,
                    ),
                  ),
                ),
              row(
                l10n.orderHelpOther,
                const ValueKey('order-help-other'),
                () => context.pushReplacement(
                  '/support/inquiries/new',
                  extra: InquiryFormArgs(orderId: o.orderId),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
