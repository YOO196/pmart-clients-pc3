// 상품 발주 — [발주 | 공급사 관리] 탭(?tab=). 사용자 2026-11-26 "Cdc에 상품 발주 탭 있어야해. 하위로 공급사 관리 탭이",
// "서비스를 새로 만들 게 아니라 페이지만 그렇게 만들고 구현 자체는 발주 내용에 따라 cdc 재고 적재량 달라지도록 단순하게".
// 흐름: 발주(공급사는 가짜라 바로 공급 확정) → 입고 → 발주 수량만큼 재고관리에 더한다. 입고 전엔 취소.
// 목 전용(mocks/purchaseHandlers) — 실서버(local·lan)에서는 부르지 않고 "준비 중"을 보인다.
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useState, type FormEvent } from 'react';
import { Link, useSearchParams } from 'react-router';

import { request } from '@pmart/web-core';
import { CommandFeedback, formatSeoul, QueryState, toUiState, useCommand } from '@pmart/web-ui';
import { commandParams } from '../../api/command';
import type { PoState, PurchaseOrder, Supplier } from '../../api/proposed/purchase';
import { useApi } from '../../app/ApiContext';
import { allMenus, centerPath } from '../../app/nav';
import { env } from '../../env';
import { messages } from '../../shared/messages';
import { SkuName } from '../../shared/SkuName';
import { PreparingPage } from '../menus/PreparingPage';

const t = messages.purchase;
type Tab = keyof typeof t.tabs;
const TABS = Object.keys(t.tabs) as Tab[];
const STATES: readonly PoState[] = ['ORDERED', 'RECEIVED', 'CANCELLED'];

const path = (cdcId: string) => centerPath(cdcId, 'purchase');
const total = (po: PurchaseOrder) => po.lines.reduce((a, l) => a + l.qty, 0);

function StateBadge({ state }: { readonly state: PoState }) {
  const tone = state === 'RECEIVED' ? 'badge-success' : state === 'CANCELLED' ? 'badge-ghost' : 'badge-outline';
  return (
    <span className={`badge badge-sm whitespace-nowrap ${tone}`} data-testid="po-state">
      {t.states[state] ?? state}
    </span>
  );
}

