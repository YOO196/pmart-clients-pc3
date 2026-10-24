import 'dart:convert';

import 'package:meta/meta.dart';

import 'command_response.dart';
import 'failure.dart';
import 'interceptors.dart' show Delay;
import 'storage.dart';

/// 결과 불명 해소 결과.
@immutable
sealed class Resolution {
  const Resolution();
}

/// 서버가 결과를 확정했다(APPLIED 또는 REJECTED).
final class Resolved extends Resolution {
  const Resolved(this.response);

  final CommandResponse response;
}

/// 아직 모른다. 화면은 "확인 중"을 유지하고 같은 행위를 다시 실행하지 못하게 한다.
///
/// 실패로 확정하지 않는다. 재진입·앱 재시작 때 다시 조회한다.
final class StillUnknown extends Resolution {
  const StillUnknown({this.last, this.lastFailure});

  /// 마지막으로 받은 응답(ACCEPTED/UNKNOWN_RESULT). 조회가 모두 실패했으면 null.
  final CommandResponse? last;
  final PmartFailure? lastFailure;
}

/// 짝 조회(`GET …/{requestId}`)로 결과 불명을 해소한다(client-architecture §5.3).
///
/// 화면이 열려 있는 동안 짧게 폴링하는 용도다. 서버의 재조회 일정(1분×5→상신→15분)을
/// 흉내 내지 않는다.
final class ResultResolver {
  ResultResolver({
    this.interval = const Duration(seconds: 2),
    this.maxAttempts = 5,
    Delay? delay,
  }) : _delay = delay ?? ((d) => Future<void>.delayed(d));

  final Duration interval;
  final int maxAttempts;
  final Delay _delay;

  Future<Resolution> resolve(Future<CommandResponse> Function() query) async {
    CommandResponse? last;
    PmartFailure? lastFailure;
    for (var i = 0; i < maxAttempts; i++) {
      if (i > 0) await _delay(interval);
      try {
        final response = await query();
        if (response.status.isFinal) return Resolved(response);
        last = response;
      } on PmartFailure catch (f) {
        // 조회 실패·404(서버가 아직 요청을 모름)도 "실패"가 아니라 "아직 모름"이다.
        lastFailure = f;
      }
    }
    return StillUnknown(last: last, lastFailure: lastFailure);
  }
}

/// 진행 중인 명령. 앱이 재시작돼도 원결과를 조회할 수 있게 저장한다.
@immutable
final class PendingCommand {
  const PendingCommand({
    required this.requestId,
    required this.kind,
    required this.targetId,
    required this.startedAt,
  });

  factory PendingCommand.fromJson(Map<String, dynamic> json) => PendingCommand(
    requestId: json['requestId'] as String,
    kind: json['kind'] as String,
    targetId: json['targetId'] as String,
    startedAt: DateTime.parse(json['startedAt'] as String),
  );

  /// = Idempotency-Key.
  final String requestId;

  /// 명령 종류(예: checkout, cancel, handover). 어느 짝 조회를 쓸지 앱이 정한다.
  final String kind;

  /// 대상 aggregate ID(주문·패키지 등). 개인정보를 넣지 않는다.
  final String targetId;
  final DateTime startedAt;

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'kind': kind,
    'targetId': targetId,
    'startedAt': startedAt.toUtc().toIso8601String(),
  };
}

/// 진행 중 명령 저장소. 보안 저장소 하나에 JSON 목록으로 둔다.
final class PendingCommandStore {
  PendingCommandStore(this._store);

  static const _key = 'pmart.pendingCommands';

  final SecureKeyValueStore _store;

  Future<List<PendingCommand>> list() async {
    final raw = await _store.read(_key);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return [
      for (final e in decoded)
        PendingCommand.fromJson(e as Map<String, dynamic>),
    ];
  }

  Future<void> add(PendingCommand command) async {
    final current = await list();
    await _save([
      for (final c in current)
        if (c.requestId != command.requestId) c,
      command,
    ]);
  }

  Future<void> remove(String requestId) async {
    final current = await list();
    await _save([
      for (final c in current)
        if (c.requestId != requestId) c,
    ]);
  }

  Future<void> _save(List<PendingCommand> commands) =>
      _store.write(_key, jsonEncode([for (final c in commands) c.toJson()]));
}
