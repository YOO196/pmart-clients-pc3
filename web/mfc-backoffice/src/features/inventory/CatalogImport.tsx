// 상품 관리 기본 목록 = 본사 상품 연동(2026-11-26 사용자 "본사상품 불러오기 말고 기본적으로 뜨는 상품들이 본사 취급품 연동이면 좋겠어",
// 같은 날 "일괄 고를 수 있는 기능 … 필터링되어 나온 결과에 한정(없으면 전체)"). 처음엔 본사 상품 불러오기 창(2026-11-25).
// - 본사 상품 목록: product-service `GET /products?q=&saleState=`(q = 관리용 명칭 부분 일치 또는 SKU·바코드 완전 일치, 커서).
// - 이 센터 취급: mfc-inventory `GET /mfcs/{mfcId}/sku-handlings`(SKU 투영 = 본사 상품 전체, 항목의 productId 로 상품에 잇는다) — 상품별 SKU·켜짐.
// - 켜기·끄기(줄 스위치·고른 것 일괄): `POST /mfcs/{mfcId}/sku-handling-batches`(한 번에 최대 500행, 전부 또는 전무). 켤 때는 켤 수 없는 SKU(비활성·본사 단종)를 뺀다.
//   500행이 넘으면 나눠 보낸다(조각마다 키 = 행위 키 + 조각 번호 — 다시 보내도 같은 키). 결과는 서버 changedCount 로만. 그 센터 MFC_SUPERVISOR·MD 만(서버 판정).
// - 모두 고르기 = 지금 찾기 조건(q·판매 상태)에 맞는 상품 전부(안 읽은 쪽까지 읽어서). 조건을 바꾸면 고른 것은 풀린다.
import { useInfiniteQuery, useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';

import { type IdempotencyKey, request } from '@pmart/web-core';
import { CommandFeedback, QueryState, toUiState, useCommand } from '@pmart/web-ui';
import { commandParams, IdempotencyKey as Key } from '../../api/command';
import { useApi } from '../../app/ApiContext';
import { messages } from '../../shared/messages';
import { ProductThumb, useProductCards, useProductView, ViewToggle } from '../../shared/productCards';
import { SearchPanel, SearchRow } from '../../shared/simList';

const m = messages.inventory.catalog;
const SALE_STATES = ['ON_SALE', 'TEMPORARILY_SOLD_OUT', 'SALE_STOPPED'] as const;
const BATCH_MAX = 500;
const PAGE_CAP = 50;
const isSale = (v: string): v is (typeof SALE_STATES)[number] => (SALE_STATES as readonly string[]).includes(v);

interface CenterSku {
  readonly sku: string;
  readonly on: boolean;
  /** 켤 수 없음(비활성·본사 단종) */
  readonly blocked: boolean;
}

/** 이 센터 취급을 상품별로 — productId → SKU 들 */
function useCenterSkus(mfcId: string) {
  const api = useApi();
  return useQuery({
    queryKey: ['handlings', mfcId, 'by-product'],
    queryFn: async () => {
      const by = new Map<string, CenterSku[]>();
      let cursor: string | undefined;
      let pages = 0;
      do {
        const page = await request('GET', api.inventory.GET('/mfcs/{mfcId}/sku-handlings', { params: { path: { mfcId }, query: { size: 200, ...(cursor ? { cursor } : {}) } } }));
        for (const h of page.items ?? []) {
          if (!h.productId) continue;
          const blocked = h.skuState === 'INACTIVE' || h.offReason === 'DISCONTINUED' || h.saleState === 'DISCONTINUED';
          by.set(h.productId, [...(by.get(h.productId) ?? []), { sku: h.sku, on: h.handlingEnabled, blocked }]);
        }
        cursor = page.page?.nextCursor ?? undefined;
        pages += 1;
      } while (cursor && pages < PAGE_CAP);
      return by;
    },
  });
}

/** 상품들의 이 센터 취급을 한꺼번에 — 바뀔 SKU 만 보내고, 500행씩 나눈다 */
function useSetHandling(mfcId: string, skus: ReadonlyMap<string, readonly CenterSku[]> | undefined) {
  const api = useApi();
  const queryClient = useQueryClient();
  return useCommand(async ({ ids, on }: { readonly ids: readonly string[]; readonly on: boolean }, key: IdempotencyKey) => {
    const rows = ids.flatMap((id) => (skus?.get(id) ?? []).filter((s) => s.on !== on && !(on && s.blocked)).map((s) => s.sku));
    const unique = [...new Set(rows)];
    let changed = 0;
    for (let i = 0; i * BATCH_MAX < unique.length; i += 1) {
      const part = unique.slice(i * BATCH_MAX, (i + 1) * BATCH_MAX);
      const partKey = i === 0 ? key : new Key(`${key.value}-${i}`);
      const r = await request(
        'POST',
        api.inventory.POST('/mfcs/{mfcId}/sku-handling-batches', { ...commandParams(partKey, { path: { mfcId } }), body: { reason: m.reason, items: part.map((sku) => ({ sku, enabled: on })) } }),
      );
      changed += r.changedCount ?? 0;
    }
    await queryClient.invalidateQueries({ queryKey: ['handlings', mfcId] });
    await queryClient.invalidateQueries({ queryKey: ['handlings-new-count', mfcId] });
    return { on, changed, products: ids.length };
  });
}

export function CatalogProducts({ mfcId }: { readonly mfcId: string }) {
  const api = useApi();
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState('');
  const [q, setQ] = useState('');
  const [sale, setSale] = useState<string>('ON_SALE');
  const [picked, setPicked] = useState<ReadonlySet<string>>(new Set());
  const [allCount, setAllCount] = useState<number | null>(null);
  const [allFailed, setAllFailed] = useState(false);
  const [allBusy, setAllBusy] = useState(false);
  const queryOf = (cursor?: string, size = 50) => ({ size, ...(q ? { q } : {}), ...(isSale(sale) ? { saleState: sale } : {}), ...(cursor ? { cursor } : {}) });
  const products = useInfiniteQuery({
    queryKey: ['catalog', q, sale],
    initialPageParam: undefined as string | undefined,
    queryFn: ({ pageParam }) => request('GET', api.product.GET('/products', { params: { query: queryOf(pageParam) } })),
    getNextPageParam: (last) => last.page?.nextCursor ?? undefined,
  });
  const center = useCenterSkus(mfcId);
  const setHandling = useSetHandling(mfcId, center.data);
  const rows = (products.data?.pages ?? []).flatMap((p) => p.items ?? []);
  const cards = useProductCards(rows.map((p) => p.productId));
  const [view, setView] = useProductView();
  const allPicked = allCount !== null && picked.size === allCount;
  // 조건이 바뀌면 고른 것은 풀린다(고르기는 지금 조건의 결과 안에서만)
  const clearPick = () => {
    setPicked(new Set());
    setAllCount(null);
    setAllFailed(false);
  };
  const filter = (nextQ: string, nextSale: string) => {
    if (nextQ !== q || nextSale !== sale) clearPick();
    setQ(nextQ);
    setSale(nextSale);
  };
  const toggle = (id: string) =>
    setPicked((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  /** 지금 조건의 상품 전부 — 안 읽은 쪽까지 */
  const pickAll = async () => {
    setAllFailed(false);
    setAllBusy(true);
    try {
      const ids = await queryClient.fetchQuery({
        queryKey: ['catalog-all', q, sale],
        queryFn: async () => {
          const out: string[] = [];
          let cursor: string | undefined;
          let pages = 0;
          do {
            const page = await request('GET', api.product.GET('/products', { params: { query: queryOf(cursor, 200) } }));
            for (const p of page.items ?? []) if (p.productId) out.push(p.productId);
            cursor = page.page?.nextCursor ?? undefined;
            pages += 1;
          } while (cursor && pages < PAGE_CAP);
          return out;
        },
      });
      setPicked(new Set(ids));
      setAllCount(ids.length);
    } catch {
      setAllFailed(true);
    } finally {
      setAllBusy(false);
    }
  };
  const runBulk = (on: boolean) => {
    if (setHandling.phase.kind === 'rejected' || setHandling.phase.kind === 'done') setHandling.reset();
    void setHandling.run({ ids: [...picked], on });
  };
  return (
    <section className="space-y-3 text-sm" data-testid="catalog-products">
      <SearchPanel
        label={m.search}
        submitLabel={messages.inventory.lookup}
        onSubmit={(e) => {
          e.preventDefault();
          filter(draft.trim(), sale);
        }}
        onReset={() => {
          setDraft('');
          filter('', 'ON_SALE');
        }}
        summary={[[m.saleState, sale ? (m.saleName[sale] ?? sale) : '', sale ? () => filter(q, '') : undefined]]}
        search={<input type="search" className="input input-sm w-60" maxLength={50} value={draft} placeholder={m.placeholder} aria-label={m.placeholder} onChange={(e) => setDraft(e.target.value)} />}
      >
        <SearchRow label={m.saleState}>
          <select className="select select-sm w-36" aria-label={m.saleState} value={sale} onChange={(e) => filter(q, e.target.value)}>
            <option value="">{m.allSale}</option>
            {SALE_STATES.map((s) => (
              <option key={s} value={s}>
                {m.saleName[s]}
              </option>
            ))}
          </select>
        </SearchRow>
      </SearchPanel>

      {/* 고르기·일괄 줄 — 목록 바로 위에 붙어 있다 */}
      <div className="sticky top-0 z-10 flex flex-wrap items-center gap-x-4 gap-y-2 rounded-box border border-base-300 bg-base-100 px-4 py-2" data-testid="catalog-bulk">
        <label className="flex cursor-pointer items-center gap-2">
          <input
            type="checkbox"
            className="checkbox checkbox-sm"
            checked={allPicked}
            disabled={allBusy || !products.isSuccess || rows.length === 0}
            onChange={() => {
              if (allPicked) clearPick();
              else void pickAll();
            }}
          />
          <span>{allBusy ? m.pickAllBusy : m.pickAll(q !== '' || sale !== '')}</span>
        </label>
        {allFailed && <span className="text-error">{m.pickAllFailed}</span>}
        <span className="text-base-content/70" data-testid="result-count">
          {m.shown(rows.length, products.hasNextPage)}
        </span>
        {picked.size > 0 && (
          <span className="flex flex-wrap items-center gap-2" data-testid="catalog-picked">
            <span className="font-semibold text-primary">{m.picked(picked.size)}</span>
            <button type="button" className="btn btn-sm btn-primary" disabled={setHandling.busy || !center.data} onClick={() => runBulk(true)}>
              {m.bulkOn}
            </button>
            <button type="button" className="btn btn-sm" disabled={setHandling.busy || !center.data} onClick={() => runBulk(false)}>
              {m.bulkOff}
            </button>
            <button
              type="button"
              className="btn btn-sm btn-ghost"
              onClick={clearPick}
            >
              {m.clearPick}
            </button>
          </span>
        )}
        <span className="ml-auto">
          <ViewToggle view={view} onChange={setView} />
        </span>
        <CommandFeedback command={setHandling}>
          {(r) => (
            <p role="status" className="basis-full text-success">
              {m.bulkDone(r.on, r.products, r.changed)}
            </p>
          )}
        </CommandFeedback>
      </div>

      <QueryState state={toUiState(products, (d) => d.pages.every((p) => (p.items ?? []).length === 0))} onRetry={() => void products.refetch()} emptyText={m.empty}>
        {() => (
          <>
            {view === 'card' ? (
              <ul className="grid grid-cols-[repeat(auto-fill,minmax(11rem,1fr))] gap-3" data-testid="catalog-cards">
                {rows.map((p) => {
                  const id = p.productId ?? '';
                  const name = p.internalName ?? id;
                  return (
                    <li key={id} className={`flex flex-col gap-2 rounded-box border bg-base-100 p-3 ${picked.has(id) ? 'border-primary ring-1 ring-primary' : 'border-base-300'}`} data-testid="catalog-card">
                      <span className="relative">
                        <ProductThumb info={cards.data?.get(id)} fallback={name} size="card" />
                        <input type="checkbox" className="checkbox checkbox-sm absolute top-2 left-2 bg-base-100" aria-label={m.pickLabel(name)} checked={picked.has(id)} onChange={() => toggle(id)} />
                      </span>
                      <span className="line-clamp-2 font-semibold" title={name}>
                        {name}
                      </span>
                      <SaleBadge state={p.saleState} />
                      <span className="mt-auto">
                        <CenterSwitch mfcId={mfcId} productId={id} name={name} center={center} />
                      </span>
                    </li>
                  );
                })}
              </ul>
            ) : (
              // 상품 칸이 화면 폭만큼 늘어나지 않게 — 표는 내용 폭(2026-11-26 사용자 "상품 칸 좁혀")
              <div className="w-fit max-w-full overflow-x-auto rounded-box border border-base-300 bg-base-100">
                <table className="table table-sm w-auto">
                  <thead>
                    <tr>
                      <th className="w-10" aria-label={m.col.pick} />
                      <th className="min-w-64">{m.col.name}</th>
                      <th className="w-32">{m.col.sale}</th>
                      <th className="w-56">{m.col.here}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((p) => {
                      const id = p.productId ?? '';
                      const name = p.internalName ?? id;
                      return (
                        <tr key={id} className={picked.has(id) ? 'bg-primary/5' : undefined} data-testid="catalog-row">
                          <td>
                            <input type="checkbox" className="checkbox checkbox-sm" aria-label={m.pickLabel(name)} checked={picked.has(id)} onChange={() => toggle(id)} />
                          </td>
                          <td>
                            <span className="flex items-center gap-3">
                              <ProductThumb info={cards.data?.get(id)} fallback={name} size="row" />
                              <span className="min-w-0">
                                <span className="block max-w-80 truncate font-medium" title={name}>{name}</span>
                                <span className="font-mono text-xs text-base-content/60">{id}</span>
                              </span>
                            </span>
                          </td>
                          <td>
                            <SaleBadge state={p.saleState} />
                          </td>
                          <td>
                            <CenterSwitch mfcId={mfcId} productId={id} name={name} center={center} />
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
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
    </section>
  );
}

function SaleBadge({ state }: { readonly state: string | undefined }) {
  const cls = state === 'SALE_STOPPED' ? 'badge-error' : state === 'TEMPORARILY_SOLD_OUT' ? 'badge-warning' : 'badge-ghost';
  return <span className={`badge badge-sm ${cls}`}>{m.saleName[state ?? ''] ?? state}</span>;
}

/** 줄마다 이 센터 취급 스위치 — 켜짐 = SKU 하나라도 켜짐, 일부만 켜졌으면 몇 개인지 */
function CenterSwitch({ mfcId, productId, name, center }: { readonly mfcId: string; readonly productId: string; readonly name: string; readonly center: ReturnType<typeof useCenterSkus> }) {
  const cmd = useSetHandling(mfcId, center.data);
  if (center.isError) return <span className="text-error">{m.hereFailed}</span>;
  if (!center.data) return <span className="loading loading-dots loading-xs" aria-label={m.loading} />;
  const skus = center.data.get(productId) ?? [];
  const onCount = skus.filter((s) => s.on).length;
  const on = onCount > 0;
  const canOn = skus.some((s) => !s.blocked);
  return (
    <span className="flex flex-col items-start gap-1">
      <label className="flex cursor-pointer items-center gap-2">
        <input
          type="checkbox"
          role="switch"
          className="toggle toggle-sm toggle-success"
          aria-label={m.toggleLabel(name)}
          checked={on}
          disabled={cmd.busy || skus.length === 0 || (!on && !canOn)}
          onChange={() => {
            if (cmd.phase.kind === 'rejected' || cmd.phase.kind === 'done') cmd.reset();
            void cmd.run({ ids: [productId], on: !on });
          }}
        />
        <span className={on ? 'font-medium text-success' : 'text-base-content/60'}>{on ? m.here : !canOn ? m.cannotOn : m.notHere}</span>
        {on && onCount < skus.length && <span className="text-xs text-base-content/60">{m.partial(onCount, skus.length)}</span>}
      </label>
      <CommandFeedback command={cmd}>{() => null}</CommandFeedback>
    </span>
  );
}