/** `/c/:cdcId/purchase` */
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
    queryFn: async () => (await request('GET', api.purchase.GET('/purchase-orders', { params: { path: {}, query: { cdcId, ...(state ? { state } : {}) } } }))).items,
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
                  <th>{t.orderedAt}</th>
                  <th>{t.state}</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((po) => (
                  <tr key={po.purchaseOrderId} className="cursor-pointer hover" onClick={() => open(po.purchaseOrderId)} data-testid="po-row">
                    <td className="font-mono text-xs">{po.purchaseOrderId}</td>
                    <td>{po.supplierName}</td>
                    <td className="text-right tabular-nums">{t.lines(po.lines.length)}</td>
                    <td className="text-right tabular-nums">{messages.qty(total(po))}</td>
                    <td>{formatSeoul(po.orderedAt)}</td>
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

function useSuppliers() {
  const api = useApi();
  return useQuery({
    queryKey: ['suppliers'],
    queryFn: async () => (await request('GET', api.purchase.GET('/suppliers', { params: { path: {} } }))).items,
  });
}

function NewPoForm({ cdcId, onCreated }: { readonly cdcId: string; readonly onCreated: (id: string) => void }) {
  const f = t.form;
  const api = useApi();
  const queryClient = useQueryClient();
  const suppliers = useSuppliers();
  const [supplierId, setSupplierId] = useState('');
  const [note, setNote] = useState('');
  const [lines, setLines] = useState<{ sku: string; qty: string }[]>([]);
  const supplier = suppliers.data?.find((s) => s.supplierId === supplierId);
  const create = useCommand(async (body: { supplierId: string; note: string; lines: { sku: string; qty: number }[] }, key) =>
    request('POST', api.purchase.POST('/purchase-orders', { ...commandParams(key), body: { cdcId, ...body } })),
  );
  const pick = (id: string) => {
    const s = suppliers.data?.find((x) => x.supplierId === id);
    setSupplierId(id);
    setLines(s?.skus[0] ? [{ sku: s.skus[0], qty: '' }] : []);
  };
  const valid = !!supplier && lines.length > 0 && lines.every((l) => l.sku && Number(l.qty) > 0);
  const submit = (e: FormEvent) => {
    e.preventDefault();
    if (!valid) return;
    void create.run({ supplierId, note: note.trim(), lines: lines.map((l) => ({ sku: l.sku, qty: Number(l.qty) })) }).then((phase) => {
      if (phase.kind === 'done') {
        void queryClient.invalidateQueries({ queryKey: ['cdc', cdcId, 'purchase-orders'] });
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
      <CommandFeedback command={create}>{() => null}</CommandFeedback>
      <button type="submit" className="btn btn-sm btn-primary" disabled={!valid || create.busy} data-testid="po-submit">
        {f.submit}
      </button>
    </form>
  );
}

// ---------------------------------------------------------------- 발주 상세(입고·취소)

function PoDetail({ cdcId, id }: { readonly cdcId: string; readonly id: string }) {
  const api = useApi();
  const queryClient = useQueryClient();
  const [params, setParams] = useSearchParams();
  const [notice, setNotice] = useState<string | null>(null);
  const query = useQuery({
    queryKey: ['cdc', cdcId, 'purchase-order', id],
    queryFn: () => request('GET', api.purchase.GET('/purchase-orders/{purchaseOrderId}', { params: { path: { purchaseOrderId: id } } })),
  });
  const receive = useCommand(async (_: null, key) =>
    request('POST', api.purchase.POST('/purchase-orders/{purchaseOrderId}/receipts', { ...commandParams(key, { path: { purchaseOrderId: id } }), body: {} })),
  );
  const cancel = useCommand(async (_: null, key) =>
    request('POST', api.purchase.POST('/purchase-orders/{purchaseOrderId}/cancellations', { ...commandParams(key, { path: { purchaseOrderId: id } }), body: {} })),
  );
  const run = (cmd: typeof receive, msg: (id: string) => string) =>
    void cmd.run(null).then((phase) => {
      if (phase.kind === 'done') {
        setNotice(msg(phase.result.purchaseOrderId));
        void queryClient.invalidateQueries({ queryKey: ['cdc', cdcId] });
      }
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
              <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm md:grid-cols-5">
                <Field label={t.supplier} value={po.supplierName} />
                <Field label={t.orderedAt} value={formatSeoul(po.orderedAt)} />
                <Field label={t.orderedBy} value={po.orderedBy} />
                <Field label={t.receivedAt} value={po.receivedAt ? formatSeoul(po.receivedAt) : messages.none} />
                <Field label={t.note} value={po.note ?? messages.none} />
              </dl>
            </div>
            <div className="overflow-x-auto rounded-box border border-base-300 bg-base-100">
              <table className="table table-sm" data-testid="po-lines">
                <thead>
                  <tr>
                    <th>{t.sku}</th>
                    <th className="text-right">{t.orderedQty}</th>
                    <th>{t.lot}</th>
                  </tr>
                </thead>
                <tbody>
                  {po.lines.map((l) => (
                    <tr key={l.sku} data-testid="po-line-row">
                      <td>
                        <SkuName sku={l.sku} />
                      </td>
                      <td className="text-right tabular-nums">{messages.qty(l.qty)}</td>
                      <td className="font-mono text-xs">{l.lot ?? messages.none}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <CommandFeedback command={receive}>{() => null}</CommandFeedback>
            <CommandFeedback command={cancel}>{() => null}</CommandFeedback>
            {po.state === 'ORDERED' && (
              <div className="flex gap-2">
                <button type="button" className="btn btn-sm btn-primary" disabled={receive.busy || cancel.busy} onClick={() => run(receive, t.received)} data-testid="po-receive">
                  {t.receive}
                </button>
                <button type="button" className="btn btn-sm btn-outline btn-error" disabled={receive.busy || cancel.busy} onClick={() => run(cancel, t.cancelled)} data-testid="po-cancel">
                  {t.cancel}
                </button>
              </div>
            )}
          </div>
        )}
      </QueryState>
    </div>
  );
}

function Field({ label, value }: { readonly label: string; readonly value: string }) {
  return (
    <div>
      <dt className="text-xs text-base-content/55">{label}</dt>
      <dd>{value}</dd>
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
                  <th>{s.contact}</th>
                  <th>{s.phone}</th>
                  <th>{s.skus}</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((x: Supplier) => (
                  <tr key={x.supplierId} data-testid="supplier-row">
                    <td>
                      <span className="font-medium">{x.name}</span>
                      <span className="block font-mono text-[11px] text-base-content/55">{x.supplierId}</span>
                    </td>
                    <td>{x.contactName ?? messages.none}</td>
                    <td className="font-mono text-xs">{x.phone ?? messages.none}</td>
                    <td>
                      <div className="flex flex-col gap-1">{x.skus.length === 0 ? messages.none : x.skus.map((sku) => <SkuName key={sku} sku={sku} />)}</div>
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

function SupplierForm({ onDone }: { readonly onDone: () => void }) {
  const s = t.sup;
  const api = useApi();
  const queryClient = useQueryClient();
  const [form, setForm] = useState({ name: '', contactName: '', phone: '', skus: '' });
  const add = useCommand(async (body: typeof form, key) =>
    request(
      'POST',
      api.purchase.POST('/suppliers', {
        ...commandParams(key),
        body: {
          name: body.name.trim(),
          ...(body.contactName.trim() ? { contactName: body.contactName.trim() } : {}),
          ...(body.phone.trim() ? { phone: body.phone.trim() } : {}),
          skus: body.skus
            .split(',')
            .map((x) => x.trim())
            .filter(Boolean),
        },
      }),
    ),
  );
  const valid = !!form.name.trim();
  const input = (k: 'name' | 'contactName' | 'phone', label: string, w = 'w-44') => (
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
        {input('contactName', s.contact, 'w-32')}
        {input('phone', s.phone)}
      </div>
      <label className="flex flex-col gap-1 text-sm">
        {s.skus}
        <input className="input input-sm w-full font-mono" value={form.skus} placeholder={s.skusHint} onChange={(e) => setForm({ ...form, skus: e.target.value })} data-testid="sup-skus" />
      </label>
      <CommandFeedback command={add}>{() => null}</CommandFeedback>
      <button type="submit" className="btn btn-sm btn-primary" disabled={!valid || add.busy} data-testid="sup-submit">
        {s.submit}
      </button>
    </form>
  );
}
