import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_api_mfc_fulfillment/pmart_api_mfc_fulfillment.dart'
    as api;
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:mfc_app/app.dart';
import 'package:mfc_app/features/tasks/data/mock_task_repository.dart';
import 'package:mfc_app/features/tasks/data/task_repository.dart';
import 'package:mfc_app/features/tasks/domain/task_list.dart';
import 'package:mfc_app/features/tasks/presentation/task_controllers.dart';
import 'package:mfc_app/shared/providers.dart';

import 'support.dart';

void main() {
  setUpAll(initPmartFormatting);

  test('계약 picks·칸 상태·안내·목록 headline 을 그대로 옮긴다', () {
    final d = taskDetailFromContract(
      api.TaskDetail.fromJson({
        'taskId': 't-1',
        'taskType': 'PICK',
        'state': 'IN_PROGRESS',
        'version': 1,
        'lines': [
          {
            'taskLineId': 'l-1',
            'orderLineId': 'ol-1',
            'sku': 'S-1',
            'plannedQty': 3,
            'completedQty': 0,
            'cancelledQty': 0,
            'remainingQty': 3,
            'picks': [
              {
                'lotId': 'LOT-1',
                'remainingQty': 3,
                'visitSeq': 2,
                'unallocatedQty': 3,
                'pickStatus': 'NOT_FOUND',
                'notice': '어느 칸에서도 못 찾음 — 센터 관리자 확인',
                'locations': <Object>[],
              },
            ],
          },
        ],
      }),
    );
    final p = d.lines.single.picks.single;
    expect(p.status, PickStatus.notFound);
    expect(p.visitSeq, 2);
    expect(p.unallocatedQty, 3);
    expect(p.notice, '어느 칸에서도 못 찾음 — 센터 관리자 확인');
    expect(p.locations, isEmpty);

    final list = taskListFromContract(
      api.ListTasks200Response.fromJson({
        'items': [
          {
            'taskId': 't-1',
            'taskType': 'PICK',
            'state': 'ASSIGNED',
            'remainingQty': 3,
            'headline': {'productName': '서울우유 1L', 'otherLineCount': 4},
          },
        ],
        'page': {'nextCursor': null, 'size': 50},
        'asOf': {'asOf': '2026-11-10T00:00:00Z', 'freshness': 'CURRENT'},
      }),
    );
    expect(list.tasks.single.headlineProduct, '서울우유 1L');
    expect(list.tasks.single.otherLineCount, 4);
  });

  testWidgets('피킹에 방문 순서·배정 칸·칸 상태·서버 안내', (t) async {
    t.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = MockTaskRepository(latency: Duration.zero);
    await t.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          envProvider.overrideWithValue(PmartEnv.mock),
          taskRepositoryProvider.overrideWithValue(repo),
          secureStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        ],
        child: const MfcApp(),
      ),
    );
    await t.pumpAndSettle();
    // 작업 상세 없이 — 열면 시작 판정을 받고 바로 피킹.
    await openRoute(t, '/tasks/task-mock-1');

    Future<void> scanTo(String id, String code) async {
      await t.enterText(find.byKey(ValueKey(id)), code);
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pumpAndSettle();
    }

    // 장바구니 → 첫 칸: 1번째 방문, 배정 칸에서 1개.
    await scanTo('cart-scan', 'CRT-C-01');
    expect(
      t.widget<Text>(find.byKey(const ValueKey('pick-location'))).data,
      'C-S1-01-1-01',
    );
    expect(find.textContaining('1번째'), findsOneWidget);
    expect(find.text('이 칸에서 1개 · 담음 0'), findsOneWidget);
    expect(find.byKey(const ValueKey('pick-status-warning')), findsNothing);

    // 칸 → 요거트를 담으면 바로 보내고 우유(2번째, 일부만 칸 정해짐).
    await scanTo('pick-loc-scan', 'C-S1-01-1-01');
    await scanTo('scan-field', MockTaskRepository.yogurtBarcode);

    expect(find.textContaining('2번째'), findsOneWidget);
    expect(find.text('일부만 칸이 정해졌어요'), findsOneWidget);
    expect(find.text('1개는 칸을 못 정했어요 — 다른 칸 확인'), findsOneWidget);
    expect(
      t.widget<Text>(find.byKey(const ValueKey('pick-location'))).data,
      'C-S1-02-2-05',
    );
    expect(find.text('이 칸에서 1개 · 담음 0'), findsOneWidget);
    expect(find.text('같은 LOT 다른 칸: C-S2-04-1-10'), findsOneWidget);
  });
}
