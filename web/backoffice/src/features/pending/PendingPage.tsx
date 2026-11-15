// 처리 대기 — 이행 확인 필요(BO-12, 백엔드 요청 all/2026-11-15-request-permission-and-pending-menus §2). OPERATOR_ADMIN.
// - 목록 `GET /fulfillment-issues?state=&mfcId=`(order 0.6.0): OPERATOR_ADMIN 은 mfcId 를 비우면 모든 센터. 상태 탭 OPEN·ACKNOWLEDGED·RESOLVED. 새 것부터 최대 500.
//   조건(상태·센터)은 URL 쿼리에 둔다. 주문 번호는 직원 주문 상세로.
// - 확인 처리 `POST /fulfillment-issues/{issueId}/acknowledgements` {note}(1~500자) — 표시만 한다(주문 상태·재고 그대로, 자동 취소·환불 없음).
//   메모에 고객 개인정보를 적지 않게 안내한다. 메모는 로그에 남기지 않는다.
// - 멈춘 주문 조치·인계 재시도·현장 중지 재시도는 서버(BO-12)가 아직 501 — "준비 중"으로만 둔다(버튼 없음).
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useState, type FormEvent } from 'react';
import { Link, useSearchParams } from 'react-router';

import { request } from '@pmart/web-core';
import { CommandFeedback, QueryState, toUiState, useCommand } from '@pmart/web-ui';
import { commandParams } from '../../api/command';
import type { components } from '../../api/generated/order';
import { useApi } from '../../app/ApiContext';
import { messages as m } from '../../shared/messages';
import { label, text, when } from '../../shared/ops';

type Issue = components['schemas']['FulfillmentIssue'];
type IssueState = NonNullable<Issue['state']>;
const STATES: readonly IssueState[] = ['OPEN', 'ACKNOWLEDGED', 'RESOLVED'];
const isState = (v: string | null): v is IssueState => STATES.some((s) => s === v);

function Acknowledge({ issue }: { readonly issue: Issue }) {
  const api = useApi();
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);
  const [note, setNote] = useState('');
  const ack = useCommand(async (v: { note: string }, key) => {
    const r = await request(
      'POST',
      api.orders.POST('/fulfillment-issues/{issueId}/acknowledgements', { ...commandParams(key, { path: { issueId: issue.issueId ?? '' } }), body: { note: v.note } }),
    );
    await queryClient.invalidateQueries({ queryKey: ['fulfillment-issues'] });
    return r;
  });
  if (!open) {
    return (
      <button type="button" className="btn btn-xs" onClick={() => setOpen(true)}>
        {m.pending.acknowledge}
      </button>
    );
  }
  const ok = note.trim().length >= 1 && note.trim().length <= 500;
  return (
    <form
      className="space-y-1"
      aria-label={`${m.pending.acknowledge} ${issue.issueId ?? ''}`}
      onSubmit={(e) => {
        e.preventDefault();
        if (!ok) return;
        if (ack.phase.kind === 'rejected') ack.reset();
        void ack.run({ note: note.trim() });
      }}
    >
      <label className="flex flex-col gap-1 text-xs">
        {m.pending.note}
        <textarea className="textarea textarea-xs w-64" maxLength={500} value={note} onChange={(e) => setNote(e.target.value)} />
      </label>
      <p className="text-xs opacity-70">{m.pending.noteHint}</p>
      <div className="flex gap-1">
        <button type="submit" className="btn btn-xs btn-primary" disabled={!ok || ack.busy}>
          {m.pending.confirm}
        </button>
        <button type="button" className="btn btn-xs" disabled={ack.busy} onClick={() => setOpen(false)}>
          {m.pending.cancel}
        </button>
      </div>
      <CommandFeedback command={ack}>{() => <span className="text-xs text-success">{m.pending.done}</span>}</CommandFeedback>
    </form>
  );
}

