import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';

import 'package:customer_app/features/address/data/mock_address_repository.dart';
import 'package:customer_app/features/address/domain/address.dart';
import 'package:customer_app/features/address/presentation/address_controller.dart';
import 'package:customer_app/features/auth/data/mock_auth_repository.dart';
import 'package:customer_app/features/auth/domain/auth.dart';
import 'package:customer_app/features/auth/presentation/auth_controller.dart';
import 'package:customer_app/shared/providers.dart';
import 'package:customer_app/shared/shopping_context.dart';

void main() {
  late MockAuthRepository authRepo;
  late MockAddressRepository addressRepo;
  late TokenStore tokens;

  ProviderContainer make({List<Override> extra = const []}) {
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        envProvider.overrideWithValue(PmartEnv.mock),
        authRepositoryProvider.overrideWithValue(authRepo),
        addressRepositoryProvider.overrideWithValue(addressRepo),
        tokenStoreProvider.overrideWithValue(tokens),
        ...extra,
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    authRepo = MockAuthRepository(latency: Duration.zero);
    addressRepo = MockAddressRepository(latency: Duration.zero);
    tokens = TokenStore(MemoryKeyValueStore());
  });

  LoginOutcome? settled(ProviderContainer c) =>
      switch (c.read(loginFlowProvider(LoginPurpose.general))) {
        LoginSettled(:final outcome) => outcome,
        _ => null,
      };

  Future<void> login(ProviderContainer c, SocialProvider p) {
    final provider = loginFlowProvider(LoginPurpose.general);
    c.listen(provider, (_, _) {});
    return c.read(provider.notifier).start(p);
  }

  group('로그인', () {
    test('기존 회원은 토큰을 저장하고 회원 세션이 된다', () async {
      final c = make();
      await login(c, SocialProvider.kakao);

      expect(settled(c), isA<LoginMember>());
      expect(c.read(sessionProvider), isA<MemberSession>());
      expect(tokens.accessToken, 'mock-access');
      expect(await tokens.readRefreshToken(), 'mock-refresh');
    });

    test('필수 동의 대기면 동의 뒤에야 회원이 된다', () async {
      final c = make();
      await login(c, SocialProvider.naver);

      final consent = settled(c)! as LoginNeedsConsent;
      expect(c.read(sessionProvider), isA<GuestSession>());
      expect(consent.requiredConsents, MockAuthRepository.requiredConsents);

      await c
          .read(loginFlowProvider(LoginPurpose.general).notifier)
          .submitConsents(consent.authRequestId, consent.requiredConsents);

      expect(settled(c), isA<LoginMember>());
      expect(c.read(sessionProvider), isA<MemberSession>());
    });

    test('제한은 서버가 준 남은 시간으로 알려 주고 세션을 바꾸지 않는다', () async {
      final c = make();
      await login(c, SocialProvider.apple);

      expect((settled(c)! as LoginRestricted).retryAfterSeconds, 600);
      expect(c.read(sessionProvider), isA<GuestSession>());
    });

    test('결과 불명은 같은 키로 다시 보내 원인증 결과를 받는다', () async {
      final c = make();
      await login(c, SocialProvider.google);

      expect(settled(c), isA<LoginMember>());
      expect(authRepo.loginKeys, hasLength(2));
      expect(authRepo.loginKeys.toSet(), hasLength(1));
    });

    test('제공자 화면에서 취소하면 실패가 아니라 취소다', () async {
      final c = make(
        extra: [
          socialTokenSourceProvider.overrideWithValue(
            MockSocialTokenSource(cancelled: {SocialProvider.kakao}),
          ),
        ],
      );
      await login(c, SocialProvider.kakao);

      expect(settled(c), isA<LoginCancelled>());
      expect(authRepo.loginKeys, isEmpty, reason: '서버에 보내지 않는다');
    });

    test('제공자 장애는 다시 시도할 수 있는 안내다', () async {
      final c = make(
        extra: [
          socialTokenSourceProvider.overrideWithValue(
            MockSocialTokenSource(down: {SocialProvider.kakao}),
          ),
        ],
      );
      await login(c, SocialProvider.kakao);

      expect(settled(c), isA<LoginProviderUnavailable>());
    });
  });

  group('주소', () {
    Future<ProviderContainer> member() async {
      final c = make();
      c.listen(currentMfcIdProvider, (_, _) {});
      await login(c, SocialProvider.kakao);
      await c.read(addressBookProvider.future);
      return c;
    }

    test('비회원은 주소록이 없다(빈 주소록과 구분)', () async {
      final c = make();
      expect(await c.read(addressBookProvider.future), isNull);
    });

    test('회원의 담당 센터는 쇼핑 컨텍스트에서 온다', () async {
      final c = await member();
      expect(c.read(currentMfcIdProvider), MockAddressRepository.homeMfcId);
    });

    test('저장 성공과 배송 가능 판정은 따로다(권역 밖도 저장된다)', () async {
      final c = await member();
      final outcome = await c
          .read(addressBookProvider.notifier)
          .add(
            const AddressDraft(
              roadAddress: '제주 제주시 첨단로 1',
              detailAddress: '1층',
              receiverName: '김피마',
              receiverPhone: '010-0000-0000',
            ),
          );

      final saved = (outcome as AddressSaved).address;
      expect(saved.serviceability, Serviceability.outOfArea);
      expect(c.read(addressBookProvider).value!.addresses, hasLength(2));
    });

    test('쇼핑 주소를 바꾸면 담당 센터가 바뀐다', () async {
      final c = await member();
      final added = await c
          .read(addressBookProvider.notifier)
          .add(
            const AddressDraft(
              roadAddress: '서울 강남구 테헤란로 1',
              detailAddress: '5층',
              receiverName: '김피마',
              receiverPhone: '010-0000-0000',
            ),
          );
      final id = (added as AddressSaved).address.addressId;

      final outcome = await c.read(addressBookProvider.notifier).select(id);

      expect(outcome, isA<ShoppingAddressChanged>());
      expect(c.read(currentMfcIdProvider), 'MFC-MOCK-02');
    });

    test('선택 응답을 잃으면 쇼핑 컨텍스트 조회로 반영을 확인한다', () async {
      final c = await member();
      await c
          .read(addressBookProvider.notifier)
          .add(
            const AddressDraft(
              roadAddress: '서울 강남구 테헤란로 1',
              detailAddress: '5층',
              receiverName: '김피마',
              receiverPhone: '010-0000-0000',
            ),
          );
      addressRepo.loseNextSelection = true;

      final outcome = await c
          .read(addressBookProvider.notifier)
          .select('addr-2');

      expect(outcome, isA<ShoppingAddressChanged>());
      expect(
        c.read(addressBookProvider).value!.context.shoppingAddressId,
        'addr-2',
      );
    });

    test('다른 곳에서 쇼핑 주소가 바뀌었으면 충돌로 알리고 최신 목록을 받는다', () async {
      final c = await member();
      addressRepo.contextVersion++;

      final outcome = await c
          .read(addressBookProvider.notifier)
          .select('addr-1');

      expect(outcome, isA<AddressConflict>());
      expect(
        c.read(addressBookProvider).value!.context.version,
        addressRepo.contextVersion,
      );
    });
  });
}
