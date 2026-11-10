import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:mfc_app/app.dart';
import 'package:mfc_app/features/packing/data/mock_packing_repository.dart';
import 'package:mfc_app/features/packing/data/packing_repository.dart';
import 'package:mfc_app/features/packing/domain/packing.dart';
import 'package:mfc_app/features/packing/presentation/packing_controller.dart';
import 'package:mfc_app/features/tasks/data/mock_task_repository.dart';
import 'package:mfc_app/features/tasks/domain/task_list.dart';
import 'package:mfc_app/features/tasks/presentation/task_controllers.dart';
import 'package:mfc_app/shared/product_hints.dart';
import 'package:mfc_app/shared/providers.dart';

import 'support.dart';

Future<void> closeLabel(WidgetTester t) async {
  await t.tap(
    find
        .descendant(
          of: find.byKey(const ValueKey('label-preview')),
          matching: find.byType(TextButton),
        )
        .last,
  );
  await t.pumpAndSettle();
}

void main() {
  setUpAll(initPmartFormatting);

  late MockTaskRepository tasks;
  late MockPackingRepository packing;

  List<Override> overrides() => [
    envProvider.overrideWithValue(PmartEnv.mock),
    taskRepositoryProvider.overrideWithValue(tasks),
    packingRepositoryProvider.overrideWithValue(packing),
    secureStoreProvider.overrideWithValue(MemoryKeyValueStore()),
  ];

  setUp(() {
    tasks = MockTaskRepository(latency: Duration.zero);
    packing = MockPackingRepository(latency: Duration.zero);
  });

  group('패킹 흐름', () {
    late ProviderContainer c;
    late PackingController ctl;
    late TaskDetailView task;

    setUp(() async {
      c = ProviderContainer(retry: (_, _) => null, overrides: overrides());
      addTearDown(c.dispose);
      c
        ..listen(packingProvider('task-mock-2'), (_, _) {})
        ..listen(shipmentProvider('shp-2'), (_, _) {});
      ctl = c.read(packingProvider('task-mock-2').notifier);
      task = await c.read(taskDetailProvider('task-mock-2').future);
    });

    Future<ShipmentView> shipment() => c.read(shipmentProvider('shp-2').future);

    test('출하에 없는 상품·담을 수량 초과는 봉투에 넣지 않는다', () async {
      final s = await shipment();
      expect(
        ctl.scan(task, s, MockTaskRepository.chipsBarcode),
        PackScan.wrongItem,
      );
      expect(
        ctl.scan(task, s, MockTaskRepository.yogurtBarcode),
        PackScan.matched,
      );
      expect(
        ctl.scan(task, s, MockTaskRepository.yogurtBarcode),
        PackScan.overExpected,
      );
      expect(c.read(packingProvider('task-mock-2')).inBag('ol-1'), 1);
    });

    test('봉투 온도대는 담은 상품으로 정해지고, 다른 온도대는 같은 봉투에 담지 않는다', () async {
      final s = await shipment();
      expect(ctl.zonesKnown(task), isTrue);
      expect(ctl.bagZone(task), isNull);
      ctl.scan(task, s, MockTaskRepository.yogurtBarcode);
      expect(ctl.bagZone(task), StorageZone.chilled);
      expect(
        c.read(packingProvider('task-mock-2')).zone,
        TemperatureZone.chilled,
      );
      expect(
        ctl.scan(task, s, MockTaskRepository.dumplingBarcode),
        PackScan.otherZone,
      );
      expect(c.read(packingProvider('task-mock-2')).inBag('ol-4'), 0);

      await ctl.seal(task, s);
      expect(
        ctl.scan(task, await shipment(), MockTaskRepository.dumplingBarcode),
        PackScan.matched,
      );
      expect(
        c.read(packingProvider('task-mock-2')).zone,
        TemperatureZone.frozen,
      );
      await ctl.seal(task, await shipment());
      final zones = [
        for (final p in (await shipment()).packages) p.temperatureZone,
      ];
      expect(zones, ['CHILLED', 'FROZEN']);
    });

    test('밀봉하면 QR 포장이 생기고, 모든 수량이 밀봉돼야 출하 준비가 된다', () async {
      var s = await shipment();
      ctl
        ..scan(task, s, MockTaskRepository.yogurtBarcode)
        ..scan(task, s, MockTaskRepository.milkBarcode);
      await ctl.seal(task, s);

      s = await shipment();
      expect(s.packages.single.qrCode, isNotNull);
      expect(s.state, ShipmentState.preparing);

      ctl.scan(task, s, MockTaskRepository.milkBarcode);
      await ctl.seal(task, s);
      s = await shipment();
      expect(s.state, ShipmentState.preparing, reason: '냉동이 아직');

      ctl.scan(task, s, MockTaskRepository.dumplingBarcode);
      await ctl.seal(task, s);

      s = await shipment();
      expect(s.packages, hasLength(3));
      expect(s.state, ShipmentState.ready);
    });

    test('밀봉 응답을 잃으면 같은 키로 다시 보내 포장을 하나만 만든다', () async {
      packing.loseNextSealResponse = true;
      final s = await shipment();
      ctl.scan(task, s, MockTaskRepository.yogurtBarcode);

      await ctl.seal(task, s);

      expect((await shipment()).packages, hasLength(1));
      expect(c.read(packingProvider('task-mock-2')).sealUnknown, isFalse);
    });

    test('재포장은 새 버전·새 QR, 옛 라벨은 무효. 인계 중에는 재포장할 수 없다', () async {
      var s = await shipment();
      ctl.scan(task, s, MockTaskRepository.yogurtBarcode);
      await ctl.seal(task, s);
      s = await shipment();
      final first = s.packages.single;

      final outcome = await ctl.repack(
        s.shipmentId,
        first,
        RepackReason.damagedBag,
      );

      final second = (outcome as PackDone).package;
      expect(second.packageVersion, 2);
      expect(second.qrCode, isNot(first.qrCode));
      s = await shipment();
      expect(
        s.packages.firstWhere((p) => p.packageId == first.packageId).state,
        PackageState.invalidated,
      );
      expect(s.packedByLine['ol-1'], 1, reason: '무효 포장은 합계에서 빠진다');

      packing.startHandover(second.packageId);
      c.invalidate(shipmentProvider('shp-2'));
      s = await shipment();
      final fenced = s.packages.firstWhere(
        (p) => p.packageId == second.packageId,
      );
      expect(fenced.canRepack, isFalse);
      expect(
        await ctl.repack(s.shipmentId, fenced, RepackReason.labelUnreadable),
        isA<PackRejected>(),
      );
    });

    test('포장 중 배차 요청(예상 분) → 출고에 점원 요청이 남고, 다시 요청해도 하나다', () async {
      final s = await shipment();
      await ctl.requestDispatch(s.shipmentId, 12);
      final after = await shipment();
      expect(after.dispatchRequest?.trigger, DispatchTrigger.manual);
      expect(after.dispatchRequest?.estimatedPackMinutes, 12);
      expect(c.read(packingProvider('task-mock-2')).dispatchUnknown, isFalse);

      await ctl.requestDispatch(s.shipmentId, 30);
      expect((await shipment()).dispatchRequest?.estimatedPackMinutes, 12);
    });

    test('요청 없이 포장이 끝나도 자동 요청은 없다(직원 요청만)', () async {
      var s = await shipment();
      ctl
        ..scan(task, s, MockTaskRepository.yogurtBarcode)
        ..scan(task, s, MockTaskRepository.milkBarcode)
        ..scan(task, s, MockTaskRepository.milkBarcode);
      await ctl.seal(task, s);
      ctl.scan(task, await shipment(), MockTaskRepository.dumplingBarcode);
      await ctl.seal(task, await shipment());
      s = await shipment();
      await ctl.finish(task, s);

      expect(tasks.taskJson('task-mock-2')['state'], 'COMPLETED');
      expect(s.state, ShipmentState.ready);
      expect(s.dispatchRequest, isNull);
    });

    test('응답을 잃으면 확인 중 — 다시 확인은 같은 키·같은 분', () async {
      packing.loseNextDispatchResponse = true;
      final id = (await shipment()).shipmentId;
      await ctl.requestDispatch(id, 7);
      expect(c.read(packingProvider('task-mock-2')).dispatchUnknown, isTrue);

      await ctl.recheckDispatch(id);
      final st = c.read(packingProvider('task-mock-2'));
      expect(st.dispatchUnknown, isFalse);
      expect(packing.dispatchCalls, 2);
      expect((await shipment()).dispatchRequest?.estimatedPackMinutes, 7);
    });

    test('취소된 출고는 배차 요청이 거절된다(INVALID_STATE)', () async {
      packing.shipmentCancelled = true;
      await ctl.requestDispatch((await shipment()).shipmentId, 5);
      expect(
        c.read(packingProvider('task-mock-2')).dispatchRejectCode,
        PackProblemCode.invalidState,
      );
    });
  });

  group('연동', () {
    ApiPackingRepository repo(FakeAdapter a) => ApiPackingRepository(
      createPmartDio(
        baseUrl: 'http://test.invalid/api/v1',
        sourceSystem: sourceSystem,
        tokens: TokenStore(MemoryKeyValueStore()),
        refresher: (_) async => null,
        adapter: a,
        delay: (_) async {},
      ),
    );

    test('밀봉: 본문 내용물·온도대, 409 CONTENT_MISMATCH 는 거절, 타임아웃은 불명', () async {
      var i = 0;
      final adapter = FakeAdapter((_, _) async {
        i++;
        return i == 1
            ? FakeReply.problem(409, problemBody('CONTENT_MISMATCH'))
            : const FakeReply.transport(DioExceptionType.receiveTimeout);
      });
      final r = repo(adapter);
      Future<PackOutcome> seal() => r.seal(
        'shp-1',
        const [ContentLine(orderLineId: 'ol-1', sku: 'E-00000001', qty: 2)],
        bagCount: 1,
        zone: TemperatureZone.chilled,
        key: IdempotencyKey('k-1'),
      );

      expect(
        await seal(),
        isA<PackRejected>().having((p) => p.code, 'code', 'CONTENT_MISMATCH'),
      );
      expect(await seal(), isA<PackUnknown>());
      final body = jsonDecode(
        adapter.requests.first.data as String,
      ) as Map<String, dynamic>;
      expect(body['temperatureZone'], 'CHILLED');
      expect((body['contents'] as List).single['qty'], 2);
      expect(
        adapter.requests.first.uri.path,
        '/api/v1/shipments/shp-1/packages',
      );
    });

    test('배차 요청: 출고 경로·예상 분 본문·멱등키, 200(이미 요청)도 요청됨, 타임아웃은 불명', () async {
      var i = 0;
      final adapter = FakeAdapter((_, _) async {
        i++;
        return i == 1
            ? const FakeReply(
                200,
                body: {
                  'shipmentId': 'shp-1',
                  'trigger': 'AUTO_ON_READY',
                  'estimatedPackMinutes': null,
                  'estimatedReadyAt': '2026-11-10T03:10:00Z',
                  'requestedAt': '2026-11-10T03:00:00Z',
                },
              )
            : const FakeReply.transport(DioExceptionType.receiveTimeout);
      });
      final r = repo(adapter);
      Future<DispatchOutcome> send() => r.requestDispatch(
        'shp-1',
        estimatedPackMinutes: 9,
        key: IdempotencyKey('k-2'),
      );

      final first = await send();
      expect(
        first,
        isA<DispatchDone>().having(
          (d) => d.request.trigger,
          'trigger',
          DispatchTrigger.autoOnReady,
        ),
      );
      expect(await send(), isA<DispatchUnknown>());
      final req = adapter.requests.first;
      expect(req.uri.path, '/api/v1/shipments/shp-1/dispatch-requests');
      expect(req.headers['Idempotency-Key'], 'k-2');
      expect(jsonDecode(req.data as String) as Map<String, dynamic>, {
        'estimatedPackMinutes': 9,
      });
    });

    test('배차 요청 409 INVALID_STATE 는 거절', () async {
      final r = repo(
        FakeAdapter(
          (_, _) async => FakeReply.problem(409, problemBody('INVALID_STATE')),
        ),
      );
      expect(
        await r.requestDispatch(
          'shp-1',
          estimatedPackMinutes: 3,
          key: IdempotencyKey('k-3'),
        ),
        isA<DispatchRejected>().having((d) => d.code, 'code', 'INVALID_STATE'),
      );
    });
  });

  testWidgets('패킹 화면: 예상 분 넣고 배차 요청 → 스캔 → 밀봉(QR) → 출하 준비 → 패킹 완료', (t) async {
    t.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: overrides(),
        child: const MfcApp(),
      ),
    );
    await t.pumpAndSettle();
    await openRoute(t, '/tasks/task-mock-2');
    await t.tap(find.byKey(const ValueKey('continue-picking')));
    await t.pumpAndSettle();
    expect(find.text('패킹'), findsOneWidget);

    // 분을 넣기 전에는 요청할 수 없다.
    expect(
      t
          .widget<FilledButton>(
            find.descendant(
              of: find.byKey(const ValueKey('request-dispatch')),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.byKey(const ValueKey('pack-minutes')),
      findsNothing,
      reason: 'PDA 는 키보드 입력 대신 버튼',
    );
    await t.tap(find.byKey(const ValueKey('pack-min-10')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('request-dispatch')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('dispatch-requested')), findsOneWidget);
    expect(find.text('배차를 요청했어요'), findsOneWidget);

    Future<void> scan(String code) async {
      await t.enterText(find.byKey(const ValueKey('pack-scan')), code);
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
    }

    expect(
      find.byKey(const ValueKey('zone-select')),
      findsNothing,
      reason: '온도대는 상품 정보로 — 작업자가 고르지 않는다',
    );
    expect(find.text('봉투 온도대는 처음 담는 상품으로 정해져요'), findsOneWidget);
    await scan(MockTaskRepository.yogurtBarcode);
    expect(find.text('지금 봉투: 냉장'), findsOneWidget);
    await scan(MockTaskRepository.dumplingBarcode);
    expect(find.byKey(const ValueKey('pack-scan-error')), findsOneWidget);
    await scan(MockTaskRepository.milkBarcode);
    await scan(MockTaskRepository.milkBarcode);
    await t.tap(find.byKey(const ValueKey('seal')));
    await t.pumpAndSettle();
    // 밀봉하면 라벨이 바로 나온다(프린터 없음 = 미리보기).
    expect(find.byKey(const ValueKey('label-preview')), findsOneWidget);
    await closeLabel(t);

    await scan(MockTaskRepository.dumplingBarcode);
    expect(find.text('지금 봉투: 냉동'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('seal')));
    await t.pumpAndSettle();
    await closeLabel(t);

    expect(find.textContaining('PKG:pkg-'), findsNWidgets(2));
    expect(find.text('모든 상품을 담았어요(출하 준비)'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('finish-packing')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('packing-finished')), findsOneWidget);

    // 점원 요청이 이미 있어 자동 요청으로 바뀌지 않는다.
    expect(find.text('배차를 요청했어요'), findsOneWidget);
  });

  testWidgets('패킹 화면: 배차 요청 없이 출하 준비가 되면 요청하라고 경고', (t) async {
    t.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: overrides(),
        child: const MfcApp(),
      ),
    );
    await t.pumpAndSettle();
    await openRoute(t, '/tasks/task-mock-2');
    await t.tap(find.byKey(const ValueKey('continue-picking')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('dispatch-missing')), findsNothing);

    for (final bag in [
      [
        MockTaskRepository.yogurtBarcode,
        MockTaskRepository.milkBarcode,
        MockTaskRepository.milkBarcode,
      ],
      [MockTaskRepository.dumplingBarcode],
    ]) {
      for (final code in bag) {
        await t.enterText(find.byKey(const ValueKey('pack-scan')), code);
        await t.testTextInput.receiveAction(TextInputAction.done);
        await t.pump();
      }
      await t.tap(find.byKey(const ValueKey('seal')));
      await t.pumpAndSettle();
      await closeLabel(t);
    }

    expect(find.byKey(const ValueKey('dispatch-missing')), findsOneWidget);
    expect(find.byKey(const ValueKey('dispatch-requested')), findsNothing);

    await t.tap(find.byKey(const ValueKey('pack-min-5')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('request-dispatch')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('dispatch-missing')), findsNothing);
    expect(find.text('배차를 요청했어요'), findsOneWidget);
  });
}
