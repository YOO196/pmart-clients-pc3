// 센터의 끝나지 않은 작업(출하 약속 초과·임박 판정 원천) — 운영판과 탭 제목(급한 건 수)이 같은 조회 키로 나눠 쓴다(두 번 읽지 않는다).
// mfc-fulfillment `GET /tasks?mfcId=&state=WAITING…BLOCKED` 를 커서로 끝까지, 최대 TASK_MAX_PAGES 쪽(넘으면 complete=false → "N건 이상").
import { useQuery } from '@tanstack/react-query';

import { request } from '@pmart/web-core';
import type { Api } from '../../api/client';
import { useApi } from '../../app/ApiContext';
import { OPEN_TASK_STATES, promiseRows, TASK_MAX_PAGES, TASK_PAGE_SIZE, type TaskSummary } from './opsRules';

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

/** 출하 약속을 넘긴 출고 수(탭 제목용) — 못 읽었으면 null(숫자를 붙이지 않는다) */
export function useOverdueCount(mfcId: string | null): { readonly n: number; readonly more: boolean } | null {
  const q = useOpenTasks(mfcId);
  if (!q.data) return null;
  const nowMs = q.data.asOf ? Date.parse(q.data.asOf) : q.dataUpdatedAt;
  return { n: promiseRows(q.data.items, nowMs).overdue, more: !q.data.complete };
}
