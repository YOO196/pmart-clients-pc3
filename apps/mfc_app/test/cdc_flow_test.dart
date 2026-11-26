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
import 'package:mfc_app/features/inbound/data/inbound_repository.dart';
import 'package:mfc_app/features/inbound/domain/inbound.dart';
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

  testWidgets(
    '패킹(박스 닫기): TRF → 빈 BOX 스캔 → 상품 스캔·수량 → 봉인 등록, 쓴 BOX 는 거절, 다 담으면 끝',
    (t) async {
      // 분배·패킹 한 메뉴 — MFC 한 곳 몫 묶음은 칸 나누기 없이 바로 BOX 에 담기
      await pump(t, 'distribute');
      expect(find.text('MFC 한 곳(MFC-SEJ-01) · 바로 BOX 에 담아요'), findsOneWidget);
      await tap(t, 'cdc-wave-WAV-mock-2');
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
      // 다른 묶음 → 분배·패킹 묶음 목록으로
      await tap(t, 'cdc-other-trf');
      expect(find.byKey(const ValueKey('cdc-wave-WAV-mock-1')), findsOneWidget);
    },
  );

  testWidgets('분배(DAS): 묶음 → 상품 스캔 → 칸마다 넣을 수량 → 넣기 → 칸 BOX 닫기(분류 결과)', (
    t,
  ) async {
    final repo = await pump(t, 'distribute');
    await tap(t, 'cdc-wave-WAV-mock-1');
    expect(find.text('나눔 10 / 집음 52'), findsOneWidget);
    // 이미 BOX 에 다 담은 상품은 나눌 것이 없다
    await scan(t, 'cdc-dist-item-scan', 'SKU-1003');
    expect(find.text('이 묶음에 나눌 것이 남은 상품이 아니에요.'), findsOneWidget);
    await scan(t, 'cdc-dist-item-scan', 'SKU-1001');
    expect(find.text('칸 1 · MFC-BJG-01'), findsWidgets);
    await tap(t, 'cdc-put-TRF-mock-1');
    expect(find.text('나눔 34 / 집음 52'), findsOneWidget);
    // 칸이 덜 찼으면 다시 상품 스캔 — 칸마다 남은 수는 보기만
    expect(find.text('넣음 24개 · 남음 12개'), findsOneWidget);
    expect(find.byKey(const ValueKey('cdc-dist-box-scan')), findsNothing);
    await scan(t, 'cdc-dist-item-scan', 'SKU-1002');
    await tap(t, 'cdc-put-TRF-mock-1');
    // 다 찬 칸은 저절로 BOX 닫기
    expect(find.text('칸 1 BOX 바코드를 스캔하세요'), findsOneWidget);
    await scan(t, 'cdc-dist-box-scan', 'BOX-D1');
    expect(find.text('칸 1 BOX 를 닫았어요.'), findsOneWidget);
    final box = (await repo.lpns('', 'TRF-mock-1')).single;
    expect([box.lpn, box.qty], ['BOX-D1', 36]);
    await scan(t, 'cdc-dist-item-scan', 'SKU-2001');
    await tap(t, 'cdc-put-TRF-mock-2');
    await scan(t, 'cdc-dist-box-scan', 'BOX-D2');
    // 다 나누면 스캔 칸 없이 끝 — 다음은 검품
    expect(find.byKey(const ValueKey('cdc-dist-done')), findsOneWidget);
    expect(find.byKey(const ValueKey('cdc-dist-item-scan')), findsNothing);
    await tap(t, 'cdc-go-inspect');
    // 분배가 끝난 TRF(SORTED)가 검품에 나온다
    expect(find.byKey(const ValueKey('cdc-trf-TRF-mock-1')), findsOneWidget);
  });

  testWidgets('검품: 출고대기 자리 → BOX 스캔 → 온도·불합격 사유 → 서버 판정, 재포장 안내', (t) async {
    await pump(t, 'inspect');
    await tap(t, 'cdc-trf-TRF-mock-2');
    await scan(t, 'cdc-staging-scan', 'CDC01-A-6-90-01-0-1');
    expect(find.text('출고대기 자리 바코드가 아니에요(통로 91).'), findsOneWidget);
    await scan(t, 'cdc-staging-scan', 'CDC01-A-6-91-01-0-1');
    await scan(t, 'cdc-insp-scan', 'BOX-0000');
    expect(find.text('이 TRF 의 BOX 가 아니에요'), findsOneWidget);
    await scan(t, 'cdc-insp-scan', 'BOX-26112600001');
    expect(find.byKey(const ValueKey('step-3')), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('cdc-temp')), '9.5');
    await tap(t, 'cdc-fail');
    await tap(t, 'cdc-fail-TEMPERATURE');
    expect(find.text('BOX-26112600001 불합격을 보냈어요'), findsOneWidget);
    expect(
      t
          .widget<Text>(find.byKey(const ValueKey('cdc-insp-BOX-26112600001')))
          .data,
      '불합격',
    );
    expect(find.byKey(const ValueKey('cdc-repack')), findsOneWidget);
  });

  testWidgets('상차: 도크 → 그 도크의 운행 → 차량 확인 → 합격 BOX 스캔·등록 → 상차완료(출발 아님)', (
    t,
  ) async {
    final repo = await pump(t, 'load');
    await scan(t, 'cdc-dock-scan', 'CDC01-A-6-91-01-0-1');
    expect(find.text('도크 바코드가 아니에요(통로 90).'), findsOneWidget);
    await scan(t, 'cdc-dock-scan', 'CDC01-A-6-90-04-0-1');
    expect(
      find.text('CDC01-A-6-90-04-0-1 에 상차할 운행이 없어요. 배차 계획완료를 확인해 주세요.'),
      findsOneWidget,
    );
    await scan(t, 'cdc-dock-scan', 'CDC01-A-6-90-01-0-1');
    expect(find.byKey(const ValueKey('cdc-trip-card')), findsOneWidget);
    await scan(t, 'cdc-vehicle-scan', '대구99사9999');
    expect(find.text('이 운행의 차량이 아니에요.'), findsOneWidget);
    await scan(t, 'cdc-vehicle-scan', '경북12가3456');
    await scan(t, 'cdc-load-scan', 'BOX-0000');
    expect(find.text('이 운행에 실을 BOX 가 아니에요.'), findsOneWidget);
    await scan(t, 'cdc-load-scan', 'BOX-26112600001');
    await scan(t, 'cdc-load-scan', 'BOX-26112600001');
    expect(find.text('이미 스캔한 BOX 예요'), findsOneWidget);
    await tap(t, 'cdc-load-go');
    final l = (await repo.lpns('', 'TRF-mock-2')).first;
    expect([l.loaded, l.tripId], [true, 'TRIP-mock-1']);
    // 덜 실었으면 상차완료 전에 확인 — 계속 싣기를 고르면 그대로
    await tap(t, 'cdc-load-complete');
    expect(find.text('아직 안 실은 BOX 가 1개 있어요'), findsOneWidget);
    await tap(t, 'cdc-load-partial-cancel');
    expect((await repo.trip('TRIP-mock-1')).state, 'CHECKED_IN');
    await scan(t, 'cdc-load-scan', 'RT-26112600001');
    await tap(t, 'cdc-load-go');
    await tap(t, 'cdc-load-complete');
    expect(find.byKey(const ValueKey('cdc-load-partial-dialog')), findsNothing);
    // 다 실었어도 한 번 더 확인 — 취소면 그대로, 상차완료를 눌러야 끝
    expect(
      find.byKey(const ValueKey('cdc-load-confirm-dialog')),
      findsOneWidget,
    );
    await tap(t, 'cdc-load-confirm-cancel');
    expect((await repo.trip('TRIP-mock-1')).state, 'CHECKED_IN');
    await tap(t, 'cdc-load-complete');
    await tap(t, 'cdc-load-confirm-ok');
    expect(find.byKey(const ValueKey('cdc-load-done')), findsOneWidget);
    expect(find.text('상차는 출발이 아니에요. 출발은 따로 확정돼요'), findsOneWidget);
    expect((await repo.trip('TRIP-mock-1')).state, 'LOADED');
    // 상차완료면 끝 — 다른 도크가 아니라 홈으로
    expect(find.byKey(const ValueKey('cdc-other-trip')), findsNothing);
    await tap(t, 'cdc-load-finish');
    expect(find.byKey(const ValueKey('cdc-home')), findsOneWidget);
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
          CdcInspection(
            lpn: 'BOX-1',
            passed: false,
            failReason: 'TEMPERATURE',
            temperatureC: 9.5,
          ),
        ],
        key: IdempotencyKey.generate(),
      );
      await repo.reportLoading(
        trfId: 'TRF-1',
        tripId: 'TRIP-1',
        vehicleId: 'V-1',
        dockCode: 'CDC01-A-6-90-01-0-1',
        compartment: 'AMBIENT',
        workerId: 'OP-1',
        lpns: const ['BOX-1'],
        key: IdempotencyKey.generate(),
      );
      expect(a.requests[0].path, endsWith('/inspection-results'));
      expect(_body(a.requests[0]), {
        'trfId': 'TRF-1',
        'inspectorId': 'OP-1',
        'items': [
          {
            'lpn': 'BOX-1',
            'result': 'FAILED',
            'failReason': 'TEMPERATURE',
            'temperatureC': 9.5,
          },
        ],
      });
      expect(a.requests[1].path, endsWith('/loading-results'));
      expect(_body(a.requests[1]), {
        'trfId': 'TRF-1',
        'tripId': 'TRIP-1',
        'vehicleId': 'V-1',
        'dockCode': 'CDC01-A-6-90-01-0-1',
        'workerId': 'OP-1',
        'action': 'LOADED',
        'lpns': [
          {'lpn': 'BOX-1', 'compartment': 'AMBIENT'},
        ],
      });
    });

    Map<String, dynamic> trip(String state) => {
      'tripId': 'TRIP-1',
      'cdcId': 'CDC01',
      'shipDate': '2026-11-26',
      'routeId': 'RT-04',
      'tempClass': 'AMBIENT',
      'vehicleId': 'VH-5T-04A',
      'plateNo': '경북12가3456',
      'dockCode': 'CDC01-A-6-90-01-0-1',
      'state': state,
      'version': 1,
      'stops': [
        {
          'seq': 1,
          'mfcId': 'MFC-BJG-01',
          'trfIds': ['TRF-1'],
        },
      ],
    };

    test(
      '상차: 도크로 운행 찾기(입차·계획완료) → 상차완료 /trips/{id}/loading-completions',
      () async {
        final a = FakeAdapter((o, _) async {
          if (o.method == 'GET') {
            final state = o.uri.queryParameters['state'];
            return FakeReply(
              200,
              body: {
                'items': [if (state == 'SCHEDULED') trip('SCHEDULED')],
                'page': 0,
                'size': 200,
                'hasNext': false,
              },
            );
          }
          return FakeReply(200, body: trip('LOADED'));
        });
        final repo = ApiCdcFlowRepository(_dio(a));
        final t = await repo.tripAtDock('CDC01', 'cdc01-a-6-90-01-0-1');
        expect(
          [t?.tripId, t?.state, t?.trfIds],
          [
            'TRIP-1',
            'SCHEDULED',
            ['TRF-1'],
          ],
        );
        expect(a.requests.first.path, endsWith('/cdcs/CDC01/trips'));
        final key = IdempotencyKey.generate();
        final done = await repo.completeLoading(
          tripId: 'TRIP-1',
          transfers: {
            'TRF-1': ['BOX-1'],
          },
          rtCounts: const {'TRF-1': 1},
          key: key,
        );
        expect(done.state, 'LOADED');
        final o = a.requests.last;
        expect(o.path, endsWith('/trips/TRIP-1/loading-completions'));
        expect(o.headers['Idempotency-Key'], key.value);
        expect(_body(o), {
          'transfers': [
            {
              'trfId': 'TRF-1',
              'lpns': ['BOX-1'],
              'rtCount': 1,
            },
          ],
        });
      },
    );

    test('분배 목록: 박스 하나 먼저 검품돼 INSPECTED 가 됐어도 덜 담았으면 남긴다', () async {
      final repo = MockCdcFlowRepository(latency: Duration.zero);
      final before = await repo.sortTransfers('CDC01');
      expect(before.map((t) => t.trfId), contains('TRF-mock-2'));
      // TRF-mock-2: 합격 BOX(생수 10) 외 양파 6 이 아직 안 담김 — 남은 BOX 도 검품해 INSPECTED 로
      await repo.reportInspection(
        trfId: 'TRF-mock-2',
        inspectorId: 'OP-1',
        items: const [CdcInspection(lpn: 'RT-26112600001', passed: true)],
        key: IdempotencyKey.generate(),
      );
      expect(
        (await repo.transfers('CDC01', const [
          'PICKED',
          'SORTED',
        ])).map((t) => t.trfId),
        isNot(contains('TRF-mock-2')),
      );
      expect(
        (await repo.sortTransfers('CDC01')).map((t) => t.trfId),
        contains('TRF-mock-2'),
      );
    });

    test('MFC 하차 인계: 그 MFC 로 오는 운행에서 정차를 찾아 /stops/{seq}/handovers', () async {
      final a = FakeAdapter((o, _) async {
        if (o.method == 'GET') {
          return FakeReply(
            200,
            body: {
              'items': [trip('DEPARTED')],
              'page': 0,
              'size': 200,
              'hasNext': false,
            },
          );
        }
        return FakeReply(200, body: trip('DEPARTED'));
      });
      final r = await ApiInboundRepository(_dio(a)).recordHandover(
        trfId: 'TRF-1',
        mfcId: 'MFC-BJG-01',
        tripId: 'TRIP-1',
        received: const ['BOX-1', 'BOX-2'],
        damaged: const ['BOX-2'],
        key: IdempotencyKey.generate(),
      );
      expect(r, isA<InboundAccepted>());
      expect(a.requests.first.path, endsWith('/mfcs/MFC-BJG-01/inbound-trips'));
      expect(a.requests.last.path, endsWith('/trips/TRIP-1/stops/1/handovers'));
      expect(_body(a.requests.last), {
        'transfers': [
          {
            'trfId': 'TRF-1',
            'receivedLpns': ['BOX-1', 'BOX-2'],
            'damagedLpns': ['BOX-2'],
          },
        ],
      });
      // 이 TRF 정차가 없으면 보내지 않고 알린다
      final none = await ApiInboundRepository(_dio(a)).recordHandover(
        trfId: 'TRF-9',
        mfcId: 'MFC-BJG-01',
        tripId: 'TRIP-1',
        received: const ['BOX-1'],
        damaged: const [],
        key: IdempotencyKey.generate(),
      );
      expect(none, isA<InboundRejected>());
    });
  });
}
