// 재고 > 재고 이력 탭 — mfc-inventory 0.48.0 `GET /mfcs/{mfcId}/stock-ledger?sku=`(백엔드 PR #470, 2026-11-25 MFC 백엔드 요청 "화면에 이력 탭도 붙여").
// 한 SKU 의 수량을 바꾼 확정 단위를 최신순으로: 원인·시각·출처·증감(H 보유·Q 격리·E 판매 가능·R 예약)·그 뒤 가용. 줄을 펼치면 칸·LOT 줄과 그 뒤 합계.
// 값은 서버 값만(계산하지 않음). 원인 이름은 아는 것만 바꾸고 모르는 값은 코드 그대로. 작업자는 원장에 없다 — 출처 번호(sourceRef)만 보인다.
import { useInfiniteQuery } from '@tanstack/react-query';
import { Fragment, useState } from 'react';
import { useSearchParams } from 'react-router';

import { request } from '@pmart/web-core';
import { formatSeoul, QueryState, toUiState } from '@pmart/web-ui';
import type { components } from '../../api/generated/mfc-inventory';
import { useApi } from '../../app/ApiContext';
import { SystemNumbers } from '../../shared/displayNumber';
import { StatCard, StatStrip } from '../../shared/listParts';
import { LotLabel } from '../../shared/LotLabel';
import { messages } from '../../shared/messages';
import { Who } from '../../shared/OperatorLabel';
import { OrderNo } from '../../shared/OrderNo';
import { Caret, expandRowProps, InlineDetail, InlineFields, ResultBar, SearchPanel, SearchRow, useInlineOpen } from '../../shared/simList';

const m = messages.inventory.ledger;
const mv = messages.moves;
type Commit = components['schemas']['StockLedgerCommit'];
type Totals = components['schemas']['StockLedgerTotals'];

const PAGE = 50;
const CAUSES = Object.keys(m.causeName);

/** 원인 이름 — 아는 코드는 이름, QUALITY_·MOVE_ 는 묶음 이름, 모르는 값은 코드 그대로 */
export function causeName(code: string): string {
  const exact = m.causeName[code];
  if (exact) return exact;
  const prefix = Object.keys(m.causePrefix).find((p) => code.startsWith(p));
  return prefix ? m.causePrefix[prefix]! : code;
}

/** 출처 — 어느 서비스 일인지 이름만(시스템 번호 sourceRef 는 펼침의 "시스템 번호"에, ADR-0070). 모르는 서비스는 그대로 */
export function sourceName(system: string): string {
  return m.sourceName[system.replace(/-service$/, '')] ?? system;
}

const signed = (n: number) => (n > 0 ? `+${n}` : n < 0 ? `−${-n}` : messages.none);
/** 날짜 칸(한국 날짜) → 그날 0시(+09:00). to 는 그다음 날 0시(서버 to 는 포함 안 함) */
const dayStart = (d: string) => `${d}T00:00:00+09:00`;
const nextDayStart = (d: string) => {
  const t = new Date(`${d}T00:00:00+09:00`);
  t.setUTCDate(t.getUTCDate() + 1);
  return t.toISOString();
};

