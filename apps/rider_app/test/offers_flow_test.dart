import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:rider_app/app.dart';
import 'package:rider_app/features/offers/data/mock_offer_repository.dart';
import 'package:rider_app/features/offers/domain/offer_list.dart';
import 'package:rider_app/features/offers/presentation/offer_controllers.dart';
import 'package:rider_app/shared/providers.dart';

void main() {
  setUpAll(initPmartFormatting);

  late MockOfferRepository repo;
  late Duration mono;

  setUp(() {
    repo = MockOfferRepository(latency: Duration.zero);
    mono = Duration.zero;
  });

  Widget app() => ProviderScope(
    retry: (_, _) => null,
    overrides: [
      envProvider.overrideWithValue(PmartEnv.mock),
      offerRepositoryProvider.overrideWithValue(repo),
      dutyRepositoryProvider.overrideWithValue(repo),
      monotonicProvider.overrideWithValue(() => mono),
    ],
    child: const RiderApp(),
  );

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> start(WidgetTester t) async {
    await t.pumpWidget(app());
    await settle(t);
  }

  testWidgets('서버 pollAfterSec 간격으로 다시 조회한다', (t) async {
    await start(t);
    expect(repo.fetches, 1);

    await t.pump(const Duration(seconds: 4));
    expect(repo.fetches, 1);
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(repo.fetches, 2);
  });

  testWidgets('신규배차를 끄면 서버가 null 을 줘서 폴링을 멈춘다. 켜면 즉시 조회한다', (t) async {
    await start(t);
    await t.tap(find.byKey(const ValueKey('new-dispatch')));
    await settle(t);
    final afterOff = repo.fetches;
    expect(find.byKey(const ValueKey('polling-stopped')), findsOneWidget);

    await t.pump(const Duration(seconds: 30));
    expect(repo.fetches, afterOff, reason: 'null 이면 폴링하지 않는다');

    await t.tap(find.byKey(const ValueKey('new-dispatch')));
    await settle(t);
    expect(repo.fetches, afterOff + 1, reason: '신규배차 ON 은 즉시 조회');
    expect(find.byKey(const ValueKey('offer-offer-mock-1')), findsOneWidget);
  });

  testWidgets('조회 실패는 "제안 없음"이 아니라 연결 확인 중이고, 받은 제안을 지우지 않는다', (t) async {
    await start(t);
    repo.failNextFetches = 1;
    await t.pump(const Duration(seconds: 5));
    await settle(t);

    expect(find.byKey(const ValueKey('reconnecting')), findsOneWidget);
    expect(find.byKey(const ValueKey('offers-empty')), findsNothing);
    expect(find.byKey(const ValueKey('offer-offer-mock-1')), findsOneWidget);

    // 지수 백오프(2초) 뒤 재시도해서 회복한다.
    await t.pump(const Duration(seconds: 2));
    await settle(t);
    expect(find.byKey(const ValueKey('reconnecting')), findsNothing);
  });

  testWidgets('남은 시간은 서버 값에서 단조 경과로 줄이고, 다시 조회하면 서버 값으로 맞춘다', (t) async {
    await start(t);
    expect(find.text('응답 42초 남음'), findsOneWidget);

    mono = const Duration(seconds: 3);
    await t.pump(const Duration(seconds: 1));
    expect(find.text('응답 39초 남음'), findsOneWidget);

    mono = const Duration(seconds: 50);
    await t.pump(const Duration(seconds: 1));
    expect(
      find.text('응답 0초 남음'),
      findsOneWidget,
      reason: '0 이어도 만료 확정이 아니라 버튼은 남는다',
    );
    expect(find.byKey(const ValueKey('accept-offer-mock-1')), findsOneWidget);
  });

  testWidgets('수락 응답을 잃어도 같은 키로 판정을 받고 내 배송에 추가된다', (t) async {
    repo.loseNextResponse = true;
    await start(t);

    await t.tap(find.byKey(const ValueKey('accept-offer-mock-1')));
    await settle(t);

    expect(repo.respondKeys, hasLength(2));
    expect(repo.respondKeys.toSet(), hasLength(1));
    expect(find.text('배정됐어요. 배송 정보를 확인해 주세요'), findsOneWidget);
    expect(find.byKey(const ValueKey('delivery-dlv-1')), findsOneWidget);
  });

  testWidgets('늦은 수락은 사유별로 안내한다', (t) async {
    repo.lateNext = LateReason.alreadyAssigned;
    await start(t);

    await t.tap(find.byKey(const ValueKey('accept-offer-mock-1')));
    await settle(t);

    expect(find.text('다른 라이더에게 이미 배정됐어요'), findsOneWidget);
    expect(find.byKey(const ValueKey('delivery-dlv-1')), findsNothing);
  });

  testWidgets('일반 배차 모드에는 거절 버튼이 없다', (t) async {
    await start(t);
    expect(find.byKey(const ValueKey('reject-offer-mock-1')), findsNothing);
  });

  testWidgets('진행 중 배송이 있으면 운행을 끝낼 수 없다(서버 판정)', (t) async {
    await start(t);
    await t.tap(find.byKey(const ValueKey('accept-offer-mock-1')));
    await settle(t);

    await t.tap(find.byKey(const ValueKey('on-duty')));
    await settle(t);

    expect(find.text('진행 중인 배송이 있어서 운행을 끝낼 수 없어요'), findsOneWidget);
    expect(
      t.widget<SwitchListTile>(find.byKey(const ValueKey('on-duty'))).value,
      isTrue,
    );
  });
}
