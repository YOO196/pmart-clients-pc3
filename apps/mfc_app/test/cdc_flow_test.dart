import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:mfc_app/app.dart';
import 'package:mfc_app/features/auth/data/auth_repository.dart';
import 'package:mfc_app/features/auth/domain/employee_auth.dart';
import 'package:mfc_app/features/auth/presentation/auth_controller.dart';
import 'package:mfc_app/features/cdc/data/cdc_flow_repository.dart';
import 'package:mfc_app/features/cdc/domain/cdc_flow.dart';
import 'package:mfc_app/features/cdc/presentation/cdc_flow_screens.dart';
import 'package:mfc_app/shared/providers.dart';

const _worker = EmployeeSession(
  operatorId: 'OP-cdcw-dl-01',
  roles: [EmployeeSession.cdcWorkerRole],
  centers: ['CDC01'],
);

Dio _dio(FakeAdapter a) => createPmartDio(
  baseUrl: 'http://test.invalid/api/v1',
  sourceSystem: sourceSystem,
  tokens: TokenStore(MemoryKeyValueStore()),
  refresher: (_) async => null,
  adapter: a,
  delay: (_) async {},
);

Map<String, dynamic> _body(RequestOptions o) =>
    jsonDecode(o.data as String) as Map<String, dynamic>;

