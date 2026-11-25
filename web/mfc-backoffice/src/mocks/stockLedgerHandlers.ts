// 재고 이력 목 — mfc-inventory 0.48.0 `GET /mfcs/{mfcId}/stock-ledger?sku=`(백엔드 PR #470, 브랜치 mfc/stock-ledger-history 계약).
// 확정 단위(commit) 하나 = 원인·시각·출처·entries(H·Q·E·R 줄). after(그 확정 뒤 센터 합계)는 서버처럼 지금 합계에서 뒤 확정들의 증감을 거슬러 뺀다.
// 재고를 바꾸는 목(위치·LOT 정정·브라우저 시연)은 stockStreamHandlers.emitStockChange 가 여기에도 적는다.
import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import type { components } from '../api/generated/mfc-inventory';
import { db } from './db';
import { MOCK_LOT_NUMBERS } from './inventoryHandlers';
import { operator, problem, unauthorized } from './support';

type Commit = components['schemas']['StockLedgerCommit'];
type Entry = Commit['entries'][number];
interface Stored extends Omit<Commit, 'after' | 'delta'> {
  readonly mfcId: string;
  readonly sku: string;
}

// 처음 쓸 때 채운다(모듈 순환 — inventoryHandlers 의 MOCK_LOT_NUMBERS 가 아직 안 읽혔을 수 있다)
let ledgerRows: Stored[] | null = null;
const rowsOf = () => (ledgerRows ??= seed());
let seq = 0;

const lotNo = (lotId: string) => MOCK_LOT_NUMBERS[lotId]?.lotNo ?? null;
const ago = (hours: number) => new Date(Date.now() - hours * 3_600_000).toISOString();

function seed(): Stored[] {
  const at = (sku: string, cause: string, hours: number, sourceSystem: string, sourceRef: string | null, entries: Entry[], orderId: string | null = null, actorOperatorId: string | null = null): Stored => ({
    orderId,
    actorOperatorId,
    mfcId: 'MFC-BJG-01',
    sku,
    commitId: `CMT-L${(seq += 1)}`,
    cause,
    occurredAt: ago(hours),
    sourceSystem,
    sourceRef,
    entries,
  });
  const h = (delta: number, locationCode: string, lotId = 'LOT-MILK-A', workState = 'STORED'): Entry => ({ symbol: 'H', delta, lotId, lotNo: lotNo(lotId), expiryDate: null, locationCode, qualityState: 'NORMAL', workState });
  const e = (delta: number, locationCode: string, lotId = 'LOT-MILK-A'): Entry => ({ symbol: 'E', delta, lotId, lotNo: lotNo(lotId), expiryDate: null, locationCode, qualityState: 'NORMAL', workState: 'STORED' });
  const q = (delta: number, locationCode: string, lotId = 'LOT-MILK-A'): Entry => ({ symbol: 'Q', delta, lotId, lotNo: lotNo(lotId), expiryDate: null, locationCode, qualityState: 'QUARANTINED', workState: 'STORED' });
  const r = (delta: number): Entry => ({ symbol: 'R', delta, lotId: null, lotNo: null, expiryDate: null, locationCode: null, qualityState: null, workState: null });
  seq = 0;
  return [
    at('SKU-MILK-1', 'TIN', 50, 'mfc-inbound', 'RCP-2026-0101', [h(5, 'RCV-C-01', 'LOT-MILK-B', 'UNSTOWED'), e(5, 'RCV-C-01', 'LOT-MILK-B')]),
    at('SKU-MILK-1', 'TASK_EXECUTION', 40, 'mfc-inbound', 'TASK-PUT-0042', [h(-3, 'RCV-C-01'), h(3, 'A-P1-01-1-01')], null, 'OP-wkr-1'),
    at('SKU-MILK-1', 'RESERVE', 30, 'mfc-fulfillment', 'RSV-20000001', [r(1)], 'ORD-1'),
    at('SKU-MILK-1', 'HANDOVER', 26, 'mfc-fulfillment', 'PKG-20000001', [h(-1, 'A-P1-01-1-01'), e(-1, 'A-P1-01-1-01'), r(-1)], 'ORD-1', 'OP-wkr-1'),
    at('SKU-MILK-1', 'QUALITY_QUARANTINE', 20, 'mfc-quality', 'QD-0007', [h(-2, 'A-P1-01-1-01'), h(2, 'QRT-A-01'), e(-2, 'A-P1-01-1-01'), q(2, 'QRT-A-01')]),
    at('SKU-MILK-1', 'CORRECTION', 3, 'mfc-backoffice', 'COR-0003', [h(-1, 'A-P1-01-1-01'), h(1, 'A-P1-01-1-01', 'LOT-MILK-B')], null, 'OP-sup-1'),
  ];
}

