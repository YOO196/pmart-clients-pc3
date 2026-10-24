import { useQuery } from '@tanstack/react-query';

import { useApi } from '../../app/ApiContext';
import { request } from '../../api/pmartFetch';
import { formatSeoul } from '../../shared/format';
import { messages as m } from '../../shared/messages';
import { QueryState, uiStateFromError, type UiState } from '../../shared/QueryState';
import { SourceStamps } from '../../shared/SourceStamps';
import type { ApprovalInboxView } from '../../api/views';

/** 승인함(BO-10). 명령 버튼은 C3 에서 bff 명령 프록시로 붙인다. */
export function ApprovalInboxPage() {
  const api = useApi();
  const query = useQuery({
    queryKey: ['bff', 'approval-inbox'],
    queryFn: () => request('GET', api.bff.GET('/views/approval-inbox', {})),
  });

  const state: UiState<ApprovalInboxView> = query.isPending
    ? { kind: 'loading' }
    : query.isError
      ? uiStateFromError(query.error)
      : (query.data.unavailableSources?.length ?? 0) > 0
        ? { kind: 'partial', data: query.data, missing: query.data.unavailableSources ?? [] }
        : (query.data.items?.length ?? 0) === 0
          ? { kind: 'empty' }
          : { kind: 'ready', data: query.data };

  return (
    <section className="space-y-4">
      <h1 className="text-xl font-bold">{m.approvals.title}</h1>
      <QueryState state={state} onRetry={() => void query.refetch()} emptyText={m.approvals.empty}>
        {(view) => (
          <>
            <SourceStamps sources={view.sources} unavailableSources={view.unavailableSources} />
            <table className="table">
              <thead>
                <tr>
                  <th>{m.approvals.dossier}</th>
                  <th>{m.approvals.type}</th>
                  <th>{m.approvals.review}</th>
                  <th>{m.approvals.execution}</th>
                  <th>{m.approvals.submittedAt}</th>
                </tr>
              </thead>
              <tbody>
                {(view.items ?? []).map((item, i) => (
                  <tr key={item.dossierId ?? `row-${i}`}>
                    <td>{item.dossierId ?? '-'}</td>
                    <td>{item.approvalType ?? '-'}</td>
                    <td>{item.reviewState ?? '-'}</td>
                    <td>{item.executionState ?? '-'}</td>
                    <td>{item.submittedAt ? formatSeoul(item.submittedAt) : '-'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </>
        )}
      </QueryState>
    </section>
  );
}
