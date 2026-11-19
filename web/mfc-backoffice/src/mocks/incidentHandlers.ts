// 품질 사고 목(mfc-quality 0.6.0): 목록·단건(그 센터 운영자), 직접 등록(그 센터 MFC_SUPERVISOR, 이 센터 재고가 남은 LOT 만 — 422 LOT_NOT_IN_CENTER),
// 닫기(MFC_SUPERVISOR, X-Expected-Version, 남은 LOT 409 LOTS_NOT_RESOLVED, 이미 닫힘 409 INVALID_STATE).
// 처리 여부는 조회 때 다시 맞춘다: 그 LOT 의 격리 해제 APPLIED(판정 incidentId 가 이 사고이거나 사고 뒤 같은 센터) 또는 폐기 승인(APPROVED·PARTIALLY_EXECUTED·COMPLETED).
import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import type { components } from '../api/generated/mfc-quality';
import { db, nextSeq, timestamp, type MockIncident } from './db';
import { expectedVersion, idempotent, operator, problem, unauthorized } from './support';

type Incident = components['schemas']['QualityIncident'];

const canAccess = (request: Request, mfcId: string) => operator(request)?.centers.includes(mfcId) ?? false;
const isSupervisor = (request: Request) => operator(request)?.roles.includes('MFC_SUPERVISOR') ?? false;

/** LOT 마다 처리한 판정·폐기 ID(없으면 null) */
function resolverOf(i: MockIncident, lotId: string): string | null {
  const seeded = i.seedResolved[lotId];
  if (seeded) return seeded;
  for (const d of db.decisions.values()) {
    const linked = d.incidentId === i.incidentId || (d.mfcId === i.mfcId && (d.decidedAt ?? '') >= i.openedAt);
    if (linked && d.decisionType === 'RELEASE' && d.state === 'APPLIED' && d.lines.some((l) => l.lotId === lotId)) return d.qualityDecisionId;
  }
  for (const d of db.disposals.values()) {
    const ok = d.state === 'APPROVED' || d.state === 'PARTIALLY_EXECUTED' || d.state === 'COMPLETED';
    if (ok && d.mfcId === i.mfcId && (d.requestedAt ?? '') >= i.openedAt && (d.lines ?? []).some((l) => l.lotId === lotId)) return d.disposalApprovalId;
  }
  return null;
}

function view(i: MockIncident): Incident {
  const lots = i.affectedLots.map((l) => {
    const by = resolverOf(i, l.lotId);
    return { ...l, resolved: by !== null, resolvedBy: by };
  });
  const remaining = lots.filter((l) => !l.resolved).length;
  const linked = [...db.decisions.values()].filter((d) => d.incidentId === i.incidentId).map((d) => d.qualityDecisionId);
  return {
    incidentId: i.incidentId,
    mfcId: i.mfcId,
    kind: i.kind,
    origin: i.origin,
    description: i.description,
    openedBy: i.openedBy,
    openedAt: i.openedAt,
    sourceEvent: i.sourceEvent,
    sourceRef: i.sourceRef,
    state: i.closed ? 'CLOSED' : remaining === 0 ? 'DECIDED' : 'OPEN',
    affectedLots: lots,
    remainingLotCount: remaining,
    decisionIds: [...new Set([...linked, ...lots.flatMap((l) => (l.resolvedBy ? [l.resolvedBy] : []))])],
    caseId: null,
    affectedOrderCount: null,
    closedBy: i.closed?.by ?? null,
    closedAt: i.closed?.at ?? null,
    closeReason: i.closed?.reason ?? null,
    version: i.version,
  };
}

export const incidentHandlers = [
  http.get(`${API_BASE}/quality-incidents`, ({ request }) => {
    if (!operator(request)) return unauthorized();
    const url = new URL(request.url);
    const mfcId = url.searchParams.get('mfcId') ?? '';
    if (!canAccess(request, mfcId)) return problem(403, 'FORBIDDEN');
    const states = url.searchParams.getAll('state');
    const wanted = states.length ? states : ['OPEN', 'DECIDED'];
    const items = [...db.incidents.values()]
      .filter((i) => i.mfcId === mfcId)
      .map(view)
      .filter((i) => wanted.includes(i.state ?? ''))
      .sort((a, b) => (a.openedAt ?? '').localeCompare(b.openedAt ?? ''));
    return HttpResponse.json({ items, nextCursor: null });
  }),

  http.get(`${API_BASE}/quality-incidents/:id`, ({ request, params }) => {
    if (!operator(request)) return unauthorized();
    const i = db.incidents.get(String(params.id));
    if (!i) return problem(404, 'NOT_FOUND');
    if (!canAccess(request, i.mfcId)) return problem(403, 'FORBIDDEN');
    return HttpResponse.json(view(i));
  }),

  http.post(`${API_BASE}/quality-incidents`, async ({ request }) => {
    const who = operator(request);
    if (!who) return unauthorized();
    const body = (await request.json()) as { mfcId: string; kind: MockIncident['kind']; description: string; affectedLots: Array<{ lotId: string; qty: number }> };
    if (!canAccess(request, body.mfcId) || !isSupervisor(request)) return problem(403, 'FORBIDDEN');
    const text = body.description.trim();
    if (!text || text.length > 300 || body.affectedLots.length < 1 || body.affectedLots.length > 50) return problem(400, 'VALIDATION_FAILED');
    const missing = body.affectedLots.filter((l) => !db.stockUnits.some((u) => u.mfcId === body.mfcId && u.lotId === l.lotId && u.qty > 0));
    if (missing.length) return problem(422, 'LOT_NOT_IN_CENTER', missing.map((l) => ({ field: 'lotId', reason: l.lotId })));
    return idempotent(request, () => {
      const i: MockIncident = {
        incidentId: `QI-${nextSeq()}`,
        mfcId: body.mfcId,
        kind: body.kind,
        origin: 'MANUAL',
        description: text,
        openedBy: who.subject,
        openedAt: timestamp(),
        sourceEvent: null,
        sourceRef: null,
        affectedLots: body.affectedLots.map((l) => ({ sku: db.stockUnits.find((u) => u.lotId === l.lotId)?.sku ?? null, lotId: l.lotId, qty: l.qty })),
        seedResolved: {},
        closed: null,
        version: 1,
      };
      db.incidents.set(i.incidentId, i);
      return { status: 201, body: view(i) };
    });
  }),

  http.post(`${API_BASE}/quality-incidents/:id/closures`, async ({ request, params }) => {
    const who = operator(request);
    if (!who) return unauthorized();
    const i = db.incidents.get(String(params.id));
    if (!i) return problem(404, 'NOT_FOUND');
    if (!canAccess(request, i.mfcId) || !isSupervisor(request)) return problem(403, 'FORBIDDEN');
    const body = (await request.json()) as { reason: string };
    return idempotent(request, () => {
      const cur = db.incidents.get(i.incidentId)!;
      if (cur.closed) return problem(409, 'INVALID_STATE');
      const v = expectedVersion(request);
      if (v !== undefined && v !== cur.version) return problem(409, 'VERSION_CONFLICT');
      const left = view(cur).affectedLots?.filter((l) => !l.resolved) ?? [];
      if (left.length) return problem(409, 'LOTS_NOT_RESOLVED', left.map((l) => ({ field: 'lotId', reason: l.lotId ?? '' })));
      const next: MockIncident = { ...cur, closed: { by: who.subject, at: timestamp(), reason: body.reason.trim() }, version: cur.version + 1 };
      db.incidents.set(next.incidentId, next);
      return { status: 200, body: view(next) };
    });
  }),
];
