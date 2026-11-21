// 센터 대시보드(사용자 2026-11-21 "mfc 프론트에 센터 현황 대시보드") — 홈(예외 처리)과 달리 센터를 숫자·추이로 한눈에.
// 원천(모두 기존 계약 — 새 API 없음). 원천마다 따로 읽어 하나가 실패해도 나머지는 보이고, 실패는 0 이 아니라 "조회 실패".
// - 피킹 줄·결품률 14일: mfc-fulfillment `GET /metrics/picking-lines?from&to&mfcId`(0.19.0). 0건 날짜는 줄 없음(계약) → 그날 0줄.
//   결품률 = shortLines ÷ pickedLines(서버 지표와 같은 분자·분모 — bff SHORTAGE_RATE 정의). 분모 0 이면 "—"(BO-28 분모 0 은 N/A).
// - 결품 많은 상품 14일 상위 5: `GET /metrics/picking-lines/by-sku?sort=shortLines&limit=5`(0.32.0).
// - 정시 배송률 14일: delivery-dispatch `GET /metrics/on-time-deliveries?from&to&mfcId`(0.13.0 DD-4) — onTime ÷ due(전달 확인 못 한 unjudged·약속 전 pending 은 분모 밖).
// - 지금 작업: 홈과 같은 끝나지 않은 작업 조회(useOpenTasks — 같은 쿼리 키라 두 번 읽지 않음).
// - 인력: capacity `GET /mfcs/{mfcId}/workers?state=ACTIVE` — 휴게 중(onBreak), 일하는 중 = 끝나지 않은 작업을 맡은 사람.
// - 배송 상태: bff live-delivery(상태를 비우면 끝나지 않은 배송 최대 50건 — 넘으면 truncated → "50건 이상"으로).
import { useQuery } from '@tanstack/react-query';
import type { ReactNode } from 'react';
import { Link } from 'react-router';

import { request } from '@pmart/web-core';
import { formatSeoul } from '@pmart/web-ui';
import { useApi } from '../../app/ApiContext';
import { centerPath } from '../../app/nav';
import { messages } from '../../shared/messages';
import { useNow } from '../../shared/motion';
import { OPS_REFRESH_MS, useOpenTasks } from '../ops/opsQueries';
import { seoulToday } from '../ops/opsRules';
import { BarList, ColumnChart, type Column } from './charts';
import { DAYS, lastDays, rate, rateText, shortDate } from './dashboardRules';

const m = messages.dashboard;
const LIVE_SIZE = 50;

function useDashboard(mfcId: string) {
  const api = useApi();
  // 날짜는 1분마다 다시 본다(자정을 넘기면 기간이 하루 밀린다) — 렌더 중 시계를 직접 읽지 않는다
  const today = seoulToday(useNow(OPS_REFRESH_MS));
  const days = lastDays(today, DAYS);
  const from = days[0] ?? today;
  const common = { refetchInterval: OPS_REFRESH_MS } as const;
  const picking = useQuery({
    ...common,
    queryKey: ['dashboard', mfcId, 'picking-lines', from, today],
    queryFn: () => request('GET', api.fulfillment.GET('/metrics/picking-lines', { params: { query: { from, to: today, mfcId } } })),
  });
  const bySku = useQuery({
    ...common,
    queryKey: ['dashboard', mfcId, 'by-sku', from, today],
    queryFn: () => request('GET', api.fulfillment.GET('/metrics/picking-lines/by-sku', { params: { query: { from, to: today, mfcId, sort: 'shortLines', limit: 5 } } })),
  });
  const onTime = useQuery({
    ...common,
    queryKey: ['dashboard', mfcId, 'on-time', from, today],
    queryFn: () => request('GET', api.dispatch.GET('/metrics/on-time-deliveries', { params: { query: { from, to: today, mfcId } } })),
  });
  const workers = useQuery({
    ...common,
    queryKey: ['dashboard', mfcId, 'workers'],
    queryFn: async () => (await request('GET', api.capacity.GET('/mfcs/{mfcId}/workers', { params: { path: { mfcId }, query: { state: 'ACTIVE' } } }))).items ?? [],
  });
  const live = useQuery({
    ...common,
    queryKey: ['dashboard', mfcId, 'live-delivery'],
    queryFn: () => request('GET', api.bff.GET('/views/live-delivery', { params: { query: { mfcId, size: LIVE_SIZE } } })),
  });
  const tasks = useOpenTasks(mfcId);
  return { today, days, picking, bySku, onTime, workers, live, tasks };
}

export function DashboardMenu({ mfcId }: { readonly mfcId: string }) {
  return <Dashboard key={mfcId} mfcId={mfcId} />;
}

