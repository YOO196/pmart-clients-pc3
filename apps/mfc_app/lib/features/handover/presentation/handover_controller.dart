import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart';
import '../../tasks/presentation/task_controllers.dart'
    show currentMfcIdProvider;
import '../data/handover_repository.dart';
import '../data/mock_handover_repository.dart';
import '../domain/handover.dart';

final handoverRepositoryProvider = Provider<HandoverRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockHandoverRepository(),
    PmartEnv.local => ApiHandoverRepository(ref.watch(dioProvider)),
  },
);

/// 확인 결과 불명일 때 같은 키로 자동 재전송하는 횟수.
final checkResendAttemptsProvider = Provider<int>((_) => 2);

/// 센터의 점원 확인 필요 포장.
final handoverChecksProvider = FutureProvider.autoDispose<HandoverCheckList>(
  (ref) => ref
      .watch(handoverRepositoryProvider)
      .toCheck(ref.watch(currentMfcIdProvider)),
);

final handoverProvider = FutureProvider.autoDispose
    .family<HandoverView, String>(
      (ref, packageId) =>
          ref.watch(handoverRepositoryProvider).resolution(packageId),
    );

final pickupEtaProvider = FutureProvider.autoDispose
    .family<PickupEtaView, String>(
      (ref, deliveryId) =>
          ref.watch(handoverRepositoryProvider).pickupEta(deliveryId),
    );

enum CheckPhase { idle, sending, done, rejected, unknown }

@immutable
class CheckFlow {
  const CheckFlow(this.phase, {this.pending, this.rejectCode, this.result});

  final CheckPhase phase;

  /// 보낸(또는 결과를 모르는) 확인 값. 결과를 모르는 동안 다른 값으로 바꿔 보내지 않는다.
  final HandoverCheck? pending;
  final String? rejectCode;

  /// 서버가 돌려준 확인 뒤 판정.
  final HandoverView? result;
}

final checkFlowProvider = NotifierProvider.autoDispose
    .family<CheckController, CheckFlow, String>(CheckController.new);

/// 점원 확인(`POST /packages/{id}/handover-checks`).
///
/// 결과를 모르면 같은 키로만 다시 보낸다. 앱을 다시 켜서 키를 잃어도 판정 조회의
/// `checkRequired`·`lastCheck` 로 반영 여부를 알 수 있다(새 키로 다시 보내면 409 INVALID_STATE).
class CheckController extends Notifier<CheckFlow> {
  CheckController(this.packageId);

  final String packageId;
  IdempotencyKey? _key;

  @override
  CheckFlow build() => const CheckFlow(CheckPhase.idle);

  Future<void> submit(HandoverCheck result, {String? note}) async {
    if (state.phase == CheckPhase.sending) return;
    // 결과 불명인 확인이 있으면 그 값으로만 다시 보낸다.
    final value = state.phase == CheckPhase.unknown
        ? state.pending ?? result
        : result;
    if (state.phase != CheckPhase.unknown) _key = null;
    final key = _key ??= IdempotencyKey.generate();
    state = CheckFlow(CheckPhase.sending, pending: value);
    final repo = ref.read(handoverRepositoryProvider);
    var outcome = await repo.check(packageId, value, note: note, key: key);
    final resend = ref.read(checkResendAttemptsProvider);
    for (var i = 0; i < resend && outcome is CheckUnknown; i++) {
      if (!ref.mounted) return;
      outcome = await repo.check(packageId, value, note: note, key: key);
    }
    if (!ref.mounted) return;
    switch (outcome) {
      case CheckDone(:final resolution):
        _key = null;
        state = CheckFlow(CheckPhase.done, pending: value, result: resolution);
        _refresh();
      case CheckRejected(:final code):
        _key = null;
        state = CheckFlow(
          CheckPhase.rejected,
          pending: value,
          rejectCode: code,
        );
        _refresh();
      case CheckUnknown():
        state = CheckFlow(CheckPhase.unknown, pending: value);
    }
  }

  void _refresh() {
    ref
      ..invalidate(handoverChecksProvider)
      ..invalidate(handoverProvider(packageId));
  }
}
