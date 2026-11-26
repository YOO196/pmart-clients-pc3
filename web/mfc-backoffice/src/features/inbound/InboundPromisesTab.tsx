// 입고 예정(TRF) — DC 에서 이 센터로 오는 물건이 지금 어디 있는지(사용자 2026-11-26 "백오피스에 입고 예정 trf 실시간 흐름 —
// dc백오피스엔 이미 뜨니까 여기에도 그대로"). DC 백오피스 "MFC 재고 이동"과 같은 꼴: ① 흐름 그림 한 줄, ② TRF 마다 한 줄, 15초마다 다시 읽는다.
// 서버: mfc-inbound `GET /inbound-promises?mfcId=`(끝나지 않은 것 EXPECTED·RECEIVING) + `?state=TIN_POSTED&date=오늘`(오늘 받은 것).
// 단계는 서버 상태 그대로 — 출발(departureId) 전 EXPECTED = DC 에서 준비 중, 출발 뒤 EXPECTED = 오는 중, RECEIVING = 도착·수령 중, TIN_POSTED = 받음.
// LAN 은 CDC 출발 사건부터 예정이 생긴다(승인 사건은 내는 서비스가 아직 없다) — 그래서 "DC 에서 준비 중"은 비어 있을 수 있고 그렇다고 안내한다.
// 못 읽으면 그 칸은 실패로(0 으로 꾸미지 않는다).
import { useQuery } from '@tanstack/react-query';
import { Fragment, useMemo, useState } from 'react';

import { request } from '@pmart/web-core';
import { formatSeoul, QueryState, toUiState } from '@pmart/web-ui';
import type { components } from '../../api/generated/mfc-inbound';
import { useApi } from '../../app/ApiContext';
import { messages } from '../../shared/messages';
import { useNow } from '../../shared/motion';
import { Caret } from '../../shared/simList';

const t = messages.inbound.promises;
type InboundPromise = components['schemas']['InboundPromise'];

export const PROMISE_REFRESH = 15_000;
const STEPS = ['PREP', 'GOING', 'RECEIVING', 'DONE'] as const;
export type PromiseStep = (typeof STEPS)[number];
const STEP_COLOR: Record<PromiseStep, string> = { PREP: 'bg-base-content/30', GOING: 'bg-info', RECEIVING: 'bg-warning', DONE: 'bg-success' };

/** 서버 상태 → 화면 단계(취소는 빼고) */
export function stepOf(x: Pick<InboundPromise, 'state' | 'departureId'>): PromiseStep | null {
  if (x.state === 'RECEIVING') return 'RECEIVING';
  if (x.state === 'TIN_POSTED') return 'DONE';
  if (x.state === 'EXPECTED') return x.departureId ? 'GOING' : 'PREP';
  return null;
}

const qtyOf = (x: InboundPromise) => (x.lines ?? []).reduce((a, l) => a + (l.expectedQty ?? 0), 0);
const receivedOf = (x: InboundPromise) => (x.lines ?? []).reduce((a, l) => a + (l.receivedQty ?? 0), 0);
const todaySeoul = () => new Date(Date.now() + 9 * 3_600_000).toISOString().slice(0, 10);
const trfNo = (id: string | undefined) => (id ? id.replace(/^TRF-/, '') : messages.none);

export function InboundPromisesTab({ mfcId }: { readonly mfcId: string }) {
  const api = useApi();
  const open = useQuery({
    queryKey: ['inbound-promises', mfcId, 'open'],
    refetchInterval: PROMISE_REFRESH,
    queryFn: () => request('GET', api.inbound.GET('/inbound-promises', { params: { query: { mfcId, size: 200 } } })),
  });
  const day = todaySeoul();
  const done = useQuery({
    queryKey: ['inbound-promises', mfcId, 'TIN_POSTED', day],
    refetchInterval: PROMISE_REFRESH,
    queryFn: () => request('GET', api.inbound.GET('/inbound-promises', { params: { query: { mfcId, state: 'TIN_POSTED', date: day, size: 200 } } })),
  });
  return (
    <section className="space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-2">
        <p className="text-sm text-base-content/60">{t.lead}</p>
        {open.dataUpdatedAt > 0 && <span className="text-xs text-base-content/55">{t.asOf(formatSeoul(new Date(open.dataUpdatedAt).toISOString()))}</span>}
      </div>
      <QueryState state={toUiState(open, () => false)} onRetry={() => void open.refetch()}>
        {(d) => (
          <FlowBody
            open={d.items ?? []}
            done={done.data?.items ?? null}
            doneFailed={done.isError}
            partial={!!d.page?.nextCursor}
          />
        )}
      </QueryState>
    </section>
  );
}

