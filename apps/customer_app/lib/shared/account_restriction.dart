import 'package:intl/intl.dart' show DateFormat;
import 'package:pmart_core/pmart_core.dart' show Problem;
import 'package:pmart_ui/pmart_ui.dart' show toSeoulWallClock;

import '../l10n/gen/app_localizations.dart';

/// 고객 계정 이용제한·정지(customer 0.16.0 CU-7, 백엔드 알림 2026-11-23 notice-account-restriction).
/// 이용제한 = 문의·리뷰 작성 막힘, 정지 = 주문·로그인까지 막힘. 늘 기한이 있다(7일, 지나면 저절로 풀림).
abstract final class AccountRestrictionCode {
  /// 로그인·토큰 갱신 403(정지).
  static const suspended = 'ACCOUNT_SUSPENDED';

  /// 문의·리뷰 작성 403(이용제한·정지).
  static const restricted = 'ACCOUNT_RESTRICTED';
}

/// Problem details 의 `until`(UTC ISO 시각). 없거나 읽지 못하면 null.
DateTime? restrictionUntilOf(Problem p) {
  for (final d in p.details) {
    if (d.field == 'until') return DateTime.tryParse(d.reason ?? '');
  }
  return null;
}

String _when(DateTime until) =>
    DateFormat('M월 d일 HH:mm', 'ko').format(toSeoulWallClock(until));

/// "11월 30일 14:00까지 계정이 정지됐어요…" — 기한을 모르면 기한 없이.
String suspendedText(AppLocalizations l10n, DateTime? until) => until == null
    ? l10n.accountSuspended
    : l10n.accountSuspendedUntil(_when(until));

/// "11월 30일 14:00까지 문의·리뷰를 쓸 수 없어요." — 기한을 모르면 기한 없이.
String restrictedText(AppLocalizations l10n, DateTime? until) => until == null
    ? l10n.accountRestricted
    : l10n.accountRestrictedUntil(_when(until));
