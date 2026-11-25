import 'dart:async';

import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart';
import '../../address/domain/address.dart';
import '../../address/presentation/address_controller.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../checkout/presentation/checkout_controller.dart'
    show clockProvider;
import '../../catalog/presentation/catalog_providers.dart' show homeProvider;
import '../data/device_consents_repository.dart';
import '../data/splash_promo.dart';
import '../data/start_store.dart';

/// 처음 실행 단계(환영·약관 → 로그인/둘러보기 → 주소)를 쓸지. 다른 화면 시험은 끈다.
final startGateEnabledProvider = Provider<bool>((_) => true);

final deviceConsentsRepositoryProvider = Provider<DeviceConsentsRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockDeviceConsentsRepository(),
    PmartEnv.local => ApiDeviceConsentsRepository(
      ref.watch(dioProvider),
      ref.watch(deviceIdProvider),
    ),
  },
);

/// 약관 항목·현행 버전(토큰 없음). 실패는 실패로 남는다 — 버전을 지어내지 않는다.
final consentTermsProvider = FutureProvider.autoDispose<ConsentTerms>(
  (ref) => ref.watch(deviceConsentsRepositoryProvider).terms(),
);

/// 약관 본문 (항목, 버전).
final consentTermDocumentProvider = FutureProvider.autoDispose
    .family<ConsentTermDocument, (String, String)>(
      (ref, k) =>
          ref.watch(deviceConsentsRepositoryProvider).document(k.$1, k.$2),
    );

final startStoreProvider = Provider<StartStore>(
  (ref) => StartStore(ref.watch(secureStoreProvider)),
);

/// 지금 시각(시험에서 바꿔 끼운다).
final startClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

final startFlagsProvider =
    AsyncNotifierProvider<StartFlagsController, StartFlags>(
      StartFlagsController.new,
    );

class StartFlagsController extends AsyncNotifier<StartFlags> {
  StartStore get _store => ref.read(startStoreProvider);

  @override
  Future<StartFlags> build() => ref.watch(startStoreProvider).read();

  Future<void> completeWelcome() async {
    await _store.completeWelcome(at: ref.read(startClockProvider)());
    if (ref.mounted) state = AsyncData(await _store.read());
  }

  Future<void> completeEntry() async {
    await _store.completeEntry();
    if (ref.mounted) state = AsyncData(await _store.read());
  }

  /// 주소 단계에서 뒤로(비회원) — 로그인/둘러보기 화면으로 돌아간다.
  Future<void> reopenEntry() async {
    await _store.reopenEntry();
    if (ref.mounted) state = AsyncData(await _store.read());
  }
}

enum StartStep {
  /// 아직 판단할 값이 없다(저장소·세션 확인·주소록을 읽는 중).
  loading,

  /// 환영·약관.
  welcome,

  /// 로그인 또는 둘러보기.
  entry,

  /// 배달 주소가 하나도 없다 — 주소부터 받는다(회원·비회원 모두).
  address,

  /// 홈으로.
  ready,
}

/// 처음 실행 단계에서 더 돌아갈 화면이 없을 때 뒤로 — 앱을 나간다(시험에서 바꿔 끼울 수 있게 변수로 둔다).
void Function() leaveApp = SystemNavigator.pop;

/// 지금 어느 처음 실행 단계인지. 주소록 조회 실패는 "주소 없음"이 아니다 — 막지 않고 홈이 오류를 보인다.
/// 로그아웃하면서 지금 주소를 비회원 배송지로 옮기는 중("지금 주소로 계속 둘러볼까요?" [예]). 그동안은 주소록이 잠깐 비어도
/// 주소 입력 화면으로 보내지 않는다 — 전에는 로그아웃 직후 빈 주소록을 보고 주소 입력창이 먼저 떴다(사용자 2026-11-21).
final logoutKeepingAddressProvider =
    NotifierProvider<LogoutKeepingAddress, bool>(LogoutKeepingAddress.new);

class LogoutKeepingAddress extends Notifier<bool> {
  @override
  bool build() => false;

  // ignore: use_setters_to_change_properties
  void set(bool value) => state = value;
}

