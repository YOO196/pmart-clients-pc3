// 재고 실시간 스트림 연결 — mfc-inventory 0.46.0 `GET /stock-stream?mfcId=`(SSE, IV-7). 화면 설계 docs/apps/mfc-backoffice-web.md §4-16.
// - 연결은 기존 API 클라이언트(pmartFetch — Authorization·X-Source-System·401 갱신)를 parseAs 'stream' 으로 써서 연다.
// - 끊기면(서버가 30분에 닫음·heartbeat 15초 없음·네트워크) 1·2·5·10·30초 늘려 가며 다시. 403 이면 멈춘다(권한 밖 센터).
// - Last-Event-ID 이어 받기는 같은 출처일 때만 보낸다: LAN 화면(:8445)→게이트웨이(:8443)는 교차 출처인데 게이트웨이 CORS 허용 헤더에
//   Last-Event-ID 가 없어(2026-11-24 확인) 보내면 사전 요청이 막힌다. 안 보내면 서버가 ready(resumed false) — 화면은 한 번 다시 읽는다.
import { ProblemFailure, request, SessionExpiredFailure, UnexpectedResponseFailure } from '@pmart/web-core';

import type { Api } from '../../api/client';
import type { components } from '../../api/generated/mfc-inventory';
import { createSseParser } from './sse';

export type StockStreamEvent = components['schemas']['StockStreamEvent'];

/** live = ready 를 받은 뒤 · connecting = 첫 연결 · reconnecting = 끊겨 다시 잇는 중 · down = 두 번 넘게 못 이음(계속 다시 해 본다) · off = 멈춤(권한 밖·세션 끝) */
export type StockStreamStatus = 'connecting' | 'live' | 'reconnecting' | 'down' | 'off';

export interface StockStreamOptions {
  readonly api: Api;
  readonly mfcId: string;
  readonly onEvent: (event: StockStreamEvent) => void;
  readonly onStatus: (status: StockStreamStatus) => void;
  /** Last-Event-ID 를 보낼지(같은 출처일 때만 — 위 설명) */
  readonly resume?: boolean;
  readonly sleep?: (ms: number, signal: AbortSignal) => Promise<void>;
  /** heartbeat 5초 — 이만큼 아무것도 안 오면 끊긴 것으로 본다 */
  readonly idleMs?: number;
}

export const RECONNECT_DELAYS_MS = [1_000, 2_000, 5_000, 10_000, 30_000] as const;
const IDLE_MS = 15_000;

const realSleep = (ms: number, signal: AbortSignal) =>
  new Promise<void>((resolve) => {
    const t = setTimeout(resolve, ms);
    signal.addEventListener('abort', () => {
      clearTimeout(t);
      resolve();
    });
  });

/** 연결을 열고 닫는 함수를 돌려준다. */
export function openStockStream(options: StockStreamOptions): () => void {
  const { api, mfcId, onEvent, onStatus, resume = false, sleep = realSleep, idleMs = IDLE_MS } = options;
  const closing = new AbortController();
  let lastEventId: string | null = null;
  // 이번 연결이 ready 까지 갔는지 — 갔으면 다시 접속 간격을 처음(1초)부터
  let reachedReady = false;

  const once = async (): Promise<'retry' | 'stop'> => {
    const conn = new AbortController();
    const abort = () => conn.abort();
    closing.signal.addEventListener('abort', abort);
    let idle: ReturnType<typeof setTimeout> | undefined;
    const touch = () => {
      clearTimeout(idle);
      idle = setTimeout(abort, idleMs);
    };
    try {
      touch();
      const body = await request(
        'GET',
        api.inventory.GET('/stock-stream', {
          params: {
            query: { mfcId: [mfcId] },
            ...(resume && lastEventId ? { header: { 'Last-Event-ID': lastEventId } } : {}),
          },
          // 기본 Accept(application/json)면 LAN 게이트웨이가 406 을 줄 수 있다(PC1 PR 세션 2026-11-25) — SSE 를 받는다고 밝힌다
          headers: { Accept: 'text/event-stream' },
          parseAs: 'stream',
          signal: conn.signal,
        }),
      );
      if (!body) return 'retry';
      const reader = (body as ReadableStream<Uint8Array>).getReader();
      const decoder = new TextDecoder();
      const parse = createSseParser();
      for (;;) {
        const { done, value } = await reader.read();
        if (done) return 'retry';
        touch();
        for (const msg of parse(decoder.decode(value, { stream: true }))) {
          let event: StockStreamEvent;
          try {
            event = JSON.parse(msg.data) as StockStreamEvent;
          } catch {
            continue;
          }
          if (msg.id) lastEventId = msg.id;
          if (event.type === 'ready') {
            reachedReady = true;
            onStatus('live');
          }
          onEvent(event);
        }
      }
    } catch (e) {
      if (closing.signal.aborted) return 'stop';
      const status = e instanceof ProblemFailure ? e.problem.status : e instanceof UnexpectedResponseFailure ? e.httpStatus : null;
      // 403 = 권한 밖 센터(접속 때 한 번 판정) — 다시 해도 같다. 세션 끝(401 갱신 실패)도 멈춘다.
      if (status === 403 || e instanceof SessionExpiredFailure) return 'stop';
      return 'retry';
    } finally {
      clearTimeout(idle);
      closing.signal.removeEventListener('abort', abort);
      conn.abort();
    }
  };

  void (async () => {
    onStatus('connecting');
    let failures = 0;
    while (!closing.signal.aborted) {
      reachedReady = false;
      const result = await once();
      if (closing.signal.aborted) return;
      if (result === 'stop') {
        onStatus('off');
        return;
      }
      if (reachedReady) failures = 0;
      onStatus(failures >= 2 ? 'down' : 'reconnecting');
      await sleep(RECONNECT_DELAYS_MS[Math.min(failures, RECONNECT_DELAYS_MS.length - 1)]!, closing.signal);
      failures += 1;
    }
  })();

  return () => closing.abort();
}
