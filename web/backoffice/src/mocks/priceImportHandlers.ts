// 가격 일괄 등록 목(pricing-service `/price-import-batches/**`, 백엔드 안내 2026-11-03).
// 업로드는 zip 을 읽지 않고 시드 3행을 만든다: 가격 변경(CHANGE)·새 가격(NEW)·상품 승인 전(SKU_NOT_FOUND).
import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import type { PriceImportBatch, PriceImportLine } from '../api/models';
import { db, nextId, timestamp } from './db';
import { expectedVersion, idempotent, operator, problem, unauthorized } from './support';

const currentPrice = (sku: string) => (db.prices.get(sku) ?? []).find((v) => v.state === 'EFFECTIVE')?.basePrice ?? null;

const firstSkuOf = (productId: string | null | undefined) => (productId ? (db.products.get(productId)?.skus?.[0]?.sku ?? null) : null);

/** 상품 승인 전이던 행: 같은 관리용 명칭의 상품이 생겼으면 SKU 를 찾는다(목에서는 이름으로 잇는다). */
function linkProduct(line: PriceImportLine): PriceImportLine {
  if (line.productId) return line;
  const p = [...db.products.values()].find((x) => x.internalName === line.productName);
  return p ? { ...line, productId: p.productId ?? null } : line;
}

/** SKU·현재 가격을 다시 대조해 상태를 매긴다. 고친 가격(edited)·뺀 행(excluded)은 그대로 둔다. */
function evaluate(lines: readonly PriceImportLine[]): PriceImportLine[] {
  const seen = new Set<string>();
  return lines.map((raw) => {
    const linked = linkProduct(raw);
    const sku = firstSkuOf(linked.productId);
    const current = sku ? currentPrice(sku) : null;
    const basePrice = linked.edited ? linked.basePrice : linked.bundlePrice;
    const priced = basePrice !== null && basePrice !== undefined && basePrice > 0;
    const changeType = sku && priced ? (current === null ? 'NEW' : current === basePrice ? 'UNCHANGED' : 'CHANGE') : undefined;
    let status: PriceImportLine['status'];
    if (linked.excluded) status = 'EXCLUDED';
    else if (!sku) status = 'SKU_NOT_FOUND';
    else if (seen.has(sku)) status = 'DUPLICATE_SKU';
    else if (!priced) status = 'PRICE_REQUIRED';
    else status = changeType === 'UNCHANGED' ? 'UNCHANGED' : 'READY';
    if (sku) seen.add(sku);
    const { result, ...rest } = linked;
    return {
      ...rest,
      sku,
      currentPrice: current,
      basePrice: basePrice ?? null,
      ...(changeType ? { changeType } : {}),
      status,
      ...(result ? { result } : {}),
    };
  });
}

function recheck(b: PriceImportBatch): PriceImportBatch {
  const lines = evaluate(b.lines);
  return { ...b, lines, lineCount: lines.length, submittableCount: lines.filter((l) => l.status === 'READY').length, checkedAt: timestamp() };
}

const seedLines = (batchId: string): PriceImportLine[] => {
  const ids = [...db.products.keys()];
  const mk = (i: number, productId: string | null, name: string, bundlePrice: number): PriceImportLine => ({
    seedProductId: `seed-${batchId}-${i}`,
    productName: name,
    productId,
    bundlePrice,
    basePrice: bundlePrice,
    excluded: false,
    edited: false,
    status: 'READY',
  });
  return [
    mk(1, ids[0] ?? null, db.products.get(ids[0] ?? '')?.internalName ?? '사과 1.5kg', 4900),
    mk(2, ids[1] ?? null, db.products.get(ids[1] ?? '')?.internalName ?? '소고기 미역국 500g', 3900),
    mk(3, null, '수입 망고', 2500),
  ];
};

const bump = (b: PriceImportBatch): PriceImportBatch => ({ ...b, version: b.version + 1 });

const load = (id: unknown) => db.priceBatches.get(String(id));