export function resetStockLedger() {
  ledgerRows = null;
}

/** 재고를 바꾼 목이 부른다(db.stockUnits 를 바꾼 뒤). H 줄 + 품질에 따라 E 또는 Q 줄 */
export function recordLedger(mfcId: string, cause: string, units: readonly { sku: string; lotId: string; locationCode: string; qualityState: string; workState: string; delta: number }[]) {
  for (const sku of new Set(units.map((u) => u.sku))) {
    const mine = units.filter((u) => u.sku === sku);
    const entries: Entry[] = mine.flatMap((u) => {
      const base = { lotId: u.lotId, lotNo: null, expiryDate: null, locationCode: u.locationCode, qualityState: u.qualityState, workState: u.workState };
      return [
        { symbol: 'H' as const, delta: u.delta, ...base },
        { symbol: u.qualityState === 'QUARANTINED' ? ('Q' as const) : ('E' as const), delta: u.delta, ...base },
      ];
    });
    rowsOf().push({ mfcId, sku, commitId: `CMT-L${(seq += 1)}`, cause, occurredAt: new Date().toISOString(), sourceSystem: 'mfc-backoffice', sourceRef: null, entries, orderId: null, actorOperatorId: null });
  }
}

function current(mfcId: string, sku: string) {
  const units = db.stockUnits.filter((u) => u.mfcId === mfcId && u.sku === sku);
  const onHandQty = units.reduce((n, u) => n + u.qty, 0);
  const quarantinedQty = units.filter((u) => u.qualityState === 'QUARANTINED').reduce((n, u) => n + u.qty, 0);
  const sellableQty = onHandQty - quarantinedQty;
  // 목은 예약(R)을 따로 두지 않는다 — 열린 예약 = 원장 R 합
  const reservedQty = rowsOf().filter((c) => c.mfcId === mfcId && c.sku === sku).reduce((n, c) => n + c.entries.filter((x) => x.symbol === 'R').reduce((m, x) => m + x.delta, 0), 0);
  return { onHandQty, quarantinedQty, sellableQty, reservedQty, availableQty: sellableQty - reservedQty };
}

const sum = (c: Stored, s: Entry['symbol']) => c.entries.filter((x) => x.symbol === s).reduce((n, x) => n + x.delta, 0);

