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
import type { components } from '../../api/generated/mfc-inventory';
import { useApi } from '../../app/ApiContext';
import { SystemNumbers } from '../../shared/displayNumber';
import { messages } from '../../shared/messages';
import { Who } from '../../shared/OperatorLabel';
import { OrderNo } from '../../shared/OrderNo';
import { InlineFields, ResultBar, SearchPanel } from '../../shared/simList';
import { causeName } from './StockLedgerTab';

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

export function LotTraceTab({ mfcId }: { readonly mfcId: string }) {
  const api = useApi();
  const [params, setParams] = useSearchParams();
  const code = params.get('lot') ?? '';
  const [draft, setDraft] = useState(code);
  const lot = useQuery({
    queryKey: ['lot-resolve', mfcId, code],
    enabled: !!code,
    queryFn: () => request('GET', api.inventory.GET('/mfcs/{mfcId}/lot-resolutions', { params: { path: { mfcId }, query: { code: lotCode(code) } } })),
  });
  return (
    <div className="space-y-4" data-testid="lot-trace">
      <SearchPanel
        label={m.search}
        submitLabel={inv.lookup}
        onSubmit={(e) => {
          e.preventDefault();
          const next = new URLSearchParams(params);
          if (draft.trim()) next.set('lot', draft.trim());
          else next.delete('lot');
          setParams(next, { replace: true });
        }}
        onReset={() => setDraft('')}
        search={<input type="search" className="input input-sm w-56 font-mono" maxLength={120} value={draft} placeholder={m.placeholder} aria-label={m.placeholder} onChange={(e) => setDraft(e.target.value)} />}
      />
      {!code ? (
        <p className="pm-empty-line">{m.needLot}</p>
      ) : (
        <QueryState state={toUiState(lot)} onRetry={() => void lot.refetch()}>
          {(l) => (
            <>
              <LotCard lot={l} />
              <Where mfcId={mfcId} lot={l} />
              <History mfcId={mfcId} lot={l} />
            </>
          )}
        </QueryState>
      )}
    </div>
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
                          <td className="font-mono text-xs">{c.sourceRef ?? c.sourceSystem}</td>
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
