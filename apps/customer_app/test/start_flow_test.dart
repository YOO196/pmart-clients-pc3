import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';

import 'package:customer_app/features/address/data/guest_address_store.dart';
import 'package:customer_app/features/address/data/mock_address_repository.dart';
import 'package:customer_app/features/address/domain/address.dart';
import 'package:customer_app/features/address/data/current_location.dart';
import 'package:customer_app/features/profile/data/consents_repository.dart';
import 'package:customer_app/features/start/data/device_consents_repository.dart';
import 'package:customer_app/features/start/presentation/current_location_flow.dart';
import 'package:customer_app/features/start/presentation/start_controller.dart';

import 'support/app_harness.dart';

/// 처음 실행: 환영·약관 → 로그인/둘러보기 → 주소(필수) → 홈. 레퍼런스 2. 처음 다운로드 시 ….
void main() {
  Finder key(String k) => find.byKey(ValueKey(k));

  // 주소 입력 칸이 많아 화면을 키운다(목록 지연 생성으로 저장 버튼이 안 만들어지지 않게).
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view
      ..physicalSize = const Size(800, 1800)
      ..devicePixelRatio = 1;
  });
  tearDown(
    () => TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        .reset(),
  );

  bool beginEnabled(WidgetTester t) =>
      t.widget<FilledButton>(key('start-begin')).onPressed != null;

  Future<void> fillAndSave(WidgetTester t) async {
    await t.enterText(key('f-detail'), '101동 202호');
    await t.enterText(key('f-name'), '김피마');
    await t.enterText(key('f-phone'), '010-0000-0000');
    await t.tap(key('address-save'));
    await t.pumpAndSettle();
  }

  testWidgets('비회원 첫 실행: 약관 고름 → 서버 반영 → 처리완료 안내 → 둘러보기 → 주소를 저장해야 홈', (
    t,
  ) async {
    final secure = MemoryKeyValueStore();
    final address = MockAddressRepository(latency: Duration.zero);
    final consents = MockDeviceConsentsRepository(
      now: () => DateTime.utc(2026, 11, 19, 5, 30),
    );
    await t.pumpWidget(
      testApp(
        [deviceConsentsRepositoryProvider.overrideWithValue(consents)],
        address: address,
        startGate: true,
        secure: secure,
      ),
    );
    await t.pumpAndSettle();

    // 1) 환영·약관 — 위치 약관은 선택(현재 위치 기능에서만 필수, BR-59 회신)
    expect(key('start-welcome'), findsOneWidget);
    expect(find.text('위치기반서비스 이용약관 동의 (선택)'), findsOneWidget);
    expect(beginEnabled(t), isTrue);
    await t.tap(key('start-agree-all'));
    await t.pump();
    await t.tap(key('start-agree-location'));
    await t.pump();
    await t.tap(key('start-begin'));
    await t.pumpAndSettle();

    // 서버로 보낸 값: 마케팅 동의, 위치 거부(현행 버전 그대로)
    final (sent, _) = consents.changes.single;
    expect(
      [for (final c in sent) (c.type, c.version, c.agreed)],
      [
        ('MARKETING', '2026-11-17', true),
        ('LOCATION_BASED_SERVICE', '2026-11-19', false),
      ],
    );
    // 서버가 돌려준 값으로 처리완료 안내(서울 시각)
    expect(key('start-marketing-result'), findsOneWidget);
    expect(find.text('마케팅정보 앱 푸시 알림 동의 안내'), findsOneWidget);
    expect(find.text('전송자 : PMart'), findsOneWidget);
    expect(find.text('수신동의 일시 : 2026년 11월 19일 14시'), findsOneWidget);
    expect(find.text('처리내용 : 수신동의 처리완료'), findsOneWidget);
    // 동의 값은 기기에 두지 않는다
    expect(
      await secure.read('pmart.start.welcome'),
      isNot(contains('marketing')),
    );
    await t.tap(key('start-marketing-result-ok'));
    await t.pumpAndSettle();

    // 2) 로그인 또는 둘러보기
    expect(key('start-entry'), findsOneWidget);
    expect(key('login-kakao'), findsOneWidget);
    await t.tap(key('login-browse'));
    await t.pumpAndSettle();

    // 3) 주소 — 뒤로 가기 없음, 검색 → 입력(도로명 채움) → 저장
    expect(key('start-address'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    await t.tap(key('start-address-search'));
    await t.pumpAndSettle();
    expect(find.text('서울 송파구 올림픽로 300'), findsOneWidget);
    await fillAndSave(t);

    // 4) 홈
    expect(key('start-address'), findsNothing);
    expect(key('start-welcome'), findsNothing);
    expect(find.text('홈'), findsWidgets);

    // 다시 켜면 바로 홈(같은 기기 저장소·서버)
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(
      testApp([], address: address, startGate: true, secure: secure),
    );
    await t.pumpAndSettle();
    expect(key('start-welcome'), findsNothing);
    expect(key('start-entry'), findsNothing);
    expect(key('start-address'), findsNothing);
  });

  testWidgets('주소 입력을 그만두면 주소 화면으로 돌아온다(홈으로 못 감)', (t) async {
    final secure = MemoryKeyValueStore();
    await secure.write('pmart.start.welcome', 'at=x');
    await secure.write('pmart.start.entry', '1');
    await t.pumpWidget(testApp([], startGate: true, secure: secure));
    await t.pumpAndSettle();
    expect(key('start-address'), findsOneWidget);

    await t.tap(key('start-address-search'));
    await t.pumpAndSettle();
    expect(key('f-road'), findsOneWidget);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(key('start-address'), findsOneWidget);
  });

  testWidgets('로그인한 회원은 주소가 있으면 바로 홈', (t) async {
    final secure = MemoryKeyValueStore();
    await secure.write('pmart.start.welcome', 'at=x');
    await t.pumpWidget(testApp([], startGate: true, secure: secure));
    await t.pumpAndSettle();
    expect(key('start-entry'), findsOneWidget);

    await t.tap(key('login-kakao'));
    await t.pumpAndSettle();

    expect(key('start-entry'), findsNothing);
    expect(key('start-address'), findsNothing);
    // 로그인했으니 로그아웃해도 다시 묻지 않는다
    expect(await secure.read('pmart.start.entry'), isNotNull);
  });

  testWidgets('주소가 없는 회원도 주소부터', (t) async {
    final secure = MemoryKeyValueStore();
    await secure.write('pmart.start.welcome', 'at=x');
    final empty = _EmptyAddressRepository();
    await t.pumpWidget(
      testApp([], address: empty, startGate: true, secure: secure),
    );
    await t.pumpAndSettle();
    await t.tap(key('login-kakao'));
    await t.pumpAndSettle();
    expect(key('start-address'), findsOneWidget);
    // 이 기기에 비회원 배송지가 없으면 묻지 않는다
    expect(key('start-guest-address'), findsNothing);
  });

  testWidgets('비회원으로 주소를 넣었던 사람이 로그인하면 그 주소를 저장할지 묻고, 저장하면 바로 홈', (t) async {
    final secure = MemoryKeyValueStore();
    await secure.write('pmart.start.welcome', 'at=x');
    final empty = _EmptyAddressRepository();
    final guest = await t.runAsync(
      () => empty.addGuest(
        const AddressDraft(
          roadAddress: '부산 부산진구 중앙대로 672',
          detailAddress: '12층',
          receiverName: '김피마',
          receiverPhone: '010-1234-5678',
          entranceNote: '1층 공동현관',
        ),
        key: IdempotencyKey.generate(),
      ),
    );
    final store = GuestAddressStore(secure);
    await store.add(guest!.addressId);
    await store.select(guest.addressId);

    await t.pumpWidget(
      testApp([], address: empty, startGate: true, secure: secure),
    );
    await t.pumpAndSettle();
    await t.tap(key('login-kakao'));
    await t.pumpAndSettle();

    // 회원 주소록은 비었지만 로그인 전 주소를 먼저 보인다
    expect(key('start-address'), findsOneWidget);
    expect(key('start-guest-address'), findsOneWidget);
    expect(find.text('부산 부산진구 중앙대로 672'), findsOneWidget);
    await t.tap(key('start-guest-address-save-${guest.addressId}'));
    await t.pumpAndSettle();

    expect(key('start-address'), findsNothing);
    final book = await t.runAsync(empty.book);
    final saved = book!.addresses.single;
    expect(saved.roadAddress, '부산 부산진구 중앙대로 672');
    expect(saved.detailAddress, '12층');
    expect(saved.receiverName, '김피마');
  });

  testWidgets('마케팅 거부도 서버 처리 결과로 거부 안내', (t) async {
    final consents = MockDeviceConsentsRepository(
      now: () => DateTime.utc(2026, 11, 19, 5),
    );
    await t.pumpWidget(
      testApp([
        deviceConsentsRepositoryProvider.overrideWithValue(consents),
      ], startGate: true),
    );
    await t.pumpAndSettle();
    await t.tap(key('start-begin'));
    await t.pumpAndSettle();
    expect(find.text('마케팅정보 앱 푸시 알림 거부 안내'), findsOneWidget);
    expect(find.text('수신거부 일시 : 2026년 11월 19일 14시'), findsOneWidget);
    expect(find.text('처리내용 : 수신거부 처리완료'), findsOneWidget);
    await t.tap(key('start-marketing-result-ok'));
    await t.pumpAndSettle();
    expect(key('start-entry'), findsOneWidget);
  });

  testWidgets('저장 실패면 넘어가지 않고 안내 없음, 다시 누르면 같은 키', (t) async {
    final secure = MemoryKeyValueStore();
    final consents = MockDeviceConsentsRepository()
      ..failNextChange = const NetworkFailure(DioExceptionType.connectionError);
    await t.pumpWidget(
      testApp(
        [deviceConsentsRepositoryProvider.overrideWithValue(consents)],
        startGate: true,
        secure: secure,
      ),
    );
    await t.pumpAndSettle();
    await t.tap(key('start-agree-marketing'));
    await t.pump();
    await t.tap(key('start-begin'));
    await t.pumpAndSettle();
    expect(key('start-consent-error'), findsOneWidget);
    expect(key('start-marketing-result'), findsNothing);
    expect(key('start-welcome'), findsOneWidget);
    expect(await secure.read('pmart.start.welcome'), isNull);

    await t.tap(key('start-begin'));
    await t.pumpAndSettle();
    expect(consents.changes, hasLength(2));
    expect(consents.changes[0].$2, consents.changes[1].$2);
    expect(key('start-marketing-result'), findsOneWidget);
  });

  testWidgets('약관 목록을 못 읽으면 시작하기가 잠기고 다시 시도로 풀린다', (t) async {
    final consents = MockDeviceConsentsRepository()
      ..failNextTerms = const NetworkFailure(DioExceptionType.connectionError);
    await t.pumpWidget(
      testApp([
        deviceConsentsRepositoryProvider.overrideWithValue(consents),
      ], startGate: true),
    );
    await t.pumpAndSettle();
    expect(key('start-terms-error'), findsOneWidget);
    expect(beginEnabled(t), isFalse);
    await t.tap(key('start-terms-retry'));
    await t.pumpAndSettle();
    expect(key('start-terms-error'), findsNothing);
    expect(beginEnabled(t), isTrue);
  });

  testWidgets('약관 > 를 누르면 서버 본문, 돌아오면 환영 화면', (t) async {
    await t.pumpWidget(testApp([], startGate: true));
    await t.pumpAndSettle();
    await t.tap(key('start-agree-location-open'));
    await t.pumpAndSettle();
    expect(key('consent-term'), findsOneWidget);
    expect(key('consent-term-body'), findsOneWidget);
    expect(find.textContaining('시연용 약관 본문'), findsOneWidget);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(key('start-welcome'), findsOneWidget);
  });

  group('현재 위치로 찾기', () {
    late MemoryKeyValueStore secure;
    late MockDeviceConsentsRepository consents;
    late MockCurrentLocationSource location;

    setUp(() async {
      secure = MemoryKeyValueStore();
      await secure.write('pmart.start.welcome', 'at=x');
      await secure.write('pmart.start.entry', '1');
      consents = MockDeviceConsentsRepository();
      location = MockCurrentLocationSource();
    });

    Future<void> open(WidgetTester t) async {
      await t.pumpWidget(
        testApp(
          [
            deviceConsentsRepositoryProvider.overrideWithValue(consents),
            currentLocationSourceProvider.overrideWithValue(location),
          ],
          startGate: true,
          secure: secure,
        ),
      );
      await t.pumpAndSettle();
      expect(key('start-address'), findsOneWidget);
      await t.tap(key('start-address-locate'));
      await t.pumpAndSettle();
    }

    testWidgets('위치 약관 동의가 없으면 묻고 서버(기기 동의)에 남긴 뒤 위치 → 도로명주소로 주소 입력', (
      t,
    ) async {
      await open(t);
      expect(key('locate-consent'), findsOneWidget);
      expect(location.calls, 0);
      await t.tap(key('dialog-confirm'));
      await t.pumpAndSettle();

      final (sent, _) = consents.changes.single;
      expect(
        [for (final c in sent) (c.type, c.version, c.agreed)],
        [('LOCATION_BASED_SERVICE', '2026-11-19', true)],
      );
      expect(location.calls, 1);
      // 목 역지오코딩 결과가 주소 입력에 채워진다
      expect(key('f-road'), findsOneWidget);
      expect(find.text('부산 부산진구 중앙대로 672'), findsOneWidget);
    });

    testWidgets('이미 동의했으면 묻지 않는다', (t) async {
      await consents.change(const [
        ConsentChange('LOCATION_BASED_SERVICE', '2026-11-19', agreed: true),
      ], key: IdempotencyKey.generate());
      await open(t);
      expect(key('locate-consent'), findsNothing);
      expect(location.calls, 1);
      expect(key('f-road'), findsOneWidget);
    });

    testWidgets('동의 창을 닫으면 위치를 읽지 않는다', (t) async {
      await open(t);
      await t.tap(key('dialog-cancel'));
      await t.pumpAndSettle();
      expect(location.calls, 0);
      expect(consents.changes, isEmpty);
      expect(key('start-address'), findsOneWidget);
    });

    testWidgets('권한 거부면 레퍼런스 5-2 안내 → 설정을 연다', (t) async {
      location.fix = const LocationDenied(forever: true);
      await open(t);
      await t.tap(key('dialog-confirm'));
      await t.pumpAndSettle();
      expect(key('locate-settings'), findsOneWidget);
      expect(find.text("현재 위치 검색을 위해 '위치 공유 설정'을 변경(허용)해주세요."), findsOneWidget);
      await t.tap(key('dialog-confirm'));
      await t.pumpAndSettle();
      expect(location.settingsOpened, [false]);
      expect(key('f-road'), findsNothing);
    });

    testWidgets('위치를 못 받으면 안내만 하고 주소를 지어내지 않는다', (t) async {
      location.fix = const LocationUnavailable();
      await open(t);
      await t.tap(key('dialog-confirm'));
      await t.pumpAndSettle();
      expect(find.text('현재 위치를 찾지 못했어요. 주소를 검색해 주세요'), findsOneWidget);
      expect(key('f-road'), findsNothing);
    });
  });

  test('redirect: 판단 중에는 처음 화면만 대기, 그 뒤 다시 읽기는 그대로', () {
    expect(startRedirect(StartStep.loading, '/', resolved: false), '/start');
    expect(startRedirect(StartStep.loading, '/', resolved: true), isNull);
    expect(
      startRedirect(StartStep.welcome, '/cart', resolved: false),
      '/start/welcome',
    );
    expect(
      startRedirect(StartStep.address, '/addresses/new', resolved: false),
      isNull,
    );
    expect(
      startRedirect(StartStep.address, '/me/info', resolved: false),
      isNull,
    );
    expect(
      startRedirect(StartStep.ready, '/start/address', resolved: true),
      '/',
    );
    expect(startRedirect(StartStep.ready, '/orders', resolved: true), isNull);
    expect(
      startRedirect(
        StartStep.welcome,
        '/terms/LOCATION_BASED_SERVICE/2026-11-19',
        resolved: false,
      ),
      isNull,
    );
  });
}

/// 회원 주소록이 빈 목.
final class _EmptyAddressRepository extends MockAddressRepository {
  _EmptyAddressRepository() : super(latency: Duration.zero);

  @override
  Future<AddressBook> book() async {
    final b = await super.book();
    return AddressBook(
      addresses: [
        for (final a in b.addresses)
          if (a.addressId != 'addr-1') a,
      ],
      context: const ShoppingContext(version: 1),
    );
  }
}
