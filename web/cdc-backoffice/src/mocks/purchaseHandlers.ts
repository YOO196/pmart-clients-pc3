// 상품 발주·공급사 목 — 단순 구현(사용자 2026-11-26 "발주 내용에 따라 cdc 재고 적재량 달라지도록 단순하게").
// 발주(ORDERED) → 입고(RECEIVED): 발주 수량만큼 재고관리에 LOT 로 더한다. 입고 전에만 취소.
import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import type { PoBody, PurchaseOrder, Supplier, SupplierBody } from '../api/proposed/purchase';
import { receiveIntoStock } from './stockHandlers';
import { idempotent, operator, problem, unauthorized } from './support';

/** 서울 날짜(YYYY-MM-DD) */
const day = (offset = 0) => new Date(Date.now() + 9 * 3_600_000 + offset * 86_400_000).toISOString().slice(0, 10);
const ymd = () => day().replaceAll('-', '');
const stamp = () => new Date().toISOString();

function seed() {
  const suppliers: Supplier[] = [
    { supplierId: 'SUP-001', name: '한빛식품(시험)', contactName: '김한빛', phone: '010-0000-0001', skus: ['SKU-1001', 'SKU-1002'], createdAt: '2026-11-20T00:00:00Z' },
    { supplierId: 'SUP-002', name: '대성농산(시험)', contactName: '박대성', phone: '010-0000-0002', skus: ['SKU-2001'], createdAt: '2026-11-20T00:00:00Z' },
    { supplierId: 'SUP-003', name: '맑은샘음료(시험)', contactName: null, phone: null, skus: ['SKU-1003'], createdAt: '2026-11-21T00:00:00Z' },
  ];
  const base = { cdcId: 'CDC01', note: null, orderedBy: 'OP-cdc-sup', cancelledAt: null };
  const pos: PurchaseOrder[] = [
    {
      ...base,
      purchaseOrderId: 'PO-20261124-0001',
      supplierId: 'SUP-001',
      supplierName: '한빛식품(시험)',
      state: 'RECEIVED',
      lines: [{ sku: 'SKU-1001', qty: 400, lot: 'L261124011' }],
      orderedAt: '2026-11-24T01:00:00Z',
      receivedAt: '2026-11-26T00:30:00Z',
    },
    {
      ...base,
      purchaseOrderId: 'PO-20261125-0002',
      supplierId: 'SUP-002',
      supplierName: '대성농산(시험)',
      state: 'ORDERED',
      lines: [{ sku: 'SKU-2001', qty: 100, lot: null }],
      orderedAt: '2026-11-25T01:00:00Z',
      receivedAt: null,
    },
  ];
  return { suppliers, pos, seq: 3, sseq: 4 };
}

let store = seed();
export const resetPurchase = () => {
  store = seed();
};

function guardCdc(request: Request, cdcId: string) {
  const who = operator(request);
  if (!who) return unauthorized();
  if (!who.centers.includes(cdcId)) return problem(403, 'FORBIDDEN');
  return null;
}

function findPo(request: Request, id: unknown): { po: PurchaseOrder; denied?: undefined } | { po?: undefined; denied: Response } {
  const po = store.pos.find((x) => x.purchaseOrderId === id);
  if (!po) return { denied: operator(request) ? problem(404, 'NOT_FOUND') : unauthorized() };
  const denied = guardCdc(request, po.cdcId);
  return denied ? { denied } : { po };
}