export function PendingPage() {
  const api = useApi();
  const [params, setParams] = useSearchParams();
  const stateParam = params.get('state');
  const state: IssueState = isState(stateParam) ? stateParam : 'OPEN';
  const mfcId = params.get('mfcId') ?? '';
  const [draftMfc, setDraftMfc] = useState(mfcId);
  const issues = useQuery({
    queryKey: ['fulfillment-issues', state, mfcId],
    queryFn: () => request('GET', api.orders.GET('/fulfillment-issues', { params: { query: { state, ...(mfcId ? { mfcId } : {}) } } })),
  });
  const setQuery = (next: { state?: IssueState; mfcId?: string }) => {
    const s = next.state ?? state;
    const c = next.mfcId ?? mfcId;
    setParams({ state: s, ...(c ? { mfcId: c } : {}) });
  };
  const onSubmit = (e: FormEvent) => {
    e.preventDefault();
    setQuery({ mfcId: draftMfc.trim() });
  };

  return (
    <section className="max-w-6xl space-y-4">
      <h1 className="text-xl font-bold">{m.pending.title}</h1>
      <p className="text-sm opacity-70">{m.pending.intro}</p>
      <div role="tablist" className="tabs tabs-box w-fit">
        {STATES.map((s) => (
          <button key={s} type="button" role="tab" aria-selected={s === state} className={`tab ${s === state ? 'tab-active' : ''}`} onClick={() => setQuery({ state: s })}>
            {label(m.orders.issueState, s)}
          </button>
        ))}
      </div>
      <form className="flex flex-wrap items-end gap-2" onSubmit={onSubmit}>
        <label className="flex flex-col gap-1 text-sm">
          {m.pending.mfcId}
          <input className="input input-sm w-48" maxLength={64} value={draftMfc} onChange={(e) => setDraftMfc(e.target.value)} />
        </label>
        <button type="submit" className="btn btn-sm">
          {m.pending.apply}
        </button>
      </form>
      <QueryState state={toUiState(issues, (r) => (r.items ?? []).length === 0)} onRetry={() => void issues.refetch()} emptyText={m.pending.empty}>
        {(r) => (
          <table className="table table-sm rounded-box bg-base-100">
            <thead>
              <tr>
                <th>{m.pending.blockedAt}</th>
                <th>{m.pending.orderId}</th>
                <th>{m.orders.mfcId}</th>
                <th>{m.pending.sku}</th>
                <th>{m.pending.lot}</th>
                <th>{m.pending.qty}</th>
                <th>{m.pending.reason}</th>
                <th>{m.pending.state}</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {(r.items ?? []).map((i, n) => (
                <tr key={i.issueId ?? `issue-${n}`} data-testid="pending-issue">
                  <td>{when(i.blockedAt)}</td>
                  <td>
                    {i.orderId ? (
                      <Link className="link" to={`/orders/${encodeURIComponent(i.orderId)}`}>
                        {i.orderId}
                      </Link>
                    ) : (
                      m.none
                    )}
                  </td>
                  <td>{text(i.mfcId)}</td>
                  <td>{text(i.sku)}</td>
                  <td>{text(i.lotId)}</td>
                  <td>{text(i.blockedQty)}</td>
                  <td>{label(m.pending.reasonName, i.reason)}</td>
                  <td>
                    {label(m.orders.issueState, i.state)}
                    {i.acknowledgedAt && <p className="text-xs opacity-70">{m.pending.acknowledged(text(i.acknowledgedBy), when(i.acknowledgedAt))}</p>}
                    {i.note && <p className="text-xs opacity-70">{i.note}</p>}
                  </td>
                  <td>{i.state === 'OPEN' && <Acknowledge issue={i} />}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </QueryState>

      <div className="space-y-1 rounded-box bg-base-100 p-4 text-sm" data-testid="pending-preparing">
        <h2 className="font-semibold">{m.pending.preparingTitle}</h2>
        <p className="opacity-70">{m.pending.preparingBody}</p>
        <ul className="list-disc pl-5">
          {m.pending.preparingItems.map((t) => (
            <li key={t}>
              {t} <span className="badge badge-ghost badge-sm">{m.pending.preparing}</span>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
