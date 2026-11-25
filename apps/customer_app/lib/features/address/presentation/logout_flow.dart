import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/notice.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/address.dart';
import '../../start/presentation/start_controller.dart'
    show logoutKeepingAddressProvider;
import '../data/address_repository.dart' show AddressRepository;
import '../data/guest_address_store.dart' show GuestAddressStore;
import 'address_controller.dart';

/// 로그아웃(customer 0.14.0 — 백엔드 요청 2026-11-20 logout-keep-browsing-address).
///
/// 이 기기에 비회원 배송지가 없고 회원의 쇼핑 주소가 있으면 "지금 주소로 계속 둘러볼까요?"를 묻는다.
/// - [예]: 로그아웃한 뒤 그 주소의 **도로명·상세 주소·우편번호·좌표**를 비회원 배송지로 만든다(받는 분·연락처·출입 메모는
///   옮기지 않는다 — 공용 기기에 개인정보를 남기지 않기). 만든 배송지를 이 기기에 기억하고 고른다.
/// - [아니요]: 지금처럼 로그아웃만(다음 화면에서 주소를 고른다).
/// - 창을 닫으면 로그아웃하지 않는다.
/// 이미 비회원 배송지가 있으면 묻지 않고 로그아웃한다(그 주소를 그대로 쓴다).
Future<void> logoutKeepingAddress(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  // 로그아웃 뒤에는 이 화면이 사라질 수 있어 앱 전체 컨테이너로 이어 간다.
  final container = ProviderScope.containerOf(context, listen: false);
  final session = ref.read(sessionProvider.notifier);
  final store = ref.read(guestAddressStoreProvider);
  final repo = ref.read(addressRepositoryProvider);
  final shopping = ref.read(addressBookProvider).value?.shoppingAddress;

  if (shopping == null || (await store.ids()).isNotEmpty) {
    await session.signOut();
    return;
  }
  if (!context.mounted) return;
  final keep = await showPmartConfirm(
    context,
    title: l10n.logoutKeepAddressTitle,
    body: l10n.logoutKeepAddressBody(shopping.roadAddress),
    confirmLabel: l10n.logoutKeepAddressYes,
    cancelLabel: l10n.logoutKeepAddressNo,
    confirmKey: const ValueKey('logout-keep-address-yes'),
    cancelKey: const ValueKey('logout-keep-address-no'),
  );
  if (keep == null) return; // 창을 닫음 — 로그아웃하지 않는다.

  // 좌표·우편번호는 회원 토큰이 있을 때 읽어 둔다(로그아웃 뒤에는 읽을 수 없다). 못 읽으면 도로명만으로.
  if (!keep) {
    await session.signOut();
    return;
  }
  AddressDraft? saved;
  try {
    saved = await repo.draft(shopping.addressId);
  } on PmartFailure {
    saved = null;
  }
  // 옮기기가 끝날 때까지 주소 입력 화면으로 보내지 않는다(로그아웃 직후 주소록이 잠깐 비어도).
  final hold = container.read(logoutKeepingAddressProvider.notifier)..set(true);
  try {
    await session.signOut();
    await _keepAsGuest(
      container,
      store,
      repo,
      shopping,
      saved,
      messenger,
      l10n,
    );
  } finally {
    hold.set(false);
  }
}

/// 탈퇴처럼 묻지 않고 비회원으로 돌아갈 때 — **회원 토큰이 있을 때** 미리 불러 주소(도로명·우편번호·좌표)를 읽어 두고,
/// 로그인 정보를 지운 뒤 돌려준 함수를 부르면 그 주소를 비회원 배송지로 만든다(로그아웃 [예] 와 같다 — 사용자 2026-11-25
/// "탈퇴하고 나서 주소 검색이 떠, 비회원으로 돌아갈 때 주소 기억하지 않아?"). 이미 비회원 배송지가 있거나 쇼핑 주소가
/// 없으면 null(할 일 없음).
Future<Future<void> Function()?> prepareKeepAddressAsGuest(
  BuildContext context,
  WidgetRef ref,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final store = ref.read(guestAddressStoreProvider);
  final repo = ref.read(addressRepositoryProvider);
  final shopping = ref.read(addressBookProvider).value?.shoppingAddress;
  if (shopping == null || (await store.ids()).isNotEmpty) return null;
  AddressDraft? saved;
  try {
    saved = await repo.draft(shopping.addressId);
  } on PmartFailure {
    saved = null;
  }
  return () =>
      _keepAsGuest(container, store, repo, shopping, saved, messenger, l10n);
}

