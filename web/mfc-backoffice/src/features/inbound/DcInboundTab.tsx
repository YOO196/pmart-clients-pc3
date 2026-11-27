// 입고 > DC 이관 입고(사용자 2026-11-26 "DC 에서 MFC 로 입고하려는 TRF 를 백오피스에서 조회 … DC 에서 입고 받은 거 적치하고,
// 입고받아서 추가되는 재고 실시간으로 추적되는 목록·기능·화면").
// - 목록: mfc-inbound `GET /inbound-promises?mfcId=&state=&date=`(0.16.0 — 출발 센터·출발·도착 예정·운행·상품 줄·박스(LPN)·수령), 30초마다 다시 읽는다.
// - 상세(?trf=): `GET /inbound-promises/{trfId}` — 단계(출발 → 도착 → 수령 → 적치 → 재고 반영), 상품 줄(예정·수령 정상/격리/보류),
//   박스(LPN), 수령 기록(재고 반영 상태·차이), 적치 작업(`GET /inbound-tasks?mfcId=&receiptId=` — 품질검사·적치, 누르면 작업 상세에서 적치),
//   상품별 지금 재고(`GET /mfcs/{mfcId}/stock?sku=` — 재고 실시간 스트림이 바뀐 SKU 만 다시 읽는다).
// - 맨 위 흐름 한 줄(DcInboundFlow, 2026-11-27 #607 흐름 그림을 옮김): 준비 중 → 오는 중 → 도착·수령 중 → 오늘 받음 건수, 누르면 목록 거르기.
// 값은 서버 값만 — 수령 ≠ 반영(재고 반영 상태가 APPLIED 일 때만 "반영"), 조회 실패는 0 이 아니라 "조회 실패".
import { useQueries, useQuery } from '@tanstack/react-query';
import { Link, useSearchParams } from 'react-router';

import { request } from '@pmart/web-core';
import { formatSeoul, QueryState, toUiState } from '@pmart/web-ui';
import type { components } from '../../api/generated/mfc-inbound';
import { useApi } from '../../app/ApiContext';
import { centerPath } from '../../app/nav';
import { messages } from '../../shared/messages';
import { ProgressSteps, type StepPlace } from '../../shared/ProgressSteps';
import { StockLiveStatus } from '../stock-stream/useStockStream';
import { DcInboundFlow } from './DcInboundFlow';

const m = messages.inbound.dc;
type Promise_ = components['schemas']['InboundPromise'];
type State = components['schemas']['InboundPromiseState'];
const STATES: readonly State[] = ['EXPECTED', 'RECEIVING', 'TIN_POSTED', 'CANCELLED'];
const REFRESH_MS = 30_000;

const stateBadge = (s: State | undefined) =>
  s === 'EXPECTED' ? 'badge-info' : s === 'RECEIVING' ? 'badge-warning' : s === 'TIN_POSTED' ? 'badge-success' : 'badge-ghost';
const sum = (p: Promise_, k: 'expectedQty' | 'receivedQty') => (p.lines ?? []).reduce((a, l) => a + (l[k] ?? 0), 0);

