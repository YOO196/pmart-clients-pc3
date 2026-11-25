import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ui_state_of.dart';
import '../../address/domain/address.dart';
import '../../auth/domain/auth.dart' show MemberSession;
import '../../auth/presentation/auth_controller.dart' show sessionProvider;
import '../../address/presentation/address_controller.dart';
import '../../address/presentation/address_screens.dart'
    show addressOutcomeText, addressSearchProvider;
import '../../address/presentation/postcode_screen.dart' show PostcodeResult;
import '../../profile/data/consents_repository.dart';
import '../../push/presentation/push_controller.dart' show pushSourceProvider;
import '../data/device_consents_repository.dart';
import 'current_location_flow.dart';
import 'start_controller.dart';
import '../../../shared/notice.dart';

/// 처음 실행 단계를 판단하는 동안(저장소·세션·주소록 읽기) — 바로픽 시작 그림(사용자 지시 2026-11-19).
/// 배경색은 Android 시작 화면(`splash_background`)과 같아 그림이 뜨기 전에도 이어 보인다.
class StartSplashScreen extends ConsumerWidget {
  const StartSplashScreen({super.key});

  static const background = Color(0xFF7E24E6);
  static const image = 'assets/images/splash.jpg';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 판단이 끝났는데 이 그림이 보이면(뒤로 가기로 아래 단계가 빠진 경우 등 — 라우터의 redirect 는 뒤로 가기에서
    // 다시 돌지 않는다) 지금 단계의 화면으로 보낸다. 판단 중(loading)이면 그대로 기다린다.
    final step = ref.watch(startStepProvider);
    final target = startRedirect(step, StartRoutes.splash, resolved: true);
    if (target != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final router = GoRouter.of(context);
        if (router.routerDelegate.currentConfiguration.uri.path ==
            StartRoutes.splash) {
          router.go(target);
        }
      });
    }
    // 지난 실행에 받아 둔 프로모션 이미지(storefront SPLASH)가 있으면 그것을 화면 가득(레퍼런스 "로딩 화면 (프로모션)").
    // 누르면 최소 시간(1.5초)을 기다리지 않고 넘어간다. 이미지를 그리지 못하면 지금 그림.
    final promo = ref.watch(splashPromoProvider).value;
    if (promo == null) return _splash;
    return AnnotatedRegion(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        key: const ValueKey('start-splash-promo'),
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref.read(splashHoldProvider.notifier).release(),
          child: DecoratedBox(
            // 그림을 다 보이고(contain) 남는 위·아래는 그림 가장자리 색(백엔드 요청 2026-11-21 R1 — 세로 9:16 그림의 글자가 잘리지 않게).
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.5, 0.5],
                colors: [
                  promo.top ?? Colors.black,
                  promo.bottom ?? promo.top ?? Colors.black,
                ],
              ),
            ),
            child: SizedBox.expand(
              child: Image.memory(
                promo.bytes,
                key: ValueKey('start-splash-promo-${promo.bannerId}'),
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => ref.read(splashHoldProvider.notifier).release(),
                  );
                  return _splash;
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const Widget _splash = AnnotatedRegion(
    value: SystemUiOverlayStyle.light,
    child: Scaffold(
      key: ValueKey('start-splash'),
      backgroundColor: background,
      body: SizedBox.expand(
        child: Image(
          image: AssetImage(image),
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      ),
    ),
  );
}

/// 레퍼런스 2-1·2-2 "처음 다운로드 후 화면" — 환영 문구, 전체동의·위치기반서비스 약관·마케팅 앱 푸시,
/// 알림 권한 묻기, 아래 "시작하기". BR-59 회신(customer 0.6.0): 위치 약관은 현재 위치 기능을 쓸 때만 필수라
/// 여기서는 고르지 않아도 시작할 수 있다. 고른 값은 기기 동의(`POST /device-consent-changes`)로 보내고,
/// 서버가 반영한 값(전송자·처리 일시)으로만 "수신동의 처리완료" 안내 창을 띄운다.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _location = false;
  bool _marketing = false;
  bool _busy = false;
  String? _error;

  /// 이 선택으로 보낼 키. 결과를 모르면 같은 키로 다시 보내고, 고른 값이 바뀌면 새 키.
  IdempotencyKey? _key;

  void _choose(VoidCallback change) => setState(() {
    change();
    _key = null;
    _error = null;
  });

  @override
  void initState() {
    super.initState();
    // 레퍼런스처럼 첫 화면에서 알림 권한을 묻는다(거절해도 진행). 토큰 등록은 회원이 된 뒤에만 한다.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final source = ref.read(pushSourceProvider);
      try {
        if (await source.ready()) await source.requestPermission();
      } on Object {
        // 단말 쪽 오류는 첫 화면을 막지 않는다.
      }
    });
  }

  Future<void> _start(ConsentTerms terms) async {
    final l10n = AppLocalizations.of(context);
    final changes = [
      if (terms.of(ConsentWire.marketing) case final t?)
        ConsentChange(t.type, t.latestVersion, agreed: _marketing),
      if (terms.of(ConsentWire.location) case final t?)
        ConsentChange(t.type, t.latestVersion, agreed: _location),
    ];
    setState(() {
      _busy = true;
      _error = null;
    });
    final key = _key ??= IdempotencyKey.generate();
    final repo = ref.read(deviceConsentsRepositoryProvider);
    // 예상하지 못한 오류(기기 저장소 등)에도 단추가 잠긴 채 남지 않게 한다 — 실패로 알리고 다시 누를 수 있다.
    try {
      await _send(terms, changes, key, repo, l10n);
    } on Object {
      if (mounted) setState(() => _error = l10n.startConsentFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send(
    ConsentTerms terms,
    List<ConsentChange> changes,
    IdempotencyKey key,
    DeviceConsentsRepository repo,
    AppLocalizations l10n,
  ) async {
    DeviceConsents? result;
    String? error;
    if (changes.isEmpty) {
      // 서버 약관 목록에 두 항목이 없다 — 보낼 것이 없다(지어내지 않는다).
      result = const DeviceConsents(items: []);
    } else {
      try {
        try {
          result = await repo.change(changes, key: key);
        } on UnknownResultFailure {
          result = await repo.change(changes, key: key);
        }
      } on ProblemFailure catch (f) {
        if (f.problem.code == ConsentProblemCode.versionOutdated) {
          ref.invalidate(consentTermsProvider);
          _key = null;
          error = l10n.consentVersionChanged;
        } else {
          error = l10n.startConsentFailed;
        }
      } on PmartFailure {
        error = l10n.startConsentFailed;
      }
    }
    if (!mounted) return;
    if (result == null) {
      setState(() => _error = error);
      return;
    }
    final marketing = result.of(ConsentWire.marketing);
    if (marketing case DeviceConsent(lastChangedAt: final at?)) {
      final sender = result.senderName;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => MarketingConsentResultDialog(
          agreed: marketing.agreed,
          senderName: sender,
          at: at,
        ),
      );
      if (!mounted) return;
    }
    await ref.read(startFlagsProvider.notifier).completeWelcome();
  }

  Widget _check({
    required String key,
    required bool value,
    required ValueChanged<bool> onChanged,
    required String label,
    String? hint,
    VoidCallback? onOpen,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // 사용자 폰 캡처(2026-11-25, 1080px = 411dp): 체크 22dp(테두리 1.9·모서리 5), 글자 14 중간 굵기,
    // 체크와 글자 사이 5, 오른쪽 > 는 끝에서 7. 설명은 글자 아래 12 회색.
    return InkWell(
      key: ValueKey(key),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(1, 10.5, 0, 10.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox.square(
                  dimension: 22,
                  child: Checkbox(
                    value: value,
                    onChanged: (v) => onChanged(v ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                    side: const BorderSide(
                      color: Color(0xFFD5D6DA),
                      width: 1.9,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF161A1B),
                    ),
                  ),
                ),
                if (onOpen != null)
                  InkResponse(
                    key: ValueKey('$key-open'),
                    onTap: onOpen,
                    radius: 20,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: PmartLineIcon(
                        PmartLineIcons.chevronRight,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(left: 27, top: 2),
                child: Text(
                  hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: const Color(0xFF7E807F),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  VoidCallback? _opener(ConsentTerms? terms, String type) {
    final t = terms?.of(type);
    if (t == null || !t.hasDocument) return null;
    return () => context.push(StartRoutes.terms(t.type, t.latestVersion));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final all = _location && _marketing;
    final termsValue = ref.watch(consentTermsProvider);
    final terms = termsValue.value;
    return PopScope(
      canPop: false,
      // 첫 화면이라 돌아갈 곳이 없다 — 뒤로는 앱을 나간다(전에는 아무 일도 없었다).
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) leaveApp();
      },
      child: Scaffold(
        key: const ValueKey('start-welcome'),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  // 사용자 폰 캡처(2026-11-25): 제목 21 굵게·줄 간격 28, 좌우 15.
                  padding: const EdgeInsets.fromLTRB(15, 73, 15, 16),
                  children: [
                    Text(
                      l10n.startWelcomeTitle,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontSize: 21.4,
                        height: 1.32,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF161A1B),
                      ),
                    ),
                    const SizedBox(height: 30.7),
                    _check(
                      key: 'start-agree-all',
                      value: all,
                      onChanged: (v) => _choose(() {
                        _location = v;
                        _marketing = v;
                      }),
                      label: l10n.startAgreeAll,
                    ),
                    // 전체동의 줄 오른쪽, 구분선 위에 선 그림(사용자 레퍼런스 2026-11-25): 100×80dp, 오른쪽에서 7.
                    SizedBox(
                      height: 21,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Positioned.fill(
                            child: Divider(
                              height: 21,
                              thickness: 1,
                              color: Color(0xFFE5E6E8),
                            ),
                          ),
                          Positioned(
                            right: 6.8,
                            bottom: 10,
                            child: Image.asset(
                              'assets/images/start_unicorn.png',
                              key: const ValueKey('start-welcome-art'),
                              width: 99.7,
                              height: 79.9,
                              color: const Color(0xFF161A1B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _check(
                      key: 'start-agree-location',
                      value: _location,
                      onChanged: (v) => _choose(() => _location = v),
                      label: l10n.startLocationTerms,
                      onOpen: _opener(terms, ConsentWire.location),
                    ),
                    const SizedBox(height: 1.4),
                    _check(
                      key: 'start-agree-marketing',
                      value: _marketing,
                      onChanged: (v) => _choose(() => _marketing = v),
                      label: l10n.startMarketingPush,
                      // 사용자 폰 캡처: 마케팅 줄은 > 없이 아래 설명 한 줄.
                      hint: l10n.startMarketingHint,
                    ),
                    if (termsValue.hasError && !termsValue.isLoading) ...[
                      const SizedBox(height: 16),
                      Text(
                        l10n.startTermsLoadFailed,
                        key: const ValueKey('start-terms-error'),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const ValueKey('start-terms-retry'),
                          onPressed: () => ref.invalidate(consentTermsProvider),
                          child: Text(l10n.startRetry),
                        ),
                      ),
                    ],
                    if (_error case final e?) ...[
                      const SizedBox(height: 16),
                      Text(
                        e,
                        key: const ValueKey('start-consent-error'),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                // 사용자 폰 캡처: 좌우 10, 아래 7, 높이 50, 모서리 4, 글자 18 굵게. 못 누르면 회색 바탕 흰 글자.
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 7),
                child: FilledButton(
                  key: const ValueKey('start-begin'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    disabledBackgroundColor: const Color(0xFFD6D7D9),
                    disabledForegroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    textStyle: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  // 약관 버전을 읽어야 보낼 수 있다. 위치 약관은 고르지 않아도 된다(현재 위치 기능에서만 필수).
                  onPressed: (terms != null && !_busy)
                      ? () => _start(terms)
                      : null,
                  child: Text(l10n.startBegin),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 레퍼런스 2-4 "둘러보기 선택 후 주소 검색 화면". 뒤로 갈 수 없다 — 배달 주소를 정해야 홈으로 간다.
/// 검색칸을 누르면 주소 검색 → 주소 입력(상세 주소 필수, 지도 핀) → 저장하면 홈.
/// "현재 위치로 찾기"(geolocator, 사용자 승인 2026-11-19)는 위치기반서비스 약관 동의 뒤 휴대폰 위치로 도로명주소를 찾는다.
class StartAddressScreen extends ConsumerStatefulWidget {
  const StartAddressScreen({super.key});

  @override
  ConsumerState<StartAddressScreen> createState() => _StartAddressScreenState();
}

class _StartAddressScreenState extends ConsumerState<StartAddressScreen> {
  bool _locating = false;
  String? _saving;

  /// 로그인 전에 쓰던 비회원 배송지를 회원 주소록에 그대로 저장한다(고객이 누른 뒤에만). 저장되면 단계가 홈으로 바뀐다.
  Future<void> _saveGuest(Address a) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = a.addressId);
    AddressCommandOutcome outcome;
    try {
      final draft = await ref
          .read(addressRepositoryProvider)
          .guestDraft(a.addressId);
      outcome = await ref.read(addressBookProvider.notifier).add(draft);
    } on PmartFailure catch (f) {
      outcome = AddressCommandFailed(f);
    }
    if (!mounted) return;
    setState(() => _saving = null);
    messenger.notice(addressOutcomeText(l10n, outcome));
    if (outcome is AddressSaved || outcome is AddressCommandUnknown) {
      context.go('/');
    }
  }

  Widget _guestCard(
    AppLocalizations l10n,
    ThemeData theme,
    Address a,
  ) => Container(
    key: ValueKey('start-guest-address-${a.addressId}'),
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    decoration: BoxDecoration(
      border: Border.all(color: theme.colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          a.roadAddress,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontSize: 15.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (a.detailAddress.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              a.detailAddress,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton(
          key: ValueKey('start-guest-address-save-${a.addressId}'),
          // 상세 주소가 없으면(회원 주소는 상세 필수) 이 주소로 입력 화면을 열어 상세만 받는다 — 검색부터 다시 하지 않게.
          onPressed: _saving != null
              ? null
              : a.detailAddress.trim().isEmpty
              ? () => _open(PostcodeResult(roadAddress: a.roadAddress))
              : () => _saveGuest(a),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(42),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            a.detailAddress.trim().isEmpty
                ? l10n.startGuestAddressDetail
                : l10n.startGuestAddressSave,
          ),
        ),
      ],
    ),
  );

  Future<void> _open(PostcodeResult? picked) async {
    if (picked == null || !mounted) return;
    await context.push('/addresses/new', extra: picked);
    // 저장했으면 단계가 홈으로 바뀌어 있다. 다시 판단하게 한다(아니면 이 화면으로 돌아온다).
    if (mounted) context.go('/');
  }

  Future<void> _search() async =>
      _open(await ref.read(addressSearchProvider)(context));

  Future<void> _locate() async {
    setState(() => _locating = true);
    final picked = await findCurrentAddress(context, ref);
    if (!mounted) return;
    setState(() => _locating = false);
    await _open(picked);
  }

  @override
  Widget build(BuildContext context) {
    final guestAddresses =
        ref.watch(loginGuestAddressesProvider).value ?? const <Address>[];
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return PopScope(
      canPop: false,
      // 주소 없이 홈으로는 못 간다. 비회원은 로그인/둘러보기 화면으로 돌아가고, 회원은 앱을 나간다.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (ref.read(sessionProvider) is MemberSession) {
          leaveApp();
        } else {
          ref.read(startFlagsProvider.notifier).reopenEntry();
        }
      },
      child: Scaffold(
        key: const ValueKey('start-address'),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          centerTitle: false,
          title: Text(l10n.addressSearchTitle),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(15, 32, 15, 24),
          children: [
            Text(
              l10n.startAddressTitle,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontSize: 19.5,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 22),
            // 로그인 전에 입력한 주소가 있으면 먼저 묻는다(그대로 저장하거나, 아래에서 다른 주소를 찾는다).
            if (guestAddresses.isNotEmpty) ...[
              Text(
                l10n.startGuestAddressTitle,
                key: const ValueKey('start-guest-address'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.startGuestAddressBody,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              for (final a in guestAddresses) _guestCard(l10n, theme, a),
              const SizedBox(height: 10),
            ],
            Material(
              color: theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                key: const ValueKey('start-address-search'),
                borderRadius: BorderRadius.circular(14),
                onTap: _search,
                child: SizedBox(
                  height: 46,
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      PmartLineIcon(
                        PmartLineIcons.search,
                        size: 20,
                        color: muted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.startAddressSearchHint,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontSize: 14,
                            color: muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 레퍼런스 2-4: 예시 묶음은 검색칸 바로 아래(약 12dp), 제목 13sp 진한 보통 굵기, 예시 12sp
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.startAddressExamplesTitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w400,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final e in [
                    l10n.startAddressExample1,
                    l10n.startAddressExample2,
                    l10n.startAddressExample3,
                  ])
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '• $e',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          color: muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 27),
            OutlinedButton(
              key: const ValueKey('start-address-locate'),
              onPressed: _locating ? null : _locate,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                foregroundColor: theme.colorScheme.onSurface,
                side: BorderSide(color: theme.colorScheme.onSurface),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 찾는 동안은 버튼만 잠근다(약관·권한 창이 떠 있을 수 있어 돌아가는 표시는 두지 않는다).
                  PmartLineIcon(
                    PmartLineIcons.locate,
                    size: 18,
                    color: _locating
                        ? theme.disabledColor
                        : theme.colorScheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Text(l10n.startAddressLocate),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 레퍼런스 2-1·2-2 "마케팅정보 앱 푸시 알림 동의/거부 안내". 서버가 반영해 돌려준 값(동의 여부·전송자·처리 일시)만 쓴다.
class MarketingConsentResultDialog extends StatelessWidget {
  const MarketingConsentResultDialog({
    super.key,
    required this.agreed,
    required this.at,
    this.senderName,
  });

  final bool agreed;
  final DateTime at;
  final String? senderName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final when = DateFormat('y년 M월 d일 H시', 'ko').format(toSeoulWallClock(at));
    // 사용자 폰 캡처(2026-11-25, 1080px = 411dp): 창 폭 299.5(좌우 56), 안쪽 21, 제목 16.5 굵게,
    // 본문 15.5 줄 간격 22.3, 안내 13.5 회색 줄 간격 21.3, "확인" 16 굵게·칸 높이 48.7.
    final line = theme.textTheme.bodyLarge?.copyWith(
      fontSize: 15.5,
      height: 1.43,
      color: const Color(0xFF181A19),
    );
    return Dialog(
      key: const ValueKey('start-marketing-result'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 55.7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      backgroundColor: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(21, 30, 21, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agreed
                      ? l10n.startMarketingResultTitleAgreed
                      : l10n.startMarketingResultTitleRefused,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF181A19),
                  ),
                ),
                const SizedBox(height: 15.3),
                if (senderName case final s?)
                  Text(l10n.startMarketingResultSender(s), style: line),
                Text(
                  agreed
                      ? l10n.startMarketingResultAtAgreed(when)
                      : l10n.startMarketingResultAtRefused(when),
                  key: const ValueKey('start-marketing-result-at'),
                  style: line,
                ),
                Text(
                  agreed
                      ? l10n.startMarketingResultDoneAgreed
                      : l10n.startMarketingResultDoneRefused,
                  style: line,
                ),
                const SizedBox(height: 15.3),
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
                const SizedBox(height: 15.3),
                Text(
                  l10n.startMarketingResultNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 13.5,
                    height: 1.58,
                    color: const Color(0xFF7E807F),
                  ),
                ),
                const SizedBox(height: 25.1),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          InkWell(
            key: const ValueKey('start-marketing-result-ok'),
            onTap: () => Navigator.of(context).pop(),
            child: SizedBox(
              height: 48.7,
              child: Center(
                child: Text(
                  l10n.startConfirm,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF181A19),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 약관 본문(customer 0.6.1 `GET /consent-terms/{항목}/{버전}`, Markdown). 서버 본문만 보인다 — 지어내지 않는다.
class ConsentTermScreen extends ConsumerWidget {
  const ConsentTermScreen({
    super.key,
    required this.type,
    required this.version,
  });

  final String type;
  final String version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final provider = consentTermDocumentProvider((type, version));
    final value = ref.watch(provider);
    return Scaffold(
      key: const ValueKey('consent-term'),
      appBar: AppBar(title: Text(value.value?.title ?? '')),
      body: UiStateView<ConsentTermDocument>(
        state: uiStateOf(value),
        onRetry: () => ref.invalidate(provider),
        ready: (context, d) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            MarkdownBody(
              key: const ValueKey('consent-term-body'),
              data: d.body,
              // 링크는 열지 않는다(앱 밖으로 나가지 않게).
              styleSheet: MarkdownStyleSheet.fromTheme(theme),
            ),
          ],
        ),
      ),
    );
  }
}
