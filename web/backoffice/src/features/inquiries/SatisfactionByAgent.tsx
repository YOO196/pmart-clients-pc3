// 문의 만족도 — 직원별(case 0.38.0, 2026-11-24 사용자 "직원마다 평점을 볼 수 있게 하고 고객 개인정보는 가리는 식으로,
// 관리자가 개인의 성과 측정 및 관리 목적"). 2026-11-17 의 "상담원별로 나누지 않는다"를 사용자가 바꿨다 — 보는 사람은 관리자(OPERATOR_ADMIN)만 그대로.
// - `GET /inquiries/satisfaction-summary/by-agent`(전체 요약과 같은 기간·대상, 줄 합 = 전체). 몫 = 평가 직전 마지막 답변자(서버 규칙).
// - 줄을 누르면 그 직원 몫의 평가 목록 `GET /inquiries/satisfaction-ratings`(남긴 것만, 최근 순) — 고객 ID·이름·연락처 없음, 의견의 전화·메일은 서버가 가림.
// - 비율은 분자·분모를 같이, 분모 0 은 "—". 평균이 없으면 "—". 이름은 hr employee-labels(StaffName).
import { useInfiniteQuery, useQuery } from '@tanstack/react-query';
import { Fragment } from 'react';
import { Link, useSearchParams } from 'react-router';

import { request } from '@pmart/web-core';
import { formatSeoul, QueryState, toUiState } from '@pmart/web-ui';
import { useApi } from '../../app/ApiContext';
import { messages } from '../../shared/messages';
import { StaffName } from '../lookup/parts';

const m = messages.satisfaction.byAgent;
const SCORES = ['5', '4', '3', '2', '1'] as const;

export function SatisfactionByAgent({ answeredFrom, answeredTo, period }: { readonly answeredFrom: string; readonly answeredTo: string; readonly period: string }) {
  const api = useApi();
  const [params, setParams] = useSearchParams();
  const open = params.get('agent');
  const query = useQuery({
    queryKey: ['inquiries', 'satisfaction', 'by-agent', answeredFrom, answeredTo],
    queryFn: () => request('GET', api.cases.GET('/inquiries/satisfaction-summary/by-agent', { params: { query: { answeredFrom, answeredTo } } })),
  });
  const toggle = (id: string) => {
    const next = new URLSearchParams(params);
    if (open === id) next.delete('agent');
    else next.set('agent', id);
    setParams(next, { replace: true });
  };
  return (
    <section className="overflow-hidden rounded-box border border-base-300 bg-base-100 shadow-sm" aria-label={m.title} data-testid="satisfaction-by-agent">
      <div className="flex items-center justify-between gap-2 border-b border-base-300 px-4 py-3">
        <h2 className="text-sm font-semibold">{m.title}</h2>
        <span className="text-xs text-base-content/50">{`${m.hint} · ${period}`}</span>
      </div>
      <QueryState state={toUiState(query)} onRetry={() => void query.refetch()}>
        {(d) =>
          d.items.length === 0 ? (
            <p className="px-4 py-6 text-center text-sm text-base-content/60">{m.empty}</p>
          ) : (
            <table className="table table-sm">
              <thead>
                <tr>
                  <th>{m.col.agent}</th>
                  <th className="text-right">{m.col.answered}</th>
                  <th className="text-right">{m.col.rated}</th>
                  <th className="text-right">{m.col.average}</th>
                  {SCORES.map((k) => (
                    <th key={k} className="text-right">
                      {messages.satisfaction.scoreLabel(k)}
                    </th>
                  ))}
                  <th aria-label={m.col.open} />
                </tr>
              </thead>
              <tbody>
                {d.items.map((r) => {
                  const id = r.agentId ?? null;
                  const isOpen = id !== null && open === id;
                  return (
                    <Fragment key={id ?? 'none'}>
                      <tr
                        className={id ? `cursor-pointer hover:bg-base-200/60 ${isOpen ? 'bg-base-200/60' : ''}` : ''}
                        onClick={id ? () => toggle(id) : undefined}
                        data-testid="by-agent-row"
                        aria-expanded={id ? isOpen : undefined}
                      >
                        <td className="font-medium">{id ? <StaffName id={id} /> : <span className="text-base-content/60">{m.noAgent}</span>}</td>
                        <td className="text-right tabular-nums">{r.answeredCount}</td>
                        <td className="text-right tabular-nums">
                          {r.ratedCount}
                          <span className="ml-1 text-xs text-base-content/50">{r.answeredCount === 0 ? '(—)' : `(${Math.round((r.ratedCount / r.answeredCount) * 1000) / 10}%)`}</span>
                        </td>
                        <td className="text-right font-semibold tabular-nums" data-testid="by-agent-average">
                          {r.averageScore === null || r.averageScore === undefined ? messages.satisfaction.none : r.averageScore.toFixed(2)}
                        </td>
                        {SCORES.map((k) => (
                          <td key={k} className="text-right tabular-nums text-base-content/70">
                            {r.byScore[k] ?? 0}
                          </td>
                        ))}
                        <td className="w-8 text-right text-base-content/50">
                          {id && (
                            <button type="button" className="btn btn-ghost btn-xs" aria-label={isOpen ? m.close : m.open} onClick={(e) => { e.stopPropagation(); toggle(id); }}>
                              {isOpen ? '▾' : '▸'}
                            </button>
                          )}
                        </td>
                      </tr>
                      {isOpen && (
                        <tr>
                          <td colSpan={5 + SCORES.length} className="bg-base-200/30 p-0">
                            <AgentRatings agentId={id} answeredFrom={answeredFrom} answeredTo={answeredTo} />
                          </td>
                        </tr>
                      )}
                    </Fragment>
                  );
                })}
              </tbody>
            </table>
          )
        }
      </QueryState>
    </section>
  );
}

