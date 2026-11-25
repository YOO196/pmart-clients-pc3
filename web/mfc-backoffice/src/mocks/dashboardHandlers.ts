// ⚠ 화면 개발·시험용 목 — 센터 대시보드 지표(결품 많은 상품 fulfillment 0.32.0 by-sku, 정시 배송 dispatch 0.13.0 DD-4). 실제 서버 동작이 아니다.
import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import { operator, problem, unauthorized } from './support';
import { hourShare } from '../features/dashboard/dashboardRules';
import { hasDemoData, scaled } from './demoCenters';
import { shipDay } from './shipSim';

const canAccess = (request: Request, mfcId: string) => operator(request)?.centers.includes(mfcId) ?? false;

const SKUS = [
  { sku: 'SKU-MILK-1L', productName: '서울우유 1L', pickedLines: 212, SHORT: 9, DAMAGED: 2, SPOILED: 1, BLOCKED: 0 },
  { sku: 'SKU-EGG-30', productName: '특란 30구', pickedLines: 96, SHORT: 3, DAMAGED: 4, SPOILED: 0, BLOCKED: 0 },
  { sku: 'SKU-TOFU', productName: '국산콩 두부 300g', pickedLines: 140, SHORT: 5, DAMAGED: 0, SPOILED: 1, BLOCKED: 0 },
  { sku: 'SKU-BANANA', productName: '바나나 1송이', pickedLines: 188, SHORT: 3, DAMAGED: 0, SPOILED: 0, BLOCKED: 0 },
  { sku: 'SKU-RAMEN-5', productName: '라면 5입', pickedLines: 75, SHORT: 2, DAMAGED: 0, SPOILED: 0, BLOCKED: 0 },
  { sku: 'SKU-WATER-2L', productName: '생수 2L', pickedLines: 260, SHORT: 1, DAMAGED: 0, SPOILED: 0, BLOCKED: 0 },
];

const days = (from: string, to: string) => {
  const out: string[] = [];
  for (let t = Date.parse(`${from}T00:00:00Z`); t <= Date.parse(`${to}T00:00:00Z`); t += 86_400_000) out.push(new Date(t).toISOString().slice(0, 10));
  return out;
};

