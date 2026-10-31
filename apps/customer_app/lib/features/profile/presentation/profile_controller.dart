import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/mock_profile_repository.dart';
import '../data/profile_repository.dart';
import '../domain/profile.dart';

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockProfileRepository(),
    PmartEnv.local => ApiProfileRepository(ref.watch(dioProvider)),
  },
);

/// 접수(ACCEPTED) 뒤 반영 확인 조회 간격·횟수.
final profilePollPolicyProvider = Provider<({Duration interval, int attempts})>(
  (_) => (interval: const Duration(seconds: 1), attempts: 5),
);

/// 본인 프로필. 비회원이면 null.
final profileProvider = AsyncNotifierProvider<ProfileController, Profile?>(
  ProfileController.new,
);

class ProfileController extends AsyncNotifier<Profile?> {
  ProfileRepository get _repo => ref.read(profileRepositoryProvider);

  @override
  Future<Profile?> build() async {
    if (ref.watch(sessionProvider) is! MemberSession) return null;
    return ref.watch(profileRepositoryProvider).get();
  }

  Future<void> _reload() async {
    try {
      final p = await _repo.get();
      if (ref.mounted) state = AsyncData(p);
    } on PmartFailure catch (e, st) {
      if (ref.mounted) state = AsyncError(e, st);
    }
  }

  /// 내 정보 저장. 바뀐 항목만 보낸다(이름은 앞뒤 공백 제거, 번호는 숫자만).
  /// 버튼 한 번 = 키 하나, 결과 불명 재전송은 같은 키·같은 본문.
  Future<ProfileChangeOutcome> changeProfile({
    String? name,
    String? phone,
  }) async {
    final current = state.value ?? await future;
    if (current == null) return const ProfileChangeRejected('NOT_MEMBER');
    final nickname = name?.trim();
    final digits = phone == null ? null : PhoneInput.normalize(phone);
    final key = IdempotencyKey.generate();
    Future<ProfileChangeOutcome> send() => _repo.changeProfile(
      nickname: nickname,
      phone: digits,
      expectedVersion: current.version,
      key: key,
    );
    var outcome = await send();
    if (outcome is ProfileChangeUnknown) outcome = await send();
    if (outcome case ProfileChangePending(:final requestId)) {
      final policy = ref.read(profilePollPolicyProvider);
      for (var i = 0; i < policy.attempts; i++) {
        await Future<void>.delayed(policy.interval);
        if (!ref.mounted) return outcome;
        try {
          final checked = await _repo.change(requestId);
          if (checked is! ProfileChangePending) {
            outcome = checked;
            break;
          }
        } on PmartFailure {
          // 조회 실패는 결과가 아니다. 계속 확인 중이다.
        }
      }
    }
    if (outcome is ProfileChangeApplied || outcome is ProfileChangeUnknown) {
      await _reload();
    }
    return outcome;
  }
}