function FlowBody({
  open,
  done,
  doneFailed,
  partial,
}: {
  readonly open: readonly InboundPromise[];
  readonly done: readonly InboundPromise[] | null;
  readonly doneFailed: boolean;
  readonly partial: boolean;
}) {
  const now = useNow(30_000);
  const all = useMemo(() => {
    const rows = [...open, ...(done ?? [])].filter((x) => stepOf(x) !== null);
    // 오는 순서대로: 도착·수령 중 → 오는 중(도착 예정 빠른 순) → 준비 중 → 받음(최근 받은 것 먼저)
    const rank: Record<PromiseStep, number> = { RECEIVING: 0, GOING: 1, PREP: 2, DONE: 3 };
    const at = (x: InboundPromise) => Date.parse(x.plannedArrivalAt ?? x.departedAt ?? '') || 0;
    return rows.sort((a, b) => rank[stepOf(a)!] - rank[stepOf(b)!] || (stepOf(a) === 'DONE' ? at(b) - at(a) : at(a) - at(b)));
  }, [open, done]);
  const count = (s: PromiseStep) => {
    const xs = all.filter((x) => stepOf(x) === s);
    return { n: xs.length, qty: xs.reduce((a, x) => a + (s === 'DONE' ? receivedOf(x) : qtyOf(x)), 0) };
  };
  return (
    <div className="space-y-5">
      {/* ① 흐름 그림 — DC 에서 이 센터까지 */}
      <ol className="flex flex-col items-stretch gap-2 md:flex-row md:items-center" data-testid="promise-flow">
        {STEPS.map((s, i) => {
          const c = count(s);
          const failed = s === 'DONE' && doneFailed;
          return (
            <Fragment key={s}>
              {i > 0 && (
                <li aria-hidden className="hidden text-2xl text-base-content/30 md:block">
                  →
                </li>
              )}
              <li className={`flex-1 rounded-box border p-4 ${c.n > 0 ? 'border-base-300 bg-base-100' : 'border-dashed border-base-300'}`} data-testid={`promise-step-${s}`}>
                <p className="flex items-center gap-2 text-sm font-semibold">
                  <span aria-hidden className={`inline-block size-2.5 rounded-full ${STEP_COLOR[s]}`} />
                  {t.steps[s]}
                </p>
                <p className="mt-1 text-2xl font-semibold tabular-nums">{failed ? t.failed : t.trfs(c.n)}</p>
                <p className="text-xs text-base-content/60">{failed ? t.doneFailed : s === 'PREP' && c.n === 0 ? t.prepHint : t.stepSub[s](c.qty)}</p>
              </li>
            </Fragment>
          );
        })}
      </ol>
      {partial && (
        <p role="note" className="text-xs text-warning">
          {t.partial}
        </p>
      )}

      {/* ② TRF 마다 한 줄 */}
      {all.length === 0 ? (
        <p className="rounded-box border border-dashed border-base-300 p-6 text-center text-sm text-base-content/60">{t.empty}</p>
      ) : (
        <ul className="divide-y divide-base-300 rounded-box border border-base-300 bg-base-100" data-testid="promise-list">
          {all.map((x) => (
            <PromiseRow key={x.trfId} x={x} now={now} />
          ))}
        </ul>
      )}
    </div>
  );
}

