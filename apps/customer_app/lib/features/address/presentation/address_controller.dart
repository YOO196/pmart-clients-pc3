import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pmart_core/pmart_core.dart';

import '../../../shared/providers.dart';
import '../../auth/domain/auth.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/address_repository.dart';
import '../data/mock_address_repository.dart';
import '../domain/address.dart';

final addressRepositoryProvider = Provider<AddressRepository>(
  (ref) => switch (ref.watch(envProvider)) {
    PmartEnv.mock => MockAddressRepository(),
    PmartEnv.local => ApiAddressRepository(ref.watch(dioProvider)),
  },
);

/// 결과 불명 주소 저장의 같은 키 재전송 횟수.
final addressResendAttemptsProvider = Provider<int>((_) => 2);

@immutable
sealed class AddressCommandOutcome {
  const AddressCommandOutcome();
}

final class AddressSaved extends AddressCommandOutcome {
  const AddressSaved(this.address);

  final Address address;
}

final class ShoppingAddressChanged extends AddressCommandOutcome {
  const ShoppingAddressChanged();
}

/// 반영 여부를 아직 모른다. 주소록을 다시 불러와 확인하게 한다(같은 행위를 새로 하지 않게).
final class AddressCommandUnknown extends AddressCommandOutcome {
  const AddressCommandUnknown();
}

/// 다른 곳에서 쇼핑 주소가 바뀌었다. 최신 주소록을 다시 받았다.
final class AddressConflict extends AddressCommandOutcome {
  const AddressConflict();
}

final class AddressCommandFailed extends AddressCommandOutcome {
  const AddressCommandFailed(this.failure);

  final PmartFailure failure;
}

/// 회원 주소록. 비회원이면 null.
final addressBookProvider =
    AsyncNotifierProvider<AddressBookController, AddressBook?>(
      AddressBookController.new,
    );

class AddressBookController extends AsyncNotifier<AddressBook?> {
  AddressRepository get _repo => ref.read(addressRepositoryProvider);

  @override
  Future<AddressBook?> build() async {
    final session = ref.watch(sessionProvider);
    if (session is! MemberSession) return null;
    return ref.watch(addressRepositoryProvider).book();
  }

  Future<void> _reload() async {
    try {
      final book = await _repo.book();
      if (ref.mounted) state = AsyncData(book);
    } on PmartFailure catch (e, st) {
      if (ref.mounted) state = AsyncError(e, st);
    }
  }

  Future<AddressCommandOutcome> add(AddressDraft draft) async {
    final key = IdempotencyKey.generate();
    final attempts = 1 + ref.read(addressResendAttemptsProvider);
    PmartFailure? last;
    for (var i = 0; i < attempts; i++) {
      try {
        final saved = await _repo.add(draft, key: key);
        await _reload();
        return AddressSaved(saved);
      } on UnknownResultFailure catch (f) {
        // 같은 키 재전송은 중복 저장이 아니다(계약 IdempotencyKey).
        last = f;
      } on PmartFailure catch (f) {
        return AddressCommandFailed(f);
      }
    }
    await _reload();
    return last is UnknownResultFailure
        ? const AddressCommandUnknown()
        : AddressCommandFailed(last!);
  }

  Future<AddressCommandOutcome> select(String addressId) async {
    final book = state.value;
    if (book == null) {
      return const AddressCommandFailed(SessionExpiredFailure());
    }
    final key = IdempotencyKey.generate();
    try {
      await _repo.select(
        addressId,
        expectedVersion: book.context.version,
        key: key,
      );
      await _reload();
      return const ShoppingAddressChanged();
    } on UnknownResultFailure {
      // 짝 조회: 현재 쇼핑 컨텍스트가 고른 주소면 반영된 것이다.
      try {
        final ctx = await _repo.context();
        await _reload();
        return ctx.shoppingAddressId == addressId
            ? const ShoppingAddressChanged()
            : const AddressCommandUnknown();
      } on PmartFailure {
        return const AddressCommandUnknown();
      }
    } on ProblemFailure catch (f) {
      if (f.problem.code == ProblemCode.versionConflict) {
        await _reload();
        return const AddressConflict();
      }
      return AddressCommandFailed(f);
    } on PmartFailure catch (f) {
      return AddressCommandFailed(f);
    }
  }
}
