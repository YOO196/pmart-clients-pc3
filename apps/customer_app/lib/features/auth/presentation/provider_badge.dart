import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../domain/auth.dart';

/// 가입·로그인 방식 배지(카카오·네이버·구글·애플 — 로그인 단추와 같은 색). 이메일만 보면 제공자를 헷갈린다
/// (네이버가 준 연락처 이메일이 gmail 주소인 경우 등 — 백엔드 요청 2026-11-25 provider-badge-next-to-email).
class ProviderBadge extends StatelessWidget {
  const ProviderBadge({super.key, required this.provider, this.textKey});

  final SocialProvider provider;

  /// 글자 위젯 키(시험이 읽는다).
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (bg, fg, border, label) = switch (provider) {
      SocialProvider.kakao => (
        const Color(0xFFFEE500),
        const Color(0xFF191600),
        false,
        l10n.loginKakaoShort,
      ),
      SocialProvider.naver => (
        const Color(0xFF03C75A),
        Colors.white,
        false,
        l10n.loginNaverShort,
      ),
      SocialProvider.google => (
        Colors.white,
        const Color(0xFF4285F4),
        true,
        l10n.loginGoogleShort,
      ),
      SocialProvider.apple => (
        Colors.black,
        Colors.white,
        false,
        l10n.loginAppleShort,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: border
            ? Border.all(color: Theme.of(context).colorScheme.outlineVariant)
            : null,
      ),
      child: Text(
        label,
        key: textKey,
        style: TextStyle(
          fontSize: 11,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
