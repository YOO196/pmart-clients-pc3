// 커서 목록(MB-1, 2026-11-18 백엔드 회신): `items` + `nextCursor`, size ≤ 200. 항목은 단건 응답과 같은 모양.
// 상태 거르기는 URL 쿼리에(목록마다 키) — 표 필터는 URL 에(react-web 규칙). 조회 실패를 빈 목록으로 보이지 않는다(QueryState).
import { useInfiniteQuery } from '@tanstack/react-query';
import type { ReactNode } from 'react';
import { useSearchParams } from 'react-router';

import { QueryState, toUiState } from '@pmart/web-ui';
import { messages } from './messages';
import { useNewIds } from './motion';

const m = messages.lists;

export interface CursorPage<T> {
  readonly items: readonly T[];
  readonly nextCursor?: string | null;
}

/** URL 쿼리 값 하나(목록 거르기·열 번호). [fallback] 은 쿼리에 그 키가 없을 때 — 빈 값으로 고르면 빈 값(전체)이 남는다. */
export function useQueryParam(key: string, fallback = ''): [string, (v: string) => void] {
  const [params, setParams] = useSearchParams();
  return [
    params.get(key) ?? fallback,
    (v) => {
      const next = new URLSearchParams(params);
      next.set(key, v);
      setParams(next, { replace: true });
    },
  ];
}

export function CursorList<T>({
  title,
  testId,
  queryKey,
  fetchPage,
  head,
  cells,
  rowKey,
  onOpen,
  emptyText,
  states,
  stateLabels,
  state,
  onState,
  filters,
}: {
  readonly title: string;
  readonly testId: string;
  readonly queryKey: readonly unknown[];
  readonly fetchPage: (cursor: string | undefined) => Promise<CursorPage<T>>;
  readonly head: readonly string[];
  readonly cells: (row: T) => readonly ReactNode[];
  readonly rowKey: (row: T) => string;
  readonly onOpen?: (row: T) => void;
  readonly emptyText: string;
  /** 고를 수 있는 상태(계약 enum). 없으면 거르기를 보이지 않는다. */
  readonly states?: readonly string[];
  readonly stateLabels?: Readonly<Record<string, string>>;
  readonly state?: string;
  readonly onState?: (v: string) => void;
  /** 그 밖 거르기 입력(날짜 등). */
  readonly filters?: ReactNode;
}) {
  const query = useInfiniteQuery({
    queryKey: [...queryKey],
    initialPageParam: undefined as string | undefined,
    queryFn: ({ pageParam }) => fetchPage(pageParam),
    getNextPageParam: (last) => last.nextCursor ?? undefined,
  });
  const rows = (query.data?.pages ?? []).flatMap((p) => p.items);
  // 저절로·다시 읽어 새로 들어온 줄만 잠깐 강조(거르기를 바꾸면 처음부터 — 통합 백오피스와 같은 움직임)
  const fresh = useNewIds(query.data ? rows.map(rowKey) : undefined, state ?? '');
  return (
    <div className="space-y-2 rounded-box bg-base-100 p-3" data-testid={testId}>
      <div className="flex flex-wrap items-end gap-3">
        <h2 className="font-bold">{title}</h2>
        {states && onState && (
          <label className="flex flex-col gap-1 text-xs">
            {m.state}
            <select className="select select-sm w-40" aria-label={`${title} ${m.state}`} value={state ?? ''} onChange={(e) => onState(e.target.value)}>
              <option value="">{m.all}</option>
              {states.map((s) => (
                <option key={s} value={s}>
                  {stateLabels?.[s] ?? s}
                </option>
              ))}
            </select>
          </label>
        )}
        {filters}
        <button type="button" className="btn btn-xs" onClick={() => void query.refetch()} disabled={query.isFetching}>
          {m.refresh}
        </button>
      </div>
      <QueryState state={toUiState(query, () => rows.length === 0)} onRetry={() => void query.refetch()} emptyText={emptyText}>
        {() => (
          <div className="space-y-2 overflow-x-auto">
            <table className="table table-sm">
              <thead>
                <tr>
                  {head.map((h) => (
                    <th key={h}>{h}</th>
                  ))}
                  {onOpen && <th />}
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={rowKey(r)} data-testid={`${testId}-row`} className={fresh.has(rowKey(r)) ? 'row-new' : undefined}>
                    {cells(r).map((c, i) => (
                      <td key={i}>{c}</td>
                    ))}
                    {onOpen && (
                      <td>
                        <button type="button" className="btn btn-xs" onClick={() => onOpen(r)}>
                          {m.open}
                        </button>
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
            <p className="text-xs text-base-content/60" data-testid={`${testId}-count`}>
              {query.hasNextPage ? m.loadedMore(rows.length) : m.loaded(rows.length)}
            </p>
            {query.hasNextPage && (
              <button type="button" className="btn btn-sm" disabled={query.isFetchingNextPage} onClick={() => void query.fetchNextPage()}>
                {m.more}
              </button>
            )}
          </div>
        )}
      </QueryState>
    </div>
  );
}
