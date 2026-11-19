// 확인 필요 포장(MB-3 — fulfillment 0.17.0 "그 센터 작업자·센터 관리자"): 라이더가 QR 을 찍었는데 인계 확정 없이 허가가 끝난 포장.
// 목록 `GET /packages?mfcId=&checkRequired=true`, 확인 `POST /packages/{id}/handover-checks` {result AT_STATION | TAKEN_BY_RIDER}.
// "포장대에 없음(라이더가 가져감)"은 재고가 빠지는 확정이라 한 번 더 묻는다. 409 FENCE_ACTIVE(허가가 아직 살아 있음)·INVALID_STATE 는 거절로.
// 결과를 모르면 같은 키로만 다시(useCommand). 확인 뒤에는 목록을 다시 읽는다.
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';

import { request } from '@pmart/web-core';
import { CommandFeedback, formatSeoul, QueryState, toUiState, useCommand } from '@pmart/web-ui';
import { commandParams } from '../../api/command';
import type { components } from '../../api/generated/mfc-fulfillment';
import { useApi } from '../../app/ApiContext';
import { idTail, RiderLabel } from '../../shared/displayNumber';
import { messages } from '../../shared/messages';

const m = messages.tasks.checks;
type Resolution = components['schemas']['HandoverResolution'];
type CheckResult = 'AT_STATION' | 'TAKEN_BY_RIDER';

export function HandoverChecks({ mfcId }: { readonly mfcId: string }) {
  const api = useApi();
  const query = useQuery({
    queryKey: ['packages-to-check', mfcId],
    queryFn: () => request('GET', api.fulfillment.GET('/packages', { params: { query: { mfcId, checkRequired: true } } })),
  });
  return (
    <div id="handover-checks" className="space-y-2 rounded-box bg-base-100 p-3 text-sm" data-testid="handover-checks">
      <div className="flex flex-wrap items-center gap-3">
        <h2 className="font-bold">{m.title}</h2>
        <button type="button" className="btn btn-xs" onClick={() => void query.refetch()} disabled={query.isFetching}>
          {messages.lists.refresh}
        </button>
      </div>
      <p className="text-xs opacity-70">{m.intro}</p>
      <QueryState state={toUiState(query, (r) => (r.items ?? []).length === 0)} onRetry={() => void query.refetch()} emptyText={m.empty}>
        {(r) => (
          <ul className="space-y-2">
            {r.asOf?.freshness && r.asOf.freshness !== 'CURRENT' && <li className="text-xs text-warning">{m.stale}</li>}
            {(r.items ?? []).map((p) => (
              <CheckRow key={p.packageId} mfcId={mfcId} item={p} />
            ))}
          </ul>
        )}
      </QueryState>
    </div>
  );
}

function CheckRow({ mfcId, item }: { readonly mfcId: string; readonly item: Resolution }) {
  const api = useApi();
  const queryClient = useQueryClient();
  const [confirming, setConfirming] = useState<CheckResult | null>(null);
  const packageId = item.packageId ?? '';
  const check = useCommand(async (result: CheckResult, key) => {
    const r = await request('POST', api.fulfillment.POST('/packages/{packageId}/handover-checks', { ...commandParams(key, { path: { packageId } }), body: { result } }));
    await queryClient.invalidateQueries({ queryKey: ['packages-to-check', mfcId] });
    return r;
  });
  const send = (result: CheckResult) => {
    setConfirming(null);
    if (check.phase.kind === 'rejected' || check.phase.kind === 'done') check.reset();
    void check.run(result);
  };
  return (
    <li className="space-y-1 rounded-box border border-base-300 p-2" data-testid="handover-check-row">
      <p className="font-semibold">{item.packingLocation ? m.location(item.packingLocation) : m.locationUnknown}</p>
      <p className="font-mono text-xs">
        {m.pkg(packageId)} {item.orderId ? `· ${m.order(item.orderId)}` : ''}
      </p>
      <p className="text-xs">
        {`${m.rider} `}
        {item.riderId ? <RiderLabel riderId={item.riderId} /> : messages.none}
        {item.fence?.expiresAt ? ` · ${m.expiredAt(formatSeoul(item.fence.expiresAt))}` : ''}
      </p>
      {confirming ? (
        <div role="alertdialog" aria-label={m.confirmTitle} className="space-y-1 rounded-box bg-base-200 p-2">
          <p>{confirming === 'TAKEN_BY_RIDER' ? m.confirmTaken(item.riderId ? idTail(item.riderId) : messages.none) : m.confirmAtStation}</p>
          <div className="flex gap-2">
            <button type="button" className="btn btn-xs btn-primary" onClick={() => send(confirming)}>
              {m.confirmOk}
            </button>
            <button type="button" className="btn btn-xs" onClick={() => setConfirming(null)}>
              {m.confirmCancel}
            </button>
          </div>
        </div>
      ) : (
        check.phase.kind !== 'done' && (
          <div className="flex flex-wrap gap-2">
            <button type="button" className="btn btn-sm" disabled={check.busy || check.phase.kind === 'unknown'} onClick={() => setConfirming('AT_STATION')}>
              {m.atStation}
            </button>
            <button type="button" className="btn btn-sm btn-error" disabled={check.busy || check.phase.kind === 'unknown'} onClick={() => setConfirming('TAKEN_BY_RIDER')}>
              {m.taken}
            </button>
          </div>
        )
      )}
      <CommandFeedback command={check}>{(r) => <p role="status">{r.verdict === 'HANDED_OVER' ? m.doneTaken : m.doneAtStation}</p>}</CommandFeedback>
    </li>
  );
}
