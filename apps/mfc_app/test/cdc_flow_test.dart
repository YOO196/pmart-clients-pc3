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
    return repo;
  }

  Future<void> tap(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(ValueKey(key)));
    await t.tap(find.byKey(ValueKey(key)));
    await t.pumpAndSettle();
  }

  FilledButton button(WidgetTester t, String key) =>
      t.widget<FilledButton>(find.byKey(ValueKey(key)));

  testWidgets('분배: TRF 고르기 → BOX 번호·담은 수량 → 봉인 등록 → 서버 BOX 목록, 다 담으면 끝', (
    t,
  ) async {
    await pump(t, 'sort');
    expect(find.byKey(const ValueKey('cdc-trf-TRF-mock-2')), findsOneWidget);
    await tap(t, 'cdc-trf-TRF-mock-1');
    expect(button(t, 'cdc-sort-go').onPressed, isNull); // BOX 번호 없음
    await t.enterText(find.byKey(const ValueKey('cdc-box')), 'BOX-A1');
    await t.enterText(find.byKey(const ValueKey('cdc-sort-qty-SKU-1002')), '0');
    await t.pumpAndSettle();
    await tap(t, 'cdc-sort-go');
    expect(find.byKey(const ValueKey('cdc-notice')), findsOneWidget);
    expect(find.byKey(const ValueKey('cdc-lpn-BOX-A1')), findsOneWidget);
    // 우유는 다 담았고 두부만 남는다
    expect(find.byKey(const ValueKey('cdc-sort-SKU-1001')), findsNothing);
    await t.enterText(find.byKey(const ValueKey('cdc-box')), 'BOX-A1');
    await t.pumpAndSettle();
    await tap(t, 'cdc-sort-go');
    expect(find.text('이미 등록된 BOX 번호예요. 다른 BOX 를 쓰세요.'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('cdc-box')), 'BOX-A2');
    await t.pumpAndSettle();
    await tap(t, 'cdc-sort-go');
    expect(find.byKey(const ValueKey('cdc-sort-done')), findsOneWidget);
  });

  testWidgets('검품: 불합격은 사유를 골라야 보낼 수 있고, 보낸 뒤 서버 판정을 보인다', (t) async {
    await pump(t, 'inspect');
    await tap(t, 'cdc-trf-TRF-mock-2');
    expect(
      find.byKey(const ValueKey('cdc-insp-BOX-26112600001')),
      findsOneWidget,
    );
    expect(button(t, 'cdc-inspect-go').onPressed, isNull);
    await t.tap(
      find.descendant(
        of: find.byKey(const ValueKey('cdc-judge-BOX-26112600001')),
        matching: find.text('불합격'),
      ),
    );
    await t.pumpAndSettle();
    expect(button(t, 'cdc-inspect-go').onPressed, isNull);
    await tap(t, 'cdc-fail-BOX-26112600001');
    await t.tap(find.text('봉인 훼손').last);
    await t.pumpAndSettle();
    await tap(t, 'cdc-inspect-go');
    expect(
      t
          .widget<Text>(find.byKey(const ValueKey('cdc-insp-BOX-26112600001')))
          .data,
      '불합격',
    );
  });

  testWidgets('상차: 운행·차량 번호와 합격 BOX → 상차 등록 → 실음 표시', (t) async {
    await pump(t, 'load');
    await tap(t, 'cdc-trf-TRF-mock-2');
    expect(button(t, 'cdc-load-go').onPressed, isNull);
    await t.enterText(find.byKey(const ValueKey('cdc-trip')), 'TRIP-1');
    await t.enterText(find.byKey(const ValueKey('cdc-vehicle')), '경북12가3456');
    await t.pumpAndSettle();
    await tap(t, 'cdc-load-go');
    expect(
      find.byKey(const ValueKey('cdc-loaded-BOX-26112600001')),
      findsOneWidget,
    );
  });

  testWidgets('검품 합격 BOX 가 없으면 상차할 것이 없다고 안내', (t) async {
    await pump(t, 'load');
    await tap(t, 'cdc-trf-TRF-mock-1');
    expect(find.byKey(const ValueKey('cdc-empty')), findsOneWidget);
  });

  testWidgets('적치: 지시 번호로 열기 → 위치를 바꾸면 이유가 필요 → 보내면 서버 진행(완료)', (t) async {
    await pump(t, 'putaway');
    await t.enterText(find.byKey(const ValueKey('cdc-putaway-id')), 'PA-nope');
    await t.pumpAndSettle();
    await tap(t, 'cdc-putaway-open');
    expect(find.byKey(const ValueKey('cdc-putaway-error')), findsOneWidget);

    await t.enterText(
      find.byKey(const ValueKey('cdc-putaway-id')),
      'PA-mock-1',
    );
    await t.pumpAndSettle();
    await tap(t, 'cdc-putaway-open');
    expect(find.text('지시 120 · 완료 0 · 남음 120'), findsOneWidget);
    await t.enterText(
      find.byKey(const ValueKey('cdc-pa-loc-SKU-1001')),
      'CDC01-R-6-03-03-1-1',
    );
    await t.pumpAndSettle();
    expect(button(t, 'cdc-putaway-go').onPressed, isNull);
    await tap(t, 'cdc-pa-reason-SKU-1001');
    await t.tap(find.text('칸 가득 참').last);
    await t.pumpAndSettle();
    await tap(t, 'cdc-putaway-go');
    expect(find.text('상태: 완료'), findsOneWidget);
    expect(find.text('지시 120 · 완료 120 · 남음 0'), findsOneWidget);
    expect(find.byKey(const ValueKey('cdc-putaway-go')), findsNothing);
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
