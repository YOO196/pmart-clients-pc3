import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_ui/pmart_ui.dart';

import 'package:customer_app/features/claims/data/mock_claims_repository.dart';

import 'support/app_harness.dart';

/// 목 클레임 하나(서버 모양 그대로).
Map<String, Object?> _claim(
  String id, {
  String type = 'CANCEL',
  String state = 'CLOSED',
  List<Map<String, Object?>> refunds = const [],
}) => {
  'claimId': id,
  'version': 1,
  'orderId': 'ORD-$id',
  'type': type,
  'state': state,
  'openedAt': '2026-11-19T03:00:00Z',
  'reason': 'CHANGE_OF_MIND',
  'lines': <Object?>[],
  'refunds': refunds,
};

Future<void> _loginAndOpen(WidgetTester t) async {
  await t.tap(find.text('마이페이지').last);
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('my-login')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('login-kakao')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('my-claims')));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(initPmartFormatting);

  testWidgets('비회원 마이에는 취소·반품 내역이 없다', (t) async {
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await t.tap(find.text('마이페이지').last);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('my-claims')), findsNothing);
  });

  testWidgets('환불 요약: 진행 중은 완료로 보이지 않고, 완료·실패를 나눠 보인다. 누르면 상세', (t) async {
    final repo = MockClaimsRepository(latency: Duration.zero);
    repo.claims
      ..['c-done'] = _claim(
        'c-done',
        refunds: [
          {
            'state': 'COMPLETED',
            'pgResult': 'SUCCESS',
            'amount': 12000,
            'completedAt': '2026-11-19T04:00:00Z',
          },
        ],
      )
      ..['c-pg'] = _claim(
        'c-pg',
        state: 'IN_PROGRESS',
        refunds: [
          {'state': 'PG_PENDING', 'pgResult': 'UNKNOWN', 'amount': 5000},
        ],
      )
      ..['c-fail'] = _claim(
        'c-fail',
        type: 'RETURN',
        state: 'IN_PROGRESS',
        refunds: [
          {'state': 'FAILED', 'pgResult': 'FAILED', 'amount': 3000},
        ],
      )
      ..['c-none'] = _claim('c-none', state: 'WITHDRAWN');
    await t.pumpWidget(testApp(const [], claims: repo));
    await t.pumpAndSettle();
    await _loginAndOpen(t);

    expect(find.text('환불 완료 12,000원'), findsOneWidget);
    expect(find.text('환불 진행 중 5,000원'), findsOneWidget);
    expect(find.text('환불 완료 5,000원'), findsNothing);
    expect(find.text('환불에 문제가 있어요. 고객센터에서 도와드릴게요'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('my-claim-refund-c-none')),
      findsNothing,
    ); // 환불 없음은 줄을 붙이지 않는다
    expect(find.text('반품 요청'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('my-claim-c-done')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('my-claims-list')), findsNothing);
  });

  testWidgets('한 쪽씩 받아 끝 가까이서 다음 쪽을 이어 받는다', (t) async {
    final repo = MockClaimsRepository(latency: Duration.zero)..myPageSize = 2;
    for (var i = 0; i < 5; i++) {
      repo.claims['c$i'] = _claim('c$i');
    }
    await t.pumpWidget(testApp(const [], claims: repo));
    await t.pumpAndSettle();
    await _loginAndOpen(t);

    for (var i = 0; i < 5; i++) {
      expect(find.byKey(ValueKey('my-claim-c$i')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('my-claims-load-more')), findsNothing);
  });

  testWidgets('조회 실패는 "내역 없음"이 아니라 오류로 보이고, 다시 시도하면 보인다', (t) async {
    final repo = MockClaimsRepository(latency: Duration.zero)
      ..failNextMine = true
      ..claims['c1'] = _claim('c1');
    await t.pumpWidget(testApp(const [], claims: repo));
    await t.pumpAndSettle();
    await _loginAndOpen(t);

    expect(find.byKey(const ValueKey('my-claims-empty')), findsNothing);
    expect(find.byKey(const ValueKey('my-claim-c1')), findsNothing);
    await t.tap(find.text('다시 시도하기'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('my-claim-c1')), findsOneWidget);
  });

  testWidgets('내역이 없으면 빈 화면 문구', (t) async {
    await t.pumpWidget(testApp(const []));
    await t.pumpAndSettle();
    await _loginAndOpen(t);
    expect(find.byKey(const ValueKey('my-claims-empty')), findsOneWidget);
  });
}
