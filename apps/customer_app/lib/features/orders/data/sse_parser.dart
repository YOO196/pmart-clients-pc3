import 'package:flutter/foundation.dart';

/// SSE(text/event-stream) 메시지 하나.
@immutable
class SseMessage {
  const SseMessage({required this.data, this.event, this.id});

  /// 마지막으로 받은 `id`(재연결 때 `Last-Event-ID`). 메시지마다 다시 오지 않아도 이어진다.
  final String? id;

  /// `event` 필드. 없으면 null(기본 "message").
  final String? event;

  /// `data` 줄들을 줄바꿈으로 이은 값.
  final String data;
}

/// 줄 단위 SSE 파서(WHATWG event-stream 해석 규칙의 필요한 부분).
///
/// - 빈 줄에서 메시지를 내보낸다. `data` 가 없으면 내보내지 않는다.
/// - `:` 로 시작하는 줄은 주석(연결 유지용)이다.
/// - `필드: 값` 의 콜론 뒤 공백 하나는 버린다. `retry` 와 모르는 필드는 무시한다.
/// - 줄 끝 `\r` 은 호출 쪽(LineSplitter)이 떼지만, 남아 있어도 지운다.
class SseParser {
  final _data = <String>[];
  String? _event;
  String? _lastId;

  String? get lastEventId => _lastId;

  /// 한 줄을 넣는다. 메시지가 끝났으면 돌려준다.
  SseMessage? add(String rawLine) {
    final line = rawLine.endsWith('\r')
        ? rawLine.substring(0, rawLine.length - 1)
        : rawLine;
    if (line.isEmpty) return _dispatch();
    if (line.startsWith(':')) return null;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'data':
        _data.add(value);
      case 'event':
        _event = value;
      case 'id':
        // NULL 문자가 든 id 는 무시한다(규격).
        if (!value.contains('\u0000')) _lastId = value;
    }
    return null;
  }

  SseMessage? _dispatch() {
    if (_data.isEmpty) {
      _event = null;
      return null;
    }
    final m = SseMessage(data: _data.join('\n'), event: _event, id: _lastId);
    _data.clear();
    _event = null;
    return m;
  }
}