export const stockLedgerHandlers = [
  http.get(`${API_BASE}/mfcs/:mfcId/stock-ledger`, ({ request, params }) => {
    const who = operator(request);
    if (!who) return unauthorized();
    const mfcId = String(params.mfcId);
    if (!who.centers.includes(mfcId)) return problem(403, 'FORBIDDEN');
    const url = new URL(request.url);
    const sku = url.searchParams.get('sku');
    if (!sku) return problem(400, 'VALIDATION_FAILED');
    const lotId = url.searchParams.get('lotId');
    const orderId = url.searchParams.get('orderId');
    const loc = url.searchParams.get('locationCode');
    const causes = url.searchParams.getAll('cause');
    const from = url.searchParams.get('from');
    const to = url.searchParams.get('to');
    const size = Math.min(Number(url.searchParams.get('size') ?? 50) || 50, 100);
    const cursor = url.searchParams.get('cursor');
    if (cursor !== null && !/^\d+$/.test(cursor)) return problem(400, 'VALIDATION_FAILED');
    // 최신순 — after 는 거르기 전 전체 순서로 계산(서버와 같다)
    const all = rowsOf().filter((c) => c.mfcId === mfcId && c.sku === sku).reverse();
    const now = current(mfcId, sku);
    let acc = { H: 0, Q: 0, E: 0, R: 0 };
    const withAfter = all.map((c) => {
      const after = {
        onHandQty: now.onHandQty - acc.H,
        quarantinedQty: now.quarantinedQty - acc.Q,
        sellableQty: now.sellableQty - acc.E,
        reservedQty: now.reservedQty - acc.R,
        availableQty: now.sellableQty - acc.E - (now.reservedQty - acc.R),
      };
      const delta = { H: sum(c, 'H'), Q: sum(c, 'Q'), E: sum(c, 'E'), R: sum(c, 'R') };
      acc = { H: acc.H + delta.H, Q: acc.Q + delta.Q, E: acc.E + delta.E, R: acc.R + delta.R };
      return { commitId: c.commitId, cause: c.cause, occurredAt: c.occurredAt, sourceSystem: c.sourceSystem, sourceRef: c.sourceRef, orderId: c.orderId ?? null, actorOperatorId: c.actorOperatorId ?? null, entries: c.entries, delta, after };
    });
    const picked = withAfter.filter(
      (c) =>
        (!lotId || c.entries.some((x) => x.lotId === lotId)) &&
        (!orderId || c.orderId === orderId) &&
        (!loc || c.entries.some((x) => x.locationCode === loc)) &&
        (causes.length === 0 || causes.includes(c.cause)) &&
        (!from || c.occurredAt >= from) &&
        (!to || c.occurredAt < to),
    );
    const start = cursor ? Number(cursor) : 0;
    const items = picked.slice(start, start + size);
    const productName = db.stockUnits.find((u) => u.mfcId === mfcId && u.sku === sku)?.productName ?? null;
    return HttpResponse.json({ mfcId, sku, productName, current: now, items, nextCursor: start + size < picked.length ? String(start + size) : null, asOf: new Date().toISOString() });
  }),

  // LOT 찾기(0.21.0 lot-resolutions) — 괄호 꼴 (10)LOT번호·LOT:{lotId}·LOT 번호 그대로. 라벨 정보 + 그 센터 보유
  http.get(`${API_BASE}/mfcs/:mfcId/lot-resolutions`, ({ request, params }) => {
    const who = operator(request);
    if (!who) return unauthorized();
    const mfcId = String(params.mfcId);
    if (!who.centers.includes(mfcId)) return problem(403, 'FORBIDDEN');
    const code = (new URL(request.url).searchParams.get('code') ?? '').trim();
    if (!code) return problem(400, 'VALIDATION_FAILED');
    const byId = code.startsWith('LOT:') ? code.slice(4) : null;
    const lotNoOf = /\(10\)([^(]+)/.exec(code)?.[1] ?? (byId ? null : code);
    const found = Object.entries(MOCK_LOT_NUMBERS).find(([id, v]) => (byId ? id === byId : v.lotNo === lotNoOf));
    if (!found) return problem(404, 'LOT_NOT_FOUND');
    const [lotId, v] = found;
    const units = db.stockUnits.filter((u) => u.mfcId === mfcId && u.lotId === lotId);
    return HttpResponse.json({
      labelValue: `LOT:${lotId}`,
      lotId,
      lotNo: v.lotNo,
      gs1: null,
      sku: v.sku,
      productName: units[0]?.productName ?? null,
      barcodes: [],
      unitType: 'E',
      unitsPerSku: null,
      tracking: 'TRACKED',
      sourceLotRef: null,
      expiryDate: v.expiryDate,
      manufactureDate: null,
      receivedAt: null,
      onHand: units.reduce((n, u) => n + u.qty, 0),
      qtyAtLocation: null,
    });
  }),

  // 주문 현장 상태(fulfillment 0.10.0 `GET /work-orders?orderId=`, 0.36.0 orderNumber) — 목은 출고(shipments)만: 작업 지시 하나에 그 주문 출고들
  http.get(`${API_BASE}/work-orders`, ({ request }) => {
    const who = operator(request);
    if (!who) return unauthorized();
    const orderId = new URL(request.url).searchParams.get('orderId');
    if (!orderId) return problem(400, 'VALIDATION_FAILED');
    const ships = [...db.shipments.values()].filter((x) => x.orderId === orderId && who.centers.includes(x.mfcId));
    if (ships.length === 0) return problem(404, 'WORK_ORDER_NOT_FOUND');
    return HttpResponse.json({
      orderId,
      orderNumber: ships[0]!.orderNumber ?? null,
      workOrders: [{ fulfillmentId: ships[0]!.fulfillmentId, kind: 'ORIGINAL', mfcId: ships[0]!.mfcId, workVersion: 1, acceptance: 'ACCEPTED', createdAt: new Date().toISOString(), shipments: ships.map((x) => ({ shipmentId: x.shipmentId, state: x.state })) }],
      stopRequests: [],
      asOf: new Date().toISOString(),
    });
  }),
];