export const dashboardHandlers = [
  // 출하 약속 준수율(fulfillment 0.35.0) — 칸 = 약속 시각(서울)을 bucket 으로 내린 값, 0건 칸은 줄 없음. 상한은 picking-lines 와 같다
  http.get(`${API_BASE}/metrics/ship-promises`, ({ request }) => {
    if (!operator(request)) return unauthorized();
    const q = new URL(request.url).searchParams;
    const mfcId = q.get('mfcId') ?? '';
    if (!canAccess(request, mfcId)) return problem(403, 'FORBIDDEN');
    const from = q.get('from') ?? '';
    const to = q.get('to') ?? '';
    const bucket = q.get('bucket') ?? 'DAY';
    const limit = ({ HOUR: 7, DAY: 92, WEEK: 366, MONTH: 366 } as Record<string, number>)[bucket];
    if (!limit) return problem(400, 'VALIDATION_FAILED');
    if (from && to && (Date.parse(to) - Date.parse(from)) / 86_400_000 + 1 > limit) return problem(400, 'VALIDATION_FAILED');
    const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(new Date());
    const nowHour = Number(new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Seoul', hour: '2-digit', hourCycle: 'h23' }).format(new Date()));
    type Acc = { date: string; hour: string | null; onTime: number; late: number };
    const acc = new Map<string, Acc>();
    const add = (key: string, date: string, hour: string | null, onTime: number, late: number) => {
      const a = acc.get(key) ?? { date, hour, onTime: 0, late: 0 };
      a.onTime += onTime;
      a.late += late;
      acc.set(key, a);
    };
    if (hasDemoData(mfcId) || mfcId === 'MFC-BJG-01')
      for (const d of days(from, to)) {
        const s = shipDay(mfcId, d, today);
        if (!s) continue;
        if (bucket === 'HOUR') {
          const last = d === today ? nowHour : 23;
          for (let h = 0; h <= last; h++) add(`${d}T${h}`, d, `${d}T${String(h).padStart(2, '0')}:00:00+09:00`, hourShare(s.onTime, h, last), hourShare(s.late, h, last));
        } else if (bucket === 'WEEK') {
          const monday = new Date(Date.parse(`${d}T00:00:00Z`) - ((new Date(`${d}T00:00:00Z`).getUTCDay() + 6) % 7) * 86_400_000).toISOString().slice(0, 10);
          add(monday, monday, null, s.onTime, s.late);
        } else if (bucket === 'MONTH') add(d.slice(0, 7), `${d.slice(0, 7)}-01`, null, s.onTime, s.late);
        else add(d, d, null, s.onTime, s.late);
      }
    const items = [...acc.values()].filter((a) => a.onTime + a.late > 0).map((a) => ({ date: a.date, hour: a.hour, mfcId, due: a.onTime + a.late, onTime: a.onTime, late: a.late, pending: 0 }));
    return HttpResponse.json({ items, asOf: new Date().toISOString() });
  }),
  http.get(`${API_BASE}/metrics/picking-lines/by-sku`, ({ request }) => {
    if (!operator(request)) return unauthorized();
    const q = new URL(request.url).searchParams;
    const mfcId = q.get('mfcId') ?? '';
    if (!canAccess(request, mfcId)) return problem(403, 'FORBIDDEN');
    if (!hasDemoData(mfcId)) return HttpResponse.json({ items: [], sort: 'shortLines', minPickedLines: null, asOf: new Date().toISOString() });
    const sc = (n: number) => scaled(n, mfcId);
    const limit = Number(q.get('limit') ?? 10);
    const items = SKUS.map(({ SHORT: s1, DAMAGED: s2, SPOILED: s3, BLOCKED: s4, ...s }) => ({ s, SHORT: sc(s1), DAMAGED: sc(s2), SPOILED: sc(s3), BLOCKED: sc(s4) }))
      .map(({ s, SHORT, DAMAGED, SPOILED, BLOCKED }) => ({ ...s, pickedLines: sc(s.pickedLines), shortLines: SHORT + DAMAGED + SPOILED + BLOCKED, shortLinesByReason: { SHORT, DAMAGED, SPOILED, BLOCKED } }))
      .sort((a, b) => b.shortLines - a.shortLines)
      .slice(0, limit);
    return HttpResponse.json({ items, sort: 'shortLines', minPickedLines: null, asOf: new Date().toISOString() });
  }),
  http.get(`${API_BASE}/metrics/on-time-deliveries`, ({ request }) => {
    if (!operator(request)) return unauthorized();
    const q = new URL(request.url).searchParams;
    const mfcId = q.get('mfcId') ?? '';
    if (!mfcId || !canAccess(request, mfcId)) return problem(403, 'FORBIDDEN');
    const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(new Date());
    const list = days(q.get('from') ?? today, q.get('to') ?? today);
    if (list.length > 31) return problem(400, 'VALIDATION_FAILED');
    // 일요일은 셀 배송 없음(줄 없음 — 0건 날짜) — 오늘은 요일과 상관없이 있다(피킹 목과 같게, 일요일에 시험이 깨지지 않게). 오늘은 약속 전(pending)이 남아 있다.
    const items = !hasDemoData(mfcId) ? [] : list
      .filter((d) => d === today || new Date(`${d}T00:00:00Z`).getUTCDay() !== 0)
      .map((d) => {
        const n = Number(d.slice(8, 10));
        const due = scaled(d === today ? 18 : 60 + ((n * 13) % 40), mfcId);
        const late = Math.min(due, scaled(d === today ? 2 : 2 + (n % 6), mfcId));
        return { date: d, mfcId, due, onTime: due - late, late, unjudged: n % 4, pending: scaled(d === today ? 9 : 0, mfcId) };
      });
    return HttpResponse.json({ items, asOf: new Date().toISOString() });
  }),
];
