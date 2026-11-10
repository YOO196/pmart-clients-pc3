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

  setUp(() => inbound = MockInboundRepository(latency: Duration.zero));

  testWidgets(
    '입고: 서버가 준 입고 → 도착 등록 → 상품별 계수(스캔·격리 사유) → 확인 → 수령 등록 → 반영 → 다음 입고',
    (t) async {
      await openInbound(t);

      // 1단계: 도착 등록.
      expect(find.byKey(const ValueKey('inbound-step-0')), findsOneWidget);
      expect(find.text('상품 3종 · 예정 66개'), findsOneWidget);
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
      await setQty(t, 'normal', 22);
      expect(find.text('합계 22 / 예정 24'), findsOneWidget);
      expect(find.text('부족'), findsOneWidget);
      expect(t.takeException(), isNull);
      await tapKey(t, 'inbound-next');

      // 요거트 — 정상 10 + 격리 2, 격리 사유를 고르기 전에는 못 넘어간다.
      expect(find.text('그릭요거트 플레인 400g'), findsOneWidget);
      await setQty(t, 'normal', 10);
      await setQty(t, 'quarantined', 2);
      expect(
        t
            .widget<FilledButton>(find.byKey(const ValueKey('inbound-next')))
            .onPressed,
        isNull,
      );
      await tapKey(t, 'reason-damaged');
      await tapKey(t, 'inbound-next');

      // 감자칩 — 예정대로 30.
      await setQty(t, 'normal', 30);
      await tapKey(t, 'inbound-next');

      // 3단계: 확인.
      expect(find.byKey(const ValueKey('inbound-step-2')), findsOneWidget);
      expect(
        find.textContaining('예정 24 · 정상 22 · 격리 0 · 미판정 0'),
        findsOneWidget,
      );
      await tapKey(t, 'inbound-submit');

      // 4단계: 접수 → 조회로 반영 확인.
      expect(find.byKey(const ValueKey('inbound-applied')), findsOneWidget);
      expect(inbound.peek('TRF-MOCK-001').state, PromiseState.tinPosted);
      final lines = inbound.peek('TRF-MOCK-001').lines;
      expect(lines[0].receivedQty, 22);
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
    for (final q in [24, 12, 30]) {
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
    for (final q in [24, 12, 30]) {
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
}
