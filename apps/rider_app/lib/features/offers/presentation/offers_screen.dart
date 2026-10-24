import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers.dart';
import '../domain/offer_list.dart';
import '../../delivery/presentation/delivery_controller.dart';
import 'offer_controllers.dart';

String lateText(AppLocalizations l10n, LateReason r) => switch (r) {
  LateReason.expired => l10n.lateExpired,
  LateReason.alreadyAssigned => l10n.lateAlreadyAssigned,
  LateReason.orderCancelled => l10n.lateOrderCancelled,
  LateReason.ineligible => l10n.lateIneligible,
  LateReason.unknown => l10n.lateExpired,
};

/// 라이더 홈: 운행 상태 + 배차 제안. 화면 상태는 서버 확정 결과로만 바꾼다.
class OffersScreen extends ConsumerStatefulWidget {
  const OffersScreen({super.key});

  @override
  ConsumerState<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends ConsumerState<OffersScreen> {
  late final AppLifecycleListener _lifecycle;
  Timer? _ticker;
  final _responding = <String>{};

  @override
  void initState() {
    super.initState();
    // 앱 실행·포그라운드 복귀 때는 간격과 상관없이 바로 조회한다(알림 유실 복구).
    Future.microtask(() => ref.read(offerPollerProvider.notifier).refreshNow());
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(offerPollerProvider.notifier).refreshNow(),
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _respond(OfferItem offer, {required bool accept}) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _responding.add(offer.offerId));
    final outcome = await ref
        .read(offerResponderProvider)
        .respond(
          offer,
          accept: accept,
          reason: accept ? null : RejectReason.other,
        );
    if (!mounted) return;
    setState(() => _responding.remove(offer.offerId));
    switch (outcome) {
      case OfferAssigned():
        _toast(l10n.offerAssigned);
      case OfferLate(:final reason):
        _toast(lateText(l10n, reason));
      case OfferRejected(:final rejectionNotice):
        if (rejectionNotice) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              content: Text(l10n.rejectionNotice),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.ok),
                ),
              ],
            ),
          );
        }
      case OfferUnknown():
        _toast(l10n.offerUnknown);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mock = ref.watch(envProvider) == PmartEnv.mock;
    final poll = ref.watch(offerPollerProvider);
    final poller = ref.read(offerPollerProvider.notifier);
    final duty = ref.watch(dutyProvider);
    final aiMode =
        ref.watch(dispatchModeProvider).value == DispatchMode.aiRecommended;
    // 진행 중 배송은 서버 목록(재접속 복구)과 이번에 수락한 배송을 합쳐 보인다.
    final assigned = {
      ...?ref.watch(myActiveDeliveriesProvider).value?.map((d) => d.deliveryId),
      ...ref.watch(assignedDeliveriesProvider),
    }.toList();
    final list = poll.list;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.offersTitle),
        actions: [
          if (mock)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(label: Text(l10n.mockModeBadge)),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: poller.refreshNow,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            switch (duty) {
              AsyncData(:final value) => _DutyCard(state: value),
              AsyncError() => ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(l10n.dutyLoadFailed),
                trailing: TextButton(
                  onPressed: () => ref.invalidate(dutyProvider),
                  child: Text(l10n.retry),
                ),
              ),
              _ => const LinearProgressIndicator(),
            },
            if (assigned.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(l10n.myDeliveries, style: theme.textTheme.titleMedium),
              for (final id in assigned)
                ListTile(
                  key: ValueKey('delivery-$id'),
                  leading: const Icon(Icons.delivery_dining),
                  title: Text(l10n.deliveryNumber(id)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/deliveries/$id'),
                ),
            ],
            const Divider(height: 24),
            if (poll.reconnecting)
              ListTile(
                key: const ValueKey('reconnecting'),
                leading: const Icon(Icons.wifi_off),
                // 조회 실패는 "제안 없음"이 아니다.
                title: Text(l10n.reconnecting),
              ),
            if (poll.stopped)
              ListTile(
                key: const ValueKey('polling-stopped'),
                leading: const Icon(Icons.pause_circle_outline),
                title: Text(l10n.pollingStopped),
              ),
            if (list == null && !poll.reconnecting)
              const Center(child: CircularProgressIndicator())
            else if (list != null &&
                list.offers.isEmpty &&
                !poll.reconnecting &&
                !poll.stopped)
              Center(
                key: const ValueKey('offers-empty'),
                child: Text(l10n.offersEmpty),
              ),
            for (final offer in list?.offers ?? const <OfferItem>[])
              Card(
                key: ValueKey('offer-${offer.offerId}'),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offer.dropAreaLabel ?? l10n.dropAreaUnknown,
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        [
                          switch (offer.estimatedFee) {
                            final int fee => l10n.offerFee(formatKrw(fee)),
                            null => l10n.offerFeeUnknown,
                          },
                          if (offer.distanceKm case final d?)
                            l10n.distanceKm(d.toStringAsFixed(1)),
                          if (offer.weightG case final w?)
                            l10n.weightKg((w / 1000).toStringAsFixed(1)),
                          if (offer.containsAlcohol ?? false)
                            l10n.containsAlcohol,
                        ].join(' · '),
                      ),
                      Text(
                        // 서버 값에서 출발해 단말 경과 시간으로 줄인다. 0 이어도 만료 확정이 아니다.
                        l10n.offerRemaining(poller.remainingFor(offer)),
                        key: ValueKey('remaining-${offer.offerId}'),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              key: ValueKey('accept-${offer.offerId}'),
                              onPressed: _responding.contains(offer.offerId)
                                  ? null
                                  : () => _respond(offer, accept: true),
                              child: Text(l10n.accept),
                            ),
                          ),
                          // 거절 버튼은 AI 추천 모드에만 있다(일반 모드는 응답하지 않으면 만료).
                          if (aiMode) ...[
                            const SizedBox(width: 8),
                            OutlinedButton(
                              key: ValueKey('reject-${offer.offerId}'),
                              onPressed: _responding.contains(offer.offerId)
                                  ? null
                                  : () => _respond(offer, accept: false),
                              child: Text(l10n.reject),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DutyCard extends ConsumerWidget {
  const _DutyCard({required this.state});

  final OperatingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ctl = ref.read(dutyProvider.notifier);
    Future<void> change(bool onDuty, bool newDispatch) async {
      final code = await ctl.change(onDuty: onDuty, newDispatch: newDispatch);
      if (code == null || !context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              code == ProblemCode.invalidState
                  ? l10n.cannotEndWithActive
                  : l10n.dutyChangeFailed,
            ),
          ),
        );
    }

    return Card(
      child: Column(
        children: [
          SwitchListTile(
            key: const ValueKey('on-duty'),
            title: Text(state.onDuty ? l10n.onDuty : l10n.offDuty),
            value: state.onDuty,
            onChanged: (v) => change(v, v),
          ),
          SwitchListTile(
            key: const ValueKey('new-dispatch'),
            title: Text(l10n.newDispatch),
            subtitle: Text(l10n.newDispatchNote),
            value: state.newDispatchEnabled,
            onChanged: state.onDuty ? (v) => change(true, v) : null,
          ),
        ],
      ),
    );
  }
}
