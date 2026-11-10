import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:mfc_app/app.dart';
import 'package:mfc_app/features/inbound/data/inbound_repository.dart';
import 'package:mfc_app/features/inbound/data/mock_inbound_repository.dart';
import 'package:mfc_app/features/inbound/domain/inbound.dart';
import 'package:mfc_app/features/inbound/presentation/inbound_controller.dart';
import 'package:mfc_app/features/packing/data/mock_packing_repository.dart';
import 'package:mfc_app/features/packing/presentation/packing_controller.dart';
import 'package:mfc_app/features/tasks/data/mock_task_repository.dart';
import 'package:mfc_app/features/tasks/presentation/task_controllers.dart';
import 'package:mfc_app/shared/providers.dart';

void main() {
  setUpAll(initPmartFormatting);

  group('계수 규칙', () {
    test('차이 사유: 0이면 미도착, 적으면 부족, 많으면 초과, 같고 격리면 격리 사유', () {
      expect(const ReceiptCount().reasonFor(10), DiscrepancyReason.notReceived);
      expect(
        const ReceiptCount(normal: 8).reasonFor(10),
        DiscrepancyReason.short,
      );
      expect(
        const ReceiptCount(normal: 11).reasonFor(10),
        DiscrepancyReason.over,
      );
      expect(const ReceiptCount(normal: 10).reasonFor(10), isNull);
      const q = ReceiptCount(
        normal: 8,
        quarantined: 2,
        quarantineReason: DiscrepancyReason.temperature,
      );
      expect(q.reasonFor(10), DiscrepancyReason.temperature);
      expect(q.total, 10);
      expect(const ReceiptCount(quarantined: 1).complete, isFalse);
    });
  });

  group('연동', () {
    InboundRepository repo(FakeAdapter a) => ApiInboundRepository(
      createPmartDio(
        baseUrl: 'http://test.invalid/api/v1',
        sourceSystem: sourceSystem,
        tokens: TokenStore(MemoryKeyValueStore()),
        refresher: (_) async => null,
        adapter: a,
        delay: (_) async {},
      ),
    );

    const line = InboundLine(sku: 'S-1', lotId: 'L-1', expectedQty: 10);

    test('수령 등록: 경로·멱등키·예상 버전, 본문 수량·차이 사유, 202 receiptId, 타임아웃은 불명', () async {
      var i = 0;
      final adapter = FakeAdapter((_, _) async {
        i++;
        return switch (i) {
          1 => const FakeReply(
            202,
            body: {
              'status': 'ACCEPTED',
              'requestId': 'k-1',
              'resultId': 'rcp-9',
            },
          ),
          2 => FakeReply.problem(409, problemBody('INVALID_STATE')),
          _ => const FakeReply.transport(DioExceptionType.receiveTimeout),
        };
      });
      final r = repo(adapter);
      Future<InboundCommandOutcome> send() => r.recordReceipt(
        'TRF-1',
        version: 3,
        counts: const [
          (
            line,
            ReceiptCount(
              normal: 7,
              quarantined: 1,
              quarantineReason: DiscrepancyReason.damaged,
            ),
          ),
        ],
        receivedAt: DateTime.utc(2026, 11, 10, 6),
        receivedBy: 'w-1',
        key: IdempotencyKey('k-1'),
      );

      expect(
        await send(),
        isA<InboundAccepted>().having((a) => a.resultId, 'resultId', 'rcp-9'),
      );
      expect(
        await send(),
        isA<InboundRejected>().having((a) => a.code, 'code', 'INVALID_STATE'),
      );
      expect(await send(), isA<InboundUnknown>());

      final req = adapter.requests.first;
      expect(req.uri.path, '/api/v1/inbound-promises/TRF-1/receipts');
      expect(req.headers['Idempotency-Key'], 'k-1');
      expect('${req.headers['X-Expected-Version']}', '3');
      final body = jsonDecode(req.data as String) as Map<String, dynamic>;
      final l = (body['lines'] as List).single as Map<String, dynamic>;
      expect(l['sku'], 'S-1');
      expect(l['lotId'], 'L-1');
      expect(l['normalQty'], 7);
      expect(l['quarantinedQty'], 1);
      expect(l['pendingQty'], 0);
      // 합계 8 < 예정 10 → 수량 사유가 먼저.
      expect(l['discrepancyReason'], 'SHORT');
    });

    test('입고 예정·수령 결과 변환', () async {
      final adapter = FakeAdapter(
        (o, _) async => o.uri.path.endsWith('/receipts/rcp-1')
            ? const FakeReply(
                200,
                body: {
                  'receiptId': 'rcp-1',
                  'inventoryApplyStatus': 'APPLIED',
                  'inventoryCommitId': 'c-1',
                },
              )
            : const FakeReply(
                200,
                body: {
                  'trfId': 'TRF-1',
                  'version': 2,
                  'state': 'RECEIVING',
                  'lines': [
                    {'sku': 'S-1', 'lotId': 'L-1', 'expectedQty': 10},
                  ],
                  'receipts': <Object>[],
                },
              ),
      );
      final r = repo(adapter);
      final p = await r.promise('TRF-1');
      expect(p.state, PromiseState.receiving);
      expect(p.lines.single.expectedQty, 10);
      expect(p.lines.single.productName, isNull); // 계약에 없음(BR-53)
      final rc = await r.receipt('TRF-1', 'rcp-1');
      expect(rc.applyStatus, ApplyStatus.applied);
      expect(rc.commitId, 'c-1');
    });
  });

  late MockInboundRepository inbound;

  Future<void> pumpApp(WidgetTester t) async {
    t.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final tasks = MockTaskRepository(latency: Duration.zero);
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          envProvider.overrideWithValue(PmartEnv.mock),
          taskRepositoryProvider.overrideWithValue(tasks),
          packingRepositoryProvider.overrideWithValue(
            MockPackingRepository(latency: Duration.zero),
          ),
          inboundRepositoryProvider.overrideWithValue(inbound),
          applyPollPolicyProvider.overrideWithValue((
            interval: Duration.zero,
            attempts: 3,
          )),
          secureStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        ],
        child: const MfcApp(),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    await t.tap(find.byKey(ValueKey(key)));
    await t.pumpAndSettle();
  }

  Future<void> scan(WidgetTester t, String code) async {
    await t.enterText(find.byKey(const ValueKey('inbound-scan')), code);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
  }

  Future<void> setQty(WidgetTester t, String bucket, int v) async {
    await tapKey(t, '$bucket-value');
    await t.enterText(find.byKey(const ValueKey('qty-input')), '$v');
    await tapKey(t, 'qty-ok');
  }

  Future<void> openInbound(WidgetTester t) async {
    await pumpApp(t);
    await tapKey(t, 'area-inbound');
    await tapKey(t, 'guide-ok');
    expect(find.byKey(const ValueKey('assigned-TRF-MOCK-001')), findsOneWidget);
    await tapKey(t, 'run-task');
  }

  // 기본은 박스 목록 없이(계약 그대로 — 상품별 계수). 박스 검수는 아래 테스트에서 따로.
  setUp(
    () => inbound = MockInboundRepository(
      latency: Duration.zero,
      withBoxes: false,
    ),
  );

  testWidgets(
    '입고(박스 목록 없음 — 계약 그대로): 도착 등록 → 상품별 계수(스캔·격리 사유) → 확인 → 수령 등록 → 반영 → 다음 입고',
    (t) async {
      await openInbound(t);

      // 1단계: 도착 등록.
      expect(find.byKey(const ValueKey('inbound-step-0')), findsOneWidget);
      // 냉장 차량 1대 = 롤테이너 6개·120박스(TMS §22), 판매 단위 1,490개.
      expect(find.text('상품 7종 · 예정 1490개'), findsOneWidget);
      expect(find.text('롤테이너 6개 · 박스 120개'), findsOneWidget);
      await tapKey(t, 'inbound-arrive');
      expect(inbound.peek('TRF-MOCK-001').state, PromiseState.receiving);

      // 2단계: 우유 — 스캔 2번(정상 +2), 다른 상품 스캔은 거절, 나머지는 직접 입력.
      expect(find.byKey(const ValueKey('inbound-step-1')), findsOneWidget);
      expect(find.text('서울우유 1L'), findsOneWidget);
      await scan(t, '8801115114154');
      await scan(t, '8801115114154');
      expect(
        t
            .widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('normal-value')),
                matching: find.byType(Text),
              ),
            )
            .data,
        '2',
      );
      await scan(t, '8801115220015');
      expect(find.byKey(const ValueKey('inbound-scan-error')), findsOneWidget);
      // 박스째 +12(입수).
      expect(find.text('예정 30박스 × 12입 = 360개'), findsOneWidget);
      await tapKey(t, 'box-plus');
      expect(
        t
            .widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('normal-value')),
                matching: find.byType(Text),
              ),
            )
            .data,
        '14',
      );
      await setQty(t, 'normal', 358);
      expect(find.text('합계 358 / 예정 360'), findsOneWidget);
      expect(find.text('부족'), findsOneWidget);
      expect(t.takeException(), isNull);
      await tapKey(t, 'inbound-next');

      // 요거트 — 정상 10 + 격리 2, 격리 사유를 고르기 전에는 못 넘어간다.
      expect(find.text('그릭요거트 플레인 400g'), findsOneWidget);
      await setQty(t, 'normal', 238);
      await setQty(t, 'quarantined', 2);
      expect(
        t
            .widget<FilledButton>(find.byKey(const ValueKey('inbound-next')))
            .onPressed,
        isNull,
      );
      await tapKey(t, 'reason-damaged');
      await tapKey(t, 'inbound-next');

      // 나머지 5종 — 예정대로.
      for (final l in inbound.peek('TRF-MOCK-001').lines.skip(2)) {
        await setQty(t, 'normal', l.expectedQty);
        await tapKey(t, 'inbound-next');
      }

      // 3단계: 확인.
      expect(find.byKey(const ValueKey('inbound-step-2')), findsOneWidget);
      expect(
        find.textContaining('예정 360 · 정상 358 · 격리 0 · 미판정 0'),
        findsOneWidget,
      );
      await tapKey(t, 'inbound-submit');

      // 4단계: 접수 → 조회로 반영 확인.
      expect(find.byKey(const ValueKey('inbound-applied')), findsOneWidget);
      expect(inbound.peek('TRF-MOCK-001').state, PromiseState.tinPosted);
      final lines = inbound.peek('TRF-MOCK-001').lines;
      expect(lines[0].receivedQty, 358);
      expect(lines[1].quarantinedQty, 2);

      // 다음 작업 → 서버가 다음 입고를 준다.
      await tapKey(t, 'inbound-message-action');
      expect(
        find.byKey(const ValueKey('assigned-TRF-MOCK-002')),
        findsOneWidget,
      );
    },
  );

  testWidgets('수령 응답을 잃으면 확인 중 — 다시 확인은 같은 키(수령 하나)', (t) async {
    inbound.loseNextReceiptResponse = true;
    await openInbound(t);
    await tapKey(t, 'inbound-arrive');
    for (final q
        in inbound.peek('TRF-MOCK-001').lines.map((l) => l.expectedQty)) {
      await setQty(t, 'normal', q);
      await tapKey(t, 'inbound-next');
    }
    await tapKey(t, 'inbound-submit');
    expect(find.byKey(const ValueKey('inbound-unknown')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbound-applied')), findsNothing);

    await tapKey(t, 'inbound-submit'); // 다시 확인
    expect(find.byKey(const ValueKey('inbound-applied')), findsOneWidget);
    expect(inbound.receiptCalls, 2);
    expect(inbound.peek('TRF-MOCK-001').receipts, hasLength(1));
  });

  testWidgets('반영이 늦으면 반영 대기 — 접수만으로 완료라고 하지 않는다', (t) async {
    inbound.applyPolls = 10;
    await openInbound(t);
    await tapKey(t, 'inbound-arrive');
    for (final q
        in inbound.peek('TRF-MOCK-001').lines.map((l) => l.expectedQty)) {
      await setQty(t, 'normal', q);
      await tapKey(t, 'inbound-next');
    }
    await tapKey(t, 'inbound-submit');
    expect(find.byKey(const ValueKey('inbound-applying')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbound-applied')), findsNothing);
    inbound.applyPolls = 1;
    await tapKey(t, 'inbound-message-action');
    expect(find.byKey(const ValueKey('inbound-applied')), findsOneWidget);
  });

  testWidgets(
    '입고(박스): 박스 검수(이 트럭 박스·이미 확인·박스째 파손·미도착) → 박스마다 열어 낱개 검수 → 상품별 합계로 수령 등록',
    (t) async {
      inbound = MockInboundRepository(latency: Duration.zero);
      await openInbound(t);
      InboundFlowController ctl() =>
          ProviderScope.containerOf(t.element(find.byType(Scaffold).first))
              .read(inboundFlowProvider('TRF-MOCK-001').notifier);

      await tapKey(t, 'inbound-arrive');

      // 2단계: 박스 검수 — 이 트럭에 어떤 상품이 몇 박스.
      expect(find.byKey(const ValueKey('inbound-step-1')), findsOneWidget);
      expect(
        find.textContaining('박스 확인 0 / 120', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('0/30박스'), findsOneWidget); // 우유 30박스
      Future<void> scanBox(String id) async {
        await t.enterText(find.byKey(const ValueKey('box-scan')), id);
        await t.testTextInput.receiveAction(TextInputAction.done);
        await t.pumpAndSettle();
      }

      await scanBox('BOX-99999999');
      expect(find.text('이 송장의 박스가 아니에요. 따로 두고 관리자에게 알려 주세요'), findsWidgets);
      await scanBox('BOX-00000001');
      await scanBox('BOX-00000001');
      expect(find.text('이미 확인한 박스예요'), findsWidgets);
      await scanBox('BOX-00000002');
      await tapKey(t, 'box-damaged'); // 우유 2번 박스 — 박스째 파손
      // 바코드가 안 읽히면 상품을 눌러 박스 번호를 골라 확인.
      await tapKey(t, 'box-line-E-00000002|LOT-Y-1110');
      await tapKey(t, 'box-chip-BOX-00000031');
      expect(
        find.textContaining('박스 확인 3 / 120', findRichText: true),
        findsOneWidget,
      );
      // 나머지는 한꺼번에(목). 샐러드 마지막 박스 BOX-00000120 은 오지 않았다.
      for (var i = 3; i <= 119; i++) {
        if (i == 31) continue;
        ctl().scanBox('BOX-${i.toString().padLeft(8, '0')}');
      }
      await t.pumpAndSettle();
      expect(
        find.textContaining('박스 확인 119 / 120', findRichText: true),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('box-missing')), findsOneWidget);
      expect(t.takeException(), isNull);
      await tapKey(t, 'box-check-done');

      // 3단계: 박스마다 열어 낱개 — 파손 박스는 열지 않는다(118 = 119 − 1).
      expect(find.byKey(const ValueKey('inbound-step-2')), findsOneWidget);
      expect(find.text('박스 열어 검수 0 / 118'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('box-open-scan')),
        'BOX-00000001',
      );
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('box-open-BOX-00000001')),
        findsOneWidget,
      );
      await setQty(t, 'box-normal', 11);
      await setQty(t, 'box-quarantined', 1);
      expect(
        t
            .widget<FilledButton>(find.byKey(const ValueKey('box-save')))
            .onPressed,
        isNull,
      ); // 격리 사유를 골라야
      await tapKey(t, 'box-reason-damaged');
      await tapKey(t, 'box-save');
      // 목록에서 눌러 열고 "입수대로 정상".
      await tapKey(t, 'box-BOX-00000003');
      await tapKey(t, 'box-all-normal');
      await tapKey(t, 'box-save');
      expect(find.text('박스 열어 검수 2 / 118'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(find.byKey(const ValueKey('box-to-review')))
            .onPressed,
        isNull,
      ); // 전부 열어야
      for (final b in ctl().state.openable) {
        if (ctl().state.boxCounts.containsKey(b.boxId)) continue;
        ctl()
          ..openBox(b.boxId)
          ..setBoxCount(b.boxId, ReceiptCount(normal: b.unitsPerBox))
          ..saveBox();
      }
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await tapKey(t, 'box-to-review');

      // 4단계: 상품별 합계 — 우유 = 11 + (파손 12 격리) + 28×12, 샐러드 1박스 미도착.
      expect(find.byKey(const ValueKey('inbound-step-3')), findsOneWidget);
      expect(
        find.textContaining('예정 360 · 정상 347 · 격리 13 · 미판정 0'),
        findsOneWidget,
      );
      expect(
        find.textContaining('예정 120 · 정상 112 · 격리 0 · 미판정 0'),
        findsOneWidget,
      );
      await tapKey(t, 'inbound-submit');
      expect(find.byKey(const ValueKey('inbound-applied')), findsOneWidget);
      final lines = inbound.peek('TRF-MOCK-001').lines;
      expect(lines[0].receivedQty, 360);
      expect(lines[0].quarantinedQty, 13);
      expect(lines[6].receivedQty, 112);
    },
  );
}
