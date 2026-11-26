import 'dart:async';

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/mock_profile_repository.dart';
import '../data/phone_verification_repository.dart';
import '../data/profile_repository.dart';
import '../domain/profile.dart';

final phoneVerificationRepositoryProvider =
    Provider<PhoneVerificationRepository>(
      (ref) => switch (ref.watch(envProvider)) {
        PmartEnv.mock => MockPhoneVerificationRepository(
          // 목: 확인되면 목 프로필도 확인됨으로.
          onVerified: () => switch (ref.read(profileRepositoryProvider)) {
            final MockProfileRepository m => m.phoneVerified = true,
            _ => null,
          },
        ),
        PmartEnv.local => ApiPhoneVerificationRepository(
          ref.watch(dioProvider),
        ),
      },
    );

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

/// 프로필 사진 사본 바이트. 키는 `Profile.profileImageUrl`(사진이 바뀌면 `v` 가 바뀌어 다시 받는다). 사본이 없으면 null.
/// 본인 토큰이 필요한 경로라 Image.network 대신 인증 Dio(getMyProfileImage)로 받는다.
final profileImageProvider = FutureProvider.family<Uint8List?, String>(
  (ref, url) => ref.watch(profileRepositoryProvider).profileImage(),
);

/// 본인 프로필. 비회원이면 null.
final profileProvider = AsyncNotifierProvider<ProfileController, Profile?>(
  ProfileController.new,
);

/// 로그인 계정 값(이름·이메일·사진)이 아직 없을 때 다시 읽는 간격. 서버는 가입·로그인 완료 약 1초 뒤 사건으로
/// 이름·이메일을, 사진은 사본을 만든 뒤 몇 초 더 걸려 넣는다(백엔드 회신 2026-11-25 BR-103). 시험은 비운다.
final profileRefreshDelaysProvider = Provider<List<Duration>>(
  (_) => const [Duration(milliseconds: 2500), Duration(seconds: 6)],
);

class ProfileController extends AsyncNotifier<Profile?> {
  ProfileRepository get _repo => ref.read(profileRepositoryProvider);

  @override
  Future<Profile?> build() async {
    if (ref.watch(sessionProvider) is! MemberSession) return null;
    final p = await ref.watch(profileRepositoryProvider).get();
    _refreshWhileIncomplete(p);
    return p;
  }

  /// 소셜 로그인 계정인데 이름·이메일이 둘 다 없거나 사진이 없으면 정해 둔 간격으로 몇 번 조용히 다시 읽는다
  /// (사용자 2026-11-25 "처음 로그인 뒤 다시 로그인해야 이메일이 뜬다"). 실패는 무시(앞 값 유지).
  void _refreshWhileIncomplete(Profile p) {
    // 가입 직후에는 서버 프로필의 socialProvider 도 아직 비어 있다(이름·이메일과 같이 채워진다) — 이 기기
    // 세션이 아는 로그인 제공자로 본다.
    final session = ref.read(sessionProvider);
    final social =
        p.socialProvider != null ||
        (session is MemberSession && session.provider != null);
    bool incomplete(Profile q) =>
        social &&
        ((q.name == null && q.email == null) || q.profileImageUrl == null);
    if (!incomplete(p)) return;
    final timers = <Timer>[];
    ref.onDispose(() {
      for (final t in timers) {
        t.cancel();
      }
    });
    for (final d in ref.read(profileRefreshDelaysProvider)) {
      timers.add(
        Timer(d, () async {
          final now = state.value;
          if (!ref.mounted || now == null || !incomplete(now)) return;
          try {
            final fresh = await _repo.get();
            if (ref.mounted) state = AsyncData(fresh);
          } on PmartFailure {
            // 다음 기회에(앞 값 유지)
          }
        }),
      );
    }
  }

  /// 화면을 열 때 조용히 다시 읽는다(읽는 동안 앞 값 유지, 실패는 무시). 서버는 로그인 사건·사진 사본을
  /// 나중에 반영하므로 한 번 읽은 값이 오래 남지 않게 한다(사용자 2026-11-25 — 사진을 바꾸고서야 이메일이 보였다).
  Future<void> refreshQuietly() async {
    if (ref.read(sessionProvider) is! MemberSession) return;
    try {
      final p = await _repo.get();
      if (ref.mounted) state = AsyncData(p);
    } on PmartFailure {
      // 앞 값 유지
    }
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
  ///
  /// [name] 은 닉네임(nickname), [realName] 은 실명(customer 0.21.0 BR-107, 빈 문자열 = 로그인 계정 이름으로).
  Future<ProfileChangeOutcome> changeProfile({
    String? name,
    String? phone,
    String? realName,
  }) async {
    final current = state.value ?? await future;
    if (current == null) return const ProfileChangeRejected('NOT_MEMBER');
    final nickname = name?.trim();
    final digits = phone == null ? null : PhoneInput.normalize(phone);
    final key = IdempotencyKey.generate();
    final real = realName?.trim();
    Future<ProfileChangeOutcome> send() => _repo.changeProfile(
      nickname: nickname,
      phone: digits,
      realName: real,
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

  /// 프로필 사진 바꾸기(BR-80). 한 번 누름 = 키 하나, 결과 불명은 같은 키로 한 번 더 보낸다.
  /// 결과와 상관없이(거절 제외) 프로필을 다시 읽어 서버 값으로만 사진을 보인다.
  /// 되돌리기는 서버가 응답 뒤 사본을 받아 두므로(계약) 사진 주소가 비어 있으면 잠시 뒤 몇 번 더 읽는다.
  Future<ProfileChangeOutcome> changePhoto(ProfilePhotoChange change) async {
    final key = IdempotencyKey.generate();
    var outcome = await _repo.changePhoto(change, key: key);
    if (outcome is ProfileChangeUnknown) {
      outcome = await _repo.changePhoto(change, key: key);
    }
    if (outcome is ProfileChangeRejected ||
        outcome is ProfileChangeUnsupported) {
      return outcome;
    }
    await _reload();
    if (outcome is ProfileChangeApplied && change is ProfilePhotoRestore) {
      final policy = ref.read(profilePollPolicyProvider);
      for (var i = 0; i < policy.attempts; i++) {
        final p = state.value;
        if (p == null || p.hasProfileImage) break;
        await Future<void>.delayed(policy.interval);
        if (!ref.mounted) break;
        await _reload();
      }
    }
    return outcome;
  }
}
