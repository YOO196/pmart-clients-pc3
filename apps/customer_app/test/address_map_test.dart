import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_api_delivery_serviceability/pmart_api_delivery_serviceability.dart'
    as api;
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/address/data/geocoding_repository.dart';
import 'package:customer_app/features/address/data/mock_address_repository.dart';
import 'package:customer_app/features/address/domain/address.dart';
import 'package:customer_app/features/address/presentation/map_pick_screen.dart';
import 'package:customer_app/features/address/presentation/postcode_screen.dart';
import 'package:customer_app/l10n/gen/app_localizations.dart';
import 'package:customer_app/shared/providers.dart';

import 'support/app_harness.dart';

/// 저장 요청(초안)을 남기는 목.
final class _RecordingAddresses extends MockAddressRepository {
  _RecordingAddresses() : super(latency: Duration.zero);

  final drafts = <AddressDraft>[];

  @override
  Future<Address> addGuest(AddressDraft draft, {required IdempotencyKey key}) {
    drafts.add(draft);
    return super.addGuest(draft, key: key);
  }
}

void main() {
  setUpAll(initPmartFormatting);

  Future<void> openForm(WidgetTester t, Widget app) async {
    t.view
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(app);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('home-address')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('address-add')));
    await t.pumpAndSettle();
  }

  Future<void> fillRest(WidgetTester t) async {
    await t.enterText(find.byKey(const ValueKey('f-detail')), '1층');
    await t.enterText(find.byKey(const ValueKey('f-name')), '김피마');
    await t.enterText(find.byKey(const ValueKey('f-phone')), '01000000000');
  }

  String pinText(WidgetTester t) =>
      t.widget<Text>(find.byKey(const ValueKey('address-pin-state'))).data!;

  testWidgets('도로명은 직접 입력하지 않고 주소 검색으로만 고른다', (t) async {
    await openForm(t, testApp(const []));
    final road = t.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('f-road')),
        matching: find.byType(TextField),
      ),
    );
    expect(road.readOnly, isTrue);
  });

  testWidgets('주소 검색 → 서버 좌표로 지도 시작 → 핀 위치를 geo 로, 우편번호와 함께 저장한다', (t) async {
    final addresses = _RecordingAddresses();
    final picker = FakeAddressPicker(
      road: '부산 부산진구 중앙대로 672',
      pin: (lat: 35.1531, lng: 129.0601),
    );
    await openForm(
      t,
      testApp(const [], addressPicker: picker, address: addresses),
    );

    await t.tap(find.byKey(const ValueKey('address-search')));
    await t.pumpAndSettle();

    // 지도는 서버 주소 변환 좌표에서 시작한다(목: 35.1529, 129.0596).
    expect(picker.mapStarts.single, (lat: 35.1529, lng: 129.0596));
    expect(pinText(t), '배달 위치를 지도에서 맞췄어요');
    expect(find.text('부산 부산진구 중앙대로 672'), findsOneWidget);

    await fillRest(t);
    await t.tap(find.byKey(const ValueKey('address-save')));
    await t.pumpAndSettle();

    final saved = addresses.drafts.single;
    expect(saved.roadAddress, '부산 부산진구 중앙대로 672');
    expect(saved.postalCode, '05551');
    expect(saved.geo, (lat: 35.1531, lng: 129.0601));
  });

  testWidgets('좌표 조회 실패는 "주소 없음"이 아니고, 주소만으로 저장할 수 있다', (t) async {
    final addresses = _RecordingAddresses();
    final picker = FakeAddressPicker(road: '부산 부산진구 중앙대로 672');
    picker.geocoding.failNext = const UnknownResultFailure(httpStatus: 503);
    await openForm(
      t,
      testApp(const [], addressPicker: picker, address: addresses),
    );

    await t.tap(find.byKey(const ValueKey('address-search')));
    await t.pumpAndSettle();

    expect(pinText(t), '지도 위치를 확인하지 못했어요. 주소만으로 저장하거나 다시 시도해 주세요');
    expect(picker.mapStarts, isEmpty);

    await fillRest(t);
    await t.tap(find.byKey(const ValueKey('address-save')));
    await t.pumpAndSettle();
    expect(addresses.drafts.single.geo, isNull);
    expect(addresses.drafts.single.roadAddress, '부산 부산진구 중앙대로 672');
  });

  testWidgets('좌표가 0건이면 지도를 열지 않고 주소만으로 저장할 수 있다고 안내한다', (t) async {
    final picker = FakeAddressPicker(road: '없는주소 1');
    await openForm(t, testApp(const [], addressPicker: picker));

    await t.tap(find.byKey(const ValueKey('address-search')));
    await t.pumpAndSettle();

    expect(pinText(t), '지도 위치를 찾지 못했어요. 주소만으로 저장할 수 있어요');
    expect(picker.mapStarts, isEmpty);
  });

  testWidgets('지도에서 맞추기를 다시 누르면 앞서 맞춘 핀 위치에서 시작한다', (t) async {
    final picker = FakeAddressPicker(
      road: '부산 부산진구 중앙대로 672',
      pin: (lat: 35.1531, lng: 129.0601),
    );
    await openForm(t, testApp(const [], addressPicker: picker));
    await t.tap(find.byKey(const ValueKey('address-search')));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('address-map')));
    await t.pumpAndSettle();

    expect(picker.mapStarts, [
      (lat: 35.1529, lng: 129.0596),
      (lat: 35.1531, lng: 129.0601),
    ]);
  });

  testWidgets('지도 화면: 지도를 쓸 수 없는 환경은 안내만 하고, 핀 위치 주소를 보이며 확인하면 그 좌표로 닫힌다', (
    t,
  ) async {
    GeoPoint? result;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          envProvider.overrideWithValue(PmartEnv.mock),
          geocodingRepositoryProvider.overrideWithValue(
            MockGeocodingRepository(latency: Duration.zero),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('ko'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    result = await Navigator.of(context).push<GeoPoint>(
                      MaterialPageRoute(
                        builder: (_) => const MapPickScreen(
                          initial: (lat: 35.1529, lng: 129.0596),
                          roadAddress: '부산 부산진구 중앙대로 672',
                        ),
                      ),
                    ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey('map-unavailable')), findsOneWidget);
    expect(find.text('핀 위치: 부산 부산진구 중앙대로 672'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('map-confirm')));
    await t.pumpAndSettle();
    expect(result, (lat: 35.1529, lng: 129.0596));
  });

  group('우편번호 검색 결과', () {
    test('도로명주소·우편번호·건물명을 옮긴다', () {
      final r = postcodeFromJson({
        'roadAddress': '부산 부산진구 중앙대로 672',
        'jibunAddress': '부산 부산진구 부전동 227-2',
        'zonecode': '47296',
        'buildingName': '삼정타워',
      });
      expect(r?.roadAddress, '부산 부산진구 중앙대로 672');
      expect(r?.zoneNo, '47296');
      expect(r?.buildingName, '삼정타워');
    });

    test('지번을 골라 도로명이 비었으면 자동 도로명을 쓰고, 둘 다 없으면 고르지 않은 것으로 본다', () {
      expect(
        postcodeFromJson({
          'roadAddress': '',
          'autoRoadAddress': '부산 부산진구 중앙대로 672',
        })?.roadAddress,
        '부산 부산진구 중앙대로 672',
      );
      expect(
        postcodeFromJson({'roadAddress': '', 'jibunAddress': '부전동 1'}),
        isNull,
      );
    });
  });

  test('좌표 없는 후보는 버린다(0,0 으로 만들지 않는다)', () {
    final r = api.AddressLookupResult.fromJson({
      'results': [
        {'roadAddress': 'a', 'lat': 35.1, 'lng': 129.0},
        {'roadAddress': 'b'},
      ],
    });
    expect(candidatesFromContract(r).map((c) => c.roadAddress), ['a']);
  });
}
