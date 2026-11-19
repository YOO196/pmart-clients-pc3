// 회수품 반입 — 반납 도착 대기에서 골라 반품 칸에 반입(mfc-inbound 0.13.0). 목(Mock) 기준.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:mfc_app/app.dart';
import 'package:mfc_app/features/stock_move/data/mock_stock_move_repository.dart';
import 'package:mfc_app/features/tasks/data/mock_task_repository.dart';
import 'package:mfc_app/features/tasks/presentation/task_controllers.dart';
import 'package:mfc_app/shared/field_repositories.dart';
import 'package:mfc_app/shared/providers.dart';

import 'support.dart';

void main() {
  setUpAll(initPmartFormatting);

  late MockStockMoveRepository repo;
  setUp(() => repo = MockStockMoveRepository(latency: Duration.zero));

  Future<void> open(WidgetTester t, String route) async {
    t.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          envProvider.overrideWithValue(PmartEnv.mock),
          taskRepositoryProvider.overrideWithValue(
            MockTaskRepository(latency: Duration.zero),
          ),
          stockMoveRepositoryProvider.overrideWithValue(repo),
          secureStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        ],
        child: const MfcApp(),
      ),
    );
    await t.pumpAndSettle();
    await openRoute(t, route);
  }

  Future<void> scanTo(WidgetTester t, String id, String code) async {
    await t.enterText(find.byKey(ValueKey(id)), code);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(ValueKey(key)));
    await t.tap(find.byKey(ValueKey(key)));
    await t.pumpAndSettle();
  }

  testWidgets('대기 목록은 종류·도착 시각·상품 × 수량 — 시스템 ID 는 보이지 않는다', (t) async {
    await open(t, '/return-arrivals');
    expect(find.text('고객 반품 회수'), findsOneWidget);
    expect(find.text('오배송 회수'), findsOneWidget);
    expect(find.text('서울우유 1L × 2'), findsOneWidget);
    expect(find.textContaining('ARR-mock'), findsNothing);
  });

  testWidgets('반품 칸 → 반납 수량 그대로 → 반입: 줄을 보내지 않고 대기 건으로, 목록에서 빠진다', (t) async {
    await open(t, '/return-arrivals');
    await tap(t, 'ri-ARR-mock-1');
    await t.enterText(
      find.byKey(const ValueKey('ri-location-scan')),
      'C-S1-01-1-01',
    );
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(find.byKey(const ValueKey('ri-scan-error')), findsOneWidget);
    await t.pumpAndSettle();
    await scanTo(t, 'ri-location-scan', 'RTN-A-01');
    expect(find.text('받은 상품을 확인하세요'), findsOneWidget);

    await tap(t, 'ri-all');
    await tap(t, 'ri-submit');
    expect(find.byKey(const ValueKey('ri-done')), findsOneWidget);
    final body = repo.receivedBodies.values.single;
    expect(body.arrivalId, 'ARR-mock-1');
    expect(body.to, 'RTN-A-01');
    expect(body.lines, isNull, reason: '대기 수량 그대로면 줄 생략 — 서버가 채운다');
    expect(repo.arrivals.map((a) => a.arrivalId), ['ARR-mock-2']);
  });

  testWidgets('받은 수량이 다르면 스캔한 줄만 보낸다(SKU·수량)', (t) async {
    await open(t, '/return-arrivals/ARR-mock-1');
    await scanTo(t, 'ri-location-scan', 'RTN-A-01');
    await scanTo(t, 'ri-item-scan', '8801115114154'); // 서울우유 1개만
    expect(find.text('1개 반입'), findsOneWidget);
    await t.enterText(
      find.byKey(const ValueKey('ri-item-scan')),
      '0000000000000',
    );
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(find.byKey(const ValueKey('ri-scan-error')), findsOneWidget);
    await t.pumpAndSettle();
    expect(find.text('1개 반입'), findsOneWidget, reason: '다른 상품은 세지 않는다');
    await tap(t, 'ri-submit');
    final lines = repo.receivedBodies.values.single.lines!;
    expect([for (final l in lines) (l.sku, l.qty)], [('E-00000001', 1)]);
  });

  testWidgets('클레임 없는 반납(오배송 회수)은 환불로 이어지지 않는다는 안내', (t) async {
    await open(t, '/return-arrivals/ARR-mock-2');
    expect(find.byKey(const ValueKey('ri-no-claim')), findsOneWidget);
  });

  testWidgets('다른 직원이 먼저 반입했으면 그렇게 안내(409 ARRIVAL_ALREADY_RECEIVED)', (
    t,
  ) async {
    repo.takenArrivals.add('ARR-mock-1');
    await open(t, '/return-arrivals/ARR-mock-1');
    await scanTo(t, 'ri-location-scan', 'RTN-A-01');
    await tap(t, 'ri-all');
    await tap(t, 'ri-submit');
    expect(find.text('다른 직원이 이미 반입했어요'), findsOneWidget);
  });

  testWidgets('결과를 모르면 다시 확인 — 같은 키로 한 번만 반입된다', (t) async {
    repo.loseNextReturnResponse = true;
    await open(t, '/return-arrivals/ARR-mock-1');
    await scanTo(t, 'ri-location-scan', 'RTN-A-01');
    await tap(t, 'ri-all');
    await tap(t, 'ri-submit');
    expect(find.byKey(const ValueKey('ri-unknown')), findsOneWidget);
    expect(find.text('다시 확인'), findsOneWidget);
    await tap(t, 'ri-submit');
    expect(find.byKey(const ValueKey('ri-done')), findsOneWidget);
    expect(repo.receivedBodies, hasLength(1), reason: '같은 키 — 반입 한 번');
  });
}
