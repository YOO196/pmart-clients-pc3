import 'package:flutter/foundation.dart';

import '../../auth/domain/auth.dart' show SocialProvider;

/// 본인 프로필(계약 `Profile`). 이름은 nickname, 연락처는 서버가 가린 값만 받는다.
/// Google 프로필(이름·이메일·사진)은 로그인마다 서버가 최신으로 바꾸고 앱은 표시만 한다(ADR-0024, 백엔드 안내 2026-10-31).
@immutable
class Profile {
  const Profile({
    required this.accountId,
    required this.version,
    this.nickname,
    this.phoneMasked,
    this.phone,
    this.phoneVerified = false,
    this.name,
    this.email,
    this.emailVerified,
    this.profileImageUrl,
    this.withdrawPending = false,
    this.socialProvider,
    this.photoSource,
    this.restriction = AccountRestriction.none,
    this.restrictedUntil,
  });

  /// 계정 제한(customer 0.16.0 CU-7) — 이용제한이면 문의·리뷰를 못 쓴다, 정지면 주문·로그인까지.
  final AccountRestriction restriction;

  /// 제한이 풀리는 시각(늘 있음 — 지나면 없음으로 본다).
  final DateTime? restrictedUntil;

  /// 지금 문의·리뷰를 쓸 수 없는지(기한이 지났으면 아니다 — 서버가 최종 판정).
  bool writingBlockedAt(DateTime now) =>
      restriction != AccountRestriction.none &&
      (restrictedUntil == null || restrictedUntil!.isAfter(now));

  /// 사진 출처(customer 0.15.0 BR-80). 모르면 null(옛 서버).
  final ProfilePhotoSource? photoSource;

  /// 탈퇴 처리 대기(계정 상태 `WITHDRAW_PENDING`, customer 0.12.0). 로그인은 되고 새 주문만 막힌다.
  final bool withdrawPending;

  /// 가입한 소셜(서버 값). 탈퇴·철회 재인증에 쓴다. 모르면 null.
  final SocialProvider? socialProvider;

  final String accountId;
  final int version;
  final String? nickname;

  /// 로그인 제공자(Google) 프로필 이름. 없을 수 있다.
  final String? name;

  /// 로그인 제공자가 준 이메일. 없을 수 있다.
  final String? email;

  /// 제공자가 이메일을 확인했는지. 모르면 null.
  final bool? emailVerified;

  /// 프로필 사진 사본의 게이트웨이 상대 경로(`/api/v1/me/profile-image?v=…`). 본인 토큰이 있어야 받는다. 사본이 없으면 null.
  final String? profileImageUrl;

  bool get hasProviderName => name?.trim().isNotEmpty ?? false;
  bool get hasEmail => email?.trim().isNotEmpty ?? false;
  bool get hasProfileImage => profileImageUrl?.isNotEmpty ?? false;

  /// 서버가 가린 휴대폰 번호(예: 010-****-1234). 없으면 아직 등록하지 않았다.
  final String? phoneMasked;

  bool get hasPhone => phoneMasked?.isNotEmpty ?? false;

  /// 본인에게만 주는 가리지 않은 번호(숫자, customer 0.7.0 — BR-32). 배송지 받는 분 연락처를 채울 때만 쓴다.
  /// 본인 확인을 거치지 않은 번호다(`phoneVerified=false`). 로그·화면 문자열에 남기지 않는다. 없으면 null.
  final String? phone;

  /// 휴대폰 번호를 OCTOMO 로 확인했는지(customer 0.9.0). 번호를 바꾸면 다시 false.
  final bool phoneVerified;

  @override
  String toString() => 'Profile($accountId, v$version)';
}

/// 프로필 사진 출처(customer 0.15.0 `Profile.photoSource`). 직접 올림·기본을 고르면 로그인해도 제공자 사진으로 덮지 않는다.
enum ProfilePhotoSource {
  /// 로그인 계정 사진(로그인마다 최신).
  provider,

  /// 고객이 직접 올린 사진.
  custom,

  /// 기본 이미지(사진 없음).
  none,
}

/// 프로필 사진 바꾸기(BR-80) — 셋 다 본인 토큰·Idempotency-Key, 결과 CommandResponse.
@immutable
sealed class ProfilePhotoChange {
  const ProfilePhotoChange();
}

/// `PUT /me/profile-image` — 앱이 정사각형으로 자르고 줄인 사진(2MB 이하, JPEG·PNG·WebP).
final class ProfilePhotoUpload extends ProfilePhotoChange {
  const ProfilePhotoUpload(this.bytes, {this.filename = 'profile.png'});

  final Uint8List bytes;
  final String filename;
}

/// `DELETE /me/profile-image` — 기본 이미지로.
final class ProfilePhotoClear extends ProfilePhotoChange {
  const ProfilePhotoClear();
}

/// `POST /me/profile-image/provider-restorations` — 로그인 계정 사진으로 되돌리기.
final class ProfilePhotoRestore extends ProfilePhotoChange {
  const ProfilePhotoRestore();
}

/// 휴대폰 번호 입력 규칙(화면 검증용, 서버가 최종 검증). 숫자만 남겨 010·011·016~019 로 시작하는 10~11자리.
abstract final class PhoneInput {
  static final _mobile = RegExp(r'^01[016789]\d{7,8}$');

  static String normalize(String raw) => raw.replaceAll(RegExp(r'\D'), '');

  static bool valid(String raw) => _mobile.hasMatch(normalize(raw));
}

/// 이름(계약 `Profile.nickname`, 최대 30자). 계약에 실명 필드가 없어 nickname 에 둔다(BR-32).
abstract final class NameInput {
  static const maxLength = 30;

  static bool valid(String raw) {
    final v = raw.trim();
    return v.isNotEmpty && v.length <= maxLength;
  }
}

/// 내 정보(이름·휴대폰 번호) 저장 결과. [ProfileChangeApplied] 만 "저장됨"이다.
@immutable
sealed class ProfileChangeOutcome {
  const ProfileChangeOutcome();
}

final class ProfileChangeApplied extends ProfileChangeOutcome {
  const ProfileChangeApplied();
}

/// 접수됐지만 반영을 아직 확인하지 못했다. 같은 요청 ID 로 다시 확인한다.
final class ProfileChangePending extends ProfileChangeOutcome {
  const ProfileChangePending(this.requestId);

  final String requestId;
}

/// 서버가 아직 이 기능을 제공하지 않는다(501 UNSUPPORTED_ACTION).
final class ProfileChangeUnsupported extends ProfileChangeOutcome {
  const ProfileChangeUnsupported();
}

final class ProfileChangeRejected extends ProfileChangeOutcome {
  const ProfileChangeRejected(this.code);

  final String code;
}

/// 결과를 모른다(응답 유실·5xx). 프로필을 다시 조회해 확인한다.
final class ProfileChangeUnknown extends ProfileChangeOutcome {
  const ProfileChangeUnknown();
}

/// 계정 제한(계약 AccountRestriction). 모르는 값은 none(서버가 막으면 그 응답으로 안내한다).
enum AccountRestriction { none, restricted, suspended }
