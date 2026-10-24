import 'package:flutter_test/flutter_test.dart';
import 'package:pmart_core/pmart_core.dart';

void main() {
  late MemoryKeyValueStore store;
  late FieldQueue queue;

  setUp(() {
    store = MemoryKeyValueStore();
    queue = FieldQueue(store, name: 'test');
  });

  Future<QueueItem> add() =>
      queue.enqueue(kind: 'pick', targetId: 'task-1', payload: {'qty': 2});

  test('앱을 다시 켜도(새 인스턴스) 저장된 실적이 남는다', () async {
    final item = await add();

    final reopened = FieldQueue(store, name: 'test');
    final items = await reopened.items();

    expect(items.single.id, item.id);
    expect(items.single.state, QueueItemState.queued);
    expect(items.single.payload, {'qty': 2});
  });

  test('오프라인이면 전송 대기로 남고, 다시 보낼 때 같은 키를 쓴다', () async {
    final item = await add();
    final sentKeys = <String>[];

    await queue.flush((i) async {
      sentKeys.add(i.key.value);
      return const SendOffline();
    });
    expect((await queue.items()).single.state, QueueItemState.queued);

    await queue.flush((i) async {
      sentKeys.add(i.key.value);
      return const SendAccepted(resultId: 'exe-1');
    });

    expect(sentKeys, [item.id, item.id]);
    final after = (await queue.items()).single;
    expect(after.state, QueueItemState.awaitingConfirm);
    expect(after.resultId, 'exe-1');
    expect(after.attempts, 2);
  });

  test('결과 불명은 확인 중이고, 같은 키 재전송·조회로만 해소한다', () async {
    await add();
    await queue.flush((_) async => const SendUnknown());
    expect((await queue.items()).single.state, QueueItemState.checking);

    await queue.confirm((_) async => ConfirmResult.unknown);
    expect((await queue.items()).single.state, QueueItemState.checking);

    await queue.confirm((_) async => ConfirmResult.applied);
    expect((await queue.items()).single.state, QueueItemState.applied);
  });

  test('거절·반영된 실적은 다시 보내지 않는다', () async {
    await add();
    await queue.flush((_) async => const SendRejected('VERSION_CONFLICT'));
    var sent = 0;

    await queue.flush((_) async {
      sent++;
      return const SendApplied();
    });

    expect(sent, 0);
    final item = (await queue.items()).single;
    expect(item.state, QueueItemState.rejected);
    expect(item.rejectCode, 'VERSION_CONFLICT');
  });

  test('확정 대기는 반영 확인 전까지 반영으로 보지 않는다', () async {
    await add();
    await queue.flush((_) async => const SendAccepted(resultId: 'exe-1'));

    await queue.confirm((_) async => ConfirmResult.pending);
    expect((await queue.items()).single.state, QueueItemState.awaitingConfirm);

    await queue.confirm((_) async => ConfirmResult.applied);
    expect((await queue.items()).single.state, QueueItemState.applied);

    await queue.clearSettled();
    expect(await queue.items(), isEmpty);
  });
}
