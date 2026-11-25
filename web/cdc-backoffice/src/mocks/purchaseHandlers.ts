// 상품 발주·공급사 목 — 제안 계약(api/proposed/purchase.ts). 진짜 공급사가 없어 **가짜 공급사가 회신·ASN 을 만든다**
// (사용자 2026-11-26 "주문에 대한 회신 가짜데이터로 받고 입고 시키라고").
// 흐름: 발주(ISSUED) → replyMs 뒤 공급사 회신(규칙: 전량·일부 80%·거절) → asnMs 뒤 ASN(LOT·유통기한·도착 예정) → 입고 확정 → 재고관리에 LOT 로 더한다.
// 시간은 읽을 때 진행한다(타이머 없이 — 화면이 다시 읽으면 바뀐다). 시험은 fakeSupplier 의 시간을 0 으로 둔다.
import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import type { PoBody, PoLine, PurchaseOrder, ReceiptBody, Supplier, SupplierBody } from '../api/proposed/purchase';
import { receiveIntoStock } from './stockHandlers';
import { idempotent, operator, problem, unauthorized } from './support';

/** 가짜 공급사가 회신·ASN 을 보내기까지(밀리초) */
export const fakeSupplier = { replyMs: 5_000, asnMs: 8_000 };

interface StoredPo {
  po: PurchaseOrder;
  /** 회신·ASN 예정 시각(epoch ms) — 시연 씨앗은 null(멈춰 있음) */
  replyDue: number | null;
  asnDue: number | null;
}

const day = (offset: number) => {
  // 서울 날짜
  const d = new Date(Date.now() + 9 * 3_600_000 + offset * 86_400_000);
  return d.toISOString().slice(0, 10);
};

function seed() {
  const suppliers: Supplier[] = [
    {
      supplierId: 'SUP-001',
      name: '한빛식품(시험)',
      businessNo: '123-45-00001',
      contactName: '김한빛',
      phone: '010-0000-0001',
      leadTimeDays: 2,
      skus: ['SKU-1001', 'SKU-1002'],
      replyMode: 'FULL',
      state: 'ACTIVE',
      createdAt: '2026-11-20T00:00:00Z',
    },
    {
      supplierId: 'SUP-002',
      name: '대성농산(시험)',
      businessNo: '123-45-00002',
      contactName: '박대성',
      phone: '010-0000-0002',
      leadTimeDays: 3,
      skus: ['SKU-2001'],
      replyMode: 'PARTIAL',
      state: 'ACTIVE',
      createdAt: '2026-11-20T00:00:00Z',
    },
    {
      supplierId: 'SUP-003',
      name: '맑은샘음료(시험)',
      businessNo: null,
      contactName: null,
      phone: null,
      leadTimeDays: 1,
      skus: ['SKU-1003'],
      replyMode: 'REJECT',
      state: 'ACTIVE',
      createdAt: '2026-11-21T00:00:00Z',
    },
  ];
  const line = (sku: string, ordered: number, rest: Partial<PoLine> = {}): PoLine => ({
    sku,
    orderedQty: ordered,
    confirmedQty: null,
    shippedQty: null,
    lot: null,
    expiresAt: null,
    receivedQty: null,
    rejectedQty: null,
    ...rest,
  });
  const base = {
    cdcId: 'CDC01',
    note: null,
    issuedBy: 'OP-cdc-sup',
    replyNote: null,
    asn: null,
    receivedAt: null,
    receivedBy: null,
    cancelledAt: null,
    cancelReason: null,
    version: 1,
  };
  const pos: StoredPo[] = [
    {
      replyDue: null,
      asnDue: null,
      po: {
        ...base,
        purchaseOrderId: 'PO-20261124-0001',
        supplierId: 'SUP-001',
        supplierName: '한빛식품(시험)',
        state: 'RECEIVED',
        dueDate: '2026-11-26',
        lines: [
          line('SKU-1001', 400, {
            confirmedQty: 400,
            shippedQty: 400,
            lot: 'L261124001',
            expiresAt: '2027-05-24',
            receivedQty: 398,
            rejectedQty: 2,
          }),
        ],
        issuedAt: '2026-11-24T01:00:00Z',
        repliedAt: '2026-11-24T02:00:00Z',
        asn: {
          asnId: 'ASN-20261125-0001',
          shippedAt: '2026-11-25T20:00:00Z',
          expectedArrivalAt: '2026-11-26T00:00:00Z',
          vehicleNo: '경북12가3456',
        },
        receivedAt: '2026-11-26T00:30:00Z',
        receivedBy: 'OP-cdc-sup',
        version: 4,
      },
    },
    {
      replyDue: null,
      asnDue: null,
      po: {
        ...base,
        purchaseOrderId: 'PO-20261125-0002',
        supplierId: 'SUP-002',
        supplierName: '대성농산(시험)',
        state: 'ASN_RECEIVED',
        dueDate: day(0),
        lines: [
          line('SKU-2001', 100, {
            confirmedQty: 80,
            shippedQty: 80,
            lot: 'L261125002',
            expiresAt: '2026-12-25',
          }),
        ],
        issuedAt: '2026-11-25T01:00:00Z',
        repliedAt: '2026-11-25T03:00:00Z',
        replyNote: '산지 물량 부족 — 80만 공급',
        asn: {
          asnId: 'ASN-20261126-0002',
          shippedAt: `${day(-1)}T10:00:00Z`,
          expectedArrivalAt: `${day(0)}T01:00:00Z`,
          vehicleNo: '경북34나5678',
        },
        version: 3,
      },
    },
  ];
  return { suppliers, pos, seq: 3, sseq: 4 };
}

