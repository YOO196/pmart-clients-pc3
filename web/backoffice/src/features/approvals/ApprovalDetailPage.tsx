// 승인 상세·결정. 5축(요청·심사·실행·전달·사건)을 한 상태로 합치지 않는다.
// 결정은 APPROVE·REJECT 만(나머지는 백엔드 미지원 → 버튼 없음). 결정 뒤 정본 반영은 비동기라 짧게 폴링한다.
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { useParams } from 'react-router';

import { commandParams } from '../../api/command';
import { CommandRejectedFailure, UnknownResultFailure } from '../../api/failure';
import type { ApprovalDetail, ExecutionState, ReviewState, SupportedDecision } from '../../api/models';
import { request } from '../../api/pmartFetch';
import { pollConfig, pollUntil } from '../../api/poll';
import { useApi } from '../../app/ApiContext';
import { useSession } from '../../app/SessionContext';
import { CommandFeedback } from '../../shared/Feedback';
import { formatKrw, formatSeoul } from '../../shared/format';
import { messages as m } from '../../shared/messages';
import { QueryState } from '../../shared/QueryState';
import { toUiState } from '../../shared/toUiState';
import { useCommand } from '../../shared/useCommand';

const OPEN_REVIEW: readonly ReviewState[] = ['REVIEW_PENDING', 'EVIDENCE_REQUIRED'];
const FINAL_EXECUTION: readonly ExecutionState[] = ['APPLIED', 'PARTIAL', 'REJECTED'];

const isWatching = (a: ApprovalDetail) =>
  (a.reviewState === 'APPROVED' || a.reviewState === 'PARTIALLY_APPROVED') &&
  !FINAL_EXECUTION.includes(a.executionState ?? 'NOT_REQUESTED');

