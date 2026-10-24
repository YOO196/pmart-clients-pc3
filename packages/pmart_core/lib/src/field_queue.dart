import 'dart:convert';

import 'package:meta/meta.dart';

import 'idempotency.dart';
import 'storage.dart';

/// 현장 실적 한 건의 전송 상태(Flutter 규칙: 전송 대기/확정 대기/반영/거절/확인 중).
enum QueueItemState {
  /// 아직 서버에 보내지 못했다(오프라인 포함). 같은 키로 보낸다.
  queued,

  /// 서버가 접수했다(ACCEPTED). 재고 반영 등 확정을 기다린다.
  awaitingConfirm,

  /// 서버가 반영을 확정했다.
  applied,

  /// 서버가 거절을 확정했다. 다시 보내지 않는다.
  rejected,

  /// 보냈지만 결과를 모른다. 같은 키 재전송 또는 결과 조회로만 해소한다.
  /// 이 동안 물리 작업을 다시 하지 않게 안내한다.
  checking,
}

/// 내구 저장되는 현장 명령. [id] 가 곧 Idempotency-Key(=requestId)다.
@immutable
final class QueueItem {
  const QueueItem({
    required this.id,
    required this.kind,
    required this.targetId,
    required this.payload,
    required this.state,
    required this.createdAt,
    this.resultId,
    this.rejectCode,
    this.attempts = 0,
  });

