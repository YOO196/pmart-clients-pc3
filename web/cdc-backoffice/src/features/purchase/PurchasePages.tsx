// 상품 발주 — [발주 | 공급사 관리] 탭(?tab=). 사용자 2026-11-26 "Cdc에 상품 발주 탭 있어야해. 하위로 공급사 관리 탭이",
// "비즈니스 로직대로 발주관련 만들되, 실제 공급사가 있는 게 아니라 주문에 대한 회신 가짜데이터로 받고 입고 시키라고".
// 흐름: 발주 → 공급사 회신(가짜 공급사 — 전량·일부·거절) → 납품 예정(ASN, LOT·유통기한) → 입고 확정(실수령·불량) → 재고관리에 LOT 로.
// 서버: procurement·supplier·cdc-inbound ASN 이 3단계 자리표시자라 **제안 계약(api/proposed/purchase.ts)으로 목에서만** 돈다.
// 실서버(local·lan)에서는 부르지 않고 "서버 기능 없음"을 보인다. 확정 표시는 서버(목) 응답 상태만 따른다 — 발주 접수 ≠ 공급 확정 ≠ 입고.
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useState, type FormEvent } from 'react';
import { Link, useSearchParams } from 'react-router';

import { request } from '@pmart/web-core';
import { CommandFeedback, formatSeoul, formatSeoulDate, QueryState, toUiState, useCommand } from '@pmart/web-ui';
import { commandParams } from '../../api/command';
import type { PoState, PurchaseOrder, ReplyMode, Supplier } from '../../api/proposed/purchase';
import { useApi } from '../../app/ApiContext';
import { allMenus, centerPath } from '../../app/nav';
import { env } from '../../env';
import { messages } from '../../shared/messages';
import { SkuName } from '../../shared/SkuName';
import { PreparingPage } from '../menus/PreparingPage';

const t = messages.purchase;
type Tab = keyof typeof t.tabs;
const TABS = Object.keys(t.tabs) as Tab[];
const STATES: readonly PoState[] = ['ISSUED', 'CONFIRMED', 'PARTIALLY_CONFIRMED', 'REJECTED', 'ASN_RECEIVED', 'RECEIVED', 'CANCELLED'];
/** 공급사·ASN 을 기다리는 상태 — 화면이 몇 초마다 다시 읽는다 */
const WAITING: readonly PoState[] = ['ISSUED', 'CONFIRMED', 'PARTIALLY_CONFIRMED'];
const CANCELLABLE: readonly PoState[] = ['ISSUED', 'CONFIRMED', 'PARTIALLY_CONFIRMED'];
const REPLY_MODES: readonly ReplyMode[] = ['FULL', 'PARTIAL', 'REJECT'];

const path = (cdcId: string) => centerPath(cdcId, 'purchase');
const sum = (ns: readonly (number | null)[]) => ns.reduce<number>((a, n) => a + (n ?? 0), 0);
/** 오늘 + n일(서울 날짜) — 납기 입력 기본값만. 확정은 서버 */
const seoulDay = (n: number) => new Date(Date.now() + 9 * 3_600_000 + n * 86_400_000).toISOString().slice(0, 10);

function StateBadge({ state }: { readonly state: PoState }) {
  const tone =
    state === 'RECEIVED'
      ? 'badge-success'
      : state === 'REJECTED' || state === 'CANCELLED'
        ? 'badge-ghost'
        : state === 'ASN_RECEIVED'
          ? 'badge-info'
          : state === 'PARTIALLY_CONFIRMED'
            ? 'badge-warning'
            : 'badge-outline';
  return (
    <span className={`badge badge-sm whitespace-nowrap ${tone}`} data-testid="po-state">
      {t.states[state] ?? state}
    </span>
  );
}

