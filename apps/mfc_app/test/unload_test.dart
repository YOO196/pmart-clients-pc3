import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:mfc_app/features/inbound/data/mock_inbound_repository.dart';
import 'package:mfc_app/features/inbound/domain/inbound.dart';
import 'package:mfc_app/features/inbound/presentation/inbound_controller.dart';
import 'package:mfc_app/features/tasks/presentation/task_controllers.dart';
import 'package:mfc_app/features/unload/data/unload_repository.dart';
import 'package:mfc_app/features/unload/presentation/unload_screen.dart';
import 'package:mfc_app/l10n/gen/app_localizations.dart';
import 'package:mfc_app/shared/providers.dart';

/// 하차(사용자 2026-11-26 "시뮬레이션에서 도착했다고 보내면 pda 에서 하차 작업을 해야 해").
void main() {
  setUpAll(initPmartFormatting);

  Future<(MockUnloadRepository, MockInboundRepository)> pump(
    WidgetTester t,
  ) async {
    t.view
      ..physicalSize = const Size(412, 1400)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final unload = MockUnloadRepository(mfcId: mockMfcId);
    final inbound = MockInboundRepository(latency: Duration.zero);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          envProvider.overrideWithValue(PmartEnv.mock),
          unloadRepositoryProvider.overrideWithValue(unload),
          inboundRepositoryProvider.overrideWithValue(inbound),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('ko'),
          home: UnloadScreen(),
        ),
      ),
    );
    await t.pumpAndSettle();
    return (unload, inbound);
  }

  Future<void> scan(WidgetTester t, String code) async {
    await t.enterText(find.byKey(const ValueKey('unload-box-scan')), code);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(ValueKey(key)));
    await t.tap(find.byKey(ValueKey(key)));
    await t.pumpAndSettle();
  }

  testWidgets('도착한 차량만 고른다 → 박스 스캔·파손 → 덜 받았으면 확인 → 정차 인계 → 입고 수령으로', (
    t,
  ) async {
    final (unload, inbound) = await pump(t);
    // 도착한 운행이 위, 오는 중은 못 고름
    final arrived = find.byKey(const ValueKey('unload-trip-TO-20261126-001'));
    expect(arrived, findsOneWidget);
    expect(
      t
          .widget<ListTile>(
            find.descendant(
              of: find.byKey(const ValueKey('unload-trip-TO-20261126-002')),
              matching: find.byType(ListTile),
            ),
          )
          .enabled,
      isFalse,
    );
    await t.tap(arrived);
    await t.pumpAndSettle();
    final boxes = inbound.peek('TRF-MOCK-001').boxList;
    expect(find.text('받은 박스 0 / ${boxes.length}'), findsOneWidget);
    await scan(t, 'BOX-99999999');
    expect(find.text('이 차량에 실려 온 박스가 아니에요.'), findsOneWidget);
    await scan(t, boxes[0].boxId);
    await scan(t, boxes[1].boxId);
    await tap(t, 'unload-damaged');
    await scan(t, boxes[1].boxId);
    expect(find.text('이미 받은 박스예요.'), findsOneWidget);
    expect(find.text('받은 박스 2 / ${boxes.length}'), findsOneWidget);
    // 덜 받았으면 확인 — 계속 받기면 보내지 않는다
    await tap(t, 'unload-handover');
    expect(find.byKey(const ValueKey('unload-missing-dialog')), findsOneWidget);
    await tap(t, 'unload-missing-keep');
    expect(unload.handovers, isEmpty);
    await tap(t, 'unload-handover');
    await tap(t, 'unload-missing-ok');
    expect(find.byKey(const ValueKey('unload-done')), findsOneWidget);
    final (received, damaged) =
        unload.handovers['TO-20261126-001']!['TRF-MOCK-001']!;
    expect(received, [boxes[0].boxId, boxes[1].boxId]);
    expect(damaged, [boxes[1].boxId]);
    expect(
      find.byKey(const ValueKey('unload-receive-TRF-MOCK-001')),
      findsOneWidget,
    );
  });

  test('실서버: 그 MFC 정차만, 정차 인계는 TRF 전부를 한 번에(/stops/{seq}/handovers)', () async {
    Map<String, dynamic> trip(String state) => {
      'tripId': 'TO-1',
      'cdcId': 'CDC01',
      'shipDate': '2026-11-26',
      'routeId': 'RT-04',
      'tempClass': 'CHILLED',
      'vehicleId': 'VH-1',
      'plateNo': '경북12가3456',
      'state': 'DEPARTED',
      'version': 1,
      'stops': [
        {
          'seq': 1,
          'mfcId': 'MFC-OTHER',
          'state': 'HANDED_OVER',
          'trfIds': ['TRF-X'],
        },
        {
          'seq': 2,
          'mfcId': 'MFC-BJG-01',
          'state': state,
          'trfIds': ['TRF-1', 'TRF-2'],
        },
      ],
    };
    final a = FakeAdapter((o, _) async {
      if (o.method == 'GET') {
        return FakeReply(
          200,
          body: {
            'items': [trip('ARRIVED')],
            'page': 0,
            'size': 200,
            'hasNext': false,
          },
        );
      }
      return FakeReply(200, body: trip('HANDED_OVER'));
    });
    final dio = createPmartDio(
      baseUrl: 'http://test.invalid/api/v1',
      sourceSystem: sourceSystem,
      tokens: TokenStore(MemoryKeyValueStore()),
      refresher: (_) async => null,
      adapter: a,
      delay: (_) async {},
    );
    final repo = ApiUnloadRepository(dio);
    final trips = await repo.trips('MFC-BJG-01');
    expect(
      [trips.single.stopSeq, trips.single.arrived, trips.single.trfIds],
      [
        2,
        true,
        ['TRF-1', 'TRF-2'],
      ],
    );
    expect(a.requests.first.path, endsWith('/mfcs/MFC-BJG-01/inbound-trips'));
    final key = IdempotencyKey.generate();
    final r = await repo.handover(
      tripId: 'TO-1',
      stopSeq: 2,
      transfers: {
        'TRF-1': (['LPN-1'], <String>[]),
        'TRF-2': (['LPN-2', 'LPN-3'], ['LPN-3']),
      },
      key: key,
    );
    expect(r, isA<InboundAccepted>());
    final o = a.requests.last;
    expect(o.path, endsWith('/trips/TO-1/stops/2/handovers'));
    expect(o.headers['Idempotency-Key'], key.value);
    expect(jsonDecode(o.data as String), {
      'transfers': [
        {
          'trfId': 'TRF-1',
          'receivedLpns': ['LPN-1'],
          'damagedLpns': <String>[],
        },
        {
          'trfId': 'TRF-2',
          'receivedLpns': ['LPN-2', 'LPN-3'],
          'damagedLpns': ['LPN-3'],
        },
      ],
    });
  });
}