Future<void> _keepAsGuest(
  ProviderContainer container,
  GuestAddressStore store,
  AddressRepository repo,
  Address shopping,
  AddressDraft? saved,
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
) async {
  final draft = AddressDraft(
    roadAddress: shopping.roadAddress,
    // 상세 주소도 옮긴다 — 다시 로그인·가입할 때 그대로 회원 주소로 옮겨 상세를 다시 묻지 않게(사용자 2026-11-25).
    // 받는 분·연락처·출입 메모는 옮기지 않는다(공용 기기).
    detailAddress: shopping.detailAddress,
    postalCode: saved?.postalCode,
    geo: saved?.geo,
  );
  final key = IdempotencyKey.generate();
  try {
    Address guest;
    try {
      guest = await repo.addGuest(draft, key: key);
    } on UnknownResultFailure {
      guest = await repo.addGuest(draft, key: key);
    }
    await store.add(guest.addressId);
    await store.select(guest.addressId);
    container.invalidate(addressBookProvider);
    // 새 비회원 주소록을 받은 뒤에 막기를 푼다(빈 주소록으로 한 번 더 판단하지 않게). 못 읽어도 막기는 푼다.
    try {
      await container.read(addressBookProvider.future);
    } on Object {
      // 주소록 화면이 실패를 보인다.
    }
  } on PmartFailure {
    // 로그아웃은 끝났다 — 주소만 못 옮겼다. 다음 화면에서 주소를 고르게 된다.
    messenger.notice(l10n.logoutKeepAddressFailed);
  }
}

/// 로그인해 회원이 되면(가입 포함) 비회원 때 쓰던 주소를 묻지 않고 회원 주소록으로 옮기고 쇼핑 주소로 정한다 —
/// 비회원으로 주소를 넣고 주문하다 로그인했는데 주소를 다시 고르라던 것(사용자 2026-11-25 "장난하냐?").
/// - 회원 주소록이 비어 있고, 비회원 때 고른 주소에 상세 주소가 있으면(회원 주소는 상세 필수) 그 주소만 옮긴다.
/// - 비회원 때 쓰던 주소 하나는 이 기기에 남긴다(로그아웃·탈퇴하면 그 주소로 되돌아간다). 옛 비회원 주소만 지운다.
/// 옮기는 동안은 주소 입력 화면으로 보내지 않는다([logoutKeepingAddressProvider]).
Future<void> carryGuestAddressOnLogin(ProviderContainer container) async {
  final store = container.read(guestAddressStoreProvider);
  final ids = await store.ids();
  if (ids.isEmpty) return;
  final hold = container.read(logoutKeepingAddressProvider.notifier)..set(true);
  try {
    final repo = container.read(addressRepositoryProvider);
    final book = await container.read(addressBookProvider.future);
    if (book != null && book.addresses.isEmpty) {
      final selected = await store.selected();
      final id = (selected != null && ids.contains(selected))
          ? selected
          : ids.first;
      try {
        // 상세 주소가 없어도 그대로 옮긴다(customer 0.20.0 BR-106 — 상세는 주문할 때만 받는다). 서버가
        // 아직 막으면(배포 전) 옮기지 못하고 주소 화면이 그 주소로 상세만 받는다.
        final draft = await repo.guestDraft(id);
        await container.read(addressBookProvider.notifier).add(draft);
      } on PmartFailure {
        // 못 옮겼다 — 주소 화면에서 고르게 된다.
      }
    }
    // 비회원 때 쓰던(고른) 주소 하나는 이 기기에 남긴다 — 로그아웃·탈퇴하면 그 비회원 주소로 되돌아간다
    // (사용자 2026-11-25 "로그아웃이든 탈퇴든 비회원 주소를 원복"). 그 밖의 옛 비회원 주소만 지운다.
    final keep = await store.selected();
    await store.retain([?keep]);
  } on Object {
    // 주소록을 못 읽었다 — 다음 화면이 실패를 보인다.
  } finally {
    hold.set(false);
  }
}
