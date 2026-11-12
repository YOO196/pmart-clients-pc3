// 승인함(approval-service GET /approvals). 필터·커서는 URL 쿼리에 둔다.
import { useQuery } from '@tanstack/react-query';
import { Link, useSearchParams } from 'react-router';

import { APPROVAL_TYPES, REVIEW_STATES, type ApprovalType, type ReviewState } from '../../api/models';
import { request } from '@pmart/web-core';
import { useApi } from '../../app/ApiContext';
import { formatSeoul } from '@pmart/web-ui';
import { messages as m } from '../../shared/messages';
import { QueryState } from '@pmart/web-ui';
import { toUiState } from '@pmart/web-ui';

const pick = <T extends string>(value: string | null, allowed: readonly T[]): T | undefined =>
  allowed.find((a) => a === value);

export function ApprovalListPage() {
  const api = useApi();
  const [params, setParams] = useSearchParams();
  const type = pick<ApprovalType>(params.get('type'), APPROVAL_TYPES);
  const reviewState = pick<ReviewState>(params.get('reviewState'), REVIEW_STATES);
  const cursor = params.get('cursor') ?? undefined;

  const query = useQuery({
    queryKey: ['approval', 'list', type, reviewState, cursor],
    queryFn: () =>
      request(
        'GET',
        api.approval.GET('/approvals', {
          params: {
            query: {
              ...(type ? { type } : {}),
              ...(reviewState ? { reviewState } : {}),
              ...(cursor ? { cursor } : {}),
              size: 50,
            },
          },
        }),
      ),
  });

  const setFilter = (key: string, value: string) => {
    const next = new URLSearchParams(params);
    if (value) next.set(key, value);
    else next.delete(key);
    next.delete('cursor');
    setParams(next);
  };

  return (
    <section className="space-y-4">
      <h1 className="text-xl font-bold">{m.approvals.title}</h1>
      <div className="flex flex-wrap gap-2">
        <select
          aria-label={m.approvals.type}
          className="select select-sm w-48"
          value={type ?? ''}
          onChange={(e) => setFilter('type', e.target.value)}
        >
          <option value="">{`${m.approvals.type}: ${m.approvals.filterAll}`}</option>
          {APPROVAL_TYPES.map((t) => (
            <option key={t} value={t}>
              {t}
            </option>
          ))}
        </select>
        <select
          aria-label={m.approvals.review}
          className="select select-sm w-56"
          value={reviewState ?? ''}
          onChange={(e) => setFilter('reviewState', e.target.value)}
        >
          <option value="">{`${m.approvals.review}: ${m.approvals.filterAll}`}</option>
          {REVIEW_STATES.map((s) => (
            <option key={s} value={s}>
              {m.approvals.reviewState[s]}
            </option>
          ))}
        </select>
      </div>

      <QueryState
        state={toUiState(query, (d) => (d.items?.length ?? 0) === 0)}
        onRetry={() => void query.refetch()}
        emptyText={m.approvals.empty}
      >
        {(data) => (
          <>
            <table className="table table-sm bg-base-100">
              <thead>
                <tr>
                  <th>{m.approvals.dossier}</th>
                  <th>{m.approvals.type}</th>
                  <th>{m.approvals.summary}</th>
                  <th>{m.approvals.requester}</th>
                  <th>{m.approvals.review}</th>
                  <th>{m.approvals.execution}</th>
                  <th>{m.approvals.submittedAt}</th>
                </tr>
              </thead>
              <tbody>
                {(data.items ?? []).map((a, i) => (
                  <tr key={a.approvalId ?? `row-${i}`}>
                    <td>
                      {a.approvalId ? (
                        <Link className="link" to={`/approvals/${encodeURIComponent(a.approvalId)}`}>
                          {a.approvalId}
                        </Link>
                      ) : (
                        m.none
                      )}
                    </td>
                    <td>{a.type ?? m.none}</td>
                    <td>{a.summary ?? m.none}</td>
                    <td>{a.requesterId ?? m.none}</td>
                    <td>{a.reviewState ? m.approvals.reviewState[a.reviewState] : m.none}</td>
                    <td>{a.executionState ? m.approvals.executionState[a.executionState] : m.none}</td>
                    <td>{a.submittedAt ? formatSeoul(a.submittedAt) : m.none}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            {data.page?.nextCursor && (
              <button type="button" className="btn btn-sm" onClick={() => setFilter('cursor', data.page?.nextCursor ?? '')}>
                {m.more}
              </button>
            )}
          </>
        )}
      </QueryState>
    </section>
  );
}
