// 작업 현황 목: mfc-fulfillment-service 0.4.11 — 작업 목록·상세·내놓기, 출하·포장 조회, 포장 인계 판정.
// 서버 규칙 중 화면이 보여 줄 것만: 그 센터 권한, 목록 기본 ASSIGNED·IN_PROGRESS(state 반복 파라미터), 커서 쪽,
// 내놓기는 담당 본인 또는 관리자 · ASSIGNED/IN_PROGRESS 만 · 진행 중 실적이 있으면 409 EXECUTION_IN_FLIGHT · 담당이 다르면 409.
import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import { db, type MockShipment, type MockTask } from './db';
import { idempotent, operator, problem, unauthorized } from './support';

const canAccess = (request: Request, mfcId: string) => operator(request)?.centers.includes(mfcId) ?? false;
const isSupervisor = (request: Request) => operator(request)?.roles.includes('MFC_SUPERVISOR') ?? false;
const asOf = () => ({ asOf: new Date().toISOString(), freshness: 'CURRENT' as const });

/** 목록은 요약만(상세 칸을 뺀다) */
function summary(t: MockTask) {
  return {
    taskId: t.taskId,
    taskType: t.taskType,
    state: t.state,
    version: t.version,
    mfcId: t.mfcId,
    fulfillmentId: t.fulfillmentId,
    shipmentId: t.shipmentId,
    // 주문 화면 번호(계약 TaskSummary.orderNumber) — 목은 출고에서
    orderNumber: (t.shipmentId ? db.shipments.get(t.shipmentId)?.orderNumber : null) ?? null,
    pickedBy: t.pickedBy ?? null,
    assignment: t.assignment,
    lineCount: t.lineCount,
    plannedQty: t.plannedQty,
    completedQty: t.completedQty,
    remainingQty: t.remainingQty,
    promisedReadyAt: t.promisedReadyAt,
    createdAt: t.createdAt,
    late: t.late,
    idle: t.idle,
    lastActivityAt: t.lastActivityAt,
    headline: t.headline,
  };
}

function found(request: Request, taskId: string): MockTask | HttpResponse<Record<string, unknown>> {
  const t = db.tasks.get(taskId);
  if (!t) return problem(404, 'NOT_FOUND');
  if (!canAccess(request, t.mfcId)) return problem(403, 'FORBIDDEN');
  return t;
}


type Pkg = NonNullable<MockShipment['packages']>[number];

/** 포장 인계 판정(HandoverResolution) — 판정 조회·확인 필요 목록·확인 응답이 같이 쓴다. */
function resolutionOf(s: MockShipment, p: Pkg) {
  return {
    packageId: p.packageId,
    packageVersion: p.packageVersion,
    packageState: p.state,
    verdict: p.state === 'HANDED_OVER' ? ('HANDED_OVER' as const) : ('READY' as const),
    fence: p.fence,
    handoverId: null,
    inventoryCommitId: null,
    inventoryApplyStatus: 'NOT_REQUESTED' as const,
    stopRequestId: null,
    checkRequired: p.state === 'SEALED' && p.fence?.state === 'EXPIRED',
    shipmentId: s.shipmentId,
    orderId: s.orderId,
    // 화면 번호(0.21.0 DL-1) — 출고의 주문번호·포장 라벨 인계 번호
    orderNumber: s.orderNumber ?? null,
    handoverCode: p.handoverCode ?? null,
    packingLocation: 'PAK-C-01',
    riderId: p.fence?.riderId ?? null,
    lastCheck: null,
    asOf: asOf(),
  };
}

/** 결품 지표 목(0.19.0): 오늘 피킹 시작 줄·결품 줄(사유별). 0건 날짜는 줄이 없다(계약) — 서울 센터는 줄 없음. */
const seoulToday = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(new Date());
const pickingLines: Readonly<Record<string, { readonly pickedLines: number; readonly SHORT: number; readonly DAMAGED: number; readonly SPOILED: number; readonly BLOCKED: number }>> = {
  'MFC-BSN-01': { pickedLines: 40, SHORT: 2, DAMAGED: 1, SPOILED: 1, BLOCKED: 0 },
};