let store = seed();
export const resetPurchase = () => {
  store = seed();
};

const stamp = () => new Date().toISOString();
/** 번호용 서울 날짜(YYYYMMDD) */
const ymd = () => new Date(Date.now() + 9 * 3_600_000).toISOString().slice(0, 10).replaceAll('-', '');

/** 가짜 공급사: 예정 시각이 지났으면 회신 → ASN 으로 진행 */
function advance(s: StoredPo) {
  const now = Date.now();
  const supplier = store.suppliers.find((x) => x.supplierId === s.po.supplierId);
  if (s.po.state === 'ISSUED' && s.replyDue !== null && now >= s.replyDue) {
    const mode = supplier?.replyMode ?? 'FULL';
    const lines = s.po.lines.map((l) => ({
      ...l,
      confirmedQty: mode === 'REJECT' ? 0 : mode === 'PARTIAL' ? Math.floor(l.orderedQty * 0.8) : l.orderedQty,
    }));
    s.po = {
      ...s.po,
      lines,
      state: mode === 'REJECT' ? 'REJECTED' : mode === 'PARTIAL' ? 'PARTIALLY_CONFIRMED' : 'CONFIRMED',
      repliedAt: stamp(),
      replyNote: mode === 'REJECT' ? '공급 불가 — 품절(가짜 회신)' : mode === 'PARTIAL' ? '재고 부족 — 일부만 공급(가짜 회신)' : '전량 공급(가짜 회신)',
      version: s.po.version + 1,
    };
    s.replyDue = null;
    s.asnDue = mode === 'REJECT' ? null : now + fakeSupplier.asnMs;
  }
  if ((s.po.state === 'CONFIRMED' || s.po.state === 'PARTIALLY_CONFIRMED') && s.asnDue !== null && now >= s.asnDue) {
    const n = store.seq++;
    const exp = day(90);
    s.po = {
      ...s.po,
      state: 'ASN_RECEIVED',
      lines: s.po.lines.map((l, i) => ({
        ...l,
        shippedQty: l.confirmedQty ?? 0,
        lot: (l.confirmedQty ?? 0) > 0 ? `L${ymd().slice(2)}${String(n).padStart(2, '0')}${i + 1}` : null,
        expiresAt: (l.confirmedQty ?? 0) > 0 ? exp : null,
      })),
      asn: {
        asnId: `ASN-${ymd()}-${String(n).padStart(4, '0')}`,
        shippedAt: stamp(),
        expectedArrivalAt: `${s.po.dueDate}T00:00:00Z`,
        vehicleNo: '경북00가0000',
      },
      version: s.po.version + 1,
    };
    s.asnDue = null;
  }
  return s.po;
}

