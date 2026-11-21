import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../data/orders_repository.dart' show deliveryNotCompletedCode;
import '../domain/orders.dart';
import 'orders_providers.dart';

/// 전달 완료 증빙(사진·놓은 곳) — 배송 하나. 실패는 그대로 던진다(사진 없음으로 바꾸지 않는다).
final deliveryProofProvider = FutureProvider.autoDispose
    .family<DeliveryProof, String>(
      (ref, deliveryId) =>
          ref.watch(ordersRepositoryProvider).deliveryProof(deliveryId),
    );

/// 증빙 사진 한 장(메모리에만 — 서버가 `no-store` 로 준다).
final deliveryProofPhotoProvider = FutureProvider.autoDispose
    .family<Uint8List, (String, String)>(
      (ref, key) => ref
          .watch(ordersRepositoryProvider)
          .deliveryProofPhoto(key.$1, key.$2),
    );

/// 이 주문에서 전달 완료된 배송(사진을 볼 수 있는 것).
List<ShipmentView> deliveredShipments(OrderDetail o) => [
  for (final s in o.shipments)
    if (s.state == ShipmentState.delivered && s.deliveryId != null) s,
];

/// 문의하기 → "입력한 주소와 다른 곳으로 배달됐어요"·"상품을 받지 못했어요"(레퍼런스 9-2 3-3):
/// "입력한 주소로 배달이 오지 않았나요?" — 내 배송지, 라이더가 남긴 전달 완료 사진(누르면 크게), 아래 [문의 남기기]·[AI 채팅 상담].
/// 계약에 라이더 통화가 없어(상담원이 연락) 레퍼런스의 [라이더님께 통화 요청] 자리는 [문의 남기기]다(사용자 2026-11-21).
/// 여러 번에 나눠 배달됐으면 배송마다 묶어 보인다.
class DeliveryProofScreen extends StatelessWidget {
  const DeliveryProofScreen({
    super.key,
    required this.order,
    required this.onInquiry,
    required this.onChat,
  });

  final OrderDetail order;
  final VoidCallback onInquiry;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shipments = deliveredShipments(order);
    final a = order.shippingAddress;
    return Scaffold(
      key: const ValueKey('delivery-proof'),
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            l10n.proofTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 20),
          // 내 배송지(주문 당시 사본, BR-37 — 없으면 "배송지 정보 없음")
          Container(
            key: const ValueKey('proof-address'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                PmartLineIcon(
                  PmartLineIcons.pin,
                  size: 20,
                  color: scheme.onSurface,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    a == null
                        ? l10n.shippingAddressUnavailable
                        : '${a.roadAddress} ${a.detailAddress}'.trim(),
                    style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          for (final (i, s) in shipments.indexed) ...[
            if (i > 0) const SizedBox(height: 28),
            _ProofGroup(
              deliveryId: s.deliveryId!,
              label: shipments.length > 1 ? l10n.proofShipmentN(i + 1) : null,
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                key: const ValueKey('proof-inquiry'),
                onPressed: onInquiry,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: scheme.onSurface,
                  foregroundColor: scheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(l10n.supportNewInquiry),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const ValueKey('proof-chat'),
                onPressed: onChat,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  foregroundColor: scheme.onSurface,
                  side: BorderSide(color: scheme.onSurface),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(l10n.helpChat),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 배송 하나의 전달 완료 증빙: (나눠 배달이면 "배송 N") · 전달 시각, 사진들, 놓은 곳 설명.
class _ProofGroup extends ConsumerWidget {
  const _ProofGroup({required this.deliveryId, this.label});

  final String deliveryId;
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      color: scheme.onSurfaceVariant,
    );
    final value = ref.watch(deliveryProofProvider(deliveryId));
    Widget notice(String text, {VoidCallback? onRetry}) => Container(
      key: ValueKey('proof-notice-$deliveryId'),
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(text, textAlign: TextAlign.center, style: muted),
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: Text(l10n.startRetry)),
          ],
        ],
      ),
    );
    return Column(
      key: ValueKey('proof-$deliveryId'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null || value.value?.completedAt != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              [
                ?label,
                if (value.value?.completedAt case final at?)
                  l10n.proofDeliveredAt(formatSeoulTime(at)),
              ].join(' · '),
              style: theme.textTheme.titleSmall?.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        switch (value) {
          AsyncData(value: final p) when p.photoRefs.isEmpty => notice(
            l10n.proofNoPhoto,
          ),
          AsyncData(value: final p) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, photo) in p.photoRefs.indexed) ...[
                if (i > 0) const SizedBox(height: 12),
                _ProofPhoto(deliveryId: deliveryId, photoRef: photo),
              ],
              if (p.placementDetail case final d?)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    l10n.proofPlacement(d),
                    key: ValueKey('proof-placement-$deliveryId'),
                    style: muted,
                  ),
                ),
            ],
          ),
          // 아직 전달 완료 전 — 사진이 없는 것이 아니라 아직 없다.
          AsyncError(error: ProblemFailure(:final problem))
              when problem.code == deliveryNotCompletedCode =>
            notice(l10n.proofNotYet),
          AsyncError(error: ProblemFailure(problem: Problem(status: 404))) =>
            notice(l10n.proofNoPhoto),
          AsyncError() => notice(
            l10n.proofFailed,
            onRetry: () => ref.invalidate(deliveryProofProvider(deliveryId)),
          ),
          _ => const AspectRatio(
            aspectRatio: 3 / 4,
            child: PmartShimmer(
              child: PmartBone(height: double.infinity, radius: 12),
            ),
          ),
        },
      ],
    );
  }
}

/// 사진 한 장(3:4 칸, 둥근 모서리). 오른쪽 아래 확대 단추 — 누르면 크게(손가락으로 늘리기).
class _ProofPhoto extends ConsumerWidget {
  const _ProofPhoto({required this.deliveryId, required this.photoRef});

  final String deliveryId;
  final String photoRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final key = (deliveryId, photoRef);
    final value = ref.watch(deliveryProofPhotoProvider(key));
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.72,
        child: AspectRatio(
          aspectRatio: 3 / 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: switch (value) {
              AsyncData(value: final bytes) => Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    key: ValueKey('proof-photo-$photoRef'),
                    onTap: () => _openLarge(context, bytes),
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.85),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _openLarge(context, bytes),
                        child: Padding(
                          padding: const EdgeInsets.all(9),
                          child: Semantics(
                            label: l10n.proofZoom,
                            child: const PmartLineIcon(
                              PmartLineIcons.expand,
                              size: 20,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              AsyncError() => ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Center(
                  child: TextButton(
                    key: ValueKey('proof-photo-retry-$photoRef'),
                    onPressed: () =>
                        ref.invalidate(deliveryProofPhotoProvider(key)),
                    child: Text(l10n.proofPhotoFailed),
                  ),
                ),
              ),
              _ => const PmartShimmer(
                child: PmartBone(height: double.infinity, radius: 12),
              ),
            },
          ),
        ),
      ),
    );
  }

  void _openLarge(BuildContext context, Uint8List bytes) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          key: const ValueKey('proof-photo-large'),
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: InteractiveViewer(
            maxScale: 4,
            child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
          ),
        ),
      ),
    );
  }
}