export function ApprovalDetailPage() {
  const { approvalId = '' } = useParams();
  const api = useApi();
  const queryClient = useQueryClient();
  const { session } = useSession();
  const [watchCount, setWatchCount] = useState<number | null>(null);
  const [comment, setComment] = useState('');

  const getApproval = () =>
    request('GET', api.approval.GET('/approvals/{approvalId}', { params: { path: { approvalId } } }));

  const query = useQuery({
    queryKey: ['approval', 'detail', approvalId],
    queryFn: getApproval,
    refetchInterval: (q) => {
      const a = q.state.data;
      if (watchCount === null || !a || !isWatching(a) || q.state.dataUpdateCount - watchCount >= pollConfig.maxAttempts) {
        return false;
      }
      return pollConfig.intervalMs;
    },
  });

  const decide = useCommand(async ({ decision, version }: { decision: SupportedDecision; version: number | undefined }, key) => {
    const res = await request(
      'POST',
      api.approval.POST('/approvals/{approvalId}/decisions', {
        ...commandParams(key, { path: { approvalId }, version: version }),
        body: { decision, ...(comment.trim() ? { comment: comment.trim() } : {}) },
      }),
    );
    if (res.status === 'REJECTED') throw new CommandRejectedFailure(res.nextAction, res.requestId);
    if (res.status === 'UNKNOWN_RESULT') {
      // 짝 조회: 심사 축이 열린 상태에서 벗어났으면 결정이 기록된 것이다.
      const outcome = await pollUntil(getApproval, (a) => !OPEN_REVIEW.includes(a.reviewState ?? 'REVIEW_PENDING'));
      if (outcome.kind !== 'done') throw new UnknownResultFailure(undefined, res.requestId);
    }
    await queryClient.invalidateQueries({ queryKey: ['approval'] });
    setWatchCount(queryClient.getQueryState(['approval', 'detail', approvalId])?.dataUpdateCount ?? 0);
    return res;
  });

  return (
    <section className="space-y-4">
      <h1 className="text-xl font-bold">{`${m.approvals.detailTitle} ${approvalId}`}</h1>
      <QueryState state={toUiState(query)} onRetry={() => void query.refetch()}>
        {(a) => {
          const open = OPEN_REVIEW.includes(a.reviewState ?? 'REVIEW_PENDING');
          const own = session !== null && a.requesterId === session.subject;
          const watching = watchCount !== null && isWatching(a);
          const updatesSinceDecision =
            (queryClient.getQueryState(['approval', 'detail', approvalId])?.dataUpdateCount ?? 0) - (watchCount ?? 0);
          const watchedOut = watching && updatesSinceDecision >= pollConfig.maxAttempts;
          return (
            <>
              <dl className="grid grid-cols-[8rem_1fr] gap-1 rounded-box bg-base-100 p-4 text-sm">
                <dt>{m.approvals.type}</dt>
                <dd>{a.type ?? m.none}</dd>
                <dt>{m.approvals.target}</dt>
                <dd>{`${a.targetService ?? m.none} · ${a.targetRef ?? m.none}`}</dd>
                <dt>{m.approvals.summary}</dt>
                <dd>{a.summary ?? m.none}</dd>
                <dt>{m.approvals.requester}</dt>
                <dd>{a.requesterId ?? m.none}</dd>
                <dt>{m.approvals.review}</dt>
                <dd data-testid="review-state">{a.reviewState ? m.approvals.reviewState[a.reviewState] : m.none}</dd>
                <dt>{m.approvals.execution}</dt>
                <dd data-testid="execution-state">
                  {a.executionState ? m.approvals.executionState[a.executionState] : m.none}
                </dd>
                <dt>{m.approvals.delivery}</dt>
                <dd>{a.deliveryState ?? m.none}</dd>
                <dt>{m.approvals.submittedAt}</dt>
                <dd>{a.submittedAt ? formatSeoul(a.submittedAt) : m.none}</dd>
              </dl>

              {watching && !watchedOut && (
                <div role="status" className="flex items-center gap-2 text-sm">
                  <span className="loading loading-spinner loading-sm" />
                  {m.approvals.executionWaiting}
                </div>
              )}
              {watchedOut && (
                <div role="status" className="alert alert-info">
                  <span>{m.approvals.executionTimeout}</span>
                  <button type="button" className="btn btn-sm" onClick={() => void query.refetch()}>
                    {m.checkAgain}
                  </button>
                </div>
              )}

              <h2 className="font-bold">{m.approvals.lines}</h2>
              <table className="table table-sm bg-base-100">
                <tbody>
                  {(a.lines ?? []).map((l) => (
                    <tr key={l.lineKey}>
                      <td>{l.lineKey}</td>
                      <td>{l.requestedAmount === undefined ? '' : formatKrw(l.requestedAmount)}</td>
                      <td>
                        <code className="text-xs break-all">{l.attributes ? JSON.stringify(l.attributes) : ''}</code>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>

              {open && (
                <div className="space-y-2 rounded-box bg-base-100 p-4">
                  {own && <p className="text-warning text-sm">{m.approvals.selfApproval}</p>}
                  <label className="floating-label block">
                    <span>{m.approvals.commentLabel}</span>
                    <input
                      className="input input-sm w-full"
                      maxLength={1000}
                      value={comment}
                      onChange={(e) => setComment(e.target.value)}
                    />
                  </label>
                  <div className="flex gap-2">
                    <button
                      type="button"
                      className="btn btn-primary btn-sm"
                      disabled={decide.busy}
                      onClick={() => void decide.run({ decision: 'APPROVE', version: a.version })}
                    >
                      {m.approvals.approve}
                    </button>
                    <button
                      type="button"
                      className="btn btn-sm"
                      disabled={decide.busy}
                      onClick={() => void decide.run({ decision: 'REJECT', version: a.version })}
                    >
                      {m.approvals.reject}
                    </button>
                  </div>
                </div>
              )}
              <CommandFeedback command={decide}>
                {() => (
                  <div role="status" className="alert alert-success">
                    {m.approvals.decided}
                  </div>
                )}
              </CommandFeedback>

              {(a.decisions?.length ?? 0) > 0 && (
                <>
                  <h2 className="font-bold">{m.approvals.decisions}</h2>
                  <ul className="text-sm">
                    {(a.decisions ?? []).map((d, i) => (
                      <li key={d.decisionId ?? i}>
                        {`${d.decision} · ${d.approverId ?? m.none} · ${d.decidedAt ? formatSeoul(d.decidedAt) : m.none}${d.comment ? ` · ${d.comment}` : ''}`}
                      </li>
                    ))}
                  </ul>
                </>
              )}
              {(a.receipts?.length ?? 0) > 0 && (
                <>
                  <h2 className="font-bold">{m.approvals.receipts}</h2>
                  <ul className="text-sm">
                    {(a.receipts ?? []).map((r, i) => (
                      <li key={r.receiptId ?? i}>{`${r.receiverService} · ${r.result}${r.reason ? ` · ${r.reason}` : ''}`}</li>
                    ))}
                  </ul>
                </>
              )}
            </>
          );
        }}
      </QueryState>
    </section>
  );
}