export const purchaseHandlers = [
  http.get(`${API_BASE}/suppliers`, ({ request }) => (operator(request) ? HttpResponse.json({ items: store.suppliers }) : unauthorized())),
  http.post(`${API_BASE}/suppliers`, async ({ request }) => {
    if (!operator(request)) return unauthorized();
    const body = (await request.clone().json()) as SupplierBody;
    return idempotent(request, () => {
      if (!body.name?.trim()) return problem(422, 'VALIDATION_FAILED', [{ field: 'name', reason: 'REQUIRED' }]);
      const s: Supplier = {
        supplierId: `SUP-${String(store.sseq++).padStart(3, '0')}`,
        name: body.name.trim(),
        contactName: body.contactName?.trim() || null,
        phone: body.phone?.trim() || null,
        skus: [...new Set(body.skus)],
        createdAt: stamp(),
      };
      store.suppliers.push(s);
      return { status: 201, body: s };
    });
  }),

  http.get(`${API_BASE}/purchase-orders`, ({ request }) => {
    const q = new URL(request.url).searchParams;
    const cdcId = q.get('cdcId') ?? '';
    const denied = guardCdc(request, cdcId);
    if (denied) return denied;
    const state = q.get('state');
    const items = store.pos.filter((po) => po.cdcId === cdcId && (!state || po.state === state)).sort((a, b) => b.orderedAt.localeCompare(a.orderedAt));
    return HttpResponse.json({ items });
  }),
  http.get(`${API_BASE}/purchase-orders/:id`, ({ request, params }) => {
    const r = findPo(request, params.id);
    return r.denied ?? HttpResponse.json(r.po);
  }),
  http.post(`${API_BASE}/purchase-orders`, async ({ request }) => {
    const body = (await request.clone().json()) as PoBody;
    const denied = guardCdc(request, body.cdcId);
    if (denied) return denied;
    const who = operator(request)!;
    return idempotent(request, () => {
      const supplier = store.suppliers.find((x) => x.supplierId === body.supplierId);
      if (!supplier) return problem(422, 'VALIDATION_FAILED', [{ field: 'supplierId', reason: 'NOT_ALLOWED' }]);
      if (!body.lines.length || body.lines.some((l) => !(l.qty > 0))) return problem(422, 'VALIDATION_FAILED', [{ field: 'lines', reason: 'REQUIRED' }]);
      const po: PurchaseOrder = {
        purchaseOrderId: `PO-${ymd()}-${String(store.seq++).padStart(4, '0')}`,
        cdcId: body.cdcId,
        supplierId: supplier.supplierId,
        supplierName: supplier.name,
        state: 'ORDERED',
        note: body.note?.trim() || null,
        lines: body.lines.map((l) => ({ sku: l.sku, qty: l.qty, lot: null })),
        orderedBy: who.subject,
        orderedAt: stamp(),
        receivedAt: null,
        cancelledAt: null,
      };
      store.pos.push(po);
      return { status: 201, body: po };
    });
  }),
  // 입고 — 발주 수량만큼 재고관리에 더한다(새 LOT, 유통기한 90일, 입고장 칸)
  http.post(`${API_BASE}/purchase-orders/:id/receipts`, ({ request, params }) => {
    const r = findPo(request, params.id);
    if (r.denied) return r.denied;
    const po = r.po;
    return idempotent(request, () => {
      if (po.state !== 'ORDERED') return problem(409, 'INVALID_STATE');
      const n = po.purchaseOrderId.slice(-2);
      po.lines = po.lines.map((l, i) => {
        const lot = `L${ymd().slice(2)}${n}${i + 1}`;
        receiveIntoStock(po.cdcId, l.sku, lot, day(90), l.qty);
        return { ...l, lot };
      });
      po.state = 'RECEIVED';
      po.receivedAt = stamp();
      return { status: 200, body: { ...po } };
    });
  }),
  http.post(`${API_BASE}/purchase-orders/:id/cancellations`, ({ request, params }) => {
    const r = findPo(request, params.id);
    if (r.denied) return r.denied;
    const po = r.po;
    return idempotent(request, () => {
      if (po.state !== 'ORDERED') return problem(409, 'INVALID_STATE');
      po.state = 'CANCELLED';
      po.cancelledAt = stamp();
      return { status: 200, body: { ...po } };
    });
  }),
];