/// 처음 로딩 화면 프로모션(storefront 0.9.0 SPLASH, 백엔드 요청서 2026-11-21 ①).
final splashBannerSourceProvider = Provider<SplashBannerSource>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockSplashBannerSource(),
    PmartEnv.local => ApiSplashBannerSource(
      ref.watch(dioProvider),
      resolveUrl: (u) => resolveImageUrl(u, ref.read(imageOriginProvider)),
    ),
  },
);

final splashPromoStoreProvider = Provider<SplashPromoStore>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MemorySplashPromoStore(),
    PmartEnv.local => FileSplashPromoStore(),
  },
);

/// 프로모션 이미지가 있으면 적어도 이만큼 보인다(사용자 결정 2026-11-21 "최소 1.5초", 누르면 바로 넘어간다).
const splashPromoMinDuration = Duration(milliseconds: 1500);

/// 이번 실행의 로딩 화면 이미지 — 지난 실행에 받아 둔 것(사용자 결정 2026-11-21 "다음 실행부터").
/// 읽고 나면 뒤에서 서버의 지금 SPLASH 배너에 맞춰 둔다(다음 실행에 보인다). 못 읽으면 지금 로딩 화면.
final splashPromoProvider = FutureProvider<SplashPromo?>((ref) async {
  final store = ref.watch(splashPromoStoreProvider);
  final source = ref.watch(splashBannerSourceProvider);
  SplashPromo? kept;
  try {
    kept = await store.read().timeout(const Duration(milliseconds: 500));
  } on Object {
    kept = null;
  }
  unawaited(Future.microtask(() => refreshSplashPromo(source, store)));
  // 받아 둔 배너의 편성 기간이 끝났으면 그리지 않는다(storefront 0.13.0 endsAt).
  if (kept != null && !kept.liveAt(ref.read(clockProvider)().toUtc())) {
    return null;
  }
  return kept;
});

/// 프로모션 로딩 화면을 붙잡아 두는 중인지(true 면 처음 실행 단계는 아직 loading).
final splashHoldProvider = NotifierProvider<SplashHold, bool>(SplashHold.new);

class SplashHold extends Notifier<bool> {
  bool _released = false;

  @override
  bool build() {
    final promo = ref.watch(splashPromoProvider).value;
    if (promo == null || _released) return false;
    final timer = Timer(splashPromoMinDuration, release);
    ref.onDispose(timer.cancel);
    return true;
  }

  /// 시간이 다 됐거나 화면을 눌렀다 — 다음 화면으로.
  void release() {
    _released = true;
    state = false;
  }
}

/// 로딩 화면(프로모션 최소 1.5초)이 떠 있는 동안 홈에 필요한 것을 미리 읽는다 — 예전에는 차례로 기다렸다:
/// 프로모션 → 세션 확인 → 주소록 → 홈 조회(로딩 구조 S4, 사용자 2026-11-25 "응").
/// 세션 확인이 끝난 뒤 주소록을(회원·비회원 주소록이 달라 먼저 읽으면 두 번 읽는다), 주소록이 온 뒤 홈을
/// 읽는다(쇼핑 센터가 정해져야 홈이 한 번에 맞다). 앱(`app.dart`)이 listen 한다 — 결과로 화면을 바꾸지 않는다.
final startPrefetchProvider = Provider<void>((ref) {
  if (ref.watch(sessionRestoreProvider).isLoading) return;
  final book = ref.watch(addressBookProvider);
  if (!book.hasValue) return;
  ref.listen(homeProvider, (_, _) {});
});

