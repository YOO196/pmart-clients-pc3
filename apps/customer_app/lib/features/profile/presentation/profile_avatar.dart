import 'package:flutter/material.dart';
import 'package:pmart_ui/pmart_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../domain/profile.dart';
import 'profile_controller.dart';

/// 프로필 사진(로그인 제공자 사진의 서버 사본, ADR-0024). 사본이 없거나 아직 못 받았거나 실패하면 기본 아바타.
/// 본인 토큰이 필요한 경로라 인증 Dio 로 바이트를 받아 그린다(Image.network 는 토큰 없이 401).
class ProfileAvatar extends ConsumerWidget {
  const ProfileAvatar({super.key, required this.profile, this.radius = 20});

  final Profile? profile;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final url = profile?.profileImageUrl;
    final bytes = (url == null || url.isEmpty)
        ? null
        : ref.watch(profileImageProvider(url)).value;
    final fallback = CircleAvatar(
      key: const ValueKey('profile-avatar-default'),
      radius: radius,
      child: PmartLineIcon(PmartLineIcons.user, size: radius),
    );
    return Semantics(
      label: l10n.infoProfileImage,
      image: true,
      child: bytes == null
          ? fallback
          : CircleAvatar(
              key: const ValueKey('profile-avatar-image'),
              radius: radius,
              backgroundImage: MemoryImage(bytes),
            ),
    );
  }
}
