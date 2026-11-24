// SSE(text/event-stream) 줄 풀기 — EventSource 는 Authorization 헤더를 못 넣어 fetch 스트림으로 읽는다(mfc-inventory 0.46.0 `/stock-stream` 설명).
// 규격(HTML Living Standard "Server-sent events")에서 쓰는 것만: `event:`·`id:`·`data:`(여러 줄이면 \n 으로 잇기), `:` 로 시작하는 줄은 주석(heartbeat `: hb`),
// 빈 줄 = 이벤트 끝. 줄 끝은 \n·\r\n·\r 모두. `retry:` 는 쓰지 않는다(다시 접속 간격은 화면이 정한다).

export interface SseMessage {
  readonly event: string;
  readonly id: string | null;
  readonly data: string;
}

/** 조각(chunk)을 받아 다 찬 이벤트를 돌려준다. 주석·빈 이벤트는 돌려주지 않는다. */
export function createSseParser() {
  let buffer = '';
  let event = '';
  let id: string | null = null;
  let data: string[] = [];

  const line = (raw: string): SseMessage | null => {
    if (raw === '') {
      const done = data.length > 0 ? { event: event || 'message', id, data: data.join('\n') } : null;
      event = '';
      id = null;
      data = [];
      return done;
    }
    if (raw.startsWith(':')) return null;
    const colon = raw.indexOf(':');
    const field = colon < 0 ? raw : raw.slice(0, colon);
    const value = colon < 0 ? '' : raw.slice(colon + 1).replace(/^ /, '');
    if (field === 'event') event = value;
    else if (field === 'id') id = value;
    else if (field === 'data') data.push(value);
    return null;
  };

  return (chunk: string): SseMessage[] => {
    buffer += chunk;
    const out: SseMessage[] = [];
    for (;;) {
      const m = /\r\n|\r|\n/.exec(buffer);
      // 조각이 \r 로 끝나면 다음 조각의 \n 과 짝일 수 있어 기다린다
      if (!m || (m[0] === '\r' && m.index === buffer.length - 1)) break;
      const msg = line(buffer.slice(0, m.index));
      buffer = buffer.slice(m.index + m[0].length);
      if (msg) out.push(msg);
    }
    return out;
  };
}
