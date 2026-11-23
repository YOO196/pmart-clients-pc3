// 홈 배달 불가 지역 표시 — 초안 11-C 회색(사용자 2026-11-23 "c로 하는데 회색으로 해줘").
// 서버가 권역 밖(OUT_OF_SERVICE_AREA)이라고 판정한 쇼핑 주소일 때만 불가로 보이고, 판정 모름은 불가로 보이지 않고 "확인 중"(초안 11-E).
import 'package:customer_app/features/address/data/guest_address_store.dart';
import 'package:customer_app/features/address/data/mock_address_repository.dart';
import 'package:customer_app/features/address/domain/address.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart' show MemoryKeyValueStore;
import 'package:pmart_ui/pmart_ui.dart' show initPmartFormatting;

import 'support/app_harness.dart';

final class _OneAddress extends MockAddressRepository {
  _OneAddress(this.state) : super(latency: Duration.zero);

  Serviceability state;
  int reads = 0;

  // 시험 앱은 비회원으로 시작한다 → 비회원 배송지(기기에 저장한 ID)로 읽는다.
  @override
  Future<Address> guest(String guestAddressId) async => (
    ++reads,
    Address(
      addressId: guestAddressId,
      version: 1,
      roadAddress: '제주 제주시 연동 312-1',
      detailAddress: '201호',
      serviceability: state,
    ),
  ).$2;
}

void main() {
  setUpAll(initPmartFormatting);
  Finder key(String k) => find.byKey(ValueKey(k));

  Future<_OneAddress> openHome(WidgetTester t, Serviceability s) async {
    t.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final secure = MemoryKeyValueStore();
    final store = GuestAddressStore(secure);
    await store.add('gaddr-x');
    await store.select('gaddr-x');
    final repo = _OneAddress(s);
    await t.pumpWidget(testApp(const [], address: repo, secure: secure));
    await t.pumpAndSettle();
    return repo;
  }

  testWidgets('권역 밖이면 주소 위 회색 불가 줄과 홈 맨 위 회색 띠', (t) async {
    await openHome(t, Serviceability.outOfArea);
    expect(find.text('배달하지 않는 지역이에요'), findsOneWidget);
    expect(key('home-out-of-area'), findsOneWidget);
    expect(find.text('이 주소는 아직 배달하지 않아요'), findsOneWidget);
    expect(find.text('둘러보기는 할 수 있어요'), findsOneWidget);
    // 회색: 분홍·보라가 아니라 회색 바탕.
    final m = t.widget<Material>(
      find
          .ancestor(
            of: key('home-out-of-area'),
            matching: find.byType(Material),
          )
          .first,
    );
    final scheme = Theme.of(t.element(key('home-out-of-area'))).colorScheme;
    expect(m.color, scheme.surfaceContainer);
  });

  testWidgets('띠를 누르면 주소 설정으로 간다', (t) async {
    await openHome(t, Serviceability.outOfArea);
    await t.tap(key('home-out-of-area'));
    await t.pumpAndSettle();
    expect(key('home-out-of-area'), findsNothing);
    expect(find.textContaining('제주 제주시 연동 312-1 201호'), findsWidgets);
  });

  // 초안 11-E(사용자 2026-11-23 "넣는다"): 판정 모름은 불가가 아니라 "확인 중" + [다시 확인].
  testWidgets('판정 모름은 불가가 아니라 확인 중, 다시 확인하면 새로 읽는다', (t) async {
    final repo = await openHome(t, Serviceability.unknown);
    expect(find.text('배달하지 않는 지역이에요'), findsNothing);
    expect(key('home-out-of-area'), findsNothing);
    expect(find.text('배달 가능 여부 확인 중'), findsOneWidget);
    expect(find.text('배달 가능 여부를 확인하고 있어요'), findsOneWidget);
    final before = repo.reads;
    repo.state = Serviceability.serviceable;
    await t.tap(key('home-service-unknown'));
    await t.pumpAndSettle();
    expect(repo.reads, greaterThan(before));
    expect(key('home-service-unknown'), findsNothing);
    expect(find.text('배달 가능 여부 확인 중'), findsNothing);
  });
}
