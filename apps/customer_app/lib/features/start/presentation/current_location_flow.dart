import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers.dart';
import '../../address/data/current_location.dart';
import '../../address/presentation/map_pick_screen.dart'
    show geocodingRepositoryProvider;
import '../../address/presentation/postcode_screen.dart' show PostcodeResult;
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../profile/data/consents_repository.dart';
import '../../profile/presentation/consents_screens.dart'
    show consentsRepositoryProvider, sendConsentChanges;
import '../data/device_consents_repository.dart';
import 'start_controller.dart';
import '../../../shared/notice.dart';

final currentLocationSourceProvider = Provider<CurrentLocationSource>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockCurrentLocationSource(),
    PmartEnv.local => const DeviceCurrentLocationSource(),
  },
);

/// "현재 위치로 찾기"(레퍼런스 2-4·5-2). 순서: 위치기반서비스 약관 동의 확인(없으면 받는다 — BR-59 회신 ①, 서버 기록)
/// → OS 위치 권한 → 휴대폰 위치 한 번 → 서버 `/address-reverse-geocodes`(카카오 로컬)로 도로명주소.
/// 찾으면 주소 입력에 넘길 값, 못 찾거나 그만두면 null(안내는 여기서 한다). 좌표는 저장·로그하지 않는다.
Future<PostcodeResult?> findCurrentAddress(
  BuildContext context,
  WidgetRef ref,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) => messenger.notice(text);

  if (!await _ensureLocationConsent(context, ref, say) || !context.mounted) {
    return null;
  }
  final source = ref.read(currentLocationSourceProvider);
  final fix = await source.current();
  if (!context.mounted) return null;
  switch (fix) {
    case LocationServiceOff():
      if (await _askSettings(context)) {
        await source.openSettings(locationService: true);
      }
      return null;
    case LocationDenied():
      if (await _askSettings(context)) {
        await source.openSettings(locationService: false);
      }
      return null;
    case LocationUnavailable():
      say(l10n.locateUnavailable);
      return null;
    case LocationFound(:final lat, :final lng):
      try {
        final geocoding = ref.read(geocodingRepositoryProvider);
        final found = await geocoding.reverse(lat, lng);
        var road = found.where((c) => c.roadAddress != null).firstOrNull;
        // 휴대폰 위치가 도로·빈터에 찍히면 카카오가 지번만 준다(도로명 없음). 그 지번을 주소 검색에 넣어
        // 그 필지의 도로명을 찾는다(배송 가능 판정은 도로명으로 한다 — ADR-0023).
        final jibun = found
            .map((c) => c.jibunAddress)
            .whereType<String>()
            .firstOrNull;
        if (road == null && jibun != null) {
          road = (await geocoding.geocode(jibun))
              .where((c) => c.roadAddress != null)
              .firstOrNull;
        }
        if (road == null) {
          say(
            jibun == null
                ? l10n.locateNoAddress
                : l10n.locateNoRoadAddress(jibun),
          );
          return null;
        }
        return PostcodeResult(
          roadAddress: road.roadAddress!,
          zoneNo: road.zoneNo,
          buildingName: road.buildingName,
        );
      } on PmartFailure {
        say(l10n.locateLookupFailed);
        return null;
      }
  }
}