function Dashboard({ mfcId }: { readonly mfcId: string }) {
  const { today, days, picking, bySku, onTime, workers, live, tasks } = useDashboard(mfcId);

  // 날짜별 — 피킹은 줄이 없으면 0줄(계약), 정시 배송은 줄이 없으면 due 0(비율 "—")
  const pickRow = new Map((picking.data?.items ?? []).filter((i) => i.mfcId === mfcId).map((i) => [i.date, i]));
  const onTimeRow = new Map((onTime.data?.items ?? []).filter((i) => i.mfcId === mfcId).map((i) => [i.date, i]));
  const pickedCols: Column[] = days.map((d) => {
    const r = pickRow.get(d);
    return { key: d, label: shortDate(d), value: r?.pickedLines ?? 0, tip: m.pickTip(shortDate(d), r?.pickedLines ?? 0, r?.shortLines ?? 0) };
  });
  const shortCols: Column[] = days.map((d) => {
    const r = pickRow.get(d);
    const v = rate(r?.shortLines ?? 0, r?.pickedLines ?? 0);
    return { key: d, label: shortDate(d), value: v, tip: m.shortTip(shortDate(d), rateText(v), r?.shortLines ?? 0, r?.pickedLines ?? 0) };
  });
  const onTimeCols: Column[] = days.map((d) => {
    const r = onTimeRow.get(d);
    const v = rate(r?.onTime ?? 0, r?.due ?? 0);
    return { key: d, label: shortDate(d), value: v, tip: m.onTimeTip(shortDate(d), rateText(v), r?.onTime ?? 0, r?.due ?? 0, r?.late ?? 0) };
  });

  const todayPick = pickRow.get(today);
  const todayOnTime = onTimeRow.get(today);
  const periodOnTime = [...onTimeRow.values()].reduce((a, r) => ({ onTime: a.onTime + r.onTime, due: a.due + r.due }), { onTime: 0, due: 0 });
  const periodPick = [...pickRow.values()].reduce((a, r) => ({ short: a.short + r.shortLines, picked: a.picked + r.pickedLines }), { short: 0, picked: 0 });

  const openTasks = tasks.data?.items ?? [];
  const tasksMore = tasks.data ? !tasks.data.complete : false;
  const blocked = openTasks.filter((t) => t.state === 'BLOCKED').length;
  const typeRows = (['PICK', 'PACK', 'DISPATCH', 'RETURN'] as const).map((type) => {
    const list = openTasks.filter((t) => t.taskType === type);
    const b = list.filter((t) => t.state === 'BLOCKED').length;
    return { key: type, label: messages.tasks.taskType[type] ?? type, value: list.length, text: b > 0 ? m.withBlocked(list.length, b) : m.count(list.length) };
  });

  const active = workers.data ?? [];
  const busyIds = new Set(openTasks.map((t) => t.assignment?.workerId).filter((id): id is string => !!id));
  const onBreak = active.filter((w) => w.onBreak).length;
  const working = active.filter((w) => !w.onBreak && w.workerId && busyIds.has(w.workerId)).length;
  const idle = active.length - onBreak - working;

  const liveItems = live.data?.items ?? [];
  const byState = new Map<string, number>();
  for (const it of liveItems) {
    const s = it.delivery?.state ?? 'UNKNOWN';
    byState.set(s, (byState.get(s) ?? 0) + 1);
  }
  const stateRows = [...byState.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([s, n]) => ({ key: s, label: s === 'UNKNOWN' ? messages.centerDelivery.unknown : (messages.centerDelivery.executionState[s] ?? s), value: n, text: m.count(n) }));

  const asOf = picking.data?.asOf ?? tasks.data?.asOf ?? null;
  const refetchAll = () => [picking, bySku, onTime, workers, live, tasks].forEach((q) => void q.refetch());

  return (
    <section className="space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">{m.title}</h1>
          <p className="text-sm text-base-content/60">{asOf ? m.subtitle(formatSeoul(asOf), DAYS) : m.intro(DAYS)}</p>
        </div>
        <button type="button" className="btn btn-sm btn-ghost" onClick={refetchAll}>
          {m.refresh}
        </button>
      </div>

      {/* 숫자 칸 넷 — 오늘 */}
      <div className="grid grid-cols-2 gap-px overflow-hidden rounded-box border border-base-300 bg-base-300 lg:grid-cols-4">
        <Kpi testId="kpi-picked" label={m.kpi.picked} q={picking} value={m.lines(todayPick?.pickedLines ?? 0)} sub={m.kpi.pickedSub(todayPick?.shortLines ?? 0)} />
        <Kpi
          testId="kpi-short-rate"
          label={m.kpi.shortRate}
          q={picking}
          value={rateText(rate(todayPick?.shortLines ?? 0, todayPick?.pickedLines ?? 0))}
          sub={m.kpi.periodRate(DAYS, rateText(rate(periodPick.short, periodPick.picked)))}
        />
        <Kpi
          testId="kpi-on-time"
          label={m.kpi.onTime}
          q={onTime}
          value={rateText(rate(todayOnTime?.onTime ?? 0, todayOnTime?.due ?? 0))}
          sub={todayOnTime ? m.kpi.onTimeSub(todayOnTime.late, todayOnTime.pending) : m.kpi.periodRate(DAYS, rateText(rate(periodOnTime.onTime, periodOnTime.due)))}
        />
        <Kpi testId="kpi-open-tasks" label={m.kpi.openTasks} q={tasks} value={tasksMore ? m.atLeast(openTasks.length) : m.count(openTasks.length)} sub={m.kpi.blocked(blocked)} />
      </div>

      {/* 14일 추이 — 한 그림에 한 숫자(축 하나) */}
      <div className="grid gap-4 lg:grid-cols-3">
        <Card title={m.chart.picked(DAYS)} q={picking}>
          <ColumnChart title={m.chart.picked(DAYS)} columns={pickedCols} format={(v) => m.lines(v)} testId="chart-picked" />
        </Card>
        <Card title={m.chart.shortRate(DAYS)} q={picking}>
          <ColumnChart title={m.chart.shortRate(DAYS)} columns={shortCols} format={(v) => rateText(v)} testId="chart-short-rate" />
        </Card>
        <Card title={m.chart.onTime(DAYS)} q={onTime} note={m.chart.onTimeNote}>
          <ColumnChart title={m.chart.onTime(DAYS)} columns={onTimeCols} format={(v) => rateText(v)} testId="chart-on-time" />
        </Card>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card title={m.chart.topShort(DAYS)} q={bySku} link={{ to: centerPath(mfcId, 'inventory'), text: m.toInventory }}>
          {(bySku.data?.items ?? []).length === 0 ? (
            <p className="text-sm text-base-content/55">{m.noShort}</p>
          ) : (
            <BarList
              testId="top-short"
              rows={(bySku.data?.items ?? []).map((s) => ({
                key: s.sku,
                label: s.productName ?? s.sku,
                value: s.shortLines,
                text: m.shortOf(s.shortLines, s.pickedLines),
              }))}
            />
          )}
        </Card>
        <Card title={m.chart.tasks} q={tasks} link={{ to: centerPath(mfcId, 'tasks'), text: m.toTasks }}>
          <BarList testId="task-types" rows={typeRows} />
          {tasksMore && <p className="mt-2 text-xs text-warning">{m.tasksMore}</p>}
        </Card>
        <Card title={m.chart.people} q={workers} link={{ to: centerPath(mfcId, 'workers'), text: m.toWorkers }}>
          <dl className="grid grid-cols-4 gap-2 text-center" data-testid="people">
            <Stat label={m.people.active} value={active.length} />
            <Stat label={m.people.working} value={tasks.isError ? null : working} />
            <Stat label={m.people.onBreak} value={onBreak} />
            <Stat label={m.people.idle} value={tasks.isError ? null : idle} />
          </dl>
          <p className="mt-2 text-xs text-base-content/55">{m.people.note}</p>
        </Card>
        <Card title={m.chart.deliveries} q={live} link={{ to: centerPath(mfcId, 'deliveries'), text: m.toDeliveries }}>
          {stateRows.length === 0 ? <p className="text-sm text-base-content/55">{m.noDeliveries}</p> : <BarList testId="delivery-states" rows={stateRows} />}
          {live.data?.truncated && <p className="mt-2 text-xs text-warning">{m.liveTruncated(LIVE_SIZE)}</p>}
        </Card>
      </div>
    </section>
  );
}

