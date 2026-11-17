// 포장 인계 현황 — 센터 관리자(MFC_SUPERVISOR), 보기만
// (백엔드 요청 clients/all/2026-11-17-request-packing-handover, bff 0.11.0 `GET /views/packing-handover`,
//  배송 원문 §10.1 포장 인계 현황 · §3.1 출고대기·인계 구역 화면 · §3.4 포장마다 인계 시각·라이더 · §3.7 일부 인계).
// - 센터 관리자는 자기 센터로 고정(다른 센터 403). 상태를 비우면 끝나지 않은 출고(PREPARING·READY·PARTIALLY_HANDED_OVER), 오래된 것부터.
//   page.nextCursor 로 다음 쪽. 모니터에 띄워 두는 화면이라 30초마다 다시 읽는다.
// - 단계(stage)는 서버가 정한다. null(규칙에 없는 조합)이면 추정하지 않고 원천 출고 상태를 그대로 보인다.
// - 배송 원천이 실패하면 delivery.state null → "모름(조회 실패)", 배송이 없으면(delivery null) "배송 없음" — 둘을 섞지 않는다.
// - 개인정보·QR 없음. 주문번호(orderNumber)가 없는 옛 주문은 주문 ID.
import { useQuery } from '@tanstack/react-query';
import { useSearchParams } from 'react-router';

import { request } from '@pmart/web-core';
import { formatSeoul, QueryState, toUiState } from '@pmart/web-ui';
import type { paths } from '../../api/generated/backoffice-bff';
import { useApi } from '../../app/ApiContext';
import { messages } from '../../shared/messages';

const m = messages.packingHandover;
const none = messages.none;
const name = (map: Readonly<Record<string, string>>, v: string | null | undefined) => (v ? (map[v] ?? v) : none);
const when = (iso: string | null | undefined) => (iso ? formatSeoul(iso) : none);

const SHIPMENT_STATES = ['PREPARING', 'READY', 'PARTIALLY_HANDED_OVER', 'HANDED_OVER', 'CANCELLED', 'CLOSED_PARTIAL'] as const;
const PAGE_SIZE = 50;
const REFRESH_MS = 30_000;

type View = paths['/views/packing-handover']['get']['responses'][200]['content']['application/json'];
type Item = NonNullable<View['items']>[number];

const STAGE_BADGE: Readonly<Record<string, string>> = {
  REQUESTED: 'badge-ghost',
  PICKING: 'badge-info',
  PACKING: 'badge-warning',
  READY_FOR_HANDOVER: 'badge-success',
  PARTIALLY_HANDED_OVER: 'badge-accent',
  HANDED_OVER: 'badge-neutral',
};