/// 위치기반서비스 약관에 지금 버전으로 동의했는지 서버에서 확인하고, 아니면 묻고 서버에 남긴다.
/// 회원은 `/me/consents`, 비회원은 기기 동의(`/device-consents`). 조회·저장 실패면 진행하지 않는다.
Future<bool> _ensureLocationConsent(
  BuildContext context,
  WidgetRef ref,
  void Function(String) say,
) async {
  final l10n = AppLocalizations.of(context);
  final device = ref.read(deviceConsentsRepositoryProvider);
  final member = ref.read(sessionProvider) is MemberSession;
  try {
    final term = (await device.terms()).of(ConsentWire.location);
    if (term == null) {
      // 서버 약관 목록에 위치 약관이 없다 — 동의를 남길 수 없으니 위치를 쓰지 않는다.
      say(l10n.locateConsentFailed);
      return false;
    }
    final bool agreed;
    if (member) {
      final mine = await ref.read(consentsRepositoryProvider).list();
      agreed =
          mine.items
              .where((c) => c.type == ConsentWire.location)
              .firstOrNull
              ?.current ??
          false;
    } else {
      final c = (await device.list()).of(ConsentWire.location);
      agreed = c != null && c.agreed && c.version == term.latestVersion;
    }
    if (agreed) return true;
    if (!context.mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => LocationConsentDialog(term: term),
    );
    if (ok != true) return false;
    final change = ConsentChange(term.type, term.latestVersion, agreed: true);
    if (member) {
      final status = await sendConsentChanges(
        ref.read(consentsRepositoryProvider),
        [change],
      );
      if (status != CommandStatus.applied) {
        say(l10n.consentUnknown);
        return false;
      }
      return true;
    }
    final key = IdempotencyKey.generate();
    DeviceConsents result;
    try {
      result = await device.change([change], key: key);
    } on UnknownResultFailure {
      result = await device.change([change], key: key);
    }
    return result.of(ConsentWire.location)?.agreed ?? false;
  } on PmartFailure {
    say(l10n.locateConsentFailed);
    return false;
  }
}

Future<bool> _askSettings(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  return await showDialog<bool>(
        context: context,
        builder: (_) => StartChoiceDialog(
          key: const ValueKey('locate-settings'),
          message: l10n.locatePermissionBody,
          cancel: l10n.locateClose,
          confirm: l10n.locateSettings,
        ),
      ) ??
      false;
}

/// 위치기반서비스 이용약관 동의 창. `>` 로 본문을 연다(서버 본문).
class LocationConsentDialog extends StatelessWidget {
  const LocationConsentDialog({super.key, required this.term});

  final ConsentTerm term;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return StartChoiceDialog(
      key: const ValueKey('locate-consent'),
      title: l10n.locateConsentTitle,
      message: l10n.locateConsentBody,
      extra: term.hasDocument
          ? TextButton(
              key: const ValueKey('locate-consent-terms'),
              onPressed: () => context.push(
                StartRoutes.terms(term.type, term.latestVersion),
              ),
              child: Text(
                l10n.locateConsentTerms,
                style: theme.textTheme.bodyMedium?.copyWith(
                  decoration: TextDecoration.underline,
                ),
              ),
            )
          : null,
      cancel: l10n.locateClose,
      confirm: l10n.locateConsentAgree,
    );
  }
}

/// 레퍼런스 5-2 모양의 두 버튼 안내 창(가운데 문구, 아래 [닫기 | 확인]). 확인이면 true.
class StartChoiceDialog extends StatelessWidget {
  const StartChoiceDialog({
    super.key,
    required this.message,
    required this.cancel,
    required this.confirm,
    this.title,
    this.extra,
  });

  final String? title;
  final String message;
  final Widget? extra;
  final String cancel;
  final String confirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final divider = theme.colorScheme.outlineVariant;
    Widget button(String k, String text, bool value, FontWeight weight) =>
        Expanded(
          child: InkWell(
            key: ValueKey(k),
            onTap: () => Navigator.of(context).pop(value),
            child: SizedBox(
              height: 47,
              child: Center(
                child: Text(
                  text,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: weight,
                  ),
                ),
              ),
            ),
          ),
        );
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 39),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      backgroundColor: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            // 레퍼런스 2-5: 창 높이 약 141dp, 글자 14.5sp
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
            child: Column(
              children: [
                if (title case final t?) ...[
                  Text(
                    t,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontSize: 14.5,
                    height: 1.45,
                  ),
                ),
                ?extra,
              ],
            ),
          ),
          Divider(height: 1, color: divider),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                button('dialog-cancel', cancel, false, FontWeight.w400),
                VerticalDivider(width: 1, color: divider),
                button('dialog-confirm', confirm, true, FontWeight.w600),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