/** `/c/:cdcId/purchase/*` */
export function PurchaseMenu({ cdcId }: { readonly cdcId: string }) {
  const [params] = useSearchParams();
  const tab = TABS.find((k) => k === params.get('tab')) ?? 'orders';
  const po = params.get('po');
  if (!env.isMock) return <PreparingPage menu={allMenus.find((x) => x.key === 'purchase')!} />;
  return (
    <section className="space-y-4">
      <h1>{messages.menus.purchase}</h1>
      <div role="tablist" className="tabs tabs-box w-fit" data-testid="purchase-tabs">
        {TABS.map((k) => (
          <Link key={k} role="tab" aria-selected={tab === k} className={`tab ${tab === k ? 'tab-active' : ''}`} to={`${path(cdcId)}?tab=${k}`}>
            {t.tabs[k]}
          </Link>
        ))}
      </div>
      <p className="text-xs text-base-content/60">{t.fakeNote}</p>
      {tab === 'orders' && (po ? <PoDetail cdcId={cdcId} id={po} /> : <OrdersTab cdcId={cdcId} />)}
      {tab === 'suppliers' && <SuppliersTab />}
    </section>
  );
}

// ---------------------------------------------------------------- 발주 목록

function OrdersTab({ cdcId }: { readonly cdcId: string }) {
  const api = useApi();
  const [params, setParams] = useSearchParams();
  const state = STATES.find((s) => s === params.get('state'));
  const [adding, setAdding] = useState(false);
  const query = useQuery({
    queryKey: ['cdc', cdcId, 'purchase-orders', state ?? 'all'],
    queryFn: async () =>
      (
        await request(
          'GET',
          api.purchase.GET('/purchase-orders', {
            params: { path: {}, query: { cdcId, ...(state ? { state } : {}) } },
          }),
        )
      ).items,
    refetchInterval: (q) => (q.state.data?.some((po) => WAITING.includes(po.state)) ? 3_000 : false),
  });
  const open = (id: string) => {
    const q = new URLSearchParams(params);
    q.set('po', id);
    setParams(q);
  };
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-end gap-3 rounded-box border border-base-300 bg-base-100 p-3" data-list-part="top">
        <label className="flex flex-col gap-1 text-sm">
          {t.stateFilter}
          <select
            className="select select-sm w-36"
            value={state ?? 'all'}
            onChange={(e) => {
              const q = new URLSearchParams(params);
              if (e.target.value === 'all') q.delete('state');
              else q.set('state', e.target.value);
              setParams(q, { replace: true });
            }}
            data-testid="po-state-filter"
          >
            <option value="all">{t.all}</option>
            {STATES.map((s) => (
              <option key={s} value={s}>
                {t.states[s]}
              </option>
            ))}
          </select>
        </label>
        <button type="button" className="btn btn-sm btn-primary ml-auto" onClick={() => setAdding((v) => !v)} aria-expanded={adding}>
          {adding ? t.closeForm : t.newOrder}
        </button>
      </div>
      {adding && <NewPoForm cdcId={cdcId} onCreated={open} />}
      <QueryState state={toUiState(query, (rows) => rows.length === 0)} onRetry={() => void query.refetch()} emptyText={t.empty}>
        {(rows) => (
          <div className="overflow-x-auto rounded-box border border-base-300 bg-base-100">
            <table className="table table-sm" data-testid="po-table">
              <thead>
                <tr>
                  <th>{t.poId}</th>
                  <th>{t.supplier}</th>
                  <th className="text-right">{t.lineCount}</th>
                  <th className="text-right">{t.orderedQty}</th>
                  <th>{t.dueDate}</th>
                  <th>{t.issuedAt}</th>
                  <th>{t.state}</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((po) => (
                  <tr key={po.purchaseOrderId} className="cursor-pointer hover" onClick={() => open(po.purchaseOrderId)} data-testid="po-row">
                    <td className="font-mono text-xs">
                      <Link to={`${path(cdcId)}?tab=orders&po=${encodeURIComponent(po.purchaseOrderId)}`} className="link link-hover" onClick={(e) => e.stopPropagation()}>
                        {po.purchaseOrderId}
                      </Link>
                    </td>
                    <td>{po.supplierName}</td>
                    <td className="text-right tabular-nums">{t.lines(po.lines.length)}</td>
                    <td className="text-right tabular-nums">{messages.qty(sum(po.lines.map((l) => l.orderedQty)))}</td>
                    <td>{formatSeoulDate(po.dueDate)}</td>
                    <td>{formatSeoul(po.issuedAt)}</td>
                    <td>
                      <StateBadge state={po.state} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </QueryState>
    </div>
  );
}

// ---------------------------------------------------------------- 발주 등록

function useSuppliers(state?: 'ACTIVE') {
  const api = useApi();
  return useQuery({
    queryKey: ['suppliers', state ?? 'all'],
    queryFn: async () =>
      (
        await request(
          'GET',
          api.purchase.GET('/suppliers', {
            params: { path: {}, query: state ? { state } : {} },
          }),
        )
      ).items,
  });
}

function NewPoForm({ cdcId, onCreated }: { readonly cdcId: string; readonly onCreated: (id: string) => void }) {
  const f = t.form;
  const api = useApi();
  const queryClient = useQueryClient();
  const suppliers = useSuppliers('ACTIVE');
  const [supplierId, setSupplierId] = useState('');
  const [dueDate, setDueDate] = useState('');
  const [note, setNote] = useState('');
  const [lines, setLines] = useState<{ sku: string; qty: string }[]>([]);
  const supplier = suppliers.data?.find((s) => s.supplierId === supplierId);
  const create = useCommand(
    async (
      body: {
        supplierId: string;
        dueDate: string;
        note: string;
        lines: { sku: string; qty: number }[];
      },
      key,
    ) =>
      request(
        'POST',
        api.purchase.POST('/purchase-orders', {
          ...commandParams(key),
          body: { cdcId, ...body },
        }),
      ),
  );
  const pick = (id: string) => {
    const s = suppliers.data?.find((x) => x.supplierId === id);
    setSupplierId(id);
    setDueDate(s ? seoulDay(s.leadTimeDays) : '');
    setLines(s?.skus[0] ? [{ sku: s.skus[0], qty: '' }] : []);
  };
  const valid = !!supplier && !!dueDate && lines.length > 0 && lines.every((l) => l.sku && Number(l.qty) > 0);
  const submit = (e: FormEvent) => {
    e.preventDefault();
    if (!valid) return;
    void create
      .run({
        supplierId,
        dueDate,
        note: note.trim(),
        lines: lines.map((l) => ({ sku: l.sku, qty: Number(l.qty) })),
      })
      .then((phase) => {
        if (phase.kind === 'done') {
          void queryClient.invalidateQueries({
            queryKey: ['cdc', cdcId, 'purchase-orders'],
          });
          onCreated(phase.result.purchaseOrderId);
        }
      });
  };
  return (
    <form className="space-y-3 rounded-box border border-base-300 bg-base-100 p-4" onSubmit={submit} data-testid="po-form">
      <div className="flex flex-wrap items-end gap-3">
        <label className="flex flex-col gap-1 text-sm">
          {f.supplier}
          <select className="select select-sm w-56" value={supplierId} onChange={(e) => pick(e.target.value)} data-testid="po-supplier">
            <option value="">{f.pick}</option>
            {suppliers.data?.map((s) => (
              <option key={s.supplierId} value={s.supplierId}>
                {s.name}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-sm">
          {f.dueDate}
          <input type="date" className="input input-sm w-40" value={dueDate} onChange={(e) => setDueDate(e.target.value)} data-testid="po-due" />
        </label>
        {supplier && <span className="pb-1 text-xs text-base-content/60">{f.leadHint(supplier.leadTimeDays)}</span>}
        <label className="flex grow flex-col gap-1 text-sm">
          {f.note}
          <input className="input input-sm w-full" value={note} maxLength={300} onChange={(e) => setNote(e.target.value)} />
        </label>
      </div>
      {supplier && supplier.skus.length === 0 && <p className="text-sm text-warning">{f.noSkus}</p>}
      {supplier && supplier.skus.length > 0 && (
        <div className="space-y-2">
          {lines.map((l, i) => (
            <div key={i} className="flex flex-wrap items-end gap-2" data-testid="po-line">
              <label className="flex flex-col gap-1 text-sm">
                {f.sku}
                <select className="select select-sm w-48 font-mono" value={l.sku} onChange={(e) => setLines(lines.map((x, j) => (j === i ? { ...x, sku: e.target.value } : x)))}>
                  {supplier.skus.map((s) => (
                    <option key={s} value={s}>
                      {s}
                    </option>
                  ))}
                </select>
              </label>
              <label className="flex flex-col gap-1 text-sm">
                {f.qty}
                <input
                  type="number"
                  min={1}
                  className="input input-sm w-28"
                  value={l.qty}
                  onChange={(e) => setLines(lines.map((x, j) => (j === i ? { ...x, qty: e.target.value } : x)))}
                  data-testid="po-qty"
                />
              </label>
              {lines.length > 1 && (
                <button type="button" className="btn btn-ghost btn-sm" onClick={() => setLines(lines.filter((_, j) => j !== i))}>
                  {f.removeLine}
                </button>
              )}
            </div>
          ))}
          <button type="button" className="btn btn-sm" onClick={() => setLines([...lines, { sku: supplier.skus[0]!, qty: '' }])}>
            {f.addLine}
          </button>
        </div>
      )}
      <CommandFeedback command={create}>
        {(po: PurchaseOrder) => (
          <p role="status" className="alert alert-success text-sm">
            {t.created(po.purchaseOrderId)}
          </p>
        )}
      </CommandFeedback>
      <button type="submit" className="btn btn-sm btn-primary" disabled={!valid || create.busy} data-testid="po-submit">
        {f.submit}
      </button>
    </form>
  );
}

// ---------------------------------------------------------------- 발주 상세

function Steps({ po }: { readonly po: PurchaseOrder }) {
  const s = t.steps;
  const steps: {
    label: string;
    at: string | null;
    done: boolean;
    bad?: boolean;
  }[] = [
    { label: s.issued, at: po.issuedAt, done: true },
    {
      label: s.replied,
      at: po.repliedAt,
      done: !!po.repliedAt,
      bad: po.state === 'REJECTED',
    },
    { label: s.asn, at: po.asn?.shippedAt ?? null, done: !!po.asn },
    { label: s.received, at: po.receivedAt, done: po.state === 'RECEIVED' },
  ];
  return (
    <ul className="steps w-full text-xs" data-testid="po-steps">
      {steps.map((x) => (
        <li key={x.label} className={`step ${x.bad ? 'step-error' : x.done ? 'step-primary' : ''}`} data-content={x.bad ? '✕' : undefined}>
          <span className="flex flex-col">
            <span className="font-semibold">{x.label}</span>
            <span className="text-base-content/55">{x.at ? formatSeoul(x.at) : messages.none}</span>
          </span>
        </li>
      ))}
    </ul>
  );
}

function PoDetail({ cdcId, id }: { readonly cdcId: string; readonly id: string }) {
  const api = useApi();
  const [params, setParams] = useSearchParams();
  // 입고·취소가 끝나면 그 폼은 사라진다(상태가 바뀌어서) — 결과 문구는 상세에 남긴다
  const [notice, setNotice] = useState<string | null>(null);
  const query = useQuery({
    queryKey: ['cdc', cdcId, 'purchase-order', id],
    queryFn: () =>
      request(
        'GET',
        api.purchase.GET('/purchase-orders/{purchaseOrderId}', {
          params: { path: { purchaseOrderId: id } },
        }),
      ),
    refetchInterval: (q) => (q.state.data && WAITING.includes(q.state.data.state) ? 3_000 : false),
  });
  const back = () => {
    const q = new URLSearchParams(params);
    q.delete('po');
    setParams(q);
  };
  return (
    <div className="space-y-3">
      <button type="button" className="btn btn-ghost btn-sm" onClick={back}>
        ‹ {t.back}
      </button>
      <QueryState state={toUiState(query)} onRetry={() => void query.refetch()}>
        {(po) => (
          <div className="space-y-3" data-testid="po-detail">
            {notice && (
              <p role="status" className="alert alert-success text-sm">
                {notice}
              </p>
            )}
            <div className="space-y-4 rounded-box border border-base-300 bg-base-100 p-4">
              <div className="flex flex-wrap items-center gap-3">
                <h2 className="font-mono text-lg font-bold">{po.purchaseOrderId}</h2>
                <StateBadge state={po.state} />
              </div>
              <Steps po={po} />
              <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm md:grid-cols-4">
                <Field label={t.supplier} value={po.supplierName} />
                <Field label={t.dueDate} value={formatSeoulDate(po.dueDate)} />
                <Field label={t.issuedBy} value={po.issuedBy} />
                <Field label={t.note} value={po.note ?? messages.none} />
                <Field label={t.replyNote} value={po.replyNote ?? messages.none} />
                <Field label={t.asnId} value={po.asn?.asnId ?? messages.none} mono />
                <Field label={t.arrival} value={po.asn ? formatSeoul(po.asn.expectedArrivalAt) : messages.none} />
                <Field label={t.vehicle} value={po.asn?.vehicleNo ?? messages.none} />
              </dl>
              {po.state === 'ISSUED' && <p className="text-sm text-base-content/70">{t.waitingReply}</p>}
              {(po.state === 'CONFIRMED' || po.state === 'PARTIALLY_CONFIRMED') && <p className="text-sm text-base-content/70">{t.waitingAsn}</p>}
            </div>
            {po.state === 'ASN_RECEIVED' && po.asn ? <ReceiveForm key={po.version} cdcId={cdcId} po={po} onDone={setNotice} /> : <LinesTable po={po} />}
            {CANCELLABLE.includes(po.state) && <CancelForm cdcId={cdcId} po={po} onDone={setNotice} />}
          </div>
        )}
      </QueryState>
    </div>
  );
}

function Field({ label, value, mono = false }: { readonly label: string; readonly value: string; readonly mono?: boolean }) {
  return (
    <div>
      <dt className="text-xs text-base-content/55">{label}</dt>
      <dd className={mono ? 'font-mono text-xs' : ''}>{value}</dd>
    </div>
  );
}

const q = (n: number | null) => (n === null ? messages.none : messages.qty(n));

function LinesTable({ po }: { readonly po: PurchaseOrder }) {
  return (
    <div className="overflow-x-auto rounded-box border border-base-300 bg-base-100">
      <table className="table table-sm" data-testid="po-lines">
        <thead>
          <tr>
            <th>{t.sku}</th>
            <th className="text-right">{t.orderedQty}</th>
            <th className="text-right">{t.confirmedQty}</th>
            <th className="text-right">{t.shippedQty}</th>
            <th>{t.lot}</th>
            <th>{t.expiresAt}</th>
            <th className="text-right">{t.receivedQty}</th>
            <th className="text-right">{t.rejectedQty}</th>
            <th className="text-right">{t.diff}</th>
          </tr>
        </thead>
        <tbody>
          {po.lines.map((l) => {
            const diff = l.receivedQty === null ? null : l.receivedQty - l.orderedQty;
            return (
              <tr key={l.sku} data-testid="po-line-row">
                <td>
                  <SkuName sku={l.sku} />
                </td>
                <td className="text-right tabular-nums">{q(l.orderedQty)}</td>
                <td className="text-right tabular-nums">{q(l.confirmedQty)}</td>
                <td className="text-right tabular-nums">{q(l.shippedQty)}</td>
                <td className="font-mono text-xs">{l.lot ?? messages.none}</td>
                <td>{l.expiresAt ? formatSeoulDate(l.expiresAt) : messages.none}</td>
                <td className="text-right tabular-nums">{q(l.receivedQty)}</td>
                <td className="text-right tabular-nums">{q(l.rejectedQty)}</td>
                <td className={`text-right tabular-nums ${diff !== null && diff < 0 ? 'text-error' : ''}`}>{diff === null ? messages.none : diff === 0 ? '0' : messages.qty(diff)}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function ReceiveForm({ cdcId, po, onDone }: { readonly cdcId: string; readonly po: PurchaseOrder; readonly onDone: (msg: string) => void }) {
  const api = useApi();
  const queryClient = useQueryClient();
  const [qty, setQty] = useState(() => Object.fromEntries(po.lines.map((l) => [l.sku, { received: String(l.shippedQty ?? 0), rejected: '0' }])));
  const receive = useCommand(async (lines: { sku: string; receivedQty: number; rejectedQty: number }[], key) =>
    request(
      'POST',
      api.purchase.POST('/asn/{asnId}/receipts', {
        ...commandParams(key, { path: { asnId: po.asn!.asnId } }),
        body: { lines },
      }),
    ),
  );
  const parsed = po.lines.map((l) => ({
    sku: l.sku,
    receivedQty: Number(qty[l.sku]?.received),
    rejectedQty: Number(qty[l.sku]?.rejected),
  }));
  const valid = parsed.every(
    (p, i) => Number.isInteger(p.receivedQty) && Number.isInteger(p.rejectedQty) && p.receivedQty >= 0 && p.rejectedQty >= 0 && p.receivedQty + p.rejectedQty <= (po.lines[i]!.shippedQty ?? 0),
  );
  const set = (sku: string, k: 'received' | 'rejected', v: string) => setQty({ ...qty, [sku]: { ...qty[sku]!, [k]: v } });
  return (
    <form
      className="space-y-3 rounded-box border border-info/40 bg-base-100 p-4"
      onSubmit={(e) => {
        e.preventDefault();
        if (!valid) return;
        void receive.run(parsed).then((phase) => {
          if (phase.kind === 'done') {
            onDone(t.received(phase.result.purchaseOrderId));
            void queryClient.invalidateQueries({ queryKey: ['cdc', cdcId] });
          }
        });
      }}
      data-testid="po-receive"
    >
      <h3 className="font-semibold">{t.receiveTitle}</h3>
      <div className="overflow-x-auto">
        <table className="table table-sm">
          <thead>
            <tr>
              <th>{t.sku}</th>
              <th className="text-right">{t.orderedQty}</th>
              <th className="text-right">{t.shippedQty}</th>
              <th>{t.lot}</th>
              <th>{t.expiresAt}</th>
              <th>{t.receivedQty}</th>
              <th>{t.rejectedQty}</th>
            </tr>
          </thead>
          <tbody>
            {po.lines.map((l) => (
              <tr key={l.sku} data-testid="po-receive-row">
                <td>
                  <SkuName sku={l.sku} />
                </td>
                <td className="text-right tabular-nums">{q(l.orderedQty)}</td>
                <td className="text-right tabular-nums">{q(l.shippedQty)}</td>
                <td className="font-mono text-xs">{l.lot ?? messages.none}</td>
                <td>{l.expiresAt ? formatSeoulDate(l.expiresAt) : messages.none}</td>
                <td>
                  <input
                    type="number"
                    min={0}
                    className="input input-sm w-24"
                    aria-label={`${l.sku} ${t.receivedQty}`}
                    value={qty[l.sku]?.received ?? ''}
                    onChange={(e) => set(l.sku, 'received', e.target.value)}
                  />
                </td>
                <td>
                  <input
                    type="number"
                    min={0}
                    className="input input-sm w-24"
                    aria-label={`${l.sku} ${t.rejectedQty}`}
                    value={qty[l.sku]?.rejected ?? ''}
                    onChange={(e) => set(l.sku, 'rejected', e.target.value)}
                  />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <CommandFeedback command={receive}>{() => null}</CommandFeedback>
      <button type="submit" className="btn btn-sm btn-primary" disabled={!valid || receive.busy} data-testid="po-receive-go">
        {t.receive}
      </button>
    </form>
  );
}

function CancelForm({ cdcId, po, onDone }: { readonly cdcId: string; readonly po: PurchaseOrder; readonly onDone: (msg: string) => void }) {
  const api = useApi();
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState('');
  const cancel = useCommand(async (r: string, key) =>
    request(
      'POST',
      api.purchase.POST('/purchase-orders/{purchaseOrderId}/cancellations', {
        ...commandParams(key, {
          path: { purchaseOrderId: po.purchaseOrderId },
        }),
        body: { reason: r },
      }),
    ),
  );
  return (
    <div className="space-y-2">
      <CommandFeedback command={cancel}>{() => null}</CommandFeedback>
      {!open ? (
        <button type="button" className="btn btn-sm btn-outline btn-error" onClick={() => setOpen(true)} data-testid="po-cancel-open">
          {t.cancel}
        </button>
      ) : (
        <form
          className="flex flex-wrap items-end gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            if (!reason.trim()) return;
            void cancel.run(reason.trim()).then((phase) => {
              if (phase.kind === 'done') {
                onDone(t.cancelled(phase.result.purchaseOrderId));
                void queryClient.invalidateQueries({
                  queryKey: ['cdc', cdcId],
                });
              }
            });
          }}
        >
          <label className="flex flex-col gap-1 text-sm">
            {t.cancelReason}
            <input className="input input-sm w-72" value={reason} maxLength={300} onChange={(e) => setReason(e.target.value)} data-testid="po-cancel-reason" />
          </label>
          <button type="submit" className="btn btn-sm btn-error" disabled={!reason.trim() || cancel.busy} data-testid="po-cancel-go">
            {t.cancel}
          </button>
        </form>
      )}
    </div>
  );
}

// ---------------------------------------------------------------- 공급사 관리

function SuppliersTab() {
  const s = t.sup;
  const query = useSuppliers();
  const [adding, setAdding] = useState(false);
  return (
    <div className="space-y-3">
      <div className="flex justify-end">
        <button type="button" className="btn btn-sm btn-primary" onClick={() => setAdding((v) => !v)} aria-expanded={adding}>
          {adding ? t.closeForm : s.add}
        </button>
      </div>
      {adding && <SupplierForm onDone={() => setAdding(false)} />}
      <QueryState state={toUiState(query, (rows) => rows.length === 0)} onRetry={() => void query.refetch()} emptyText={s.empty}>
        {(rows) => (
          <div className="overflow-x-auto rounded-box border border-base-300 bg-base-100">
            <table className="table table-sm" data-testid="supplier-table">
              <thead>
                <tr>
                  <th>{s.name}</th>
                  <th>{s.businessNo}</th>
                  <th>{s.contact}</th>
                  <th>{s.phone}</th>
                  <th className="text-right">{s.leadTime}</th>
                  <th>{s.skus}</th>
                  <th>{s.replyMode}</th>
                  <th>{s.state}</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((x: Supplier) => (
                  <tr key={x.supplierId} data-testid="supplier-row">
                    <td>
                      <span className="font-medium">{x.name}</span>
                      <span className="block font-mono text-[11px] text-base-content/55">{x.supplierId}</span>
                    </td>
                    <td className="font-mono text-xs">{x.businessNo ?? messages.none}</td>
                    <td>{x.contactName ?? messages.none}</td>
                    <td className="font-mono text-xs">{x.phone ?? messages.none}</td>
                    <td className="text-right tabular-nums">{s.days(x.leadTimeDays)}</td>
                    <td>
                      <div className="flex flex-col gap-1">{x.skus.length === 0 ? messages.none : x.skus.map((sku) => <SkuName key={sku} sku={sku} />)}</div>
                    </td>
                    <td>{s.replyModes[x.replyMode] ?? x.replyMode}</td>
                    <td>{s.states[x.state] ?? x.state}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </QueryState>
    </div>
  );
}

function SupplierForm({ onDone }: { readonly onDone: () => void }) {
  const s = t.sup;
  const api = useApi();
  const queryClient = useQueryClient();
  const [form, setForm] = useState({
    name: '',
    businessNo: '',
    contactName: '',
    phone: '',
    leadTimeDays: '2',
    skus: '',
    replyMode: 'FULL' as ReplyMode,
  });
  const add = useCommand(async (body: typeof form, key) =>
    request(
      'POST',
      api.purchase.POST('/suppliers', {
        ...commandParams(key),
        body: {
          name: body.name.trim(),
          ...(body.businessNo.trim() ? { businessNo: body.businessNo.trim() } : {}),
          ...(body.contactName.trim() ? { contactName: body.contactName.trim() } : {}),
          ...(body.phone.trim() ? { phone: body.phone.trim() } : {}),
          leadTimeDays: Number(body.leadTimeDays),
          skus: body.skus
            .split(',')
            .map((x) => x.trim())
            .filter(Boolean),
          replyMode: body.replyMode,
        },
      }),
    ),
  );
  const valid = !!form.name.trim() && Number.isInteger(Number(form.leadTimeDays)) && Number(form.leadTimeDays) >= 0;
  const input = (k: 'name' | 'businessNo' | 'contactName' | 'phone', label: string, w = 'w-44') => (
    <label className="flex flex-col gap-1 text-sm">
      {label}
      <input className={`input input-sm ${w}`} value={form[k]} onChange={(e) => setForm({ ...form, [k]: e.target.value })} data-testid={`sup-${k}`} />
    </label>
  );
  return (
    <form
      className="space-y-3 rounded-box border border-base-300 bg-base-100 p-4"
      onSubmit={(e) => {
        e.preventDefault();
        if (!valid) return;
        void add.run(form).then((phase) => {
          if (phase.kind === 'done') {
            void queryClient.invalidateQueries({ queryKey: ['suppliers'] });
            onDone();
          }
        });
      }}
      data-testid="supplier-form"
    >
      <div className="flex flex-wrap items-end gap-3">
        {input('name', s.name, 'w-56')}
        {input('businessNo', s.businessNo)}
        {input('contactName', s.contact, 'w-32')}
        {input('phone', s.phone)}
        <label className="flex flex-col gap-1 text-sm">
          {s.leadTime}
          <input type="number" min={0} className="input input-sm w-24" value={form.leadTimeDays} onChange={(e) => setForm({ ...form, leadTimeDays: e.target.value })} />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          {s.replyMode}
          <select className="select select-sm w-40" value={form.replyMode} onChange={(e) => setForm({ ...form, replyMode: e.target.value as ReplyMode })} data-testid="sup-reply">
            {REPLY_MODES.map((m) => (
              <option key={m} value={m}>
                {s.replyModes[m]}
              </option>
            ))}
          </select>
        </label>
      </div>
      <label className="flex flex-col gap-1 text-sm">
        {s.skus}
        <input className="input input-sm w-full font-mono" value={form.skus} placeholder={s.skusHint} onChange={(e) => setForm({ ...form, skus: e.target.value })} data-testid="sup-skus" />
      </label>
      <CommandFeedback command={add}>
        {(x: Supplier) => (
          <p role="status" className="alert alert-success text-sm">
            {s.created(x.name)}
          </p>
        )}
      </CommandFeedback>
      <button type="submit" className="btn btn-sm btn-primary" disabled={!valid || add.busy} data-testid="sup-submit">
        {s.submit}
      </button>
    </form>
  );
}
