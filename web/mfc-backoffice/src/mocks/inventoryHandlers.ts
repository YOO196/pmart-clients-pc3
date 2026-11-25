// 재고 목: mfc-inventory-service 0.16.0 — 위치·LOT 정정, 순환 실사(시작·조회·승인), 출하 부적격 LOT, 보충 기준, 상품 취급.
// 상품별 재고 조회(`/mfcs/{id}/stock`)는 moveHandlers 에 있다(같은 db.stockUnits).
// 서버 규칙 중 화면이 보여 줄 것만: 그 센터 권한, 본사 승인 번호(AP-1 — 정정은 목 기준 한 줄 10개 이상이면 422 APPROVAL_REQUIRED, 실사·그 밖은 번호 선택), 정정 수량 ≤ 출발 단위(422 INSUFFICIENT_STOCK),
// 실사 시작은 실사 잠금 칸만(409 LOCATION_NOT_LOCKED), 승인은 PENDING_APPROVAL·시작/계수한 사람 아님(422 SELF_APPROVAL),
// 보충 기준은 고회전 선반만(422 REPLENISH_ONLY_HIGH_TURNOVER)·min ≤ target, 취급 켜기는 ACTIVE 만(422 SKU_INACTIVE)·버전.
import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import { db, nextSeq, timestamp, type MockCountSession } from './db';
import { approvalProblem, expectedVersion, idempotent, operator, problem, unauthorized } from './support';
import { MOCK_PRODUCTS, productOfSku } from './catalog';
import { emitStockChange } from './stockStreamHandlers';

const canAccess = (request: Request, mfcId: string) => operator(request)?.centers.includes(mfcId) ?? false;
const isSupervisor = (request: Request) => operator(request)?.roles.includes('MFC_SUPERVISOR') ?? false;
const actor = (request: Request) => operator(request)?.subject ?? '';
const keyOf = (request: Request) => request.headers.get('Idempotency-Key') ?? '';
const base = `${API_BASE}/mfcs/:mfcId`;

function gate(request: Request, params: Record<string, unknown>): string | Response {
  if (!operator(request)) return unauthorized();
  const mfcId = String(params.mfcId);
  return canAccess(request, mfcId) ? mfcId : problem(403, 'FORBIDDEN');
}

/** LOT 화면 번호(inventory 0.30.0 lot-numbers 목) — 목에 없는 LOT 은 응답에서 빠진다 */
export const MOCK_LOT_NUMBERS: Readonly<Record<string, { lotNo: string; sku: string; expiryDate: string }>> = {
  'LOT-MILK-A': { lotNo: 'L261107000497', sku: 'SKU-MILK-1', expiryDate: '2026-11-25' },
  'LOT-MILK-B': { lotNo: 'L261110000102', sku: 'SKU-MILK-1', expiryDate: '2026-11-28' },
  'LOT-RAMEN-1': { lotNo: 'L261101000033', sku: 'SKU-RAMEN-5', expiryDate: '2027-05-01' },
  'LOT-RCV-1': { lotNo: 'L261118000201', sku: 'SKU-MILK-1', expiryDate: '2026-11-30' },
};

