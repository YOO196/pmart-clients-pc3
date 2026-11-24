// 메뉴 할 일 숫자(2026-11-24 사용자 "인사 쪽 메뉴바라든가 전체적으로 허전") — 통합 백오피스 메뉴 숫자와 같은 모양.
// 숫자는 첫 화면과 같은 서버 집계(hr GET /hr/employees/counts, 같은 queryKey 라 한 번만 부른다):
// 직원 목록 = 계정 발급 실패(빨강), 권한 관리 = 권한 승인 대기(회색). 0 이면 칩 없음, 못 읽으면 점선 "?"(0 으로 보이지 않게).
import { request } from '@pmart/web-core';
import { useQuery } from '@tanstack/react-query';

import { messages as m } from '../shared/messages';
import { useApi } from './ApiContext';

export function useEmployeeCounts(enabled: boolean) {
  const api = useApi();
  return useQuery({
    queryKey: ['hr', 'employee-counts'],
    queryFn: () => request('GET', api.hr.GET('/hr/employees/counts', { params: { query: { endingWithinDays: 7 } } })),
    enabled,
    refetchInterval: 60_000,
  });
}

const chip = 'inline-flex h-[18px] min-w-[18px] shrink-0 items-center justify-center rounded-full px-1.5 text-[11px] font-semibold tabular-nums';

export function MenuCount({ kind, enabled }: { readonly kind: 'failed' | 'grant'; readonly enabled: boolean }) {
  const q = useEmployeeCounts(enabled);
  if (!enabled || q.isPending) return null;
  if (q.isError) {
    return (
      <span className={`${chip} border border-dashed border-base-content/30 text-base-content/50`} title={m.nav.countUnknown} data-testid={`menu-count-${kind}`}>
        ?
      </span>
    );
  }
  const c = kind === 'failed' ? q.data.provisioningFailed : q.data.grantPendingApproval;
  if (!c || c.value <= 0) return null;
  const n = `${c.value}${c.complete ? '' : '+'}`; // 다 세지 못했으면 "+"(첫 화면과 같음)
  const title = kind === 'failed' ? m.nav.countFailed(n) : m.nav.countGrant(n);
  return (
    <span className={`${chip} ${kind === 'failed' ? 'bg-error/10 text-error' : 'bg-base-200 text-base-content/70'}`} title={title} aria-label={title} data-testid={`menu-count-${kind}`}>
      {n}
    </span>
  );
}

/** 메뉴 아래 — 숫자 보는 법 */
export function MenuLegend() {
  return (
    <div className="mx-4 mb-3 border-t border-base-300 pt-2 text-[11px] text-base-content/55" data-testid="menu-legend">
      <p className="mb-1">{m.nav.legendTitle}</p>
      <p className="flex items-center gap-3">
        <span className="flex items-center gap-1">
          <span className={`${chip} bg-base-200 text-base-content/70`}>&nbsp;</span>
          {m.nav.legendTodo}
        </span>
        <span className="flex items-center gap-1">
          <span className={`${chip} bg-error/10 text-error`}>&nbsp;</span>
          {m.nav.legendFailed}
        </span>
      </p>
    </div>
  );
}