/** 직원 한 명 몫의 평가 — 남긴 것만, 최근 순, 고객 정보 없음 */
function AgentRatings({ agentId, answeredFrom, answeredTo }: { readonly agentId: string; readonly answeredFrom: string; readonly answeredTo: string }) {
  const api = useApi();
  const query = useInfiniteQuery({
    queryKey: ['inquiries', 'satisfaction', 'ratings', agentId, answeredFrom, answeredTo],
    queryFn: ({ pageParam }) =>
      request('GET', api.cases.GET('/inquiries/satisfaction-ratings', { params: { query: { agentId, answeredFrom, answeredTo, size: 20, ...(pageParam ? { cursor: pageParam } : {}) } } })),
    initialPageParam: undefined as string | undefined,
    getNextPageParam: (last) => last.page.nextCursor ?? undefined,
  });
  return (
    <div className="px-4 py-3" data-testid="agent-ratings">
      <QueryState state={toUiState(query)} onRetry={() => void query.refetch()}>
        {(d) => {
          const items = d.pages.flatMap((p) => p.items);
          return items.length === 0 ? (
            <p className="text-sm text-base-content/60">{m.noRatings}</p>
          ) : (
            <div className="space-y-2">
              <ul className="divide-y divide-base-300/70 text-sm">
                {items.map((x) => (
                  <li key={x.inquiryId} className="grid grid-cols-[5.5rem_3rem_1fr_auto] items-baseline gap-3 py-1.5" data-testid="agent-rating">
                    <Link className="link link-hover font-mono text-xs" to={`/inquiries/${encodeURIComponent(x.inquiryId)}`}>
                      {x.inquiryNumber ?? m.inquiry}
                    </Link>
                    <span className="font-semibold tabular-nums">{messages.satisfaction.scoreLabel(String(x.score))}</span>
                    <span className="min-w-0 truncate text-base-content/80" title={x.comment ?? undefined}>
                      {x.comment ?? <span className="text-base-content/45">{m.noComment}</span>}
                    </span>
                    <span className="text-xs text-base-content/50">{m.ratedAt(formatSeoul(x.ratedAt))}</span>
                  </li>
                ))}
              </ul>
              {query.hasNextPage && (
                <button type="button" className="btn btn-xs" disabled={query.isFetchingNextPage} onClick={() => void query.fetchNextPage()}>
                  {m.more}
                </button>
              )}
              <p className="text-xs text-base-content/45">{m.privacy}</p>
            </div>
          );
        }}
      </QueryState>
    </div>
  );
}
