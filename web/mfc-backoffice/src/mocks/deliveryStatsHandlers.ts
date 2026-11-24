// 배송 통계 목 — delivery-execution 0.38.0 `GET /delivery-metrics`, delivery-dispatch 0.16.0 `GET /metrics/dispatch`.
// 서버 규칙 중 화면이 보여 줄 것만: 관리자(OPERATOR_ADMIN·RIDER_OPS·CS_AGENT)가 아니면 mfcId 필수(400)·그 센터만(403), 최대 31일(400),
// 0건 묶음은 줄 없음. 값은 날짜·라이더로 정해지는 결정적인 수(목 배송은 부산 MFC-BJG-01 에만).
import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import { operator, problem, unauthorized } from './support';
import { hasDemoData } from './demoCenters';

const CENTER = 'MFC-BJG-01';
const RIDERS = ['RD-1', 'RD-2', 'RD-7', 'RD-31'] as const;
const ALL_CENTERS = ['OPERATOR_ADMIN', 'RIDER_OPS', 'CS_AGENT'];
const iso = /^\d{4}-\d{2}-\d{2}$/;
const seoulToday = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(new Date());
const addDays = (d: string, n: number) => new Date(Date.parse(`${d}T00:00:00Z`) + n * 86_400_000).toISOString().slice(0, 10);
const span = (from: string, to: string) => Math.round((Date.parse(to) - Date.parse(from)) / 86_400_000) + 1;
const num = (s: string) => {
  let x = 7;
  for (let i = 0; i < s.length; i++) x = (x * 31 + s.charCodeAt(i)) % 9973;
  return x;
};

/** 권한·기간 — 통과하면 [from, to, mfcId|null] */
function guard(request: Request, defaultDays: number): Response | readonly [string, string, string | null] {
  const op = operator(request);
  if (!op) return unauthorized();
  const q = new URL(request.url).searchParams;
  const mfcId = q.get('mfcId');
  if (!op.roles.some((r) => ALL_CENTERS.includes(r))) {
    if (!mfcId) return problem(400, 'VALIDATION_FAILED');
    if (!op.centers.includes(mfcId)) return problem(403, 'FORBIDDEN');
  }
  const to = q.get('to') ?? seoulToday();
  const from = q.get('from') ?? addDays(to, -(defaultDays - 1));
  if (!iso.test(from) || !iso.test(to) || from > to || span(from, to) > 31) return problem(400, 'VALIDATION_FAILED');
  return [from, to, mfcId] as const;
}

function* days(from: string, to: string) {
  for (let d = from; d <= to; d = addDays(d, 1)) yield d;
}

export const deliveryStatsHandlers = [
  http.get(`${API_BASE}/delivery-metrics`, ({ request }) => {
    const g = guard(request, 7);
    if (g instanceof Response) return g;
    const [from, to, mfcId] = g;
    const mine = !mfcId || hasDemoData(mfcId);
    const at = mfcId ?? CENTER;
    // 다른 센터(브라우저 목)는 센터 ID 를 섞어 다른 값
    const salt = at === CENTER ? '' : at;
    const rows = mine
      ? [...days(from, to)].flatMap((date) =>
          RIDERS.flatMap((riderId) => {
            const k = num(`${date}${riderId}${salt}`);
            const assigned = k % 9;
            if (assigned === 0) return [];
            const failed = k % 7 === 0 ? 1 : 0;
            const completed = Math.max(0, assigned - failed - (k % 5 === 0 ? 1 : 0));
            const judged = Math.max(0, completed - (k % 3 === 0 ? 1 : 0));
            const late = judged > 0 && k % 4 === 0 ? 1 : 0;
            return [
              {
                date,
                mfcId: at,
                riderId,
                assigned,
                completed,
                failed,
                cancelled: 0,
                late,
                judged,
                pickupWaitSeconds: completed > 0 ? 120 + (k % 420) : null,
                pickupWaitCount: completed,
                deliverySeconds: completed > 0 ? 900 + (k % 900) : null,
                deliveryCount: completed,
              },
            ];
          }),
        )
      : [];
    const incidents = mine && rows.length > 0
      ? [
          { category: 'CUSTOMER_UNREACHABLE', count: 3, resolved: 3, resolveSeconds: 540 },
          { category: 'STORE_WAITING', count: 2, resolved: 1, resolveSeconds: 780 },
          { category: 'DELIVERY_FAILURE', count: 1, resolved: 1, resolveSeconds: 1500 },
        ]
      : [];
    return HttpResponse.json({ from, to, rows, incidents });
  }),

  http.get(`${API_BASE}/metrics/dispatch`, ({ request }) => {
    const g = guard(request, 1);
    if (g instanceof Response) return g;
    const [from, to, mfcId] = g;
    const mine = !mfcId || hasDemoData(mfcId);
    const at = mfcId ?? CENTER;
    const rows = mine
      ? [...days(from, to)].flatMap((date) => {
          const k = num(`${date}${at === CENTER ? '' : at}`);
          const created = 10 + (k % 14);
          const assigned = created - (k % 3);
          const sent = assigned + 4 + (k % 5);
          return [
            {
              date,
              mfcId: at,
              created,
              assigned,
              avgAssignSeconds: 60 + (k % 240),
              reassigned: k % 3,
              failedRounds: k % 4,
              autoCancelled: k % 11 === 0 ? 1 : 0,
              offersSent: sent,
              offersAccepted: assigned,
              offersRejected: Math.floor((sent - assigned) / 2),
              offersExpired: Math.ceil((sent - assigned) / 2),
              assignedByAi: assigned - 2,
              assignedByList: 2,
              assignedByFailedReturn: 0,
            },
          ];
        })
      : [];
    const failureReasons = rows.length > 0 ? [{ reason: 'NO_RIDER', rounds: 4 }, { reason: 'EXPIRED', rounds: 2 }] : [];
    return HttpResponse.json({ from, to, rows, failureReasons });
  }),
];
