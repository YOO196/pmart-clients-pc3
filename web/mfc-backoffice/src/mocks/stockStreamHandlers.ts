// 재고 실시간 스트림 목 — mfc-inventory 0.46.0 `GET /stock-stream?mfcId=`(SSE). 계약 모양 그대로: 접속 직후 ready, 5초마다 `: hb`,
// 재고가 바뀐 확정 단위마다 stock-changed(id = eventId, SKU 마다 바뀐 뒤 센터 값 H·Q·E·R·A·version, 위치 단위 증감), 가용이 0 경계를 넘으면 summary-changed.
// 권한: 토큰 센터만(권한 밖 센터를 주면 403, 비우면 토큰 센터 전부). 목은 예약(R)이 없어 R = 0, A = E.
// 바뀌는 곳: 위치·LOT 정정(inventoryHandlers) · 브라우저 목의 시연(startStockStreamSim — 피킹 −1 · 집품 뒤 취소 복귀 +1).
import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import { db } from './db';
import { operator, problem, unauthorized } from './support';

export interface StockUnitChange {
  readonly sku: string;
  readonly lotId: string;
  readonly locationCode: string;
  readonly qualityState: string;
  readonly workState: string;
  readonly delta: number;
}

interface Subscriber {
  readonly mfcIds: ReadonlySet<string>;
  readonly send: (text: string) => void;
}

const subscribers = new Set<Subscriber>();
const versions = new Map<string, number>();
let seq = 0;

export function resetStockStream() {
  subscribers.clear();
  versions.clear();
  seq = 0;
}

/** 지금 스트림을 받는 센터(시연이 이 센터만 바꾼다) */
export const streamingCenters = () => new Set([...subscribers].flatMap((s) => [...s.mfcIds]));

function centerValues(mfcId: string, sku: string) {
  const units = db.stockUnits.filter((u) => u.mfcId === mfcId && u.sku === sku);
  const onHandQty = units.reduce((n, u) => n + u.qty, 0);
  const quarantinedQty = units.filter((u) => u.qualityState === 'QUARANTINED').reduce((n, u) => n + u.qty, 0);
  const sellableQty = onHandQty - quarantinedQty;
  return {
    onHandQty,
    quarantinedQty,
    sellableQty,
    reservedQty: 0,
    availableQty: sellableQty,
  };
}

const frame = (event: string, data: unknown, id?: string) => `event: ${event}\n${id ? `id: ${id}\n` : ''}data: ${JSON.stringify(data)}\n\n`;

/** db.stockUnits 를 바꾼 **뒤** 부른다(서버: 커밋 뒤). 그 센터를 받는 연결에 stock-changed(+ 0 경계면 summary-changed). */
export function emitStockChange(mfcId: string, cause: string, units: readonly StockUnitChange[]) {
  if (units.length === 0) return;
  const skus = [...new Set(units.map((u) => u.sku))];
  const items = skus.map((sku) => {
    const now = centerValues(mfcId, sku);
    const availableDelta = units.filter((u) => u.sku === sku && u.qualityState !== 'QUARANTINED').reduce((n, u) => n + u.delta, 0);
    const version = (versions.get(`${mfcId}:${sku}`) ?? 0) + 1;
    versions.set(`${mfcId}:${sku}`, version);
    return { sku, ...now, availableDelta, version };
  });
  seq += 1;
  const eventId = `SE-${String(seq).padStart(6, '0')}`;
  const occurredAt = new Date().toISOString();
  const text = frame(
    'stock-changed',
    {
      type: 'stock-changed',
      eventId,
      mfcId,
      commitId: `CMT-S${seq}`,
      cause,
      occurredAt,
      items,
      units,
      holds: [],
    },
    eventId,
  );
  const crossed = items.filter((i) => i.availableQty > 0 !== i.availableQty - i.availableDelta > 0).map((i) => i.sku);
  const summary =
    crossed.length > 0
      ? frame(
          'summary-changed',
          {
            type: 'summary-changed',
            eventId: `${eventId}-S`,
            mfcId,
            occurredAt,
            skus: crossed,
          },
          `${eventId}-S`,
        )
      : '';
  for (const s of subscribers) if (s.mfcIds.has(mfcId)) s.send(text + summary);
}

export const stockStreamHandlers = [
  http.get(`${API_BASE}/stock-stream`, ({ request }) => {
    const who = operator(request);
    if (!who) return unauthorized();
    const asked = new URL(request.url).searchParams.getAll('mfcId');
    if (asked.some((c) => !who.centers.includes(c))) return problem(403, 'FORBIDDEN');
    const mfcIds = new Set(asked.length > 0 ? asked : who.centers);
    const encoder = new TextEncoder();
    let sub: Subscriber | null = null;
    let hb: ReturnType<typeof setInterval> | undefined;
    const stop = () => {
      clearInterval(hb);
      if (sub) subscribers.delete(sub);
      sub = null;
    };
    const body = new ReadableStream<Uint8Array>({
      start(controller) {
        const send = (text: string) => {
          try {
            controller.enqueue(encoder.encode(text));
          } catch {
            stop();
          }
        };
        // 목은 보관이 없어 이어 받기를 못 한다 — 늘 ready(resumed false), Last-Event-ID 가 오면 resync 도
        send(
          frame('ready', {
            type: 'ready',
            resumed: false,
            mfcIds: [...mfcIds],
          }),
        );
        if (request.headers.get('Last-Event-ID')) send(frame('resync', { type: 'resync', reason: 'RESUME_UNAVAILABLE' }));
        sub = { mfcIds, send };
        subscribers.add(sub);
        hb = setInterval(() => send(': hb\n\n'), 5_000);
        request.signal.addEventListener('abort', () => {
          stop();
          try {
            controller.close();
          } catch {
            // 이미 닫힘
          }
        });
      },
      cancel: stop,
    });
    return new HttpResponse(body, {
      headers: {
        'Content-Type': 'text/event-stream;charset=UTF-8',
        'Cache-Control': 'no-cache',
      },
    });
  }),
];

/** 브라우저 목 시연 — 스트림을 받는 센터에서 몇 초마다 재고 한 칸을 피킹(−1)·취소 복귀(+1). 시험에서는 켜지 않는다. */
export function startStockStreamSim(everyMs = 6_000) {
  let flip = false;
  return setInterval(() => {
    for (const mfcId of streamingCenters()) {
      const candidates = db.stockUnits.filter((u) => u.mfcId === mfcId && u.workState === 'STORED' && u.qualityState === 'NORMAL' && u.qty > 1);
      const unit = candidates[Math.floor(Math.random() * candidates.length)];
      if (!unit) continue;
      flip = !flip;
      const delta = flip ? -1 : 1;
      db.stockUnits = db.stockUnits.map((u) => (u === unit ? { ...u, qty: u.qty + delta } : u));
      emitStockChange(mfcId, flip ? 'TASK_EXECUTION' : 'CANCEL_RETURN', [
        {
          sku: unit.sku,
          lotId: unit.lotId,
          locationCode: unit.locationCode,
          qualityState: unit.qualityState,
          workState: unit.workState,
          delta,
        },
      ]);
    }
  }, everyMs);
}
