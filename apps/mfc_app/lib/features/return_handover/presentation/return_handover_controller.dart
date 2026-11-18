import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart';
import '../../tasks/presentation/task_controllers.dart'
    show currentMfcIdProvider;
import '../data/mock_return_handover_repository.dart';
import '../data/return_handover_repository.dart';
import '../domain/return_handover.dart';

final returnHandoverRepositoryProvider = Provider<ReturnHandoverRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockReturnHandoverRepository(),
    PmartEnv.local => ApiReturnHandoverRepository(ref.watch(dioProvider)),
  },
);

/// 새 번호 결과 불명일 때 같은 키로 자동 재전송하는 횟수.
final reissueResendAttemptsProvider = Provider<int>((_) => 2);

/// 센터의 반납 대기 배송과 번호.
final returnHandoversProvider =
    FutureProvider.autoDispose<List<ReturnHandoverView>>(
      (ref) => ref
          .watch(returnHandoverRepositoryProvider)
          .waiting(ref.watch(currentMfcIdProvider)),
    );

enum ReissuePhase { idle, sending, done, rejected, unknown }

@immutable
class ReissueFlow {
  const ReissueFlow(this.phase, {this.rejectCode});

  final ReissuePhase phase;
  final String? rejectCode;
}

final reissueFlowProvider = NotifierProvider.autoDispose
    .family<ReissueController, ReissueFlow, String>(ReissueController.new);

/// 새 번호 내기. 결과를 모르면 같은 키로만 다시 보낸다 — 새 키로 보내면 번호가 한 번 더 바뀐다.
class ReissueController extends Notifier<ReissueFlow> {
  ReissueController(this.deliveryId);

  final String deliveryId;
  IdempotencyKey? _key;

  @override
  ReissueFlow build() => const ReissueFlow(ReissuePhase.idle);

  Future<void> submit() async {
    if (state.phase == ReissuePhase.sending) return;
    if (state.phase != ReissuePhase.unknown) _key = null;
    final key = _key ??= IdempotencyKey.generate();
    state = const ReissueFlow(ReissuePhase.sending);
    final repo = ref.read(returnHandoverRepositoryProvider);
    var outcome = await repo.reissue(deliveryId, key: key);
    final resend = ref.read(reissueResendAttemptsProvider);
    for (var i = 0; i < resend && outcome is ReissueUnknown; i++) {
      if (!ref.mounted) return;
      outcome = await repo.reissue(deliveryId, key: key);
    }
    if (!ref.mounted) return;
    switch (outcome) {
      case Reissued():
        _key = null;
        state = const ReissueFlow(ReissuePhase.done);
        ref.invalidate(returnHandoversProvider);
      case ReissueRejected(:final code):
        _key = null;
        state = ReissueFlow(ReissuePhase.rejected, rejectCode: code);
        ref.invalidate(returnHandoversProvider);
      case ReissueUnknown():
        state = const ReissueFlow(ReissuePhase.unknown);
    }
  }
}