export function StockLedgerTab({ mfcId }: { readonly mfcId: string }) {
  const api = useApi();
  const [params, setParams] = useSearchParams();
  const get = (k: string) => params.get(k) ?? '';
  const sku = get('sku');
  const cause = get('cause');
  const lotId = get('lot');
  const loc = get('loc');
  const from = get('from');
  const to = get('to');
  const [draft, setDraft] = useState(sku);
  const set = (patch: Record<string, string>) => {
    const next = new URLSearchParams(params);
    for (const [k, v] of Object.entries(patch)) {
      if (v) next.set(k, v);
      else next.delete(k);
    }
    setParams(next, { replace: true });
  };
  const query = useInfiniteQuery({
    queryKey: ['stock-ledger', mfcId, sku, cause, lotId, loc, from, to],
    enabled: !!sku,
    initialPageParam: undefined as string | undefined,
    queryFn: ({ pageParam }) =>
      request(
        'GET',
        api.inventory.GET('/mfcs/{mfcId}/stock-ledger', {
          params: {
            path: { mfcId },
            query: {
              sku,
              size: PAGE,
              ...(cause ? { cause: [cause] } : {}),
              ...(lotId ? { lotId } : {}),
              ...(loc ? { locationCode: loc } : {}),
              ...(from ? { from: dayStart(from) } : {}),
              ...(to ? { to: nextDayStart(to) } : {}),
              ...(pageParam ? { cursor: pageParam } : {}),
            },
          },
        }),
      ),
    getNextPageParam: (last) => last.nextCursor ?? undefined,
  });
  const inline = useInlineOpen();
  const first = query.data?.pages[0];
  const items = query.data?.pages.flatMap((p) => p.items) ?? [];
  const period = from || to ? `${from || '…'} ~ ${to || '…'}` : '';
  return (
    <div className="space-y-4" data-testid="stock-ledger">
      <SearchPanel
        label={m.search}
        submitLabel={messages.inventory.lookup}
        onSubmit={(e) => {
          e.preventDefault();
          set({ sku: draft.trim().toUpperCase() });
        }}
        onReset={() => set({ cause: '', lot: '', loc: '', from: '', to: '' })}
        summary={[
          [m.cause, cause ? causeName(cause) : '', () => set({ cause: '' })],
          [m.lot, lotId, () => set({ lot: '' })],
          [m.location, loc, () => set({ loc: '' })],
          [m.period, period, () => set({ from: '', to: '' })],
        ]}
        search={<input type="search" className="input input-sm w-48 font-mono" maxLength={64} value={draft} placeholder={m.skuPlaceholder} aria-label={m.skuPlaceholder} onChange={(e) => setDraft(e.target.value)} />}
      >
        <SearchRow label={m.cause}>
          <select className="select select-sm w-40" aria-label={m.cause} value={cause} onChange={(e) => set({ cause: e.target.value })}>
            <option value="">{m.allCauses}</option>
            {CAUSES.map((c) => (
              <option key={c} value={c}>
                {m.causeName[c]}
              </option>
            ))}
          </select>
        </SearchRow>
        <SearchRow label={m.lot}>
          <input className="input input-sm w-44 font-mono" aria-label={m.lot} maxLength={64} value={lotId} onChange={(e) => set({ lot: e.target.value.trim() })} />
        </SearchRow>
        <SearchRow label={m.location}>
          <input className="input input-sm w-44 font-mono" aria-label={m.location} maxLength={64} value={loc} onChange={(e) => set({ loc: e.target.value.trim().toUpperCase() })} />
        </SearchRow>
        <SearchRow label={m.period}>
          <span className="flex items-center gap-1">
            <input type="date" className="input input-sm w-36" aria-label={m.from} value={from} onChange={(e) => set({ from: e.target.value })} />
            <span aria-hidden="true">~</span>
            <input type="date" className="input input-sm w-36" aria-label={m.to} value={to} onChange={(e) => set({ to: e.target.value })} />
          </span>
        </SearchRow>
      </SearchPanel>
      {!sku ? (
        <p className="pm-empty-line">{m.needSku}</p>
      ) : (
        <QueryState state={toUiState(query, (d) => d.pages.every((p) => p.items.length === 0))} onRetry={() => void query.refetch()} emptyText={m.empty}>
          {() => (
            <>
              {first && <NowTotals name={first.productName ?? first.sku} totals={first.current} asOf={first.asOf} />}
              <div className="pm-list-box">
                <ResultBar count={items.length} more={query.hasNextPage} />
                <div className="overflow-x-auto" data-list-part="table">
                  <table className="table table-sm">
                    <thead>
                      <tr>
                        <th>{m.col.at}</th>
                        <th>{m.col.cause}</th>
                        <th className="text-right">{m.col.H}</th>
                        <th className="text-right">{m.col.Q}</th>
                        <th className="text-right">{m.col.E}</th>
                        <th className="text-right">{m.col.R}</th>
                        <th className="text-right">{m.col.after}</th>
                        <th>{m.col.source}</th>
                      </tr>
                    </thead>
                    <tbody>
                      {items.map((c) => {
                        const open = inline.isOpen(c.commitId);
                        return (
                          <Fragment key={c.commitId}>
                            <tr data-testid="ledger-row" {...expandRowProps(open, () => inline.toggle(c.commitId))}>
                              <td className="whitespace-nowrap">
                                <Caret open={open} />
                                <time dateTime={c.occurredAt}>{formatSeoul(c.occurredAt)}</time>
                              </td>
                              <td title={c.cause}>{causeName(c.cause)}</td>
                              <td className="text-right">{signed(c.delta.H)}</td>
                              <td className="text-right">{signed(c.delta.Q)}</td>
                              <td className="text-right">{signed(c.delta.E)}</td>
                              <td className="text-right">{signed(c.delta.R)}</td>
                              <td className="text-right font-semibold">{c.after.availableQty}</td>
                              <td>{sourceName(c.sourceSystem)}</td>
                            </tr>
                            {open && (
                              <InlineDetail colSpan={8} testId="ledger-inline">
                                <CommitDetail commit={c} />
                              </InlineDetail>
                            )}
                          </Fragment>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              </div>
              {query.hasNextPage && (
                <button type="button" className="btn btn-sm" disabled={query.isFetchingNextPage} onClick={() => void query.fetchNextPage()}>
                  {m.more}
                </button>
              )}
              {query.isFetchNextPageError && (
                <p role="alert" className="text-sm text-error">
                  {messages.errorTitle}
                </p>
              )}
            </>
          )}
        </QueryState>
      )}
    </div>
  );
}

/** 지금 합계(서버 current) — 숫자 띠 */
function NowTotals({ name, totals, asOf }: { readonly name: string; readonly totals: Totals; readonly asOf: string }) {
  const s = m.symbol;
  return (
    <div className="space-y-1">
      <p className="text-sm">
        <span className="font-semibold">{name}</span> <span className="text-base-content/60">{`· ${m.now} · ${m.asOf(formatSeoul(asOf))}`}</span>
      </p>
      <StatStrip label={m.now} testId="ledger-now">
        <StatCard label={s.H} value={String(totals.onHandQty)} />
        <StatCard label={s.Q} value={String(totals.quarantinedQty)} />
        <StatCard label={s.E} value={String(totals.sellableQty)} />
        <StatCard label={s.R} value={String(totals.reservedQty)} />
        <StatCard label={messages.inventory.lot.available} value={String(totals.availableQty)} testId="ledger-now-available" />
      </StatStrip>
    </div>
  );
}

/** 펼친 줄 — 칸·LOT·상태별 증감 줄 + 그 뒤 합계 + 시스템 번호 */
function CommitDetail({ commit: c }: { readonly commit: Commit }) {
  const a = c.after;
  return (
    <div className="space-y-3">
      <table className="table table-xs">
        <thead>
          <tr>
            <th>{m.entry.symbol}</th>
            <th className="text-right">{m.entry.delta}</th>
            <th>{m.entry.location}</th>
            <th>{m.entry.lot}</th>
            <th>{m.entry.expiry}</th>
            <th>{m.entry.state}</th>
          </tr>
        </thead>
        <tbody>
          {c.entries.map((e, i) => (
            <tr key={i} data-testid="ledger-entry">
              <td>{m.symbol[e.symbol] ?? e.symbol}</td>
              <td className="text-right">{signed(e.delta)}</td>
              <td className="font-mono text-xs">{e.locationCode ?? messages.none}</td>
              <td>{e.lotId ? <LotLabel lotId={e.lotId} lotNo={e.lotNo} /> : messages.none}</td>
              <td>{e.expiryDate ?? messages.none}</td>
              <td>{[e.qualityState && (mv.quality[e.qualityState] ?? e.qualityState), e.workState && (mv.work[e.workState] ?? e.workState)].filter(Boolean).join(' · ') || messages.none}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <InlineFields
        rows={[
          [`${m.afterLabel} · ${m.symbol.H}`, a.onHandQty],
          [m.symbol.Q!, a.quarantinedQty],
          [m.symbol.E!, a.sellableQty],
          [m.symbol.R!, a.reservedQty],
          [messages.inventory.lot.available, a.availableQty],
          [m.order, <OrderNo key="o" orderId={c.orderId} />],
          [m.actor, c.actorOperatorId ? <Who key="a" id={c.actorOperatorId} /> : messages.none],
          [m.col.source, sourceName(c.sourceSystem)],
        ]}
      />
      <SystemNumbers
        ids={[
          { label: m.commit, id: c.commitId },
          { label: m.col.source, id: c.sourceRef },
        ]}
      />
    </div>
  );
}