  factory QueueItem.fromJson(Map<String, dynamic> json) => QueueItem(
    id: json['id'] as String,
    kind: json['kind'] as String,
    targetId: json['targetId'] as String,
    payload: (json['payload'] as Map).cast<String, Object?>(),
    state: QueueItemState.values.byName(json['state'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
    resultId: json['resultId'] as String?,
    rejectCode: json['rejectCode'] as String?,
    attempts: (json['attempts'] as int?) ?? 0,
  );

  final String id;

  /// 명령 종류(예: pick-execution, handover-commit). 어느 API 로 보낼지 앱이 정한다.
  final String kind;

  /// 대상(작업·포장 ID). 개인정보를 넣지 않는다.
  final String targetId;

  /// 요청 본문 재료. 토큰·비밀번호를 넣지 않는다.
  final Map<String, Object?> payload;
  final QueueItemState state;
  final DateTime createdAt;

  /// 서버가 준 결과 식별자(executionId 등). 확정 조회에 쓴다.
  final String? resultId;
  final String? rejectCode;
  final int attempts;

  IdempotencyKey get key => IdempotencyKey(id);

  bool get isOpen =>
      state != QueueItemState.applied && state != QueueItemState.rejected;

  QueueItem copyWith({
    QueueItemState? state,
    String? resultId,
    String? rejectCode,
    int? attempts,
  }) => QueueItem(
    id: id,
    kind: kind,
    targetId: targetId,
    payload: payload,
    state: state ?? this.state,
    createdAt: createdAt,
    resultId: resultId ?? this.resultId,
    rejectCode: rejectCode ?? this.rejectCode,
    attempts: attempts ?? this.attempts,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'targetId': targetId,
    'payload': payload,
    'state': state.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'resultId': ?resultId,
    'rejectCode': ?rejectCode,
    'attempts': attempts,
  };
}

/// 보낸 결과.
@immutable
sealed class SendResult {
  const SendResult();
}

/// 접수됨. 확정은 조회로 기다린다.
final class SendAccepted extends SendResult {
  const SendAccepted({this.resultId});

  final String? resultId;
}

final class SendApplied extends SendResult {
  const SendApplied({this.resultId});

  final String? resultId;
}

final class SendRejected extends SendResult {
  const SendRejected(this.code);

  final String code;
}

/// 서버에 닿았는지 모른다(타임아웃·5xx). 같은 키로 다시 보낼 대상이다.
final class SendUnknown extends SendResult {
  const SendUnknown();
}

/// 보내지 못했다(연결 없음). 전송 대기로 둔다.
final class SendOffline extends SendResult {
  const SendOffline();
}

/// 확정 조회 결과.
enum ConfirmResult { applied, rejected, pending, unknown }

/// 현장 실적 내구 큐. 앱이 꺼져도 남고, 재전송은 항상 같은 키다.
///
/// 임시 저장분을 완료로 표시하지 않는다. [QueueItemState.applied] 만 반영이다.
final class FieldQueue {
  FieldQueue(this._store, {String name = 'default'})
    : _key = 'pmart.fieldQueue.$name';

  final SecureKeyValueStore _store;
  final String _key;

  Future<List<QueueItem>> items() async {
    final raw = await _store.read(_key);
    if (raw == null || raw.isEmpty) return const [];
    return [
      for (final e in jsonDecode(raw) as List<dynamic>)
        QueueItem.fromJson(e as Map<String, dynamic>),
    ];
  }

  Future<void> _save(List<QueueItem> items) =>
      _store.write(_key, jsonEncode([for (final i in items) i.toJson()]));

  Future<void> _update(QueueItem item) async {
    final all = await items();
    await _save([for (final i in all) i.id == item.id ? item : i]);
  }

  /// 새 실적을 저장한다(사용자 행위 1회 = 새 키).
  Future<QueueItem> enqueue({
    required String kind,
    required String targetId,
    required Map<String, Object?> payload,
    DateTime? now,
  }) async {
    final item = QueueItem(
      id: IdempotencyKey.generate().value,
      kind: kind,
      targetId: targetId,
      payload: payload,
      state: QueueItemState.queued,
      createdAt: (now ?? DateTime.now()).toUtc(),
    );
    await _save([...await items(), item]);
    return item;
  }

  /// 전송 대기·확인 중인 실적을 같은 키로 보낸다. 거절·반영은 다시 보내지 않는다.
  Future<void> flush(Future<SendResult> Function(QueueItem item) send) async {
    for (final item in await items()) {
      if (item.state != QueueItemState.queued &&
          item.state != QueueItemState.checking) {
        continue;
      }
      final result = await send(item);
      final attempts = item.attempts + 1;
      await _update(switch (result) {
        SendAccepted(:final resultId) => item.copyWith(
          state: QueueItemState.awaitingConfirm,
          resultId: resultId,
          attempts: attempts,
        ),
        SendApplied(:final resultId) => item.copyWith(
          state: QueueItemState.applied,
          resultId: resultId,
          attempts: attempts,
        ),
        SendRejected(:final code) => item.copyWith(
          state: QueueItemState.rejected,
          rejectCode: code,
          attempts: attempts,
        ),
        SendUnknown() => item.copyWith(
          state: QueueItemState.checking,
          attempts: attempts,
        ),
        SendOffline() => item.copyWith(attempts: attempts),
      });
    }
  }

  /// 확정 대기·확인 중인 실적의 결과를 조회한다(다시 보내지 않는다).
  Future<void> confirm(
    Future<ConfirmResult> Function(QueueItem item) lookup,
  ) async {
    for (final item in await items()) {
      if (item.state != QueueItemState.awaitingConfirm &&
          item.state != QueueItemState.checking) {
        continue;
      }
      final r = await lookup(item);
      final next = switch (r) {
        ConfirmResult.applied => QueueItemState.applied,
        ConfirmResult.rejected => QueueItemState.rejected,
        // 접수 확인 중이면 그대로, 모르면 확인 중(같은 키 재전송 대상).
        ConfirmResult.pending => item.state,
        ConfirmResult.unknown => item.state,
      };
      if (next != item.state) await _update(item.copyWith(state: next));
    }
  }

  /// 반영·거절이 끝난 항목을 지운다(화면에서 확인한 뒤).
  Future<void> clearSettled() async {
    await _save([
      for (final i in await items())
        if (i.isOpen) i,
    ]);
  }
}
