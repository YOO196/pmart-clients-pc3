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
import 'package:mfc_app/shared/providers.dart';

void main() {
  setUpAll(initPmartFormatting);

  late MockTaskRepository tasks;
  late MockPackingRepository packing;

  List<Override> overrides() => [
    envProvider.overrideWithValue(PmartEnv.mock),
    taskRepositoryProvider.overrideWithValue(tasks),
    packingRepositoryProvider.overrideWithValue(packing),
    secureStoreProvider.overrideWithValue(MemoryKeyValueStore()),
    dispatchPollPolicyProvider.overrideWithValue((
      interval: Duration.zero,
      attempts: 4,
    )),
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
      expect(s.packages, hasLength(2));
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

    test('패킹 완료 실적을 보내고 배차 요청은 배정까지 조회한다', () async {
      var s = await shipment();
      ctl
        ..scan(task, s, MockTaskRepository.yogurtBarcode)
        ..scan(task, s, MockTaskRepository.milkBarcode)
        ..scan(task, s, MockTaskRepository.milkBarcode);
      await ctl.seal(task, s);
      s = await shipment();

      await ctl.finish(task, s);
      await ctl.requestDispatch(s);

      expect(tasks.taskJson('task-mock-2')['state'], 'COMPLETED');
      final state = c.read(packingProvider('task-mock-2'));
      expect(state.packingFinished, isTrue);
      expect(state.dispatch?.state, DispatchState.assigned);
    });

    test('주문이 취소됐으면 배차 요청이 거절된다', () async {
      packing.orderCancelled = true;
      await ctl.requestDispatch(await shipment());
      expect(
        c.read(packingProvider('task-mock-2')).rejectCode,
        PackProblemCode.orderCancelled,
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

    test('배차 요청 본문에 포장 규격, 결과 조회는 같은 키', () async {
      final adapter = FakeAdapter(
        (o, _) async => o.method == 'POST'
            ? const FakeReply(
                202,
                body: {'status': 'ACCEPTED', 'requestId': 'k-2'},
              )
            : const FakeReply(
                200,
                body: {'requestId': 'k-2', 'state': 'OFFERING'},
              ),
      );
      final r = repo(adapter);

      final id = await r.requestDispatch(
        deliveryId: 'dlv-1',
        mfcId: 'MFC-1',
        packagingMinutes: 4,
        bagCount: 2,
        coldChain: true,
        packageIds: const ['pkg-1', 'pkg-2'],
        key: IdempotencyKey('k-2'),
      );
      final view = await r.dispatch(id!);

      final body = jsonDecode(
        adapter.requests.first.data as String,
      ) as Map<String, dynamic>;
      expect(body['deliveryId'], 'dlv-1');
      expect(
        body['packageSpec'],
        containsPair('packageIds', ['pkg-1', 'pkg-2']),
      );
      expect(body['packageSpec'], containsPair('coldChain', true));
      expect(adapter.requests.last.uri.path, '/api/v1/dispatch-requests/k-2');
      expect(view.state, DispatchState.offering);
    });
  });

  testWidgets('패킹 화면: 스캔 → 밀봉(QR) → 출하 준비 → 패킹 완료 → 배차 배정', (t) async {
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
    await t.tap(find.byKey(const ValueKey('task-task-mock-2')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('continue-picking')));
    await t.pumpAndSettle();
    expect(find.text('패킹'), findsOneWidget);

    Future<void> scan(String code) async {
      await t.enterText(find.byKey(const ValueKey('pack-scan')), code);
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
    }

    await scan(MockTaskRepository.yogurtBarcode);
    await scan(MockTaskRepository.milkBarcode);
    await scan(MockTaskRepository.milkBarcode);
    await t.tap(find.byKey(const ValueKey('seal')));
    await t.pumpAndSettle();

    expect(find.textContaining('PMART-PKG:'), findsOneWidget);
    expect(find.text('모든 상품을 담았어요(출하 준비)'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('finish-packing')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('packing-finished')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('request-dispatch')));
    await t.pumpAndSettle();
    expect(find.text('라이더가 배정됐어요'), findsOneWidget);
  });
}