interface QueryLike {
  readonly isPending: boolean;
  readonly isError: boolean;
}

function Kpi({ testId, label, value, sub, q }: { readonly testId: string; readonly label: string; readonly value: string; readonly sub: string; readonly q: QueryLike }) {
  return (
    <div className="bg-base-100 px-5 py-4" data-testid={testId}>
      <p className="truncate text-sm text-base-content/70">{label}</p>
      {q.isPending ? (
        <p className="mt-0.5 text-2xl font-bold text-base-content/40">…</p>
      ) : q.isError ? (
        <p className="mt-0.5 text-sm font-semibold text-error" data-state="error">
          {m.failed}
        </p>
      ) : (
        <>
          <p data-testid={`${testId}-value`} className="mt-0.5 text-[26px] font-semibold leading-tight tracking-tight tabular-nums">
            {value}
          </p>
          <p className="mt-0.5 truncate text-xs text-base-content/55">{sub}</p>
        </>
      )}
    </div>
  );
}

function Card({ title, q, note, link, children }: { readonly title: string; readonly q: QueryLike; readonly note?: string; readonly link?: { readonly to: string; readonly text: string }; readonly children: ReactNode }) {
  return (
    <section className="space-y-3 rounded-box border border-base-300 bg-base-100 p-4" aria-label={title}>
      <div className="flex items-baseline justify-between gap-2">
        <h2 className="font-bold">{title}</h2>
        {link && (
          <Link to={link.to} className="link text-xs">
            {link.text}
          </Link>
        )}
      </div>
      {q.isPending ? (
        <p className="text-sm text-base-content/40">…</p>
      ) : q.isError ? (
        <p role="alert" className="text-sm font-semibold text-error" data-state="error">
          {m.failed}
        </p>
      ) : (
        children
      )}
      {note && <p className="text-xs text-base-content/50">{note}</p>}
    </section>
  );
}

function Stat({ label, value }: { readonly label: string; readonly value: number | null }) {
  return (
    <div className="rounded-box bg-base-200/60 px-2 py-3">
      <dt className="text-xs text-base-content/60">{label}</dt>
      <dd className="text-xl font-semibold tabular-nums">{value === null ? m.failedShort : value}</dd>
    </div>
  );
}
