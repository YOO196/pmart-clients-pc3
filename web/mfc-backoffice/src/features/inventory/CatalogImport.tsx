// 재고 > 상품 취급 > 본사 상품 불러오기(2026-11-25 사용자 "백오피스에 등록된 상품일람 열람하고 일부 품목을 이 센터에서 판매하겠다고 올릴 수 있게").
// - 본사 상품 목록: product-service `GET /products?q=&saleState=`(0.5.0 — q = 관리용 명칭 부분 일치 또는 SKU·바코드 완전 일치, 커서).
// - 이 센터 취급 여부: mfc-inventory `GET /mfcs/{mfcId}/sku-handlings?enabled=true`(켜진 SKU 전부 — 항목의 productId 로 상품에 잇는다).
// - 고른 상품 → 각 상품의 SKU(`GET /products/{id}` skus, 단종 SKU 빼고) → `POST /mfcs/{mfcId}/sku-handling-batches`(최대 500행, 전부 또는 전무) 켜기.
//   이미 켜진 SKU 는 서버가 그대로 둔다(changedCount). 그 센터 MFC_SUPERVISOR·MD 만(서버 판정 — 아니면 403).
import { useInfiniteQuery, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';

import { request } from '@pmart/web-core';
import { CommandFeedback, QueryState, toUiState, useCommand } from '@pmart/web-ui';
import { commandParams } from '../../api/command';
import { useApi } from '../../app/ApiContext';
import { messages } from '../../shared/messages';
import { ProductThumb, useProductCards, useProductView, ViewToggle } from '../../shared/productCards';
import { ResultBar, SearchPanel, SearchRow } from '../../shared/simList';

const m = messages.inventory.catalog;
const SALE_STATES = ['ON_SALE', 'TEMPORARILY_SOLD_OUT', 'SALE_STOPPED'] as const;
const BATCH_MAX = 500;
const isSale = (v: string): v is (typeof SALE_STATES)[number] => (SALE_STATES as readonly string[]).includes(v);

/** 이 센터에서 켜진 SKU 를 상품별로 — productId → 켜진 SKU 수 */
function useHandlingOn(mfcId: string) {
  const api = useApi();
  return useQuery({
    queryKey: ['handlings', mfcId, 'on-by-product'],
    queryFn: async () => {
      const on = new Map<string, number>();
      let cursor: string | undefined;
      let pages = 0;
      do {
        const page = await request('GET', api.inventory.GET('/mfcs/{mfcId}/sku-handlings', { params: { path: { mfcId }, query: { enabled: true, size: 200, ...(cursor ? { cursor } : {}) } } }));
        for (const h of page.items ?? []) if (h.productId && h.handlingEnabled) on.set(h.productId, (on.get(h.productId) ?? 0) + 1);
        cursor = page.page?.nextCursor ?? undefined;
        pages += 1;
      } while (cursor && pages < 50);
      return on;
    },
  });
}

export function CatalogImport({ mfcId, onClose }: { readonly mfcId: string; readonly onClose: () => void }) {
  const api = useApi();
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState('');
  const [q, setQ] = useState('');
  const [sale, setSale] = useState<string>('ON_SALE');
  const [picked, setPicked] = useState<ReadonlySet<string>>(new Set());
  const products = useInfiniteQuery({
    queryKey: ['catalog', q, sale],
    initialPageParam: undefined as string | undefined,
    queryFn: ({ pageParam }) =>
      request(
        'GET',
        api.product.GET('/products', {
          params: { query: { size: 50, ...(q ? { q } : {}), ...(isSale(sale) ? { saleState: sale } : {}), ...(pageParam ? { cursor: pageParam } : {}) } },
        }),
      ),
    getNextPageParam: (last) => last.page?.nextCursor ?? undefined,
  });
  const on = useHandlingOn(mfcId);
  const rows = (products.data?.pages ?? []).flatMap((p) => p.items ?? []);
  // 상품 사진·고객용 이름(product-content), 목록/카드 보기 — 상품 관리 목록과 같은 ?view
  const cards = useProductCards(rows.map((p) => p.productId));
  const [view, setView] = useProductView();
  const toggle = (id: string) =>
    setPicked((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  const importCmd = useCommand(async (ids: readonly string[], key) => {
    // 고른 상품의 SKU — 판매 중지(SALE_STOPPED — 취급 쪽에서는 단종) SKU 는 서버가 거절(전부 또는 전무)하므로 미리 뺀다
    const details = await Promise.all(ids.map((productId) => request('GET', api.product.GET('/products/{productId}', { params: { path: { productId } } }))));
    const skus = [...new Set(details.flatMap((d) => (d.skus ?? []).filter((s) => s.saleState !== 'SALE_STOPPED').map((s) => s.sku)))].slice(0, BATCH_MAX);
    if (skus.length === 0) return { changed: 0, skus: 0 };
    const r = await request(
      'POST',
      api.inventory.POST('/mfcs/{mfcId}/sku-handling-batches', { ...commandParams(key, { path: { mfcId } }), body: { reason: m.reason, items: skus.map((sku) => ({ sku, enabled: true })) } }),
    );
    setPicked(new Set());
    await queryClient.invalidateQueries({ queryKey: ['handlings', mfcId] });
    await queryClient.invalidateQueries({ queryKey: ['handlings-new-count', mfcId] });
    return { changed: r.changedCount ?? 0, skus: skus.length };
  });
  return (
    <section className="space-y-3 rounded-box border border-base-300 bg-base-100 p-4" data-testid="catalog-import">
      <div className="flex items-center justify-between gap-2">
        <h2 className="font-bold">{m.title}</h2>
        <button type="button" className="btn btn-sm" onClick={onClose}>
          {m.close}
        </button>
      </div>
      <SearchPanel
        label={m.search}
        submitLabel={messages.inventory.lookup}
        onSubmit={(e) => {
          e.preventDefault();
          setQ(draft.trim());
        }}
        onReset={() => {
          setDraft('');
          setQ('');
          setSale('ON_SALE');
        }}
        summary={[[m.saleState, sale ? (m.saleName[sale] ?? sale) : '', sale ? () => setSale('') : undefined]]}
        search={<input type="search" className="input input-sm w-60" maxLength={50} value={draft} placeholder={m.placeholder} aria-label={m.placeholder} onChange={(e) => setDraft(e.target.value)} />}
      >
        <SearchRow label={m.saleState}>
          <select className="select select-sm w-36" aria-label={m.saleState} value={sale} onChange={(e) => setSale(e.target.value)}>
            <option value="">{m.allSale}</option>
            {SALE_STATES.map((s) => (
              <option key={s} value={s}>
                {m.saleName[s]}
              </option>
            ))}
          </select>
        </SearchRow>
      </SearchPanel>
      <div className="flex justify-end">
        <ViewToggle view={view} onChange={setView} />
      </div>
      <QueryState state={toUiState(products, (d) => d.pages.every((p) => (p.items ?? []).length === 0))} onRetry={() => void products.refetch()} emptyText={m.empty}>
        {() => (
          <>
            {view === 'card' ? (
              <ul className="grid grid-cols-[repeat(auto-fill,minmax(11rem,1fr))] gap-3" data-testid="catalog-cards">
                {rows.map((p) => {
                  const id = p.productId ?? '';
                  const discontinued = p.saleState === 'SALE_STOPPED';
                  const here = on.data?.get(id) ?? 0;
                  const info = cards.data?.get(id);
                  return (
                    <li key={id} data-testid="catalog-card">
                      <label className={`flex h-full cursor-pointer flex-col gap-2 rounded-box border p-3 ${picked.has(id) ? 'border-primary' : 'border-base-300'} ${discontinued ? 'cursor-not-allowed opacity-60' : ''}`}>
                        <span className="relative">
                          <ProductThumb info={info} fallback={p.internalName ?? id} size="card" />
                          <input type="checkbox" className="checkbox checkbox-sm absolute top-2 left-2 bg-base-100" aria-label={m.pickLabel(p.internalName ?? id)} disabled={discontinued} checked={picked.has(id)} onChange={() => toggle(id)} />
                        </span>
                        <span className="line-clamp-2 font-semibold" title={p.internalName ?? id}>
                          {p.internalName}
                        </span>
                        <span className="mt-auto flex flex-wrap items-center gap-1 text-xs">
                          <span className={`badge badge-sm ${discontinued ? 'badge-error' : p.saleState === 'TEMPORARILY_SOLD_OUT' ? 'badge-warning' : 'badge-ghost'}`}>{m.saleName[p.saleState ?? ''] ?? p.saleState}</span>
                          {on.data && (here > 0 ? <span className="badge badge-sm badge-success">{m.here}</span> : <span className="badge badge-sm badge-ghost">{m.notHere}</span>)}
                        </span>
                      </label>
                    </li>
                  );
                })}
              </ul>
            ) : (
            <div className="pm-list-box">
              <ResultBar count={rows.length} more={products.hasNextPage} />
              <div className="overflow-x-auto" data-list-part="table">
                <table className="table table-sm">
                  <thead>
                    <tr>
                      <th className="w-12">{m.col.pick}</th>
                      <th>{m.col.name}</th>
                      <th>{m.col.sale}</th>
                      <th>{m.col.here}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((p) => {
                      const id = p.productId ?? '';
                      const discontinued = p.saleState === 'SALE_STOPPED';
                      const here = on.data?.get(id) ?? 0;
                      return (
                        <tr key={id} data-testid="catalog-row">
                          <td>
                            <input type="checkbox" className="checkbox checkbox-sm" aria-label={m.pickLabel(p.internalName ?? id)} disabled={discontinued} checked={picked.has(id)} onChange={() => toggle(id)} />
                          </td>
                          <td>
                            <span className="flex items-center gap-2">
                              <ProductThumb info={cards.data?.get(id)} fallback={p.internalName ?? id} size="row" />
                              {p.internalName}
                            </span>
                          </td>
                          <td>
                            <span className={`badge badge-sm ${discontinued ? 'badge-error' : p.saleState === 'TEMPORARILY_SOLD_OUT' ? 'badge-warning' : 'badge-ghost'}`}>{m.saleName[p.saleState ?? ''] ?? p.saleState}</span>
                          </td>
                          <td>{on.isError ? m.hereFailed : !on.data ? '…' : here > 0 ? <span className="badge badge-sm badge-success">{m.here}</span> : <span className="badge badge-sm badge-ghost">{m.notHere}</span>}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
            )}
            {products.hasNextPage && (
              <button type="button" className="btn btn-sm" disabled={products.isFetchingNextPage} onClick={() => void products.fetchNextPage()}>
                {m.more}
              </button>
            )}
          </>
        )}
      </QueryState>
      <div className="flex flex-wrap items-center gap-3">
        <button
          type="button"
          className="btn btn-sm btn-primary"
          disabled={picked.size === 0 || importCmd.busy}
          onClick={() => {
            if (importCmd.phase.kind === 'rejected' || importCmd.phase.kind === 'done') importCmd.reset();
            void importCmd.run([...picked]);
          }}
        >
          {m.submit(picked.size)}
        </button>
        <CommandFeedback command={importCmd}>
          {(r) => (
            <p role="status" className="text-sm text-success">
              {r.skus === 0 ? m.noSkus : m.done(r.changed, r.skus)}
            </p>
          )}
        </CommandFeedback>
      </div>
    </section>
  );
}