void main() {
  setUpAll(initPmartFormatting);

  Future<MockCdcFlowRepository> pump(WidgetTester t, String area) async {
    t.view
      ..physicalSize = const Size(412, 1400)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = MockCdcFlowRepository(latency: Duration.zero);
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          envProvider.overrideWithValue(PmartEnv.mock),
          authRepositoryProvider.overrideWithValue(
            MockAuthRepository(session: _worker),
          ),
          cdcFlowRepositoryProvider.overrideWithValue(repo),
          secureStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        ],
        child: const MfcApp(),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(ValueKey('cdc-area-$area')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('cdc-guide-ok')));
    await t.pumpAndSettle();
    return repo;
  }

  Future<void> tap(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(ValueKey(key)));
    await t.tap(find.byKey(ValueKey(key)));
    await t.pumpAndSettle();
  }

  Future<void> scan(WidgetTester t, String id, String code) async {
    await t.enterText(find.byKey(ValueKey(id)), code);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
  }

  FilledButton button(WidgetTester t, String key) =>
      t.widget<FilledButton>(find.byKey(ValueKey(key)));

  testWidgets('분배: TRF → 빈 BOX 스캔 → 상품 스캔·수량 → 봉인 등록, 쓴 BOX 는 거절, 다 담으면 끝', (
    t,
  ) async {
    await pump(t, 'sort');
    await tap(t, 'cdc-trf-TRF-mock-1');
    expect(find.byKey(const ValueKey('step-1')), findsOneWidget);
    await scan(t, 'cdc-box-scan', 'BOX-A1');
    expect(find.byKey(const ValueKey('step-2')), findsOneWidget);
    expect(button(t, 'cdc-sort-go').onPressed, isNull);
    await scan(t, 'cdc-sort-item-scan', 'SKU-1001');
    await t.enterText(find.byKey(const ValueKey('cdc-sort-qty')), '24');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    await tap(t, 'cdc-sort-go');
    expect(find.text('BOX-A1 봉인을 보냈어요'), findsOneWidget);
    expect(find.text('분배 24 / 집음 36'), findsOneWidget);
    // 같은 BOX 번호는 다시 못 쓴다
    await scan(t, 'cdc-box-scan', 'BOX-A1');
    expect(find.text('이미 등록된 BOX 번호예요. 다른 BOX 를 쓰세요.'), findsOneWidget);
    await scan(t, 'cdc-box-scan', 'BOX-A2');
    await scan(t, 'cdc-sort-item-scan', 'SKU-1001');
    expect(find.text('이 TRF 에 남은 상품이 아니에요'), findsOneWidget);
    for (var i = 0; i < 12; i++) {
      await scan(t, 'cdc-sort-item-scan', 'SKU-1002');
    }
    await tap(t, 'cdc-sort-go');
    expect(find.byKey(const ValueKey('cdc-sort-done')), findsOneWidget);
  });

  testWidgets('검품: BOX 스캔 → 불합격은 사유 → 서버 판정을 보인다', (t) async {
    await pump(t, 'inspect');
    await tap(t, 'cdc-trf-TRF-mock-2');
    await scan(t, 'cdc-insp-scan', 'BOX-0000');
    expect(find.text('이 TRF 의 BOX 가 아니에요'), findsOneWidget);
    await scan(t, 'cdc-insp-scan', 'BOX-26112600001');
    expect(find.byKey(const ValueKey('step-2')), findsOneWidget);
    await tap(t, 'cdc-fail');
    await tap(t, 'cdc-fail-SEAL_BROKEN');
    expect(find.text('BOX-26112600001 불합격을 보냈어요'), findsOneWidget);
    expect(
      t
          .widget<Text>(find.byKey(const ValueKey('cdc-insp-BOX-26112600001')))
          .data,
      '불합격',
    );
  });

  testWidgets('상차: 운행 → 차량 → 합격 BOX 스캔 → 등록 → 다 실으면 끝(출발 아님)', (t) async {
    await pump(t, 'load');
    await tap(t, 'cdc-trf-TRF-mock-2');
    await scan(t, 'cdc-trip-scan', 'TRIP-1');
    await scan(t, 'cdc-vehicle-scan', '경북12가3456');
    expect(button(t, 'cdc-load-go').onPressed, isNull);
    await scan(t, 'cdc-load-scan', 'BOX-26112600001');
    await scan(t, 'cdc-load-scan', 'BOX-26112600001');
    expect(find.text('이미 스캔한 BOX 예요'), findsOneWidget);
    await tap(t, 'cdc-load-go');
    expect(find.byKey(const ValueKey('cdc-load-done')), findsOneWidget);
    expect(find.text('상차는 출발이 아니에요. 출발은 따로 확정돼요'), findsOneWidget);
  });

  testWidgets('검품 합격 BOX 가 없으면 상차할 것이 없다고 안내', (t) async {
    await pump(t, 'load');
    await tap(t, 'cdc-trf-TRF-mock-1');
    expect(find.byKey(const ValueKey('cdc-empty')), findsOneWidget);
  });

  testWidgets('적치: 지시 스캔 → 다른 칸이면 이유 → 수량 → 적치 완료, 없는 지시는 안내', (t) async {
    await pump(t, 'putaway');
    await scan(t, 'cdc-pa-scan', 'PA-nope');
    expect(find.byKey(const ValueKey('cdc-putaway-error')), findsOneWidget);
    await scan(t, 'cdc-pa-scan', 'PA-mock-1');
    expect(find.byKey(const ValueKey('cdc-pa-location')), findsOneWidget);
    await scan(t, 'cdc-pa-loc-scan', 'CDC01-C-5-03-10-2-1');
    await tap(t, 'cdc-pa-reason-LOCATION_FULL');
    expect(find.text('다른 칸 · CDC01-C-5-03-10-2-1'), findsOneWidget);
    await tap(t, 'cdc-putaway-go');
    expect(find.byKey(const ValueKey('cdc-pa-done')), findsOneWidget);
    expect(find.text('상태: 완료'), findsOneWidget);
  });

  group('실서버 요청', () {
    test('분배: /sorting-results — Wave·TRF·작업자·BOX(SEALED) 내용, 멱등 키', () async {
      final a = FakeAdapter(
        (_, _) async => const FakeReply(
          202,
          body: {'requestId': 'r', 'status': 'ACCEPTED'},
        ),
      );
      final key = IdempotencyKey.generate();
      await ApiCdcFlowRepository(_dio(a)).reportSort(
        trf: MockCdcFlowRepository.trfs.first,
        workerId: 'OP-1',
        box: const CdcBoxDraft(
          lpn: 'BOX-1',
          temperatureZone: 'CHILLED',
          contents: [CdcLpnContent(sku: 'SKU-1001', lot: 'L1', qty: 5)],
        ),
        key: key,
      );
      final o = a.requests.single;
      expect(o.path, endsWith('/sorting-results'));
      expect(o.headers['Idempotency-Key'], key.value);
      expect(_body(o), {
        'waveId': 'WAV-mock-1',
        'trfId': 'TRF-mock-1',
        'workerId': 'OP-1',
        'lpns': [
          {
            'lpn': 'BOX-1',
            'unitType': 'BOX',
            'state': 'SEALED',
            'temperatureZone': 'CHILLED',
            'contents': [
              {'sku': 'SKU-1001', 'lot': 'L1', 'qty': 5},
            ],
          },
        ],
      });
    });

    test('검품·상차 본문', () async {
      final a = FakeAdapter(
        (_, _) async => const FakeReply(
          202,
          body: {'requestId': 'r', 'status': 'ACCEPTED'},
        ),
      );
      final repo = ApiCdcFlowRepository(_dio(a));
      await repo.reportInspection(
        trfId: 'TRF-1',
        inspectorId: 'OP-1',
        items: const [
          CdcInspection(lpn: 'BOX-1', passed: false, failReason: 'DAMAGE'),
        ],
        key: IdempotencyKey.generate(),
      );
      await repo.reportLoading(
        trfId: 'TRF-1',
        tripId: 'TRIP-1',
        vehicleId: 'V-1',
        dockCode: null,
        workerId: 'OP-1',
        lpns: const ['BOX-1'],
        key: IdempotencyKey.generate(),
      );
      expect(a.requests[0].path, endsWith('/inspection-results'));
      expect(_body(a.requests[0]), {
        'trfId': 'TRF-1',
        'inspectorId': 'OP-1',
        'items': [
          {'lpn': 'BOX-1', 'result': 'FAILED', 'failReason': 'DAMAGE'},
        ],
      });
      expect(a.requests[1].path, endsWith('/loading-results'));
      expect(_body(a.requests[1]), {
        'trfId': 'TRF-1',
        'tripId': 'TRIP-1',
        'vehicleId': 'V-1',
        'workerId': 'OP-1',
        'action': 'LOADED',
        'lpns': [
          {'lpn': 'BOX-1'},
        ],
      });
    });

    test(
      '적치 실행: /putaway-tasks/{id}/executions — X-Expected-Version·위치·예외 사유',
      () async {
        final a = FakeAdapter(
          (_, _) async => const FakeReply(
            202,
            body: {'requestId': 'r', 'status': 'ACCEPTED'},
          ),
        );
        const row = CdcPutawayRow(
          sku: 'SKU-1',
          lot: 'L1',
          location: 'A',
          q: 10,
          c: 0,
          u: 10,
          k: 0,
        );
        await ApiCdcFlowRepository(_dio(a)).executePutaway(
          task: const CdcPutaway(
            taskId: 'PA-1',
            state: 'DISPATCHED',
            version: 4,
            rows: [row],
          ),
          workerId: 'OP-1',
          lines: const [
            CdcPutawayLine(
              row: row,
              toLocation: 'B',
              completedQty: 10,
              exceptionReason: 'LOCATION_FULL',
            ),
          ],
          key: IdempotencyKey.generate(),
        );
        final o = a.requests.single;
        expect(o.path, endsWith('/putaway-tasks/PA-1/executions'));
        expect(o.headers['X-Expected-Version'], '4');
        expect(_body(o), {
          'workerId': 'OP-1',
          'lines': [
            {
              'sku': 'SKU-1',
              'lot': 'L1',
              'toLocationCode': 'B',
              'completedQty': 10,
              'exceptionReason': 'LOCATION_FULL',
            },
          ],
        });
      },
    );
  });
}