function guardCdc(request: Request, cdcId: string) {
  const who = operator(request);
  if (!who) return unauthorized();
  if (!who.centers.includes(cdcId)) return problem(403, 'FORBIDDEN');
  return null;
}

export const purchaseHandlers = [
  // ---------------------------------------------------------------- 공급사
  http.get(`${API_BASE}/suppliers`, ({ request }) => {
    if (!operator(request)) return unauthorized();
    const state = new URL(request.url).searchParams.get('state');
    return HttpResponse.json({
      items: store.suppliers.filter((s) => !state || s.state === state),
    });
  }),
  http.get(`${API_BASE}/suppliers/:supplierId`, ({ request, params }) => {
    if (!operator(request)) return unauthorized();
    const s = store.suppliers.find((x) => x.supplierId === params.supplierId);
    return s ? HttpResponse.json(s) : problem(404, 'NOT_FOUND');
  }),
  http.post(`${API_BASE}/suppliers`, async ({ request }) => {
    if (!operator(request)) return unauthorized();
    const body = (await request.clone().json()) as SupplierBody;
    return idempotent(request, () => {
      if (!body.name?.trim()) return problem(422, 'VALIDATION_FAILED', [{ field: 'name', reason: 'REQUIRED' }]);
      if (!(body.leadTimeDays >= 0)) return problem(422, 'VALIDATION_FAILED', [{ field: 'leadTimeDays', reason: 'INVALID_FORMAT' }]);
      const s: Supplier = {
        supplierId: `SUP-${String(store.sseq++).padStart(3, '0')}`,
        name: body.name.trim(),
        businessNo: body.businessNo?.trim() || null,
        contactName: body.contactName?.trim() || null,
        phone: body.phone?.trim() || null,
        leadTimeDays: body.leadTimeDays,
        skus: [...new Set(body.skus)],
        replyMode: body.replyMode,
        state: 'ACTIVE',
        createdAt: stamp(),
      };
      store.suppliers.push(s);
      return { status: 201, body: s };
    });
  }),

  // ---------------------------------------------------------------- 발주
  http.get(`${API_BASE}/purchase-orders`, ({ request }) => {
    const q = new URL(request.url).searchParams;
    const cdcId = q.get('cdcId') ?? '';
    const denied = guardCdc(request, cdcId);
    if (denied) return denied;
    const state = q.get('state');
    const items = store.pos
      .filter((s) => s.po.cdcId === cdcId)
      .map(advance)
      .filter((po) => !state || po.state === state)
      .sort((a, b) => b.issuedAt.localeCompare(a.issuedAt));
    return HttpResponse.json({ items });
  }),
  http.get(`${API_BASE}/purchase-orders/:id`, ({ request, params }) => {
    const s = store.pos.find((x) => x.po.purchaseOrderId === params.id);
    if (!s) return operator(request) ? problem(404, 'NOT_FOUND') : unauthorized();
    const denied = guardCdc(request, s.po.cdcId);
    return denied ?? HttpResponse.json(advance(s));
  }),
  http.post(`${API_BASE}/purchase-orders`, async ({ request }) => {
    const body = (await request.clone().json()) as PoBody;
    const denied = guardCdc(request, body.cdcId);
    if (denied) return denied;
    const who = operator(request)!;
    return idempotent(request, () => {
      const supplier = store.suppliers.find((x) => x.supplierId === body.supplierId);
      if (!supplier || supplier.state !== 'ACTIVE') return problem(422, 'VALIDATION_FAILED', [{ field: 'supplierId', reason: 'NOT_ALLOWED' }]);
      if (!body.lines.length || body.lines.some((l) => !(l.qty > 0))) return problem(422, 'VALIDATION_FAILED', [{ field: 'lines', reason: 'REQUIRED' }]);
      if (body.lines.some((l) => !supplier.skus.includes(l.sku))) return problem(422, 'VALIDATION_FAILED', [{ field: 'lines.sku', reason: 'NOT_ALLOWED' }]);
      const n = store.seq++;
      const po: PurchaseOrder = {
        purchaseOrderId: `PO-${ymd()}-${String(n).padStart(4, '0')}`,
        cdcId: body.cdcId,
        supplierId: supplier.supplierId,
        supplierName: supplier.name,
        state: 'ISSUED',
        dueDate: body.dueDate,
        note: body.note?.trim() || null,
        lines: body.lines.map((l) => ({
          sku: l.sku,
          orderedQty: l.qty,
          confirmedQty: null,
          shippedQty: null,
          lot: null,
          expiresAt: null,
          receivedQty: null,
          rejectedQty: null,
        })),
        issuedBy: who.subject,
        issuedAt: stamp(),
        repliedAt: null,
        replyNote: null,
        asn: null,
        receivedAt: null,
        receivedBy: null,
        cancelledAt: null,
        cancelReason: null,
        version: 1,
      };
      store.pos.push({
        po,
        replyDue: Date.now() + fakeSupplier.replyMs,
        asnDue: null,
      });
      return { status: 201, body: po };
    });
  }),
  http.post(`${API_BASE}/purchase-orders/:id/cancellations`, async ({ request, params }) => {
    const s = store.pos.find((x) => x.po.purchaseOrderId === params.id);
    if (!s) return operator(request) ? problem(404, 'NOT_FOUND') : unauthorized();
    const denied = guardCdc(request, s.po.cdcId);
    if (denied) return denied;
    const { reason } = (await request.clone().json()) as { reason: string };
    return idempotent(request, () => {
      advance(s);
      if (!['ISSUED', 'CONFIRMED', 'PARTIALLY_CONFIRMED'].includes(s.po.state)) return problem(409, 'INVALID_STATE');
      if (!reason?.trim()) return problem(422, 'VALIDATION_FAILED', [{ field: 'reason', reason: 'REQUIRED' }]);
      s.po = {
        ...s.po,
        state: 'CANCELLED',
        cancelledAt: stamp(),
        cancelReason: reason.trim(),
        version: s.po.version + 1,
      };
      s.replyDue = null;
      s.asnDue = null;
      return { status: 200, body: s.po };
    });
  }),
  // cdc-inbound — ASN 실수령·검수 확정 → 재고관리에 LOT 로 더한다(입고장 칸)
  http.post(`${API_BASE}/asn/:asnId/receipts`, async ({ request, params }) => {
    const s = store.pos.find((x) => x.po.asn?.asnId === params.asnId);
    if (!s) return operator(request) ? problem(404, 'NOT_FOUND') : unauthorized();
    const denied = guardCdc(request, s.po.cdcId);
    if (denied) return denied;
    const who = operator(request)!;
    const body = (await request.clone().json()) as ReceiptBody;
    return idempotent(request, () => {
      if (s.po.state !== 'ASN_RECEIVED') return problem(409, 'INVALID_STATE');
      for (const l of s.po.lines) {
        const r = body.lines.find((x) => x.sku === l.sku);
        const got = (r?.receivedQty ?? 0) + (r?.rejectedQty ?? 0);
        if (!r || r.receivedQty < 0 || r.rejectedQty < 0 || got > (l.shippedQty ?? 0)) return problem(422, 'VALIDATION_FAILED', [{ field: `lines.${l.sku}`, reason: 'NOT_ALLOWED' }]);
      }
      const lines = s.po.lines.map((l) => {
        const r = body.lines.find((x) => x.sku === l.sku)!;
        if (r.receivedQty > 0 && l.lot) receiveIntoStock(s.po.cdcId, l.sku, l.lot, l.expiresAt, r.receivedQty);
        return { ...l, receivedQty: r.receivedQty, rejectedQty: r.rejectedQty };
      });
      s.po = {
        ...s.po,
        lines,
        state: 'RECEIVED',
        receivedAt: stamp(),
        receivedBy: who.subject,
        version: s.po.version + 1,
      };
      return { status: 200, body: s.po };
    });
  }),
];
