import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:rider_app/app.dart';
import 'package:rider_app/features/delivery/data/delivery_repository.dart';
import 'package:rider_app/features/delivery/data/mock_delivery_repository.dart';
import 'package:rider_app/features/delivery/domain/delivery.dart';
import 'package:rider_app/features/delivery/presentation/delivery_controller.dart';
import 'package:rider_app/features/offers/data/mock_offer_repository.dart';
import 'package:rider_app/features/offers/presentation/offer_controllers.dart';
import 'package:rider_app/shared/providers.dart';

void main() {
  setUpAll(initPmartFormatting);

  late MockDeliveryRepository repo;
  late MemoryKeyValueStore store;

  List<Override> overrides() => [
    envProvider.overrideWithValue(PmartEnv.mock),
    deliveryRepositoryProvider.overrideWithValue(repo),
    handoverRepositoryProvider.overrideWithValue(repo),
    evidenceUploaderProvider.overrideWithValue(repo),
    secureStoreProvider.overrideWithValue(store),
  ];

  setUp(() {
    repo = MockDeliveryRepository(latency: Duration.zero);
    store = MemoryKeyValueStore();
  });

  test('QR 형식(BR-23 목)에서 포장 ID 를 꺼낸다', () {
    expect(packageIdFromQr(MockDeliveryRepository.qrFor('pkg-1')), 'pkg-1');
    expect(packageIdFromQr('garbage'), isNull);
  });

  group('배송 수행', () {
    late ProviderContainer c;
    late DeliveryFlowController flow;

    setUp(() {
      c = ProviderContainer(retry: (_, _) => null, overrides: overrides());
      addTearDown(c.dispose);
      c.listen(deliveryFlowProvider('dlv-1'), (_, _) {});
      flow = c.read(deliveryFlowProvider('dlv-1').notifier);
    });

    Future<DeliveryView> delivery() => repo.get('dlv-1');
    DeliveryFlowState state() => c.read(deliveryFlowProvider('dlv-1'));
    String qr(String p) => MockDeliveryRepository.qrFor(p);

    test('가게 도착 → 포장별 인계 → 전부 인계 뒤 픽업 → 고객 도착 → 사진 업로드 뒤 전달 완료', () async {
      await flow.arriveAtStore();
      var d = await delivery();
      expect(d.state, ExecutionState.arrivedAtStore);

      await flow.scan(d, qr('pkg-1'));
      expect(state().phaseOf('pkg-1').phase, HandoverPhase.handedOver);
      expect(state().handoverIds, ['hof-pkg-1']);

      await flow.scan(d, qr('pkg-2'));
      await flow.pickup();
      d = await delivery();
      expect(d.state, ExecutionState.pickedUp);
      expect(d.handoverIds.toSet(), {'hof-pkg-1', 'hof-pkg-2'});

      await flow.arriveAtCustomer();
      await flow.complete(CompletionMethod.contactless, Placement.frontDoor);
      expect(
        (await delivery()).state,
        ExecutionState.arrivedAtCustomer,
        reason: '사진 없으면 보내지 않는다',
      );

      await flow.uploadPhoto();
      await flow.complete(CompletionMethod.contactless, Placement.frontDoor);
      expect((await delivery()).state, ExecutionState.completed);
    });

    test('부분 인계로 픽업을 보내면 서버가 HANDOVER_NOT_CONFIRMED 로 거절한다', () async {
      await flow.arriveAtStore();
      await flow.scan(await delivery(), qr('pkg-1'));

      await flow.pickup();

      final items = await c.read(riderQueueProvider).items();
      final pickup = items.firstWhere(
        (i) => i.kind == DeliveryCommandKind.pickup,
      );
      expect(pickup.state, QueueItemState.rejected);
      expect(pickup.rejectCode, HandoverProblemCode.handoverNotConfirmed);
      expect((await delivery()).state, ExecutionState.arrivedAtStore);
    });

    test('다른 배송·중복·읽기 실패 QR 은 서버에 보내기 전에 막는다', () async {
      await flow.arriveAtStore();
      final d = await delivery();

      expect(await flow.scan(d, qr('pkg-x')), ScanVerdict.otherDelivery);
      expect(await flow.scan(d, 'abc'), ScanVerdict.unreadable);
      await flow.scan(d, qr('pkg-1'));
      expect(await flow.scan(d, qr('pkg-1')), ScanVerdict.duplicate);
    });

    test('재포장으로 무효가 된 구 라벨은 서버가 거절한다', () async {
      await flow.arriveAtStore();
      repo.invalidatedQrs.add(qr('pkg-1'));

      await flow.scan(await delivery(), qr('pkg-1'));

      expect(state().phaseOf('pkg-1').phase, HandoverPhase.rejected);
      expect(
        state().phaseOf('pkg-1').rejectCode,
        HandoverProblemCode.packageInvalidated,
      );
    });

    test('커밋 응답이 불명이면 판정 조회로 인계 완료를 확인한다(다시 스캔 안 함)', () async {
      await flow.arriveAtStore();
      repo.commitMode = MockCommit.unknownButApplied;

      await flow.scan(await delivery(), qr('pkg-1'));

      expect(state().phaseOf('pkg-1').phase, HandoverPhase.handedOver);
      expect(state().phaseOf('pkg-1').handoverId, 'hof-pkg-1');
    });

    test('fence 불명이 계속되면 확인 중이고, 서버 확정 뒤 다시 확인으로 인계 완료가 된다', () async {
      await flow.arriveAtStore();
      repo.commitMode = MockCommit.unknownStillInProgress;
      await flow.scan(await delivery(), qr('pkg-1'));

      expect(state().phaseOf('pkg-1').phase, HandoverPhase.checking);
      expect(state().handoverIds, isEmpty, reason: '불명은 인계 완료가 아니다');
      final keys = repo.commitKeys.toSet();
      expect(keys, hasLength(1), reason: '불명 재전송은 같은 키');

      repo.settleInProgress();
      await flow.checkAgain('pkg-1');

      expect(state().phaseOf('pkg-1').phase, HandoverPhase.handedOver);
    });

    test('출고가 중지된 포장은 중지로 보인다', () async {
      await flow.arriveAtStore();
      repo.stoppedPackages.add('pkg-2');

      await flow.scan(await delivery(), qr('pkg-2'));
      await flow.resolve('pkg-2');

      expect(state().phaseOf('pkg-2').phase, HandoverPhase.stopped);
    });

    test('오프라인 수행 명령은 저장됐다가 같은 키로 다시 보낸다', () async {
      repo.offline = true;
      await flow.arriveAtStore();
      final saved = await FieldQueue(store, name: 'rider').items();
      expect(saved.single.state, QueueItemState.queued);
      expect((await delivery()).state, ExecutionState.assigned);

      repo.offline = false;
      await flow.sync();

      expect(repo.sentKeys, [saved.single.id, saved.single.id]);
      expect((await delivery()).state, ExecutionState.arrivedAtStore);
      expect(
        (await c.read(riderQueueProvider).items()).single.state,
        QueueItemState.applied,
      );
    });

    test('사진 업로드 실패는 실패로 보이고 전달 완료를 보내지 않는다', () async {
      repo.uploadFails = true;
      await flow.uploadPhoto();
      expect(state().uploadFailed, isTrue);
      expect(state().photoRef, isNull);
    });
  });

  testWidgets('홈에서 배송 → 가게 도착 → QR 2개 인계 → 픽업 → 전달 완료', (t) async {
    t.view
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
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
    expect(find.text('배정됨 · 가게로 이동'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('arrive-store')));
    await settle();
    expect(find.text('포장 인계 0 / 2'), findsOneWidget);

    Future<void> scan(String code) async {
      await t.enterText(find.byKey(const ValueKey('qr-scan')), code);
      await t.testTextInput.receiveAction(TextInputAction.done);
      await settle();
    }

    final pickup = find.byKey(const ValueKey('pickup'));
    await scan(MockDeliveryRepository.qrFor('pkg-1'));
    expect(find.text('포장 인계 1 / 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('partial-handover')), findsOneWidget);
    expect(t.widget<FilledButton>(pickup).onPressed, isNull);

    await scan(MockDeliveryRepository.qrFor('pkg-2'));
    expect(t.widget<FilledButton>(pickup).onPressed, isNotNull);
    await t.tap(pickup);
    await settle();
    expect(find.text('픽업 완료 · 고객에게 이동'), findsOneWidget);
    expect(find.text('목동 1단지 101동'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('arrive-customer')));
    await settle();
    final complete = find.byKey(const ValueKey('complete'));
    expect(
      t.widget<FilledButton>(complete).onPressed,
      isNull,
      reason: '사진 업로드 전',
    );
    await t.tap(find.byKey(const ValueKey('upload-photo')));
    await settle();
    await t.tap(complete);
    await settle();

    expect(find.byKey(const ValueKey('delivery-done')), findsOneWidget);
  });
}