final startStepProvider = Provider<StartStep>((ref) {
  if (!ref.watch(startGateEnabledProvider)) return StartStep.ready;
  // 로딩 화면 이미지를 읽는 동안·프로모션을 보이는 동안(최소 1.5초)은 로딩 화면에 둔다.
  if (ref.watch(splashPromoProvider).isLoading) return StartStep.loading;
  if (ref.watch(splashHoldProvider)) return StartStep.loading;
  final flags = ref.watch(startFlagsProvider);
  final f = flags.value;
  if (f == null) return flags.hasError ? StartStep.ready : StartStep.loading;
  if (!f.welcomeDone) return StartStep.welcome;
  if (ref.watch(sessionRestoreProvider).isLoading) return StartStep.loading;
  // 저장된 세션을 서버에 확인하지 못했다 — 회원인지 모르니 묻지도 막지도 않는다.
  if (ref.watch(sessionUnverifiedProvider)) return StartStep.ready;
  final member = ref.watch(sessionProvider) is MemberSession;
  if (!member && !f.entryDone) return StartStep.entry;
  // 로그아웃 중 주소 옮기기가 끝날 때까지는 지금 화면에 둔다.
  if (ref.watch(logoutKeepingAddressProvider)) return StartStep.ready;
  final book = ref.watch(addressBookProvider);
  if (book.isLoading) return StartStep.loading;
  final b = book.value;
  if (b == null) return StartStep.ready;
  return b.addresses.isEmpty ? StartStep.address : StartStep.ready;
});

/// 로그인한 회원의 주소록이 비었을 때, 이 기기에 남은 비회원 배송지(로그인 전에 입력한 주소). 주소 화면이
/// "이 주소 저장하고 시작하기"로 묻는다(사용자 결정 2026-11-19 "물어보고 옮기기" — 서버에 옮기는 경로가 없다).
/// 비회원이면 빈 목록. 서버에 없는(404) 것은 뺀다. 그 밖의 조회 실패는 실패로 남는다(화면은 묻지 않고 검색만 보인다).
final loginGuestAddressesProvider = FutureProvider.autoDispose<List<Address>>((
  ref,
) async {
  if (ref.watch(sessionProvider) is! MemberSession) return const [];
  final store = ref.watch(guestAddressStoreProvider);
  final repo = ref.watch(addressRepositoryProvider);
  // 비회원일 때 쓰던(고른) 주소 하나만 — 옛 비회원 주소들을 늘어놓지 않는다(사용자 2026-11-25).
  final ids = await store.ids();
  final selected = await store.selected();
  final id = (selected != null && ids.contains(selected))
      ? selected
      : ids.firstOrNull;
  if (id == null) return const [];
  try {
    return [await repo.guest(id)];
  } on ProblemFailure catch (f) {
    if (f.problem.code != ProblemCode.notFound) rethrow;
    return const [];
  }
});

/// 처음 실행 단계 화면 경로.
abstract final class StartRoutes {
  static const splash = '/start';
  static const welcome = '/start/welcome';
  static const entry = '/start/entry';
  static const address = '/start/address';

  /// 단계 중에도 열 수 있는 화면(가입 뒤 내 정보, 주소 입력, 재동의).
  static const side = {'/me/info', '/addresses/new', '/me/consents/reconsent'};

  /// 약관 본문 `/terms/{항목}/{버전}` — 환영 화면의 `>` 에서 연다.
  static const termsPrefix = '/terms/';

  static String terms(String type, String version) =>
      '$termsPrefix$type/${Uri.encodeComponent(version)}';
}

/// 라우터 redirect. [resolved] 는 한 번이라도 홈 단계에 닿았는지 — 그 뒤의 다시 읽기(로그인 직후 주소록 등)는
/// 대기 화면으로 보내지 않는다.
String? startRedirect(
  StartStep step,
  String location, {
  required bool resolved,
}) {
  final inStart =
      location == StartRoutes.splash ||
      location.startsWith('${StartRoutes.splash}/');
  switch (step) {
    case StartStep.ready:
      return inStart ? '/' : null;
    case StartStep.loading:
      return (!resolved && location == '/') ? StartRoutes.splash : null;
    case StartStep.welcome || StartStep.entry || StartStep.address:
      if (StartRoutes.side.contains(location) ||
          location.startsWith(StartRoutes.termsPrefix)) {
        return null;
      }
      final target = switch (step) {
        StartStep.welcome => StartRoutes.welcome,
        StartStep.entry => StartRoutes.entry,
        _ => StartRoutes.address,
      };
      return location == target ? null : target;
  }
}
