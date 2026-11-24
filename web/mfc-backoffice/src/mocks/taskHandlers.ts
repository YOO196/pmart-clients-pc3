// 작업 현황 목: mfc-fulfillment-service 0.4.11 — 작업 목록·상세·내놓기, 출하·포장 조회, 포장 인계 판정.
// 서버 규칙 중 화면이 보여 줄 것만: 그 센터 권한, 목록 기본 ASSIGNED·IN_PROGRESS(state 반복 파라미터), 커서 쪽,
// 내놓기는 담당 본인 또는 관리자 · ASSIGNED/IN_PROGRESS 만 · 진행 중 실적이 있으면 409 EXECUTION_IN_FLIGHT · 담당이 다르면 409.
import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import { hourShare } from '../features/dashboard/dashboardRules';
import { db, type MockShipment, type MockTask } from './db';
import { idempotent, operator, problem, unauthorized } from './support';
import { DEMO_HOME, hasDemoData, scaled } from './demoCenters';

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

/** 결품 지표 목(0.19.0, bucket 0.34.0): 오늘 피킹 시작 줄·결품 줄(사유별). 0건 날짜는 줄이 없다(계약) — 서울 센터는 줄 없음. */
const seoulToday = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(new Date());
const pickingLines: Readonly<Record<string, { readonly pickedLines: number; readonly SHORT: number; readonly DAMAGED: number; readonly SPOILED: number; readonly BLOCKED: number }>> = {
  'MFC-SEED-01': { pickedLines: 40, SHORT: 2, DAMAGED: 1, SPOILED: 1, BLOCKED: 0 },
};

const pastDays = (today: string, n: number) => {
  const base = Date.parse(`${today}T00:00:00Z`);
  return Array.from({ length: n }, (_, i) => new Date(base - (n - 1 - i) * 86_400_000).toISOString().slice(0, 10));
};
function pastPicking(date: string) {
  const day = Number(date.slice(8, 10));
  if (new Date(`${date}T00:00:00Z`).getUTCDay() === 0) return null;
  // 확대해 볼 만하게 몇 주에 걸친 물결을 얹는다
  const wave = Math.round(35 * Math.sin(Date.parse(`${date}T00:00:00Z`) / 86_400_000 / 9));
  return { pickedLines: 120 + ((day * 37) % 90) + wave, SHORT: 2 + (day % 5), DAMAGED: day % 3 === 0 ? 1 : 0, SPOILED: day % 7 === 0 ? 1 : 0, BLOCKED: 0 };
}

export const taskHandlers = [
  http.get(`${API_BASE}/metrics/picking-lines`, ({ request }) => {
    if (!operator(request)) return unauthorized();
    const q = new URL(request.url).searchParams;
    const mfcId = q.get('mfcId') ?? '';
    if (!canAccess(request, mfcId)) return problem(403, 'FORBIDDEN');
    const today = seoulToday();
    const from = q.get('from') ?? '';
    const to = q.get('to') ?? '';
    // bucket(0.34.0): HOUR 7일·DAY 92일·WEEK·MONTH 366일 상한, 빼면 DAY
    const bucket = q.get('bucket') ?? 'DAY';
    const limit = { HOUR: 7, DAY: 92, WEEK: 366, MONTH: 366 }[bucket];
    if (!limit) return problem(400, 'VALIDATION_FAILED');
    if (from && to && (Date.parse(to) - Date.parse(from)) / 86_400_000 + 1 > limit) return problem(400, 'VALIDATION_FAILED');
    const sc = <T extends Record<string, number>>(x: T): T => Object.fromEntries(Object.entries(x).map(([k, n]) => [k, scaled(n, mfcId)])) as T;
    // 다른 센터(브라우저 목) — 부산진구 값에 센터 규모를 곱한다
    const v = pickingLines[mfcId] ?? (hasDemoData(mfcId) ? sc(pickingLines[DEMO_HOME]!) : undefined);
    const home = mfcId === DEMO_HOME;
    // 날마다 값(오늘은 위 표 그대로). 일요일은 0건 → 줄 없음(계약)
    const daily = v ? pastDays(today, 400).filter((d) => from <= d && d <= to).flatMap((d) => (d === today ? [{ d, x: v }] : pastPicking(d) ? [{ d, x: home ? pastPicking(d)! : sc(pastPicking(d)!) }] : [])) : [];
    type Acc = { date: string; hour: string | null; picked: number; SHORT: number; DAMAGED: number; SPOILED: number; BLOCKED: number };
    const acc = new Map<string, Acc>();
    const add = (key: string, date: string, hour: string | null, x: (typeof pickingLines)[string], part: (n: number) => number) => {
      const a = acc.get(key) ?? { date, hour, picked: 0, SHORT: 0, DAMAGED: 0, SPOILED: 0, BLOCKED: 0 };
      a.picked += part(x.pickedLines);
      a.SHORT += part(x.SHORT);
      a.DAMAGED += part(x.DAMAGED);
      a.SPOILED += part(x.SPOILED);
      a.BLOCKED += part(x.BLOCKED);
      acc.set(key, a);
    };
    const nowHour = Number(new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Seoul', hour: '2-digit', hourCycle: 'h23' }).format(new Date()));
    for (const { d, x } of daily) {
      if (bucket === 'HOUR') {
        // 그날 합계를 하루 수요 곡선으로 나눈다(시간 합 = 그날 합 — 서버 시험과 같은 성질)
        const last = d === today ? nowHour : 23;
        for (let h = 0; h <= last; h++) add(`${d}T${h}`, d, `${d}T${String(h).padStart(2, '0')}:00:00+09:00`, x, (n) => hourShare(n, h, last));
      } else if (bucket === 'WEEK') {
        const monday = new Date(Date.parse(`${d}T00:00:00Z`) - ((new Date(`${d}T00:00:00Z`).getUTCDay() + 6) % 7) * 86_400_000).toISOString().slice(0, 10);
        add(monday, monday, null, x, (n) => n);
      } else if (bucket === 'MONTH') add(d.slice(0, 7), `${d.slice(0, 7)}-01`, null, x, (n) => n);
      else add(d, d, null, x, (n) => n);
    }
    const items = [...acc.values()]
      .filter((a) => a.picked > 0 || a.SHORT + a.DAMAGED + a.SPOILED + a.BLOCKED > 0)
      .map((a) => ({ date: a.date, hour: a.hour, mfcId, pickedLines: a.picked, shortLines: a.SHORT + a.DAMAGED + a.SPOILED + a.BLOCKED, shortLinesByReason: { SHORT: a.SHORT, DAMAGED: a.DAMAGED, SPOILED: a.SPOILED, BLOCKED: a.BLOCKED } }));
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