/** `/c/:mfcId/packing-handover` */
export function PackingHandoverMenu({ mfcId }: { readonly mfcId: string }) {
  const api = useApi();
  const [params, setParams] = useSearchParams();
  const raw = params.get('state') ?? '';
  const state = (SHIPMENT_STATES as readonly string[]).includes(raw) ? raw : '';
  const cursor = params.get('cursor') ?? '';
  const set = (next: { state?: string; cursor?: string }) => {
    const s = next.state ?? state;
    setParams({ ...(s ? { state: s } : {}), ...(next.cursor ? { cursor: next.cursor } : {}) });
  };
  const query = useQuery({
    queryKey: ['packing-handover', mfcId, state, cursor],
    refetchInterval: REFRESH_MS,
    queryFn: () =>
      request(
        'GET',
        api.bff.GET('/views/packing-handover', { params: { query: { mfcId, size: PAGE_SIZE, ...(state ? { state: [state] } : {}), ...(cursor ? { cursor } : {}) } } }),
      ),
  });
  return (
    <section className="space-y-4">
      <h1 className="text-xl font-bold">{m.title}</h1>
      <p className="text-sm opacity-70">{m.intro}</p>
      <div className="flex flex-wrap items-end gap-2 rounded-box bg-base-100 p-3 text-sm">
        <label className="flex flex-col gap-1">
          {m.state}
          <select className="select select-sm w-44" value={state} onChange={(e) => set({ state: e.target.value })}>
            <option value="">{m.activeStates}</option>
            {SHIPMENT_STATES.map((s) => (
              <option key={s} value={s}>
                {name(m.shipmentState, s)}
              </option>
            ))}
          </select>
        </label>
        <button type="button" className="btn btn-sm" onClick={() => void query.refetch()} disabled={query.isFetching}>
          {m.refresh}
        </button>
        <span className="text-xs opacity-70">{m.autoRefreshNote}</span>
      </div>
      <QueryState state={toUiState(query)} onRetry={() => void query.refetch()}>
        {(view) => {
          const items = view.items ?? [];
          const nextCursor = view.page?.nextCursor ?? null;
          return (
            <div className="space-y-3">
              {(view.unavailableSources?.length ?? 0) > 0 && (
                <p role="alert" className="alert alert-warning text-sm">{`${messages.unavailableSources}: ${(view.unavailableSources ?? []).join(', ')}`}</p>
              )}
              {items.length === 0 ? (
                <p data-state="empty" className="p-4 opacity-70">
                  {m.empty}
                </p>
              ) : (
                <div className="overflow-x-auto">
                  <table className="table table-sm rounded-box bg-base-100">
                    <thead>
                      <tr>
                        <th>{m.col.order}</th>
                        <th>{m.col.stage}</th>
                        <th>{m.col.tasks}</th>
                        <th>{m.col.packages}</th>
                        <th>{m.col.readyAt}</th>
                        <th>{m.col.dispatch}</th>
                        <th>{m.col.delivery}</th>
                      </tr>
                    </thead>
                    <tbody>
                      {items.map((it, i) => (
                        <Row key={it.shipmentId ?? `shp-${i}`} it={it} />
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
              {(cursor || nextCursor) && (
                <div className="flex gap-2">
                  {cursor && (
                    <button type="button" className="btn btn-sm" onClick={() => set({})}>
                      {m.first}
                    </button>
                  )}
                  {nextCursor && (
                    <button type="button" className="btn btn-sm" onClick={() => set({ cursor: nextCursor })}>
                      {m.next}
                    </button>
                  )}
                </div>
              )}
            </div>
          );
        }}
      </QueryState>
    </section>
  );
}

function Row({ it }: { readonly it: Item }) {
  const task = (t: Item['pick']) => (t ? `${name(m.taskState, t.state)}${t.blockReason ? ` (${t.blockReason})` : ''}` : m.noTask);
  return (
    <tr data-testid="packing-row">
      <td>
        <div className="font-mono font-semibold">{it.orderNumber ?? it.orderId ?? none}</div>
        {it.workOrderKind === 'RESHIPMENT' && <span className="badge badge-warning badge-sm">{m.reshipment}</span>}
        <div className="font-mono text-xs opacity-60">{it.shipmentId}</div>
      </td>
      <td data-testid="stage">
        {it.stage ? (
          <span className={`badge ${STAGE_BADGE[it.stage] ?? 'badge-ghost'}`}>{name(m.stageName, it.stage)}</span>
        ) : (
          <span className="text-xs opacity-70">{m.stageNone(name(m.shipmentState, it.shipment?.state))}</span>
        )}
      </td>
      <td className="text-xs">
        <div>{`${m.pick} ${task(it.pick)}`}</div>
        <div>{`${m.pack} ${task(it.pack)}`}</div>
      </td>
      <td className="text-xs" data-testid="packages">
        <div>{m.packageSummary(it.sealedPackages ?? null, it.packageCount ?? null, it.handedOverQty?.qty ?? null, it.remainingPackages ?? null)}</div>
        {(it.packages ?? []).length > 0 && (
          <ul className="mt-1 space-y-0.5">
            {(it.packages ?? []).map((p) => (
              <li key={p.packageId} className="font-mono">
                {`${p.packageId} · ${name(m.packageState, p.state)}`}
                {p.fenceState && m.fenceState[p.fenceState] ? ` · ${m.fenceState[p.fenceState]}` : ''}
                {p.handedOverAt ? ` · ${m.handedTo(when(p.handedOverAt), p.riderId ?? none)}` : ''}
              </li>
            ))}
          </ul>
        )}
      </td>
      <td className="text-xs">{when(it.readyAt)}</td>
      <td className="text-xs">{when(it.dispatchRequestedAt)}</td>
      <td className="text-xs" data-testid="delivery">
        {it.delivery == null ? (
          <span className="opacity-70">{m.noDelivery}</span>
        ) : it.delivery.state ? (
          <>
            <div>{name(messages.centerDelivery.executionState, it.delivery.state)}</div>
            {it.riderId && <div>{m.assignedRider(it.riderId)}</div>}
          </>
        ) : (
          <span className="text-warning">{m.deliveryUnknown}</span>
        )}
      </td>
    </tr>
  );
}
