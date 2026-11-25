// 재고 > LOT 추적 탭(2026-11-25 사용자 "재고추적탭 만들어줘" → "LOT 추적") — 새 API 없이 있는 조회 셋으로:
// 1) LOT 찾기 `GET /mfcs/{mfcId}/lot-resolutions?code=`(0.21.0) — LOT 번호는 GS1 괄호 꼴 (10)번호 로, 라벨 바코드·LOT:{id} 는 그대로. 라벨 정보·이 센터 보유.
// 2) 지금 있는 곳 `GET /mfcs/{mfcId}/stock?sku=` 의 units 중 이 LOT(상품별 재고와 같은 조회 키 — 실시간 반영이 같이 다시 읽는다).
// 3) 지나온 길 `GET /mfcs/{mfcId}/stock-ledger?sku=&lotId=`(0.48.0) — 그 LOT 줄이 있는 확정 단위, 화면은 이 LOT 줄만 요약(이동이면 출발 칸 − → 도착 칸 +).
// 다른 센터·간선은 이 센터 원장 밖이라 보이지 않는다. 값은 서버 값만.
import { useInfiniteQuery, useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { useSearchParams } from 'react-router';

import { request } from '@pmart/web-core';
import { formatSeoul, QueryState, toUiState } from '@pmart/web-ui';
import type { components, paths as InvPaths } from '../../api/generated/mfc-inventory';
import { useApi } from '../../app/ApiContext';
import { BackButton } from '../../shared/DetailHead';
import { SystemNumbers } from '../../shared/displayNumber';
import { LotLabel } from '../../shared/LotLabel';
import { messages } from '../../shared/messages';
import { Who } from '../../shared/OperatorLabel';
import { OrderNo } from '../../shared/OrderNo';
import { Pager, usePage } from '../../shared/Pager';
import { InlineFields, ResultBar, SearchPanel, SearchRow } from '../../shared/simList';
import { causeName, sourceName } from './StockLedgerTab';

const m = messages.inventory.lotTrace;
const inv = messages.inventory;
const mv = messages.moves;
type Commit = components['schemas']['StockLedgerCommit'];
type Lot = components['schemas']['LotLabel'];

/** 입력 → lot-resolutions code. 괄호 꼴·LOT:·스캐너 원문(GS·]C1)은 그대로, 맨 LOT 번호는 (10) 을 붙인다 */
export function lotCode(input: string): string {
  const v = input.trim();
  if (!v) return '';
  if (v.startsWith('(') || v.startsWith('LOT:') || v.startsWith(']C1') || v.includes(String.fromCharCode(29)) || /^\d{14,}/.test(v)) return v;
  return `(10)${v.toUpperCase()}`;
}

const signed = (n: number) => (n > 0 ? `+${n}` : `−${-n}`);

/** 이 LOT 줄만 — H 는 칸별 증감("A-P1 −2 → QRT +2"), 나머지(E·Q)는 판매 가능·격리 증감 */
function lotSummary(c: Commit, lotId: string) {
  const mine = c.entries.filter((e) => e.lotId === lotId);
  const moves = mine
    .filter((e) => e.symbol === 'H')
    .map((e) => `${e.locationCode ?? messages.none} ${signed(e.delta)}`)
    .join(' → ');
  const sum = (s: 'E' | 'Q') => mine.filter((e) => e.symbol === s).reduce((n, e) => n + e.delta, 0);
  const states = [
    [inv.ledger.symbol.E, sum('E')],
    [inv.ledger.symbol.Q, sum('Q')],
  ]
    .filter(([, n]) => n !== 0)
    .map(([k, n]) => `${String(k)} ${signed(Number(n))}`)
    .join(' · ');
  // 예약(R)은 LOT 이 없다 — 그 확정의 예약 증감을 그대로
  const r = c.delta.R !== 0 ? `${inv.ledger.symbol.R} ${signed(c.delta.R)}` : '';
  return { moves: moves || messages.none, states: [states, r].filter(Boolean).join(' · ') || messages.none };
}

/** 찾기 칸 글자가 LOT 번호·바코드(괄호 꼴·스캐너 원문·LOT:)면 바로 그 LOT 으로, 아니면 목록 거르기 글자로 */
export function looksLikeLotCode(v: string): boolean {
  const t = v.trim();
  // LOT 번호 꼴(영문 한 글자 + 숫자 9자리 넘게, 예 L261107000497)도 바로 그 LOT 으로
  return t.startsWith('(') || t.startsWith('LOT:') || t.startsWith(']C1') || t.includes(String.fromCharCode(29)) || /^\d{14,}/.test(t) || /^[A-Za-z]\d{9,}$/.test(t);
}

export function LotTraceTab({ mfcId }: { readonly mfcId: string }) {
  const api = useApi();
  const [params, setParams] = useSearchParams();
  const code = params.get('lot') ?? '';
  const q = params.get('q') ?? '';
  const quality = params.get('quality') ?? '';
  const temp = params.get('temp') ?? '';
  const [draft, setDraft] = useState(q);
  const set = (patch: Record<string, string>) => {
    const next = new URLSearchParams(params);
    for (const [k, v] of Object.entries(patch)) {
      if (v) next.set(k, v);
      else next.delete(k);
    }
    next.delete('page');
    setParams(next, { replace: true });
  };
  const lot = useQuery({
    queryKey: ['lot-resolve', mfcId, code],
    enabled: !!code,
    queryFn: () => request('GET', api.inventory.GET('/mfcs/{mfcId}/lot-resolutions', { params: { path: { mfcId }, query: { code: lotCode(code) } } })),
  });
  if (code)
    return (
      <div className="space-y-4" data-testid="lot-trace">
        <div className="flex items-center gap-2">
          <BackButton onClick={() => set({ lot: '' })} label={m.backToList} />
          <span className="text-sm text-base-content/60">{m.backToList}</span>
        </div>
        <QueryState state={toUiState(lot)} onRetry={() => void lot.refetch()}>
          {(l) => (
            <>
              <LotCard lot={l} />
              <Where mfcId={mfcId} lot={l} />
              <History mfcId={mfcId} lot={l} />
            </>
          )}
        </QueryState>
      </div>
    );
  return (
    <div className="space-y-4" data-testid="lot-trace">
      {/* LOT 번호를 몰라도 — 센터에 지금 있는 LOT 목록(상품명·상품 코드·LOT 번호로 찾기, 품질·온도대 필터). 라벨 바코드를 찍으면 바로 그 LOT */}
      <SearchPanel
        label={m.search}
        submitLabel={inv.lookup}
        onSubmit={(e) => {
          e.preventDefault();
          const t = draft.trim();
          if (looksLikeLotCode(t)) set({ lot: t, q: '' });
          else set({ q: t });
        }}
        onReset={() => {
          setDraft('');
          set({ q: '', quality: '', temp: '' });
        }}
        summary={[
          [m.quality, quality ? (mv.quality[quality] ?? quality) : '', () => set({ quality: '' })],
          [m.temperature, temp ? (messages.locations.temperature[temp] ?? temp) : '', () => set({ temp: '' })],
        ]}
        search={<input type="search" className="input input-sm w-60" maxLength={120} value={draft} placeholder={m.placeholder} aria-label={m.placeholder} onChange={(e) => setDraft(e.target.value)} />}
      >
        <SearchRow label={m.quality}>
          <select className="select select-sm w-36" aria-label={m.quality} value={quality} onChange={(e) => set({ quality: e.target.value })}>
            <option value="">{m.all}</option>
            {QUALITIES.map((x) => (
              <option key={x} value={x}>
                {mv.quality[x] ?? x}
              </option>
            ))}
          </select>
        </SearchRow>
        <SearchRow label={m.temperature}>
          <select className="select select-sm w-36" aria-label={m.temperature} value={temp} onChange={(e) => set({ temp: e.target.value })}>
            <option value="">{m.all}</option>
            {TEMPS.map((x) => (
              <option key={x} value={x}>
                {messages.locations.temperature[x] ?? x}
              </option>
            ))}
          </select>
        </SearchRow>
      </SearchPanel>
      <LotList mfcId={mfcId} q={q} quality={quality} temp={temp} onOpen={(c) => set({ lot: c })} />
    </div>
  );
}

const QUALITIES = ['NORMAL', 'QUARANTINED'] as const;
const TEMPS = ['AMBIENT', 'CHILLED', 'FROZEN'] as const;
/** 센터 재고 한 번에 읽는 상한 — stock-units 한 쪽 200줄 × 20쪽 */
const LIST_PAGE = 200;
const LIST_MAX_PAGES = 20;
const LOT_ROWS = 20;

type StockUnitRow = InvPaths['/mfcs/{mfcId}/stock-units']['get']['responses']['200']['content']['application/json']['items'][number];

interface LotRow {
  readonly lotId: string;
  readonly lotNo: string | null;
  readonly sku: string;
  readonly productName: string | null;
  readonly expiryDate: string | null;
  readonly places: readonly string[];
  readonly qty: number;
  readonly quarantined: number;
}

/** 단위 행 → LOT 별 한 줄(칸·수량·격리 합), 글자 거르기(상품명·상품 코드·LOT 번호), 소비기한 이른 순 */
function groupLots(rows: readonly StockUnitRow[], q: string): LotRow[] {
  const needle = q.trim().toLowerCase();
  const by = new Map<string, LotRow>();
  for (const u of rows) {
    const prev = by.get(u.lotId);
    by.set(u.lotId, {
      lotId: u.lotId,
      lotNo: prev?.lotNo ?? u.lotNo ?? null,
      sku: u.sku,
      productName: prev?.productName ?? u.productName ?? null,
      expiryDate: prev?.expiryDate ?? u.expiryDate ?? null,
      places: prev ? (prev.places.includes(u.locationCode) ? prev.places : [...prev.places, u.locationCode]) : [u.locationCode],
      qty: (prev?.qty ?? 0) + u.qty,
      quarantined: (prev?.quarantined ?? 0) + (u.qualityState === 'QUARANTINED' ? u.qty : 0),
    });
  }
  return [...by.values()]
    .filter((r) => !needle || [r.productName, r.sku, r.lotNo].some((x) => x?.toLowerCase().includes(needle)))
    .sort((x, y) => (x.expiryDate ?? '9999').localeCompare(y.expiryDate ?? '9999') || (x.productName ?? x.sku).localeCompare(y.productName ?? y.sku));
}

/** LOT 목록 — `GET /mfcs/{mfcId}/stock-units`(0.26.0, 수량 > 0 인 단위 행)를 LOT 별로 묶는다. 품질·온도대는 서버 거르기, 글자는 받은 목록 안에서. 소비기한 이른 순 */
function LotList({ mfcId, q, quality, temp, onOpen }: { readonly mfcId: string; readonly q: string; readonly quality: string; readonly temp: string; readonly onOpen: (code: string) => void }) {
  const api = useApi();
  // 'list','stock-units',mfcId 로 시작 — 재고 실시간 반영이 같이 다시 읽는다
  const units = useQuery({
    queryKey: ['list', 'stock-units', mfcId, 'lots', quality, temp],
    queryFn: async () => {
      const rows: StockUnitRow[] = [];
      let cursor: string | undefined;
      let pages = 0;
      do {
        const page = await request(
          'GET',
          api.inventory.GET('/mfcs/{mfcId}/stock-units', {
            params: {
              path: { mfcId },
              query: {
                size: LIST_PAGE,
                ...(quality ? { qualityState: quality as StockUnitRow['qualityState'] } : {}),
                ...(temp ? { temperatureZone: temp } : {}),
                ...(cursor ? { cursor } : {}),
              },
            },
          }),
        );
        rows.push(...page.items);
        cursor = page.nextCursor ?? undefined;
        pages += 1;
      } while (cursor && pages < LIST_MAX_PAGES);
      return { rows, cut: !!cursor };
    },
  });
  const lotsOf = (rows: readonly StockUnitRow[]) => groupLots(rows, q);
  const lots = units.data ? lotsOf(units.data.rows) : [];
  const paging = usePage(lots.length, LOT_ROWS);
  return (
    <QueryState state={toUiState(units, (d) => lotsOf(d.rows).length === 0)} onRetry={() => void units.refetch()} emptyText={m.listEmpty}>
      {(d) => (
        <>
          <div className="pm-list-box" data-testid="lot-list">
            <ResultBar count={lots.length} />
            <div className="overflow-x-auto" data-list-part="table">
              <table className="table table-sm">
                <thead>
                  <tr>
                    <th>{m.lcol.lot}</th>
                    <th>{m.lcol.product}</th>
                    <th>{m.lcol.expiry}</th>
                    <th>{m.lcol.places}</th>
                    <th className="text-right">{m.lcol.qty}</th>
                    <th>{m.lcol.quality}</th>
                  </tr>
                </thead>
                <tbody>
                  {lots.slice(paging.from, paging.to).map((r) => (
                    <tr key={r.lotId} data-testid="lot-row">
                      <td>
                        {/* LOT 번호를 누르면 그 LOT 추적(번호를 모르면 라벨 값 LOT:{id} — 화면에는 번호만) */}
                        <button type="button" className="cursor-pointer underline decoration-dotted underline-offset-2 hover:text-primary" onClick={() => onOpen(r.lotNo ?? `LOT:${r.lotId}`)}>
                          <LotLabel lotId={r.lotId} lotNo={r.lotNo} />
                        </button>
                      </td>
                      <td>{r.productName ? `${r.productName} (${r.sku})` : r.sku}</td>
                      <td>{r.expiryDate ?? messages.none}</td>
                      <td className="font-mono text-xs">{m.placesText(r.places[0] ?? messages.none, r.places.length)}</td>
                      <td className="text-right">{r.qty}</td>
                      <td>{r.quarantined > 0 ? <span className="badge badge-sm badge-warning">{m.quarantined(r.quarantined)}</span> : <span className="badge badge-sm badge-success">{mv.quality.NORMAL}</span>}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
          <Pager testId="lot-pager" page={paging.page} pageCount={paging.pageCount} total={lots.length} from={paging.from} to={paging.to} onChange={paging.set} />
          {d.cut && <p className="text-xs text-base-content/60">{m.more(d.rows.length)}</p>}
        </>
      )}
    </QueryState>
  );
}

function LotCard({ lot: l }: { readonly lot: Lot }) {
  return (
    <section className="space-y-3 rounded-box border border-base-300 bg-base-100 p-4" data-testid="lot-card">
      <h2 className="text-lg font-bold">
        <span className="font-mono">{l.lotNo}</span> <span className="text-base font-semibold text-base-content/70">{`· ${l.productName ?? l.sku}`}</span>
      </h2>
      <InlineFields
        rows={[
          [m.product, l.productName ? `${l.productName} (${l.sku})` : l.sku],
          [inv.lot.expiry, l.expiryDate ?? messages.none],
          [inv.lot.manufacture, l.manufactureDate ?? messages.none],
          [m.received, l.receivedAt ? formatSeoul(l.receivedAt) : messages.none],
          [inv.lot.tracking, inv.tracking[l.tracking] ?? l.tracking],
          [m.sourceLotRef, l.sourceLotRef ?? messages.none],
          [m.onHand, l.onHand],
        ]}
      />
      <SystemNumbers ids={[{ label: 'LOT', id: l.lotId }]} />
    </section>
  );
}

function Where({ mfcId, lot: l }: { readonly mfcId: string; readonly lot: Lot }) {
  const api = useApi();
  const stock = useQuery({
    queryKey: ['stock', mfcId, l.sku],
    queryFn: () => request('GET', api.inventory.GET('/mfcs/{mfcId}/stock', { params: { path: { mfcId }, query: { sku: l.sku } } })),
  });
  return (
    <section className="space-y-2" data-testid="lot-where">
      <h2 className="font-bold">{m.where}</h2>
      <QueryState state={toUiState(stock, (s) => s.units.every((u) => u.lotId !== l.lotId))} onRetry={() => void stock.refetch()} emptyText={m.whereEmpty}>
        {(s) => (
          <div className="pm-list-box overflow-x-auto">
            <table className="table table-sm">
              <thead>
                <tr>
                  <th>{inv.unit.location}</th>
                  <th>{inv.unit.quality}</th>
                  <th>{inv.unit.work}</th>
                  <th className="text-right">{inv.unit.qty}</th>
                </tr>
              </thead>
              <tbody>
                {s.units
                  .filter((u) => u.lotId === l.lotId)
                  .map((u, i) => (
                    <tr key={`${u.locationCode ?? ''}-${u.qualityState ?? ''}-${i}`} data-testid="lot-where-row">
                      <td className="font-mono">{u.locationCode}</td>
                      <td>{mv.quality[u.qualityState ?? ''] ?? u.qualityState}</td>
                      <td>{mv.work[u.workState ?? ''] ?? u.workState}</td>
                      <td className="text-right">{u.qty}</td>
                    </tr>
                  ))}
              </tbody>
            </table>
          </div>
        )}
      </QueryState>
    </section>
  );
}

function History({ mfcId, lot: l }: { readonly mfcId: string; readonly lot: Lot }) {
  const api = useApi();
  // 재고 이력 탭과 같은 조회 키 모양(실시간 반영 'stock-ledger' 가 같이 다시 읽는다)
  const query = useInfiniteQuery({
    queryKey: ['stock-ledger', mfcId, l.sku, '', l.lotId, '', '', ''],
    initialPageParam: undefined as string | undefined,
    queryFn: ({ pageParam }) =>
      request('GET', api.inventory.GET('/mfcs/{mfcId}/stock-ledger', { params: { path: { mfcId }, query: { sku: l.sku, lotId: l.lotId, size: 50, ...(pageParam ? { cursor: pageParam } : {}) } } })),
    getNextPageParam: (last) => last.nextCursor ?? undefined,
  });
  const items = query.data?.pages.flatMap((p) => p.items) ?? [];
  return (
    <section className="space-y-2" data-testid="lot-history">
      <h2 className="font-bold">{m.history}</h2>
      <QueryState state={toUiState(query, (d) => d.pages.every((p) => p.items.length === 0))} onRetry={() => void query.refetch()} emptyText={m.historyEmpty}>
        {() => (
          <>
            <div className="pm-list-box">
              <ResultBar count={items.length} more={query.hasNextPage} />
              <div className="overflow-x-auto" data-list-part="table">
                <table className="table table-sm">
                  <thead>
                    <tr>
                      <th>{m.col.at}</th>
                      <th>{m.col.cause}</th>
                      <th>{m.col.move}</th>
                      <th>{m.col.state}</th>
                      <th>{m.col.order}</th>
                      <th>{m.col.actor}</th>
                      <th>{m.col.source}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {items.map((c) => {
                      const s = lotSummary(c, l.lotId);
                      return (
                        <tr key={c.commitId} data-testid="lot-history-row">
                          <td className="whitespace-nowrap">
                            <time dateTime={c.occurredAt}>{formatSeoul(c.occurredAt)}</time>
                          </td>
                          <td title={c.cause}>{causeName(c.cause)}</td>
                          <td className="font-mono text-xs">{s.moves}</td>
                          <td>{s.states}</td>
                          <td>
                            <OrderNo orderId={c.orderId} />
                          </td>
                          <td>{c.actorOperatorId ? <Who id={c.actorOperatorId} /> : messages.none}</td>
                          <td>{sourceName(c.sourceSystem)}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
            {query.hasNextPage && (
              <button type="button" className="btn btn-sm" disabled={query.isFetchingNextPage} onClick={() => void query.fetchNextPage()}>
                {inv.ledger.more}
              </button>
            )}
          </>
        )}
      </QueryState>
    </section>
  );
}