export const inventoryHandlers = [
  http.get(`${API_BASE}/mfcs/:mfcId/lot-numbers`, ({ request, params }) => {
    const who = operator(request);
    if (!who) return unauthorized();
    if (!who.centers.includes(String(params.mfcId))) return problem(403, 'FORBIDDEN');
    const ids = [...new Set(new URL(request.url).searchParams.getAll('lotIds'))];
    if (ids.length === 0 || ids.length > 200) return problem(400, 'VALIDATION_FAILED');
    const items = ids.filter((id) => MOCK_LOT_NUMBERS[id]).map((id) => ({ lotId: id, productName: null, ...MOCK_LOT_NUMBERS[id]! }));
    return HttpResponse.json({ items });
  }),
  http.post(`${base}/stock-corrections`, async ({ request, params }) => {
    const mfcId = gate(request, params);
    if (mfcId instanceof Response) return mfcId;
    const body = (await request.json()) as {
      reason: string;
      approvalRef?: string;
      lines: Array<{ sku: string; lotId: string; fromLocation: string; qualityState: string; workState: string; qty: number; toLocation?: string; toSourceLotRef?: string }>;
    };
    return idempotent(request, () => {
      // 목 기준: 한 줄 10개 이상(실서버 기준은 한 건 손실 10만 원 이상 또는 한 SKU 20개 이상 — 서버가 정함). 승인 대상 = 이 요청의 키.
      const big = body.lines.some((l) => l.qty >= 10);
      const need = big || body.approvalRef ? approvalProblem(`${mfcId}:CORRECTION:${keyOf(request)}`, '한 SKU 20개 이상(목: 10개 이상)', body.approvalRef) : null;
      if (need) return need;
      for (const l of body.lines) {
        const unit = db.stockUnits.find(
          (u) => u.mfcId === mfcId && u.sku === l.sku && u.lotId === l.lotId && u.locationCode === l.fromLocation && u.qualityState === l.qualityState && u.workState === l.workState,
        );
        if (!unit || unit.qty < l.qty) return problem(422, 'INSUFFICIENT_STOCK');
      }
      for (const l of body.lines) {
        db.stockUnits = db.stockUnits.flatMap((u) => {
          if (u.mfcId !== mfcId || u.sku !== l.sku || u.lotId !== l.lotId || u.locationCode !== l.fromLocation || u.qualityState !== l.qualityState) return [u];
          const rest = u.qty - l.qty;
          const moved = { ...u, qty: l.qty, locationCode: l.toLocation || u.locationCode, lotId: l.toSourceLotRef ? `LOT-${l.toSourceLotRef}` : u.lotId };
          return rest > 0 ? [{ ...u, qty: rest }, moved] : [moved];
        });
      }
      // 재고 실시간 스트림(0.46.0) — 정정도 확정 단위 하나(CORRECTION)
      emitStockChange(
        mfcId,
        'CORRECTION',
        body.lines.flatMap((l) => {
          const from = { sku: l.sku, lotId: l.lotId, locationCode: l.fromLocation, qualityState: l.qualityState, workState: l.workState };
          const to = { ...from, locationCode: l.toLocation || l.fromLocation, lotId: l.toSourceLotRef ? `LOT-${l.toSourceLotRef}` : l.lotId };
          return [
            { ...from, delta: -l.qty },
            { ...to, delta: l.qty },
          ];
        }),
      );
      return { status: 201, body: { status: 'APPLIED', requestId: keyOf(request), resultId: `CMT-${nextSeq()}` } };
    });
  }),

  // (0.42.0) 실사 계획 — locationCodes 없이 rotationSize(없으면 20)면 서버가 칸을 고른다(순환 실사). 목: 그 센터 ACTIVE 칸 중 열린 실사에 없는 칸을 코드 순으로
  http.post(`${base}/count-plans`, async ({ request, params }) => {
    const mfcId = gate(request, params);
    if (mfcId instanceof Response) return mfcId;
    if (!isSupervisor(request)) return problem(403, 'FORBIDDEN');
    const body = (await request.json()) as { locationCodes?: string[]; rotationSize?: number; assigneeId?: string | null; reason?: string };
    return idempotent(request, () => {
      if (body.locationCodes && body.rotationSize !== undefined) return problem(400, 'VALIDATION_FAILED', [{ field: 'rotationSize', reason: 'CONFLICT' }]);
      const size = body.rotationSize ?? 20;
      if (!body.locationCodes && (size < 1 || size > 200)) return problem(400, 'VALIDATION_FAILED', [{ field: 'rotationSize', reason: 'RANGE' }]);
      const busy = new Set([...db.countSessions.values()].filter((c) => c.mfcId === mfcId && ['COUNTING', 'RECOUNT_REQUIRED', 'PENDING_APPROVAL'].includes(c.state)).flatMap((c) => c.locationCodes ?? []));
      const codes =
        body.locationCodes ??
        [...db.locations.values()]
          .filter((l) => l.mfcId === mfcId && l.state === 'ACTIVE' && !busy.has(l.locationCode ?? ''))
          .map((l) => l.locationCode ?? '')
          .sort()
          .slice(0, size);
      if (codes.length === 0) return problem(422, 'NO_COUNT_LOCATIONS');
      const planId = `PLAN-${nextSeq()}`;
      const sessions = codes.map((code) => {
        const s: MockCountSession = {
          sessionId: `CNT-${nextSeq()}`,
          mfcId,
          state: 'COUNTING',
          locationCodes: [code],
          reason: body.reason ?? '순환 실사',
          createdBy: actor(request),
          firstCounter: null,
          recounter: null,
          approverId: null,
          approvalRef: null,
          baselineAt: timestamp(),
          sheet: [],
          differences: null,
          commitId: null,
          version: 1,
          updatedAt: timestamp(),
        };
        db.countSessions.set(s.sessionId, s);
        return { sessionId: s.sessionId, locationCode: code, state: 'COUNTING' as const, exceptionCount: 0, openExceptionCount: 0 };
      });
      return {
        status: 201,
        body: { planId, mfcId, state: 'OPEN', reason: body.reason ?? '순환 실사', assigneeId: body.assigneeId ?? null, createdBy: actor(request), createdAt: timestamp(), sessions, lockedLocationCodes: codes },
      };
    });
  }),

  http.post(`${base}/count-sessions`, async ({ request, params }) => {
    const mfcId = gate(request, params);
    if (mfcId instanceof Response) return mfcId;
    const body = (await request.json()) as { locationCodes: string[]; reason?: string };
    return idempotent(request, () => {
      const locked = body.locationCodes.every((code) => [...db.locations.values()].some((l) => l.mfcId === mfcId && l.locationCode === code && l.state === 'COUNT_LOCKED'));
      if (!locked) return problem(409, 'LOCATION_NOT_LOCKED');
      const s: MockCountSession = {
        sessionId: `CNT-${nextSeq()}`,
        mfcId,
        state: 'COUNTING',
        locationCodes: body.locationCodes,
        reason: body.reason ?? null,
        createdBy: actor(request),
        firstCounter: null,
        recounter: null,
        approverId: null,
        approvalRef: null,
        baselineAt: timestamp(),
        sheet: db.stockUnits
          .filter((u) => u.mfcId === mfcId && body.locationCodes.includes(u.locationCode))
          .map((u) => ({ locationCode: u.locationCode, sku: u.sku, productName: null, barcodes: [], lotId: u.lotId, expiryDate: null })),
        differences: null,
        commitId: null,
        version: 1,
        updatedAt: timestamp(),
      };
      db.countSessions.set(s.sessionId, s);
      return { status: 201, body: s };
    });
  }),

  http.get(`${base}/count-sessions/:sessionId`, ({ request, params }) => {
    const mfcId = gate(request, params);
    if (mfcId instanceof Response) return mfcId;
    const s = db.countSessions.get(String(params.sessionId));
    return s && s.mfcId === mfcId ? HttpResponse.json(s) : problem(404, 'NOT_FOUND');
  }),

  http.post(`${base}/count-sessions/:sessionId/approvals`, async ({ request, params }) => {
    const mfcId = gate(request, params);
    if (mfcId instanceof Response) return mfcId;
    if (!isSupervisor(request)) return problem(403, 'FORBIDDEN');
    const s = db.countSessions.get(String(params.sessionId));
    if (!s || s.mfcId !== mfcId) return problem(404, 'NOT_FOUND');
    const body = (await request.json()) as { action: 'APPROVE' | 'REJECT'; approvalRef?: string; note?: string };
    return idempotent(request, () => {
      if (s.state !== 'PENDING_APPROVAL') return problem(409, 'INVALID_STATE');
      const me = actor(request);
      if ([s.createdBy, s.firstCounter, s.recounter].includes(me)) return problem(422, 'SELF_APPROVAL');
      const next: MockCountSession = {
        ...s,
        state: body.action === 'APPROVE' ? 'ADJUSTED' : 'REJECTED',
        approverId: me,
        approvalRef: body.approvalRef ?? null,
        commitId: body.action === 'APPROVE' ? `CMT-${nextSeq()}` : null,
        version: (s.version ?? 0) + 1,
        updatedAt: timestamp(),
      };
      db.countSessions.set(next.sessionId, next);
      return { status: 200, body: next };
    });
  }),

  http.get(`${base}/unshippable-lots`, ({ request, params }) => {
    const mfcId = gate(request, params);
    if (mfcId instanceof Response) return mfcId;
    const items = db.unshippable
      .filter((u) => u.mfcId === mfcId)
      .sort((a, b) => (a.expiryDate ?? '').localeCompare(b.expiryDate ?? ''))
      .map((u) => ({
        sku: u.sku,
        lotId: u.lotId,
        expiryDate: u.expiryDate,
        manufactureDate: u.manufactureDate,
        locationCode: u.locationCode,
        locationCategoryId: u.locationCategoryId,
        onMiscShelf: u.onMiscShelf,
        qty: u.qty,
      }));
    return HttpResponse.json({ items });
  }),

  http.get(`${base}/replenishment-policies`, ({ request, params }) => {
    const mfcId = gate(request, params);
    if (mfcId instanceof Response) return mfcId;
    return HttpResponse.json({ items: db.policies.filter((p) => p.mfcId === mfcId) });
  }),

  http.put(`${base}/replenishment-policies`, async ({ request, params }) => {
    const mfcId = gate(request, params);
    if (mfcId instanceof Response) return mfcId;
    if (!isSupervisor(request)) return problem(403, 'FORBIDDEN');
    const body = (await request.json()) as { locationCode: string; sku: string; minQty: number; targetQty: number; unitQty: number };
    return idempotent(request, () => {
      if (body.minQty > body.targetQty || body.unitQty < 1) return problem(400, 'VALIDATION_FAILED', [{ field: 'minQty', reason: 'INVALID_FORMAT' }]);
      const loc = [...db.locations.values()].find((l) => l.mfcId === mfcId && l.locationCode === body.locationCode);
      if (!loc?.highTurnover) return problem(422, 'REPLENISH_ONLY_HIGH_TURNOVER');
      const p = { mfcId, ...body, updatedBy: actor(request), updatedAt: timestamp() };
      db.policies = [...db.policies.filter((x) => !(x.mfcId === mfcId && x.locationCode === body.locationCode && x.sku === body.sku)), p];
      return { status: 200, body: p };
    });
  }),

  http.delete(`${base}/replenishment-policies`, ({ request, params }) => {
    const mfcId = gate(request, params);
    if (mfcId instanceof Response) return mfcId;
    if (!isSupervisor(request)) return problem(403, 'FORBIDDEN');
    const q = new URL(request.url).searchParams;
    db.policies = db.policies.filter((x) => !(x.mfcId === mfcId && x.locationCode === q.get('locationCode') && x.sku === q.get('sku')));
    return new HttpResponse(null, { status: 204 });
  }),

  http.get(`${base}/sku-handlings`, ({ request, params }) => {
    const mfcId = gate(request, params);
    if (mfcId instanceof Response) return mfcId;
    const q = new URL(request.url).searchParams;
    const enabled = q.get('enabled');
    // 0.27.0: undecided = 정한 적 없음(레코드 없음 = version 0)·단종 제외, introducedSince = 그 뒤 생긴 상품(생긴 시각 모르는 예전 상품은 빠짐), totalCount = 거르기 전체 수
    const undecided = q.get('undecided') === 'true';
    const since = q.get('introducedSince');
    const size = Number(q.get('size') ?? 50);
    const all = db.handlings
      .filter((h) => enabled === null || String(h.handlingEnabled) === enabled)
      .filter((h) => !undecided || (h.version === 0 && h.offReason !== 'DISCONTINUED' && h.saleState !== 'DISCONTINUED'))
      .filter((h) => !since || (!!h.introducedAt && h.introducedAt >= since))
      .map((h) => ({ sku: h.sku, handlingEnabled: h.handlingEnabled, version: h.version, skuState: h.skuState, productId: productOfSku(h.sku)?.productId ?? null, changedBy: h.offReason === 'DISCONTINUED' ? 'product-service' : null, reason: h.offReason === 'DISCONTINUED' ? '본사 단종' : null, updatedAt: null, saleState: h.saleState ?? null, offReason: h.offReason ?? null, introducedAt: h.introducedAt ?? null }));
    const items = all.slice(0, size);
    return HttpResponse.json({ centerId: mfcId, items, totalCount: all.length, page: { nextCursor: null, size: items.length } });
  }),

  // 일괄(전부 또는 전무, 최대 500행) — 행 규칙은 단건과 같다(없음 SKU_NOT_FOUND·INACTIVE·단종). 하나라도 틀리면 422 + details[].field = items[i]
  http.post(`${base}/sku-handling-batches`, async ({ request, params }) => {
    const mfcId = gate(request, params);
    if (mfcId instanceof Response) return mfcId;
    if (!isSupervisor(request)) return problem(403, 'FORBIDDEN');
    const body = (await request.json()) as { reason?: string; items: { sku: string; enabled: boolean; expectedVersion?: number }[] };
    return idempotent(request, () => {
      if (body.items.length === 0 || body.items.length > 500 || new Set(body.items.map((i) => i.sku)).size !== body.items.length) return problem(400, 'VALIDATION_FAILED');
      const bad = body.items.flatMap((it, i) => {
        const h = db.handlings.find((x) => x.sku === it.sku);
        const reason = !h
          ? 'SKU_NOT_FOUND'
          : it.expectedVersion !== undefined && it.expectedVersion !== h.version
            ? 'VERSION_CONFLICT'
            : it.enabled && h.skuState === 'INACTIVE'
              ? 'SKU_INACTIVE'
              : it.enabled && (h.offReason === 'DISCONTINUED' || h.saleState === 'DISCONTINUED')
                ? 'SKU_DISCONTINUED'
                : null;
        return reason ? [{ field: `items[${i}]`, reason }] : [];
      });
      if (bad.length > 0) return problem(422, 'SKU_HANDLING_BATCH_REJECTED', bad);
      let changedCount = 0;
      const items = body.items.map((it) => {
        const h = db.handlings.find((x) => x.sku === it.sku)!;
        const changed = h.handlingEnabled !== it.enabled;
        if (changed) changedCount += 1;
        const next = changed ? { ...h, handlingEnabled: it.enabled, version: h.version + 1, offReason: it.enabled ? null : ('CENTER' as const) } : h;
        db.handlings = db.handlings.map((x) => (x === h ? next : x));
        return { sku: next.sku, handlingEnabled: next.handlingEnabled, version: next.version, skuState: next.skuState, productId: productOfSku(next.sku)?.productId ?? null, changedBy: actor(request), reason: body.reason ?? null, updatedAt: timestamp() };
      });
      return { status: 200, body: { status: 'APPLIED', requestId: keyOf(request), occurredAt: timestamp(), changedCount, items } };
    });
  }),

  // 본사 상품 목록·상세(product-service 0.5.0 — q = 관리용 명칭 부분 일치 또는 SKU·바코드 완전 일치)
  http.get(`${API_BASE}/products`, ({ request }) => {
    if (!operator(request)) return unauthorized();
    const q = new URL(request.url).searchParams;
    const text = (q.get('q') ?? '').replace(/\s/g, '').toLowerCase();
    const sale = q.get('saleState');
    const size = Math.min(Number(q.get('size') ?? 50) || 50, 200);
    const start = Number(q.get('cursor') ?? 0) || 0;
    const all = MOCK_PRODUCTS.filter((p) => (!sale || p.saleState === sale) && (!text || p.name.replace(/\s/g, '').toLowerCase().includes(text) || p.skus.some((s) => s.toLowerCase() === text)));
    const items = all.slice(start, start + size).map((p) => ({ productId: p.productId, baseProductId: `BP-${p.productId}`, internalName: p.name, primaryCategoryId: p.categoryId, saleState: p.saleState, version: 1 }));
    return HttpResponse.json({ items, page: { nextCursor: start + size < all.length ? String(start + size) : null, size: items.length } });
  }),
  http.get(`${API_BASE}/products/:productId`, ({ request, params }) => {
    if (!operator(request)) return unauthorized();
    const p = MOCK_PRODUCTS.find((x) => x.productId === String(params.productId));
    if (!p) return problem(404, 'NOT_FOUND');
    return HttpResponse.json({
      productId: p.productId,
      baseProductId: `BP-${p.productId}`,
      internalName: p.name,
      primaryCategoryId: p.categoryId,
      saleState: p.saleState,
      version: 1,
      categoryIds: [p.categoryId],
      skus: p.skus.map((sku) => ({ sku, productId: p.productId, baseProductId: `BP-${p.productId}`, unitType: 'E', unitsPerSku: 1, saleState: p.saleState, version: 1 })),
    });
  }),

  http.post(`${base}/sku-handlings`, async ({ request, params }) => {
    const mfcId = gate(request, params);
    if (mfcId instanceof Response) return mfcId;
    const body = (await request.json()) as { sku: string; enabled: boolean; reason?: string };
    return idempotent(request, () => {
      const h = db.handlings.find((x) => x.sku === body.sku);
      if (!h) return problem(404, 'SKU_NOT_FOUND');
      if (expectedVersion(request) !== h.version) return problem(409, 'VERSION_CONFLICT');
      if (body.enabled && h.skuState === 'INACTIVE') return problem(422, 'SKU_INACTIVE');
      if (body.enabled && (h.offReason === 'DISCONTINUED' || h.saleState === 'DISCONTINUED')) return problem(409, 'SKU_DISCONTINUED');
      const changed = h.handlingEnabled !== body.enabled;
      const next = changed ? { ...h, handlingEnabled: body.enabled, version: h.version + 1, offReason: body.enabled ? null : ('CENTER' as const) } : h.version === 0 ? { ...h, version: 1, offReason: 'CENTER' as const } : h;
      db.handlings = db.handlings.map((x) => (x === h ? next : x));
      return {
        status: 200,
        body: {
          status: 'APPLIED',
          requestId: keyOf(request),
          occurredAt: timestamp(),
          changed,
          handling: { sku: next.sku, handlingEnabled: next.handlingEnabled, version: next.version, skuState: next.skuState, productId: null, changedBy: actor(request), reason: body.reason ?? null, updatedAt: timestamp() },
        },
      };
    });
  }),
];