export function DcInboundTab({ mfcId }: { readonly mfcId: string }) {
  const api = useApi();
  const [params, setParams] = useSearchParams();
  const rawState = params.get('dstate') ?? '';
  const state = (STATES as readonly string[]).includes(rawState) ? (rawState as State) : undefined;
  const date = params.get('ddate') ?? '';
  const trf = params.get('trf');
  const set = (next: Record<string, string>) => {
    const p = new URLSearchParams(params);
    for (const [k, v] of Object.entries(next)) {
      if (v) p.set(k, v);
      else p.delete(k);
    }
    setParams(p, { replace: true });
  };
  const list = useQuery({
    queryKey: ['inbound-promises', mfcId, state ?? 'ALL', date],
    refetchInterval: REFRESH_MS,
    queryFn: async () => {
      const get = async (st?: State) =>
        (await request('GET', api.inbound.GET('/inbound-promises', { params: { query: { mfcId, size: 200, ...(st ? { state: st } : {}), ...(date ? { date } : {}) } } }))).items ?? [];
      if (state) return get(state);
      // "전체" — 서버는 state 를 비우면 끝나지 않은 것(EXPECTED·RECEIVING)만 준다(mfc-inbound 0.16.0).
      // 수령·적치까지 끝난(재고 반영 TIN_POSTED) TRF 가 빠지지 않게 함께 읽는다(사용자 2026-11-27 "적치까지 완료했는데 백오피스에 안 떠").
      const [open, posted] = await Promise.all([get(), get('TIN_POSTED')]);
      const seen = new Set(open.map((p) => p.trfId));
      return [...open, ...posted.filter((p) => !seen.has(p.trfId))];
    },
  });
  if (trf) return <DcInboundDetail mfcId={mfcId} trfId={trf} onBack={() => set({ trf: '' })} />;
  return (
    <div className="space-y-3 text-sm" data-testid="dc-inbound">
      {/* DC 에서 이 센터까지 단계별 건수 — 누르면 아래 목록을 그 상태로 거른다 */}
      <DcInboundFlow mfcId={mfcId} onPick={(st) => set({ dstate: st, ddate: st === 'TIN_POSTED' ? new Date(Date.now() + 9 * 3_600_000).toISOString().slice(0, 10) : '' })} />
      <div className="flex flex-wrap items-end gap-3">
        <label className="flex flex-col gap-1">
          {m.state}
          <select className="select select-sm w-36" aria-label={m.state} value={state ?? ''} onChange={(e) => set({ dstate: e.target.value })}>
            <option value="">{m.all}</option>
            {STATES.map((s) => (
              <option key={s} value={s}>
                {m.stateName[s]}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1">
          {m.date}
          <input type="date" className="input input-sm w-40" aria-label={m.date} value={date} onChange={(e) => set({ ddate: e.target.value })} />
        </label>
        <span className="ml-auto flex items-center gap-2 text-xs text-base-content/60">
          <StockLiveStatus mfcId={mfcId} />· {m.refreshNote}
        </span>
      </div>
      <QueryState state={toUiState(list, (d) => d.length === 0)} onRetry={() => void list.refetch()} emptyText={m.empty}>
        {(items) => (
          <div className="overflow-x-auto rounded-box border border-base-300 bg-base-100">
            <table className="table table-sm">
              <thead>
                <tr>
                  <th>{m.col.trf}</th>
                  <th>{m.col.from}</th>
                  <th>{m.col.state}</th>
                  <th>{m.col.departed}</th>
                  <th>{m.col.eta}</th>
                  <th>{m.col.arrived}</th>
                  <th className="text-right">{m.col.qty}</th>
                  <th className="text-right">{m.col.boxes}</th>
                </tr>
              </thead>
              <tbody>
                {items.map((p) => {
                  const expected = sum(p, 'expectedQty');
                  const received = sum(p, 'receivedQty');
                  return (
                    <tr key={p.trfId} className="cursor-pointer hover:bg-base-200/50" onClick={() => set({ trf: p.trfId ?? '' })} data-testid="dc-inbound-row">
                      <td>
                        {/* 긴 trfId 대신 화면 번호(T…·W…, mfc-inbound 0.25.0) — 없으면 "번호 없음"(trfId 를 대신 내지 않음) */}
                        <button type="button" className="link font-mono font-semibold" onClick={() => set({ trf: p.trfId ?? '' })} data-testid="dc-inbound-no">
                          {p.trfNumber ?? m.noNumber}
                        </button>
                        {p.waveNumber && <span className="ml-1.5 font-mono text-xs text-base-content/55">{p.waveNumber}</span>}
                      </td>
                      <td>{p.fromCdc ?? messages.none}</td>
                      <td>
                        <span className={`badge badge-sm ${stateBadge(p.state)}`}>{m.stateName[p.state ?? ''] ?? p.state}</span>
                        {p.state === 'TIN_POSTED' && <AfterReceipt mfcId={mfcId} receiptIds={(p.receipts ?? []).map((r) => r.receiptId).filter((x): x is string => !!x)} />}
                      </td>
                      <td>{p.departedAt ? formatSeoul(p.departedAt) : m.notDeparted}</td>
                      <td>{p.eta ? formatSeoul(p.eta) : p.plannedArrivalAt ? formatSeoul(p.plannedArrivalAt) : messages.none}</td>
                      <td>{p.arrivedAt ? formatSeoul(p.arrivedAt) : messages.none}</td>
                      <td className="text-right">
                        <span className="font-semibold">{m.qty(received, expected)}</span>
                        <span className="block text-xs text-base-content/60">{m.lines((p.lines ?? []).length)}</span>
                      </td>
                      <td className="text-right">{(p.packages ?? []).length}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </QueryState>
    </div>
  );
}

type InboundTask = components['schemas']['InboundTask'];

/** 검사·적치 진행 — 수량 합(격리 이동은 빼고). 작업이 모두 끝나면 판매 가능 */
export function afterProgress(tasks: readonly InboundTask[]) {
  const sum = (ts: readonly InboundTask[], f: (t: InboundTask) => number) => ts.reduce((a, t) => a + f(t), 0);
  const ins = tasks.filter((t) => t.taskType === 'INSPECT');
  const put = tasks.filter((t) => t.taskType === 'PUTAWAY');
  const open = tasks.filter((t) => t.taskType !== 'QUARANTINE_MOVE' && t.state !== 'COMPLETED');
  return {
    inspect: [sum(ins, (t) => t.doneQty), sum(ins, (t) => t.plannedQty)] as const,
    putaway: [sum(put, (t) => t.doneQty), sum(put, (t) => t.plannedQty)] as const,
    sellable: tasks.length > 0 && open.length === 0,
  };
}

/** 목록의 "수령 끝" 옆 — 검사 a/b · 적치 c/d, 다 끝나면 판매 가능(mfc 시뮬 C-7) */
function AfterReceipt({ mfcId, receiptIds }: { readonly mfcId: string; readonly receiptIds: readonly string[] }) {
  const api = useApi();
  const q = useQuery({
    queryKey: ['inbound-tasks', mfcId, 'by-receipts', receiptIds.join(',')],
    enabled: receiptIds.length > 0,
    refetchInterval: 15_000,
    queryFn: async () =>
      (await Promise.all(receiptIds.map((receiptId) => request('GET', api.inbound.GET('/inbound-tasks', { params: { query: { mfcId, receiptId } } }))))).flatMap((r) => r.items ?? []),
  });
  if (receiptIds.length === 0) return null;
  if (q.isError) return <span className="block text-xs text-error">{m.after.failed}</span>;
  if (!q.data) return <span className="block text-xs text-base-content/40">…</span>;
  return <AfterText tasks={q.data} />;
}

function AfterText({ tasks }: { readonly tasks: readonly InboundTask[] }) {
  const x = afterProgress(tasks);
  if (tasks.length === 0)
    return (
      <span className="block text-xs text-base-content/60" data-testid="dc-after">
        {m.after.noTasks}
      </span>
    );
  if (x.sellable)
    return (
      <span className="block text-xs font-semibold text-success" data-testid="dc-after">
        {m.after.sellable}
      </span>
    );
  return (
    <span className="block text-xs text-warning" data-testid="dc-after">
      {m.after.inspect(x.inspect[0], x.inspect[1])} · {x.putaway[1] > 0 ? m.after.putaway(x.putaway[0], x.putaway[1]) : m.after.putawayWait}
    </span>
  );
}

type Line = NonNullable<Promise_['lines']>[number];

/** 박스(LPN) 내용 → SKU·LOT 별 예정 수량(받은 수는 수령 등록 전이라 0) */
function boxLines(packages: NonNullable<Promise_['packages']>): Line[] {
  const m = new Map<string, Line>();
  for (const b of packages) {
    const key = `${b.sku}|${b.lotId ?? ''}`;
    const cur = m.get(key);
    m.set(key, { sku: b.sku, lotId: b.lotId ?? null, expectedQty: (cur?.expectedQty ?? 0) + (b.qty ?? 0), receivedQty: 0, quarantinedQty: 0, pendingQty: 0, barcodes: [] } as Line);
  }
  return [...m.values()];
}

/** 지금 단계를 한 문장으로 */
function nowText(p: Promise_, putawayLeft: number | null): string {
  const n = messages.inbound.dc.now;
  const applied = (p.receipts ?? []).some((r) => r.inventoryApplyStatus === 'APPLIED');
  if (p.state === 'CANCELLED') return n.cancelled;
  if (p.state === 'TIN_POSTED' || applied) return putawayLeft === 0 ? n.done : putawayLeft === null ? n.applied : n.putaway(putawayLeft);
  if ((p.receipts ?? []).length > 0) return n.applying;
  if (p.state === 'RECEIVING' || p.arrivedAt) return n.receiving((p.packages ?? []).length);
  return p.departedAt ? n.coming : n.prep;
}

/** 단계 자리 — 출발 → 도착 → 수령 → 적치 → 재고 반영 */
function placeOf(p: Promise_, putawayLeft: number | null): StepPlace | null {
  const applied = (p.receipts ?? []).some((r) => r.inventoryApplyStatus === 'APPLIED');
  if (p.state === 'TIN_POSTED' || applied) return putawayLeft === 0 ? { step: 4, done: true } : { step: 3, done: false };
  if (p.state === 'RECEIVING') return (p.receipts ?? []).length > 0 ? { step: 2, done: false } : { step: 1, done: !!p.arrivedAt };
  if (p.state === 'EXPECTED') return p.departedAt ? { step: 0, done: true } : { step: 0, done: false };
  return null;
}

function DcInboundDetail({ mfcId, trfId, onBack }: { readonly mfcId: string; readonly trfId: string; readonly onBack: () => void }) {
  const api = useApi();
  const q = useQuery({
    queryKey: ['inbound-promise', trfId],
    refetchInterval: 15_000,
    queryFn: () => request('GET', api.inbound.GET('/inbound-promises/{trfId}', { params: { path: { trfId } } })),
  });
  const receiptIds = (q.data?.receipts ?? []).map((r) => r.receiptId).filter((x): x is string => !!x);
  const tasks = useQuery({
    queryKey: ['inbound-tasks', mfcId, 'by-receipts', receiptIds.join(',')],
    enabled: receiptIds.length > 0,
    refetchInterval: 15_000,
    queryFn: async () =>
      (await Promise.all(receiptIds.map((receiptId) => request('GET', api.inbound.GET('/inbound-tasks', { params: { query: { mfcId, receiptId } } }))))).flatMap((r) => r.items ?? []),
  });
  // 상품 줄이 비었으면(서버가 출발 줄 없이 박스 매니페스트만 가진 건) 박스(LPN) 내용을 SKU·LOT 별로 묶어 상품 줄 대신 — 사용자 2026-11-27 "상품 줄이 비어 진행을 모르겠다"
  const fromBoxes = (q.data?.lines ?? []).length === 0;
  const lines: readonly Line[] = fromBoxes ? boxLines(q.data?.packages ?? []) : (q.data?.lines ?? []);
  const skus = [...new Set(lines.map((l) => l.sku).filter((x): x is string => !!x))];
  // 지금 누가 이 입고를 하고 있나 — RECEIVE 작업 taskId = trfId(mfc-capacity 0.13.1)
  const assignee = useQuery({
    queryKey: ['assignments', mfcId, 'task', trfId],
    refetchInterval: 15_000,
    queryFn: async () => ((await request('GET', api.capacity.GET('/assignments', { params: { query: { mfcId, taskId: trfId } } }))).items ?? []).find((a) => a.state === 'ACTIVE') ?? null,
  });
  const workers = useQuery({
    queryKey: ['workers', mfcId, 'DEFAULT'],
    enabled: !!assignee.data,
    queryFn: async () => (await request('GET', api.capacity.GET('/mfcs/{mfcId}/workers', { params: { path: { mfcId }, query: {} } }))).items ?? [],
  });
  const assigneeName = assignee.data ? (workers.data?.find((w) => w.workerId === assignee.data?.workerId)?.displayName ?? assignee.data.workerId) : null;
  // 상품별 지금 재고 — 쿼리 키 ['stock', mfcId, sku] 는 재고 실시간 스트림이 바뀐 SKU 만 다시 읽는다
  const stocks = useQueries({
    queries: skus.map((sku) => ({
      queryKey: ['stock', mfcId, sku],
      queryFn: () => request('GET', api.inventory.GET('/mfcs/{mfcId}/stock', { params: { path: { mfcId }, query: { sku } } })),
    })),
  });
  const stockOf = (sku: string) => {
    const s = stocks[skus.indexOf(sku)];
    if (!s || s.isPending) return null;
    if (s.isError) return 'error' as const;
    const lots = s.data?.lots ?? [];
    return { onHand: lots.reduce((a, l) => a + (l.onHand ?? 0), 0), available: lots.reduce((a, l) => a + Math.max(0, l.available ?? 0), 0) };
  };
  const putawayLeft = tasks.data ? tasks.data.filter((t) => t.state !== 'COMPLETED').length : null;
  const nameOf = (sku: string) => {
    const st = stocks[skus.indexOf(sku)];
    return st?.data?.productName ?? null;
  };
  return (
    <div className="space-y-4 text-sm" data-testid="dc-inbound-detail">
      <div className="flex flex-wrap items-center gap-3">
        <button type="button" className="btn btn-sm" onClick={onBack}>
          {m.back}
        </button>
        <h2 className="font-mono text-lg font-bold" data-testid="dc-inbound-title">
          {q.data ? [q.data.trfNumber ?? m.noNumber, q.data.waveNumber].filter(Boolean).join(' · ') : '…'}
        </h2>
        <span className="ml-auto text-xs text-base-content/60">
          <StockLiveStatus mfcId={mfcId} />
        </span>
      </div>
      <QueryState state={toUiState(q)} onRetry={() => void q.refetch()}>
        {(p) => (
          <>
            <ProgressSteps
              steps={m.steps}
              place={placeOf(p, putawayLeft)}
              ended={p.state === 'CANCELLED' ? m.stateName.CANCELLED : undefined}
              label={m.stepsLabel}
              testId="dc-inbound-steps"
              endedTestId="dc-inbound-ended"
            />
            {/* 지금 어디까지 — 서버가 아는 것만(PDA 에서 센 수량은 수령 등록 전까지 서버에 없다) */}
            <p className="rounded-box bg-primary/5 px-4 py-3 text-base font-semibold" data-testid="dc-inbound-now">
              {nowText(p, putawayLeft)}
              {assigneeName && <span className="ml-2 text-sm font-normal text-base-content/70">{m.assignee(assigneeName)}</span>}
            </p>
            <dl className="grid grid-cols-2 gap-x-6 gap-y-1 rounded-box bg-base-100 p-4 md:grid-cols-4">
              {(
                [
                  [
                    m.col.state,
                    <>
                      <span className={`badge badge-sm ${stateBadge(p.state)}`}>{m.stateName[p.state ?? ''] ?? p.state}</span>
                      {p.state === 'TIN_POSTED' && tasks.data && <AfterText tasks={tasks.data} />}
                    </>,
                  ],
                  [m.col.from, p.fromCdc ?? messages.none],
                  [m.trip, p.tripId ?? messages.none],
                  // 출발 시각이 안 왔어도 도착했으면 "출발 전" 이 아니다
                  [m.col.departed, p.departedAt ? formatSeoul(p.departedAt) : p.arrivedAt ? m.departedUnknown : m.notDeparted],
                  [m.col.eta, p.eta ? formatSeoul(p.eta) : p.plannedArrivalAt ? formatSeoul(p.plannedArrivalAt) : messages.none],
                  [m.col.arrived, p.arrivedAt ? formatSeoul(p.arrivedAt) : messages.none],
                ] as const
              ).map(([k, v]) => (
                <div key={k}>
                  <dt className="text-xs text-base-content/60">{k}</dt>
                  <dd className="font-medium">{v}</dd>
                </div>
              ))}
            </dl>

            <section className="space-y-2 rounded-box bg-base-100 p-4">
              <h3 className="font-semibold">{m.linesTitle}</h3>
              {fromBoxes && lines.length > 0 && <p className="text-xs text-base-content/60" data-testid="dc-inbound-from-boxes">{m.fromBoxes}</p>}
              {lines.length === 0 && <p className="text-base-content/60">{m.noLines}</p>}
              <div className="overflow-x-auto">
                <table className="table table-sm" data-testid="dc-inbound-lines">
                  <thead>
                    <tr>
                      <th>{m.col.product}</th>
                      <th>{m.col.lot}</th>
                      <th className="text-right">{m.col.expected}</th>
                      <th className="text-right">{m.col.received}</th>
                      <th className="text-right">{m.col.left}</th>
                      <th className="text-right">{m.col.nowStock}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {lines.map((l) => {
                      const st = l.sku ? stockOf(l.sku) : null;
                      const left = (l.expectedQty ?? 0) - (l.receivedQty ?? 0);
                      return (
                        <tr key={`${l.sku}-${l.lotId ?? ''}`} data-testid="dc-inbound-line">
                          <td>
                            <span className="block font-medium">{l.productName ?? (l.sku ? nameOf(l.sku) : null) ?? l.sku}</span>
                            <span className="font-mono text-xs text-base-content/60">{l.sku}</span>
                          </td>
                          <td>
                            <span className="font-mono text-xs">{l.lotId ?? messages.none}</span>
                            {l.expiryDate && <span className="block text-xs text-base-content/60">{m.expiry(l.expiryDate)}</span>}
                          </td>
                          <td className="text-right">{l.expectedQty ?? 0}</td>
                          <td className="text-right">
                            <span className="font-semibold">{l.receivedQty ?? 0}</span>
                            {((l.quarantinedQty ?? 0) > 0 || (l.pendingQty ?? 0) > 0) && (
                              <span className="block text-xs text-warning">{m.receivedSplit(l.quarantinedQty ?? 0, l.pendingQty ?? 0)}</span>
                            )}
                          </td>
                          <td className={`text-right ${left > 0 ? 'font-semibold text-warning' : 'text-base-content/50'}`}>{left}</td>
                          <td className="text-right" data-testid="dc-inbound-stock">
                            {st === null ? (
                              '…'
                            ) : st === 'error' ? (
                              <span className="text-error">{m.stockFailed}</span>
                            ) : (
                              <>
                                <span className="font-bold text-primary">{m.available(st.available)}</span>
                                <span className="block text-xs text-base-content/60">{m.onHand(st.onHand)}</span>
                              </>
                            )}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </section>

            <div className="grid gap-4 lg:grid-cols-2">
              <section className="space-y-2 rounded-box bg-base-100 p-4">
                <h3 className="font-semibold">{m.receiptsTitle}</h3>
                {(p.receipts ?? []).length === 0 ? (
                  <p className="text-base-content/60">{p.state === 'EXPECTED' ? m.noReceiptYet : m.noReceipt}</p>
                ) : (
                  <ul className="space-y-1.5">
                    {(p.receipts ?? []).map((r) => (
                      <li key={r.receiptId} className="flex flex-wrap items-center gap-2" data-testid="dc-inbound-receipt">
                        <span className="font-mono text-xs">{r.receiptId}</span>
                        <span className={`badge badge-sm ${r.inventoryApplyStatus === 'APPLIED' ? 'badge-success' : r.inventoryApplyStatus === 'REJECTED' ? 'badge-error' : 'badge-warning'}`}>
                          {m.apply[r.inventoryApplyStatus ?? ''] ?? r.inventoryApplyStatus}
                        </span>
                        {r.receivedAt && <span className="text-xs text-base-content/60">{formatSeoul(r.receivedAt)}</span>}
                        {(r.discrepancies ?? []).length > 0 && <span className="text-xs text-warning">{m.discrepancies((r.discrepancies ?? []).length)}</span>}
                      </li>
                    ))}
                  </ul>
                )}
              </section>
              <section className="space-y-2 rounded-box bg-base-100 p-4">
                <h3 className="font-semibold">{m.tasksTitle}</h3>
                {receiptIds.length === 0 ? (
                  <p className="text-base-content/60">{m.tasksAfterReceipt}</p>
                ) : (
                  <QueryState state={toUiState(tasks, (d) => d.length === 0)} onRetry={() => void tasks.refetch()} emptyText={m.noTasks}>
                    {(list) => (
                      <ul className="space-y-1.5">
                        {list.map((t) => (
                          <li key={t.taskId} className="flex flex-wrap items-center gap-2" data-testid="dc-inbound-task">
                            <span className="badge badge-sm badge-outline">{messages.inbound.taskType[t.taskType ?? ''] ?? t.taskType}</span>
                            <span>{t.productName ?? t.sku}</span>
                            <span className="text-xs text-base-content/60">{m.taskQty(t.doneQty, t.plannedQty ?? 0)}</span>
                            <span className={`badge badge-sm ${t.state === 'COMPLETED' ? 'badge-success' : 'badge-warning'}`}>{messages.inbound.taskState[t.state ?? ''] ?? t.state}</span>
                            {t.state !== 'COMPLETED' && (
                              <Link className="link ml-auto text-xs" to={centerPath(mfcId, `inbound/tasks/${encodeURIComponent(t.taskId ?? '')}`)}>
                                {t.taskType === 'PUTAWAY' ? m.doPutaway : m.doInspect}
                              </Link>
                            )}
                          </li>
                        ))}
                      </ul>
                    )}
                  </QueryState>
                )}
              </section>
            </div>

            <section className="space-y-2 rounded-box bg-base-100 p-4">
              <h3 className="font-semibold">{m.boxesTitle((p.packages ?? []).length)}</h3>
              {(p.packages ?? []).length === 0 ? (
                <p className="text-base-content/60">{m.noBoxes}</p>
              ) : (
                <div className="flex flex-wrap gap-2">
                  {(p.packages ?? []).map((b, i) => (
                    <span key={`${b.lpn ?? ''}-${i}`} className="rounded-field border border-base-300 px-2 py-1 font-mono text-xs" data-testid="dc-inbound-box">
                      {b.lpn ?? messages.none} · {b.sku} × {b.qty ?? 0}
                    </span>
                  ))}
                </div>
              )}
            </section>
          </>
        )}
      </QueryState>
    </div>
  );
}
