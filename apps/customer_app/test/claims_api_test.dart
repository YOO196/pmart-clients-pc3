import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';
import 'package:pmart_core/testing.dart';

import 'package:customer_app/features/claims/data/claims_repository.dart';
import 'package:customer_app/features/claims/domain/claims.dart';
import 'package:customer_app/shared/providers.dart';

/// 주문의 처리 내역 목록 — 주문 상세의 `claims` 는 서버가 비워 보내므로 `GET /claims?orderId=` 로 받는다
/// (백엔드 안내 2026-10-31 주문 취소 §6).
void main() {
  late FakeAdapter adapter;

  ApiClaimsRepository repo(FakeReply Function(int index) reply) {
    adapter = FakeAdapter((_, i) async => reply(i));
    return ApiClaimsRepository(
      createPmartDio(
        baseUrl: 'http://test.invalid/api/v1',
        sourceSystem: sourceSystem,
        tokens: TokenStore(MemoryKeyValueStore()),
        refresher: (_) async => null,
        adapter: adapter,
        delay: (_) async {},
      ),
    );
  }

  test('listForOrder 는 GET /claims?orderId= 를 부르고 목록 항목을 그대로 옮긴다', () async {
    final list = await repo(
      (_) => const FakeReply(
        200,
        body: {
          'items': [
            {
              'claimId': 'clm-9',
              'orderId': 'o-1',
              'type': 'CANCEL',
              'state': 'IN_PROGRESS',
              'openedAt': '2026-11-03T02:00:00Z',
            },
            {'claimId': 'clm-8', 'orderId': 'o-1', 'type': 'RETURN'},
          ],
        },
      ),
    ).listForOrder('o-1');

    final req = adapter.requests.single;
    expect(req.method, 'GET');
    expect(req.uri.path, '/api/v1/claims');
    expect(req.uri.queryParameters, {'orderId': 'o-1', 'size': '50'});

    expect(list.map((c) => c.claimId), ['clm-9', 'clm-8']);
    expect(list.first.type, ClaimType.cancel);
    expect(list.first.state, ClaimState.inProgress);
    expect(list.first.openedAt, DateTime.utc(2026, 11, 3, 2));
    expect(list.last.type, ClaimType.returnItems);
    expect(list.last.state, ClaimState.unknown);
    expect(list.last.openedAt, isNull);
  });

  test('목록 본문이 없으면 빈 목록이 아니라 실패다', () async {
    await expectLater(
      repo((_) => const FakeReply(200, body: null)).listForOrder('o-1'),
      throwsA(isA<ContractViolationFailure>()),
    );
  });
}
