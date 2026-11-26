// 센터의 끝나지 않은 작업(출하 약속 초과·임박 판정 원천) — 운영판과 탭 제목(급한 건 수)이 같은 조회 키로 나눠 쓴다(두 번 읽지 않는다).
// mfc-fulfillment `GET /tasks?mfcId=&state=WAITING…BLOCKED` 를 커서로 끝까지, 최대 TASK_MAX_PAGES 쪽(넘으면 complete=false → "N건 이상").
// 출하 약속(0.35.0 — 배차 요청 예상 준비 시각): 숫자는 `GET /shipments/promise-summary`(서버가 셈), 예외 줄은 출고마다 —
// `GET /shipments?mfcId=&state=PREPARING`(READY 전) 중 배차 요청된 것(dispatchRequestedAt)의 `GET /shipments/{id}` dispatchRequest.estimatedReadyAt.
import { useQuery } from '@tanstack/react-query';

import { request } from '@pmart/web-core';
import type { Api } from '../../api/client';
import { useApi } from '../../app/ApiContext';
import { DUE_SOON_MINUTES, OPEN_TASK_STATES, TASK_MAX_PAGES, TASK_PAGE_SIZE, type TaskSummary } from './opsRules';

export const OPS_REFRESH_MS = 60_000;

async function readOpenTasks(api: Api, mfcId: string) {
  const items: TaskSummary[] = [];
  let cursor: string | undefined;
  let asOf: string | undefined;
  for (let page = 0; page < TASK_MAX_PAGES; page += 1) {
    const r = await request(
      'GET',
      api.fulfillment.GET('/tasks', { params: { query: { mfcId, state: [...OPEN_TASK_STATES], size: TASK_PAGE_SIZE, ...(cursor ? { cursor } : {}) } } }),
    );
    asOf ??= r.asOf?.asOf ?? undefined;
    items.push(...(r.items ?? []));
    cursor = r.page?.nextCursor ?? undefined;
    if (!cursor) return { items, complete: true, asOf };
  }
  return { items, complete: false, asOf };
}

export function useOpenTasks(mfcId: string | null) {
  const api = useApi();
  return useQuery({
    queryKey: ['ops', mfcId ?? '', 'tasks'],
    queryFn: () => readOpenTasks(api, mfcId ?? ''),
    enabled: !!mfcId,
    refetchInterval: OPS_REFRESH_MS,
    staleTime: 30_000,
  });
}

/** 출하 약속 요약(서버가 센 초과·임박·약속 없음) — 운영판 숫자 칸·탭 제목이 같은 조회 키로 나눠 쓴다 */
export function usePromiseSummary(mfcId: string | null) {
  const api = useApi();
  return useQuery({
    queryKey: ['ops', mfcId ?? '', 'promise-summary'],
    queryFn: () => request('GET', api.fulfillment.GET('/shipments/promise-summary', { params: { query: { mfcId: mfcId ?? '', dueWithinMinutes: DUE_SOON_MINUTES } } })),
    enabled: !!mfcId,
    refetchInterval: OPS_REFRESH_MS,
    staleTime: 30_000,
  });
}

/** 출고 목록 쪽 수·상세를 읽을 최대 출고 수 — 넘으면 complete=false(예외 줄이 일부만) */
const SHIP_MAX_PAGES = 5;
const SHIP_DETAIL_MAX = 100;
const SHIP_DETAIL_PARALLEL = 10;

async function readShipPromises(api: Api, mfcId: string) {
  const requested: string[] = [];
  let cursor: string | undefined;
  let complete = true;
  for (let page = 0; ; page += 1) {
    const r = await request('GET', api.fulfillment.GET('/shipments', { params: { query: { mfcId, state: ['PREPARING'], size: TASK_PAGE_SIZE, ...(cursor ? { cursor } : {}) } } }));
    for (const s of r.items) if (s.dispatchRequestedAt) requested.push(s.shipmentId);
    cursor = r.nextCursor ?? undefined;
    if (!cursor) break;
    if (page + 1 >= SHIP_MAX_PAGES) {
      complete = false;
      break;
    }
  }
  if (requested.length > SHIP_DETAIL_MAX) complete = false;
  const promises = new Map<string, string>();
  const ids = requested.slice(0, SHIP_DETAIL_MAX);
  for (let i = 0; i < ids.length; i += SHIP_DETAIL_PARALLEL) {
    const part = await Promise.all(ids.slice(i, i + SHIP_DETAIL_PARALLEL).map((shipmentId) => request('GET', api.fulfillment.GET('/shipments/{shipmentId}', { params: { path: { shipmentId } } }))));
    for (const s of part) if (s.shipmentId && s.dispatchRequest?.estimatedReadyAt) promises.set(s.shipmentId, s.dispatchRequest.estimatedReadyAt);
  }
  return { promises, complete };
}

/** 출고별 출하 약속(shipmentId → 배차 요청 예상 준비 시각) — 예외 줄용 */
export function useShipPromises(mfcId: string | null) {
  const api = useApi();
  return useQuery({
    queryKey: ['ops', mfcId ?? '', 'ship-promises'],
    queryFn: () => readShipPromises(api, mfcId ?? ''),
    enabled: !!mfcId,
    refetchInterval: OPS_REFRESH_MS,
    staleTime: 30_000,
  });
}

/** 출하 약속을 넘긴 출고 수(탭 제목용, 서버 요약) — 못 읽었으면 null(숫자를 붙이지 않는다) */
export function useOverdueCount(mfcId: string | null): { readonly n: number; readonly more: boolean } | null {
  const q = usePromiseSummary(mfcId);
  if (!q.data) return null;
  return { n: q.data.overdue, more: false };
}