export const priceImportHandlers = [
  http.post(`${API_BASE}/price-import-batches`, async ({ request }) => {
    if (!operator(request)) return unauthorized();
    const form = await request.formData();
    const file = form.get('file');
    return idempotent(request, () => {
      if (!(file instanceof Blob)) return problem(422, 'BUNDLE_INVALID');
      const batchId = nextId('PB');
      const batch = recheck({
        batchId,
        format: 'SEED_V1',
        sourceSystem: 'bmart-capture',
        sourceName: file instanceof File ? file.name : null,
        state: 'DRAFT',
        version: 0,
        lineCount: 0,
        submittableCount: 0,
        effectiveFrom: null,
        approvalTargetRef: null,
        approvalId: null,
        lines: seedLines(batchId),
        createdAt: timestamp(),
        submittedAt: null,
      });
      db.priceBatches.set(batchId, batch);
      return { status: 201, body: batch };
    });
  }),
  http.get(`${API_BASE}/price-import-batches/:id`, ({ params }) => {
    const b = load(params['id']);
    return b ? HttpResponse.json(b) : problem(404, 'NOT_FOUND');
  }),
  http.put(`${API_BASE}/price-import-batches/:id/lines/:seed`, async ({ request, params }) => {
    if (!operator(request)) return unauthorized();
    const body = (await request.json()) as { basePrice?: number | null; excluded?: boolean };
    return idempotent(request, () => {
      const b = load(params['id']);
      if (!b) return problem(404, 'NOT_FOUND');
      if (b.state !== 'DRAFT') return problem(409, 'BATCH_LOCKED');
      const v = expectedVersion(request);
      if (v !== undefined && v !== b.version) return problem(409, 'VERSION_CONFLICT');
      if (!b.lines.some((l) => l.seedProductId === params['seed'])) return problem(404, 'NOT_FOUND');
      if (body.basePrice !== null && body.basePrice !== undefined && (!Number.isInteger(body.basePrice) || body.basePrice < 1)) {
        return problem(400, 'VALIDATION_FAILED', [{ field: 'basePrice', reason: 'MIN_1' }]);
      }
      const lines = b.lines.map((l) =>
        l.seedProductId === params['seed']
          ? {
              ...l,
              excluded: body.excluded ?? false,
              edited: body.basePrice !== null && body.basePrice !== undefined,
              basePrice: body.basePrice ?? l.bundlePrice ?? null,
            }
          : l,
      );
      const next = bump(recheck({ ...b, lines }));
      db.priceBatches.set(next.batchId, next);
      return { status: 200, body: next };
    });
  }),
  http.post(`${API_BASE}/price-import-batches/:id/refreshes`, ({ request, params }) => {
    if (!operator(request)) return unauthorized();
    return idempotent(request, () => {
      const b = load(params['id']);
      if (!b) return problem(404, 'NOT_FOUND');
      if (b.state !== 'DRAFT') return problem(409, 'BATCH_LOCKED');
      const next = bump(recheck(b));
      db.priceBatches.set(next.batchId, next);
      return { status: 200, body: next };
    });
  }),
  http.post(`${API_BASE}/price-import-batches/:id/submissions`, async ({ request, params }) => {
    if (!operator(request)) return unauthorized();
    const text = await request.text();
    const body = (text ? JSON.parse(text) : {}) as { effectiveFrom?: string | null };
    return idempotent(request, () => {
      const b = load(params['id']);
      if (!b) return problem(404, 'NOT_FOUND');
      if (b.state !== 'DRAFT') return problem(409, 'BATCH_LOCKED');
      const v = expectedVersion(request);
      if (v !== undefined && v !== b.version) return problem(409, 'VERSION_CONFLICT');
      const effectiveFrom = body.effectiveFrom ?? null;
      if (effectiveFrom && new Date(effectiveFrom).getTime() < Date.now()) return problem(422, 'EFFECTIVE_FROM_IN_PAST');
      const checked = recheck(b);
      const ready = checked.lines.filter((l) => l.status === 'READY');
      if (ready.length === 0) return problem(422, 'NOTHING_TO_SUBMIT');
      const targetRef = `priceImportBatch:${b.batchId}`;
      const next = bump({ ...checked, state: 'SUBMITTED', effectiveFrom, approvalTargetRef: targetRef, submittedAt: timestamp() });
      db.priceBatches.set(next.batchId, next);
      const approvalRequest = {
        type: 'PRICE' as const,
        targetService: 'pricing-service' as const,
        targetRef,
        allowedActions: ['APPLY_PRICE_VERSION'],
        summary: `가격 일괄 등록 ${ready.length}건`,
        ...(effectiveFrom ? { requestedEffectiveFrom: effectiveFrom } : {}),
        lines: ready.map((l) => ({
          lineKey: l.sku ?? '',
          requestedAmount: l.basePrice ?? 0,
          attributes: {
            sku: l.sku,
            basePrice: l.basePrice,
            ...(effectiveFrom ? { effectiveFrom } : {}),
            previousPrice: l.currentPrice ?? null,
            changeType: l.changeType,
            seedProductId: l.seedProductId,
            productName: l.productName,
          },
        })),
      };
      return { status: 200, body: { batch: next, approvalRequest }};
    });
  }),
];

/** 승인 결정 → 배치 결과(effects.decide 에서 부른다). 승인이면 가격 버전이 생긴 행은 APPLIED, 반려면 전부 REJECTED. */
export function settlePriceImportBatch(targetRef: string | null | undefined, approvalId: string, approved: boolean): void {
  const batchId = targetRef?.startsWith('priceImportBatch:') ? targetRef.slice('priceImportBatch:'.length) : null;
  const b = batchId ? db.priceBatches.get(batchId) : undefined;
  if (!b) return;
  const lines = b.lines.map((l) => {
    if (l.status !== 'READY') return l;
    const version = l.sku ? (db.prices.get(l.sku) ?? []).find((v) => v.approvalId === approvalId)?.priceVersion : undefined;
    const result = approved && version !== undefined ? { state: 'APPLIED' as const, reasonCode: null, priceVersion: version } : { state: 'REJECTED' as const, reasonCode: approved ? 'SKU_NOT_FOUND' : 'APPROVAL_REJECTED', priceVersion: null };
    return { ...l, result };
  });
  const applied = lines.filter((l) => l.result?.state === 'APPLIED').length;
  const submitted = lines.filter((l) => l.result).length;
  const state = !approved ? 'REJECTED' : applied === submitted ? 'APPLIED' : 'PARTIALLY_APPLIED';
  db.priceBatches.set(b.batchId, { ...b, lines, state, approvalId });
}