export const taskHandlers = [
  http.get(`${API_BASE}/metrics/picking-lines`, ({ request }) => {
    if (!operator(request)) return unauthorized();
    const q = new URL(request.url).searchParams;
    const mfcId = q.get('mfcId') ?? '';
    if (!canAccess(request, mfcId)) return problem(403, 'FORBIDDEN');
    const today = seoulToday();
    const from = q.get('from') ?? '';
    const to = q.get('to') ?? '';
    const v = pickingLines[mfcId];
    const items =
      v && from <= today && today <= to
        ? [{ date: today, mfcId, pickedLines: v.pickedLines, shortLines: v.SHORT + v.DAMAGED + v.SPOILED + v.BLOCKED, shortLinesByReason: { SHORT: v.SHORT, DAMAGED: v.DAMAGED, SPOILED: v.SPOILED, BLOCKED: v.BLOCKED } }]
        : [];
    return HttpResponse.json({ items, asOf: new Date().toISOString() });
  }),

  http.get(`${API_BASE}/tasks`, ({ request }) => {
    if (!operator(request)) return unauthorized();
    const q = new URL(request.url).searchParams;
    const mfcId = q.get('mfcId') ?? '';
    if (!canAccess(request, mfcId)) return problem(403, 'FORBIDDEN');
    const states = q.getAll('state');
    const wanted = states.length ? states : ['ASSIGNED', 'IN_PROGRESS'];
    const type = q.get('type');
    const size = Number(q.get('size') ?? 50);
    const start = Number(q.get('cursor') ?? 0);
    const rows = [...db.tasks.values()]
      .filter((t) => t.mfcId === mfcId && wanted.includes(t.state) && (!type || t.taskType === type))
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt));
    const next = start + size < rows.length ? String(start + size) : null;
    return HttpResponse.json({ items: rows.slice(start, start + size).map(summary), page: { nextCursor: next, size }, asOf: asOf() });
  }),

  http.get(`${API_BASE}/tasks/:taskId`, ({ request, params }) => {
    if (!operator(request)) return unauthorized();
    const t = found(request, String(params.taskId));
    return t instanceof Response ? t : HttpResponse.json({ ...t, orderNumber: (t.shipmentId ? db.shipments.get(t.shipmentId)?.orderNumber : null) ?? null, asOf: asOf() });
  }),

  http.post(`${API_BASE}/tasks/:taskId/releases`, async ({ request, params }) => {
    if (!operator(request)) return unauthorized();
    const t = found(request, String(params.taskId));
    if (t instanceof Response) return t;
    const body = (await request.json()) as { workerId: string; reason?: string };
    const self = operator(request)?.subject === t.assignment?.workerId;
    if (!isSupervisor(request) && !self) return problem(403, 'FORBIDDEN');
    return idempotent(request, () => {
      if (t.state !== 'ASSIGNED' && t.state !== 'IN_PROGRESS') return problem(409, 'INVALID_STATE');
      if (t.assignment?.workerId !== body.workerId) return problem(409, 'INVALID_STATE');
      if ((t.pendingExecutions ?? []).length > 0) return problem(409, 'EXECUTION_IN_FLIGHT');
      const next: MockTask = {
        ...t,
        state: 'READY',
        version: t.version + 1,
        assignment: { workerId: null, assignmentVersion: (t.assignment?.assignmentVersion ?? 0) + 1 },
      };
      db.tasks.set(next.taskId, next);
      return { status: 200, body: summary(next) };
    });
  }),

  http.get(`${API_BASE}/shipments/:shipmentId`, ({ request, params }) => {
    if (!operator(request)) return unauthorized();
    const s = db.shipments.get(String(params.shipmentId));
    if (!s) return problem(404, 'NOT_FOUND');
    if (!canAccess(request, s.mfcId)) return problem(403, 'FORBIDDEN');
    return HttpResponse.json({ ...s, mfcId: undefined });
  }),

  http.get(`${API_BASE}/packages/:packageId/handover-resolution`, ({ request, params }) => {
    if (!operator(request)) return unauthorized();
    const id = String(params.packageId);
    const s = [...db.shipments.values()].find((x) => x.packages?.some((p) => p.packageId === id));
    const p = s?.packages?.find((x) => x.packageId === id);
    if (!s || !p) return problem(404, 'NOT_FOUND');
    if (!canAccess(request, s.mfcId)) return problem(403, 'FORBIDDEN');
    return HttpResponse.json(resolutionOf(s, p));
  }),

  // 확인 필요 포장(MB-3 — 그 센터 작업자·센터 관리자): 인계 허가가 끝났는데(EXPIRED) 확정 없는 밀봉 포장.
  http.get(`${API_BASE}/packages`, ({ request }) => {
    if (!operator(request)) return unauthorized();
    const q = new URL(request.url).searchParams;
    const mfcId = q.get('mfcId') ?? '';
    if (q.get('checkRequired') !== 'true') return problem(400, 'VALIDATION_FAILED', [{ field: 'checkRequired', reason: 'NOT_ALLOWED' }]);
    if (!canAccess(request, mfcId)) return problem(403, 'FORBIDDEN');
    const items = [...db.shipments.values()]
      .filter((s) => s.mfcId === mfcId)
      .flatMap((s) => (s.packages ?? []).filter((p) => p.state === 'SEALED' && p.fence?.state === 'EXPIRED').map((p) => resolutionOf(s, p)));
    return HttpResponse.json({ items, asOf: asOf() });
  }),

  http.post(`${API_BASE}/packages/:packageId/handover-checks`, async ({ request, params }) => {
    if (!operator(request)) return unauthorized();
    const id = String(params.packageId);
    const s = [...db.shipments.values()].find((x) => x.packages?.some((p) => p.packageId === id));
    const p = s?.packages?.find((x) => x.packageId === id);
    if (!s || !p) return problem(404, 'NOT_FOUND');
    if (!canAccess(request, s.mfcId)) return problem(403, 'FORBIDDEN');
    const body = (await request.json()) as { result: 'AT_STATION' | 'TAKEN_BY_RIDER' };
    return idempotent(request, () => {
      if (p.fence?.state === 'HANDOVER_IN_PROGRESS') return problem(409, 'FENCE_ACTIVE');
      if (p.fence?.state !== 'EXPIRED') return problem(409, 'INVALID_STATE');
      const next = body.result === 'TAKEN_BY_RIDER' ? { ...p, state: 'HANDED_OVER' as const, fence: { ...p.fence, state: 'COMMITTED' as const }, handedOverAt: new Date().toISOString() } : { ...p, fence: { ...p.fence, state: 'NONE' as const } };
      s.packages = (s.packages ?? []).map((x) => (x.packageId === id ? next : x));
      return { status: 200, body: resolutionOf(s, next) };
    });
  }),
];
