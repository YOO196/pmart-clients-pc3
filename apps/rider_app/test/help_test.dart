import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:rider_app/app.dart';
import 'package:rider_app/features/delivery/data/mock_delivery_repository.dart';
import 'package:rider_app/features/delivery/domain/delivery.dart';
import 'package:rider_app/features/delivery/presentation/delivery_controller.dart';
import 'package:rider_app/features/offers/data/mock_offer_repository.dart';
import 'package:rider_app/features/offers/presentation/offer_controllers.dart';
import 'package:rider_app/shared/providers.dart';

void main() {
  setUpAll(initPmartFormatting);

  late MockDeliveryRepository repo;

  List<Override> overrides() => [
    envProvider.overrideWithValue(PmartEnv.mock),
    deliveryRepositoryProvider.overrideWithValue(repo),
    handoverRepositoryProvider.overrideWithValue(repo),
    evidenceUploaderProvider.overrideWithValue(repo),
    secureStoreProvider.overrideWithValue(MemoryKeyValueStore()),
  ];

  setUp(() => repo = MockDeliveryRepository(latency: Duration.zero));

  test('도움요청 접수 응답을 잃어도 같은 키로 다시 보내 상태를 확인한다', () async {
    final c = ProviderContainer(retry: (_, _) => null, overrides: overrides());
    addTearDown(c.dispose);
    final p = helpFlowProvider('dlv-1');
    c.listen(p, (_, _) {});
    repo.loseNextHelpResponse = true;

    await c.read(p.notifier).send(HelpCategory.customerUnreachable);

    expect(c.read(p).state, HelpState.open, reason: '접수 ≠ 해결');
    await c.read(p.notifier).refresh();
    expect(c.read(p).state, HelpState.inProgress);
    await c.read(p.notifier).refresh();
    expect(c.read(p).state, HelpState.resolved);
  });

  testWidgets('사진 업로드에 실패하면 도움요청에서 "사진을 올릴 수 없어요"가 먼저 나온다', (t) async {
    t.view
      ..physicalSize = const Size(800, 2200)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final d = repo.deliveryJson('dlv-1')..['state'] = 'ARRIVED_AT_CUSTOMER';
    expect(d['state'], 'ARRIVED_AT_CUSTOMER');
    repo.uploadFails = true;
    final offers = MockOfferRepository(latency: Duration.zero);
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          ...overrides(),
          offerRepositoryProvider.overrideWithValue(offers),
          dutyRepositoryProvider.overrideWithValue(offers),
        ],
        child: const RiderApp(),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
    }

    await settle();
    await t.tap(find.byKey(const ValueKey('delivery-dlv-1')));
    await settle();
    await t.tap(find.byKey(const ValueKey('upload-photo')));
    await settle();
    expect(find.byKey(const ValueKey('upload-failed')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('help')));
    await settle();
    final options = find.byType(SimpleDialogOption);
    expect(
      t.widget<SimpleDialogOption>(options.first).key,
      const ValueKey('help-photoUploadFailed'),
    );

    await t.tap(options.first);
    await settle();
    expect(find.text('지원센터에 접수했어요'), findsOneWidget);
  });
}
