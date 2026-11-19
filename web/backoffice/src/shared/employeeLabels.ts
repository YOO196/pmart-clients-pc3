// 직원 표시(ADR-0070 덧붙임 2026-11-19 — 백엔드 알림 clients/backoffice/2026-11-19-notice-display-numbers-all).
// 목록·표·링크에는 OP-… 대신 "이름 · 사번". hr 0.8.0 `GET /hr/employee-labels?operatorIds=`(50개까지, 아는 ID 만 돌려준다).
// 같은 화면에서 여러 칸이 부르면 한 틱 안의 ID 를 모아 50개씩 한 번에 묻는다(줄마다 요청하지 않게). 결과는 queryKey 로 캐시.
// 못 읽으면 failed(화면은 "직원 · 확인 불가"), 모르는 ID 면 null("직원 · 이름 없음") — 시스템 ID 는 상세의 시스템 번호 칸에서만.
import { useQuery } from '@tanstack/react-query';

import { request } from '@pmart/web-core';
import { useApi } from '../app/ApiContext';

type Api = ReturnType<typeof useApi>;
export interface EmployeeLabel {
  readonly name: string;
  readonly employeeNo: string;
}

const BATCH = 50;
interface Job {
  readonly id: string;
  readonly resolve: (v: EmployeeLabel | null) => void;
  readonly reject: (e: unknown) => void;
}
let queue: Job[] = [];
let scheduled = false;
let queueApi: Api | null = null;

function flush() {
  scheduled = false;
  const api = queueApi;
  const jobs = queue;
  queue = [];
  if (!api) return;
  const ids = [...new Set(jobs.map((j) => j.id))];
  for (let i = 0; i < ids.length; i += BATCH) {
    const chunk = ids.slice(i, i + BATCH);
    const mine = jobs.filter((j) => chunk.includes(j.id));
    request('GET', api.hr.GET('/hr/employee-labels', { params: { query: { operatorIds: chunk } } })).then(
      (r) => {
        const found = new Map((r.items ?? []).map((x) => [x.operatorId, { name: x.name, employeeNo: x.employeeNo }]));
        for (const j of mine) j.resolve(found.get(j.id) ?? null);
      },
      (e: unknown) => {
        for (const j of mine) j.reject(e);
      },
    );
  }
}

function loadLabel(api: Api, id: string): Promise<EmployeeLabel | null> {
  queueApi = api;
  return new Promise((resolve, reject) => {
    queue.push({ id, resolve, reject });
    if (!scheduled) {
      scheduled = true;
      setTimeout(flush, 0);
    }
  });
}

/** 운영자 ID 하나 → 이름·사번(같은 틱의 다른 칸과 묶어서) */
export function useEmployeeLabel(operatorId: string | null | undefined) {
  const api = useApi();
  return useQuery({
    queryKey: ['hr', 'employee-label', operatorId],
    enabled: Boolean(operatorId),
    staleTime: 10 * 60_000,
    queryFn: () => loadLabel(api, operatorId ?? ''),
  });
}

export const labelText = (l: EmployeeLabel) => `${l.name} · ${l.employeeNo}`;
