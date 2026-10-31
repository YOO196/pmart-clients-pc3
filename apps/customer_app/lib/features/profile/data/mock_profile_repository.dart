import 'package:pmart_core/pmart_core.dart';

import '../domain/profile.dart';
import 'profile_repository.dart';

/// 목 프로필. 저장한 번호는 서버처럼 가려서 돌려준다.
final class MockProfileRepository implements ProfileRepository {
  MockProfileRepository({this.latency = const Duration(milliseconds: 200)});

  final Duration latency;
  String? _phone;
  int _version = 1;

  /// 다음 변경을 501(미구현)로 만든다.
  bool unsupported = false;

  final changeKeys = <String>[];

  Future<void> _wait() => Future<void>.delayed(latency);

  static String mask(String digits) => digits.length < 7
      ? '***'
      : '${digits.substring(0, 3)}-****-${digits.substring(digits.length - 4)}';

  @override
  Future<Profile> get() async {
    await _wait();
    return Profile(
      accountId: 'acct-mock-1',
      version: _version,
      nickname: '피마',
      phoneMasked: _phone == null ? null : mask(_phone!),
    );
  }

  @override
  Future<ProfileChangeOutcome> changePhone(
    String phone, {
    required int expectedVersion,
    required IdempotencyKey key,
  }) async {
    await _wait();
    changeKeys.add(key.value);
    if (unsupported) {
      return profileChangeFailure(const UnknownResultFailure(httpStatus: 501));
    }
    if (expectedVersion != _version) {
      return const ProfileChangeRejected(ProblemCode.versionConflict);
    }
    _phone = phone;
    _version++;
    return const ProfileChangeApplied();
  }

  @override
  Future<ProfileChangeOutcome> change(String requestId) async {
    await _wait();
    return const ProfileChangeApplied();
  }
}