function PromiseRow({ x, now }: { readonly x: InboundPromise; readonly now: number }) {
  const step = stepOf(x)!;
  const [opened, setOpened] = useState(false);
  const lines = x.lines ?? [];
  const qty = qtyOf(x);
  const got = receivedOf(x);
  const minutes = (iso: string | null | undefined) => (iso ? Math.round((Date.parse(iso) - now) / 60_000) : null);
  const eta = minutes(x.eta ?? x.plannedArrivalAt);
  const when =
    step === 'GOING'
      ? eta === null
        ? t.etaUnknown
        : eta >= 0
          ? t.etaIn(eta)
          : t.etaLate(-eta)
      : step === 'RECEIVING'
        ? t.arrivedAgo(Math.max(0, -(minutes(x.arrivedAt) ?? 0)))
        : step === 'DONE'
          ? got < qty
            ? t.receivedShort(got, qty)
            : t.receivedAll(got)
          : x.plannedArrivalAt
            ? t.due(formatSeoul(x.plannedArrivalAt))
            : t.notDeparted;
  return (
    <li data-testid="promise-row" data-step={step}>
      <button
        type="button"
        className="flex w-full flex-wrap items-center gap-x-4 gap-y-1 px-4 py-3 text-left hover:bg-base-200/50"
        aria-expanded={opened}
        onClick={() => setOpened((v) => !v)}
      >
        <Caret open={opened} />
        <span className={`badge badge-sm whitespace-nowrap ${step === 'GOING' ? 'badge-info' : step === 'RECEIVING' ? 'badge-warning' : step === 'DONE' ? 'badge-success' : 'badge-ghost'}`}>{t.steps[step]}</span>
        <span className="font-mono text-sm font-semibold" title={x.trfId}>
          {trfNo(x.trfId)}
        </span>
        <span className="text-sm">{t.rowText(x.fromCdc ?? messages.none, lines.length, qty, (x.packages ?? []).length)}</span>
        <span className={`ml-auto text-sm ${step === 'GOING' && eta !== null && eta < 0 ? 'text-error' : step === 'DONE' && got < qty ? 'text-warning' : 'text-base-content/70'}`} data-testid="promise-when">
          {when}
        </span>
      </button>
      {opened && (
        <div className="border-t border-base-200 bg-base-200/30 px-4 py-3" data-testid="promise-detail">
          <dl className="mb-2 grid grid-cols-2 gap-x-4 gap-y-1 text-xs md:grid-cols-4">
            <dt className="text-base-content/55">{t.departedAt}</dt>
            <dd>{x.departedAt ? formatSeoul(x.departedAt) : messages.none}</dd>
            <dt className="text-base-content/55">{t.plannedArrivalAt}</dt>
            <dd>{x.plannedArrivalAt ? formatSeoul(x.plannedArrivalAt) : messages.none}</dd>
            <dt className="text-base-content/55">{t.arrivedAt}</dt>
            <dd>{x.arrivedAt ? formatSeoul(x.arrivedAt) : messages.none}</dd>
            <dt className="text-base-content/55">{t.trip}</dt>
            <dd className="font-mono">{x.tripId ?? messages.none}</dd>
          </dl>
          <table className="table table-xs">
            <thead>
              <tr>
                <th>{t.col.product}</th>
                <th>{t.col.lot}</th>
                <th className="text-right">{t.col.expected}</th>
                <th className="text-right">{t.col.received}</th>
              </tr>
            </thead>
            <tbody>
              {lines.map((l, i) => (
                <tr key={`${l.sku}-${l.lotId ?? i}`}>
                  <td>
                    {l.productName ?? l.sku}
                    <span className="ml-1 font-mono text-base-content/50">{l.sku}</span>
                  </td>
                  <td className="font-mono">
                    {l.lotId ?? messages.none}
                    {l.expiryDate && <span className="ml-1 text-base-content/50">{t.until(l.expiryDate)}</span>}
                  </td>
                  <td className="text-right tabular-nums">{l.expectedQty ?? 0}</td>
                  <td className="text-right tabular-nums">{step === 'DONE' || step === 'RECEIVING' ? (l.receivedQty ?? 0) : messages.none}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </li>
  );
}
