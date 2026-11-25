// 센터 목록 목(MB-1 — 백엔드 회신 2026-11-18): `?mfcId=&state=` + cursor/size(≤200), 응답 `{items, nextCursor}`.
// 그 센터 운영자만(아니면 403). 커서는 불투명 값 — 목은 다음 시작 위치를 문자열로 준다.
// 초기 보유(`/initial-stock-loads`)는 approvalId 방식과 같은 경로라 inboundHandlers 에 있다.
import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import { db } from './db';
import { operator, problem, unauthorized } from './support';

const canAccess = (request: Request, mfcId: string) => operator(request)?.centers.includes(mfcId) ?? false;

/** 목록 공통: 권한·상태 거르기·쪽 나누기. 권한이 없으면 Response. */
export function listPage<T>(request: Request, mfcId: string | null, rows: readonly T[], stateOf?: (r: T) => string | undefined | null): Response {
  if (!operator(request)) return unauthorized();
  if (!mfcId) return problem(400, 'VALIDATION_FAILED', [{ field: 'mfcId', reason: 'REQUIRED' }]);
  if (!canAccess(request, mfcId)) return problem(403, 'FORBIDDEN');
  const q = new URL(request.url).searchParams;
  const states = q.getAll('state');
  const size = Math.min(Number(q.get('size') ?? 50) || 50, 200);
  const start = Number(q.get('cursor') ?? 0) || 0;
  const filtered = states.length && stateOf ? rows.filter((r) => states.includes(stateOf(r) ?? '')) : rows;
  const items = filtered.slice(start, start + size);
  const next = start + size < filtered.length ? String(start + size) : null;
  return HttpResponse.json({ items, nextCursor: next });
}

const mfcOf = (request: Request) => new URL(request.url).searchParams.get('mfcId');
const newestFirst = <T>(rows: readonly T[], at: (r: T) => string | null | undefined) => [...rows].sort((a, b) => (at(b) ?? '').localeCompare(at(a) ?? ''));

export const listHandlers = [
  http.get(`${API_BASE}/quality-decisions`, ({ request }) => {
    const mfcId = mfcOf(request);
    const rows = newestFirst([...db.decisions.values()].filter((d) => d.mfcId === mfcId), (d) => d.decidedAt);
    return listPage(request, mfcId, rows, (d) => d.state);
  }),
  http.get(`${API_BASE}/disposal-approvals`, ({ request }) => {
    const mfcId = mfcOf(request);
    const rows = newestFirst([...db.disposals.values()].filter((d) => d.mfcId === mfcId), (d) => d.requestedAt);
    return listPage(request, mfcId, rows, (d) => d.state);
  }),
  http.get(`${API_BASE}/return-inspections`, ({ request }) => {
    const mfcId = mfcOf(request);
    const rows = newestFirst([...db.inspections.values()].filter((d) => d.mfcId === mfcId), (d) => d.inspectedAt);
    return listPage(request, mfcId, rows, (d) => d.inventoryApplyStatus);
  }),
  http.get(`${API_BASE}/return-receipts`, ({ request }) => {
    const mfcId = mfcOf(request);
    const rows = newestFirst([...db.returnReceipts.values()].filter((d) => d.mfcId === mfcId), (d) => d.receivedAt);
    return listPage(request, mfcId, rows, (d) => d.inventoryApplyStatus);
  }),
  http.get(`${API_BASE}/supply-requests`, ({ request }) => {
    const mfcId = mfcOf(request);
    const rows = newestFirst([...db.supplyRequests.values()].filter((d) => d.mfcId === mfcId), (d) => d.submittedAt);
    return listPage(request, mfcId, rows, (d) => d.state);
  }),
  http.get(`${API_BASE}/assignment-plans`, ({ request }) => {
    const mfcId = mfcOf(request);
    const date = new URL(request.url).searchParams.get('date');
    const rows = newestFirst(
      [...db.plans.values()].filter((p) => p.mfcId === mfcId && (!date || (p.createdAt ?? '').startsWith(date))),
      (p) => p.createdAt,
    );
    return listPage(request, mfcId, rows, (p) => p.state);
  }),
  http.get(`${API_BASE}/mfcs/:mfcId/count-sessions`, ({ request, params }) => {
    const mfcId = String(params.mfcId);
    const rows = newestFirst([...db.countSessions.values()].filter((s) => s.mfcId === mfcId), (s) => s.updatedAt);
    return listPage(request, mfcId, rows, (s) => s.state);
  }),
  http.get(`${API_BASE}/mfcs/:mfcId/stock-units`, ({ request, params }) => {
    const mfcId = String(params.mfcId);
    const q = new URL(request.url).searchParams;
    const match = (k: string, v: string) => !q.get(k) || q.get(k) === v;
    const rows = db.stockUnits
      .filter((u) => u.mfcId === mfcId && match('sku', u.sku) && match('lotId', u.lotId) && match('locationCode', u.locationCode) && match('qualityState', u.qualityState) && match('workState', u.workState))
      .filter((u) => !q.get('locationPrefix') || u.locationCode.startsWith(q.get('locationPrefix') ?? ''))
      .map((u) => {
        // (0.33.0) 위치 사본의 구역·온도대 — 목 위치(db.locations)에 없는 칸은 null(그 둘로 거르면 빠진다, 계약과 같다)
        const loc = [...db.locations.values()].find((l) => l.mfcId === mfcId && l.locationCode === u.locationCode);
        return { sku: u.sku, productName: u.productName ?? null, lotId: u.lotId, lotNo: u.lotNo ?? null, locationCode: u.locationCode, qty: u.qty, qualityState: u.qualityState, workState: u.workState, expiryDate: u.expiryDate ?? null, zone: loc?.zone ?? null, temperatureZone: loc?.temperatureZone ?? null };
      })
      .filter((u) => match('zone', u.zone ?? '') && match('temperatureZone', u.temperatureZone ?? ''));
    return listPage(request, mfcId, rows);
  }),
];
