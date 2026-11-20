import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart';
import '../../address/domain/address.dart';
import '../../address/presentation/address_controller.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/device_consents_repository.dart';
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

final startStepProvider = Provider<StartStep>((ref) {
  if (!ref.watch(startGateEnabledProvider)) return StartStep.ready;
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
  final selected = await store.selected();
  final found = <Address>[];
  for (final id in await store.ids()) {
    try {
      final a = await repo.guest(id);
      // 상세 주소 없는 둘러보기 배송지(로그아웃 때 옮긴 것)는 회원 주소록으로 옮길 수 없다(회원은 상세 주소 필수) — 묻지 않는다.
      if (a.detailAddress.trim().isNotEmpty) found.add(a);
    } on ProblemFailure catch (f) {
      if (f.problem.code != ProblemCode.notFound) rethrow;
    }
  }
  // 비회원일 때 쓰던(고른) 주소를 맨 앞에.
  found.sort(
    (a, b) =>
        (b.addressId == selected ? 1 : 0) - (a.addressId == selected ? 1 : 0),
  );
  return found;
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
