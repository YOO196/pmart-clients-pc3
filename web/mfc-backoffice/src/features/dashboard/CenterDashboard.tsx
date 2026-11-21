// 센터 대시보드(사용자 2026-11-21) — 관제실 짜임(참고 corap/mfc-control-tower·mfc-admin): 우선 확인 줄 → 지표 칸 넷(미니 추이) →
// 추이 패널 → 알림 피드·지금 작업·인력 → 결품 상품·배송 상태. 12칸 격자를 본문 폭(컨테이너)으로 다시 놓는다(메뉴를 접거나 창이 좁아져도).
// 원천(모두 기존 계약 — 새 API 없음, 참고 화면의 로봇·UPH 같은 계약에 없는 지표는 넣지 않는다). 원천마다 따로 읽고 실패는 "조회 실패"(0 아님).
// - 피킹 줄·결품률 14일: mfc-fulfillment `GET /metrics/picking-lines`(0건 날짜 줄 없음 = 0줄). 결품률 = shortLines ÷ pickedLines, 분모 0 은 "—".
// - 결품 많은 상품: `/metrics/picking-lines/by-sku?sort=shortLines&limit=5`. 정시 배송률: delivery-dispatch `/metrics/on-time-deliveries`(onTime ÷ due).
// - 작업·인력: 홈과 같은 끝나지 않은 작업·작업자. 배송 상태: bff live-delivery 50건(넘으면 안내).
// - 알림 피드·우선 확인: 홈 원천(useOps — 출하 약속·인계 확인·피킹 파손 사고)과 배차 지연(useDispatchDelays) — 같은 쿼리 키라 두 번 읽지 않는다.
import { useQuery } from '@tanstack/react-query';
import { useState, type ReactNode } from 'react';
import { Link } from 'react-router';

import { request } from '@pmart/web-core';
import { formatSeoul } from '@pmart/web-ui';
import { useApi } from '../../app/ApiContext';
import { centerPath } from '../../app/nav';
import { messages } from '../../shared/messages';
import { useNow } from '../../shared/motion';
import { useDispatchDelays } from '../delivery/DispatchDelayPage';
import { useOps } from '../ops/OpsBoard';
import { OPS_REFRESH_MS } from '../ops/opsQueries';
import { minutesText, promiseRows, seoulToday } from '../ops/opsRules';
import { AreaChart, BarList, type Column } from './charts';
import { FloorMap } from './FloorMap';
import { DAYS, lastDays, rate, rateText, shortDate } from './dashboardRules';

const m = messages.dashboard;
const LIVE_SIZE = 50;
const FEED_ROWS = 5;
const hm = new Intl.DateTimeFormat('ko-KR', { timeZone: 'Asia/Seoul', hour: '2-digit', minute: '2-digit', hour12: false });
const md = new Intl.DateTimeFormat('ko-KR', { timeZone: 'Asia/Seoul', month: 'numeric', day: 'numeric' });
/** 알림 시각 — 오늘이면 "10:06", 아니면 "11/19 09:10"(레퍼런스처럼 짧게) */
const shortAt = (iso: string, today: string) => {
  const t = Date.parse(iso);
  const day = seoulToday(t);
  return day === today ? hm.format(t) : `${md.format(t).replace(/\.\s?/g, '/').replace(/\/$/, '')} ${hm.format(t)}`;
};

function useDashboard(mfcId: string) {
  const api = useApi();
  // 날짜는 1분마다 다시 본다(자정을 넘기면 기간이 하루 밀린다) — 렌더 중 시계를 직접 읽지 않는다
  const nowMs = useNow(OPS_REFRESH_MS);
  const today = seoulToday(nowMs);
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
  const ops = useOps(mfcId);
  const delays = useDispatchDelays(mfcId);
  return { nowMs, today, days, picking, bySku, onTime, workers, live, ops, delays };
}

export function DashboardMenu({ mfcId }: { readonly mfcId: string }) {
  return <Dashboard key={mfcId} mfcId={mfcId} />;
}

type ChartKind = 'picked' | 'shortRate' | 'onTime';

function Dashboard({ mfcId }: { readonly mfcId: string }) {
  const { nowMs, today, days, picking, bySku, onTime, workers, live, ops, delays } = useDashboard(mfcId);
  const { tasks, damages, handovers } = ops;
  const [chart, setChart] = useState<ChartKind>('picked');

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
  const todayOnTimeRate = rate(todayOnTime?.onTime ?? 0, todayOnTime?.due ?? 0);
  const periodOnTime = [...onTimeRow.values()].reduce((a, r) => ({ onTime: a.onTime + r.onTime, due: a.due + r.due }), { onTime: 0, due: 0 });
  const periodPick = [...pickRow.values()].reduce((a, r) => ({ short: a.short + r.shortLines, picked: a.picked + r.pickedLines }), { short: 0, picked: 0 });

  const openTasks = tasks.data?.items ?? [];
  const tasksMore = tasks.data ? !tasks.data.complete : false;
  const blocked = openTasks.filter((t) => t.state === 'BLOCKED').length;
  const waitingN = openTasks.filter((t) => t.state === 'WAITING' || t.state === 'READY').length;
  const runningN = openTasks.filter((t) => t.state === 'ASSIGNED' || t.state === 'IN_PROGRESS').length;
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

  const byState = new Map<string, number>();
  for (const it of live.data?.items ?? []) {
    const s = it.delivery?.state ?? 'UNKNOWN';
    byState.set(s, (byState.get(s) ?? 0) + 1);
  }
  const stateRows = [...byState.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([s, n]) => ({ key: s, label: s === 'UNKNOWN' ? messages.centerDelivery.unknown : (messages.centerDelivery.executionState[s] ?? s), value: n, text: m.count(n) }));

  // 알림 피드 — 서버 값으로 판정한 것만(약속 초과 = 작업 promisedReadyAt, 배차 지연 = 서버 지연 안내, 인계 확인·파손 = 서버 목록)
  const taskNow = tasks.data?.asOf ? Date.parse(tasks.data.asOf) : nowMs;
  const promise = tasks.data ? promiseRows(tasks.data.items, taskNow) : null;
  const feed: FeedItem[] = [
    ...(promise?.rows ?? [])
      .filter((r) => r.kind === 'overdue')
      .map((r) => ({
        key: `p-${r.shipmentId ?? r.task.taskId ?? ''}`,
        tone: 'error' as const,
        title: m.feed.overdue(minutesText(r.minutes)),
        where: m.feed.order(r.orderNumber, messages.tasks.taskType[r.task.taskType ?? ''] ?? ''),
        at: r.promisedAt,
        to: centerPath(mfcId, `tasks/${encodeURIComponent(r.task.taskId ?? '')}`),
      })),
    ...(delays.data ?? []).map((d) => ({
      key: `d-${d.deliveryId}`,
      tone: d.promisedAt && Date.parse(d.promisedAt) <= nowMs ? ('error' as const) : ('warning' as const),
      title: m.feed.delay,
      where: messages.dispatchDelays.state[d.state] ?? d.state,
      at: d.delayAlertedAt,
      to: centerPath(mfcId, 'dispatch-delays'),
    })),
    ...(handovers.data?.items ?? []).map((p) => ({
      key: `h-${p.packageId ?? ''}`,
      tone: 'warning' as const,
      title: m.feed.handover,
      where: m.feed.packingAt(p.packingLocation ?? null),
      at: p.fence?.expiresAt ?? null,
      to: `${centerPath(mfcId, 'tasks')}#handover-checks`,
    })),
    ...(damages.data?.items ?? []).map((i) => ({
      key: `q-${i.incidentId ?? ''}`,
      tone: 'warning' as const,
      title: i.kind === 'SPOILAGE' ? m.feed.spoiled : m.feed.damaged,
      where: m.feed.incident,
      at: i.openedAt ?? null,
      to: `${centerPath(mfcId, 'quality')}?tab=incidents&incidentId=${encodeURIComponent(i.incidentId ?? '')}`,
    })),
  ].sort((a, b) => (a.tone === b.tone ? (b.at ?? '').localeCompare(a.at ?? '') : a.tone === 'error' ? -1 : 1));
  const feedState = { isPending: tasks.isPending && delays.isPending, isError: tasks.isError && delays.isError && handovers.isError && damages.isError };
  const feedPartial = tasks.isError || delays.isError || handovers.isError || damages.isError;

  const asOf = picking.data?.asOf ?? tasks.data?.asOf ?? null;
  const refetchAll = () => [picking, bySku, onTime, workers, live, tasks, damages, handovers, delays].forEach((q) => void q.refetch());

  return (
    <section className="@container space-y-3">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1>{m.title}</h1>
          <p className="mt-1 text-sm text-base-content/60">{asOf ? m.subtitle(formatSeoul(asOf), DAYS) : m.intro(DAYS)}</p>
        </div>
        <button type="button" className="btn btn-sm btn-ghost" onClick={refetchAll}>
          {m.refresh}
        </button>
      </div>

      {/* 우선 확인 — 급한 일 칩, 누르면 그 화면 */}
      <nav className="flex flex-wrap items-center gap-2" aria-label={m.priority.label} data-testid="priority-bar">
        <span className="mr-1 text-xs font-bold text-base-content/60">{m.priority.label}</span>
        <PriorityChip to={`${centerPath(mfcId, 'ops')}?type=promise`} label={m.priority.overdue} n={promise?.overdue} failed={tasks.isError} tone="error" />
        <PriorityChip to={centerPath(mfcId, 'dispatch-delays')} label={m.priority.delays} n={delays.data?.length} failed={delays.isError} tone="error" />
        <PriorityChip to={`${centerPath(mfcId, 'tasks')}#handover-checks`} label={m.priority.handover} n={handovers.data?.items?.length} failed={handovers.isError} tone="warning" />
        <PriorityChip to={`${centerPath(mfcId, 'tasks')}?state=BLOCKED`} label={m.priority.blocked} n={tasks.data ? blocked : undefined} failed={tasks.isError} tone="warning" />
      </nav>

      <div className="grid grid-cols-12 gap-3">
        {/* 지표 칸 넷 — 오늘 */}
        <Kpi
          testId="kpi-picked"
          label={m.kpi.picked}
          icon={ICON.pick}
          q={picking}
          value={m.lines(todayPick?.pickedLines ?? 0)}
          foot={m.kpi.pickedSub(todayPick?.shortLines ?? 0)}
          trend={pickedCols.map((c) => c.value ?? 0)}
        />
        <Kpi
          testId="kpi-short-rate"
          label={m.kpi.shortRate}
          icon={ICON.short}
          q={picking}
          value={rateText(rate(todayPick?.shortLines ?? 0, todayPick?.pickedLines ?? 0))}
          foot={m.kpi.periodRate(DAYS, rateText(rate(periodPick.short, periodPick.picked)))}
          trend={shortCols.map((c) => c.value ?? 0)}
        />
        <Kpi
          testId="kpi-on-time"
          label={m.kpi.onTime}
          icon={ICON.clock}
          q={onTime}
          value={rateText(todayOnTimeRate)}
          foot={todayOnTime ? m.kpi.onTimeSub(todayOnTime.late, todayOnTime.pending) : m.kpi.periodRate(DAYS, rateText(rate(periodOnTime.onTime, periodOnTime.due)))}
          track={todayOnTimeRate}
        />
        <Kpi
          testId="kpi-open-tasks"
          label={m.kpi.openTasks}
          icon={ICON.tasks}
          q={tasks}
          value={tasksMore ? m.atLeast(openTasks.length) : m.count(openTasks.length)}
          trio={[waitingN, runningN, blocked]}
          foot={m.kpi.taskTrio}
          stack={[waitingN, runningN, blocked]}
        />

        {/* 추이 — 피킹 줄·결품률은 한 패널에서 골라 보기(축 하나), 정시 배송은 옆 패널 */}
        <Panel
          className="@5xl:col-span-7"
          title={m.floor.title}
          sub={m.floor.sub}
          q={{ isPending: false, isError: false }}
          aside={
            <Link to={centerPath(mfcId, 'floor')} className="link text-xs">
              {m.floor.openFull}
            </Link>
          }
        >
          <FloorMap mfcId={mfcId} />
        </Panel>
        <Panel
          className="@5xl:col-span-5"
          title={m.chart.trend(DAYS)}
          sub={chart === 'onTime' ? m.chart.onTimeNote : m.chart.pickSub}
          {...(chart === 'onTime' ? { help: m.chart.onTimeHelp } : {})}
          q={chart === 'onTime' ? onTime : picking}
          aside={
            <div className="pm-seg" role="group" aria-label={m.chart.pickToggle}>
              {(['picked', 'shortRate', 'onTime'] as const).map((k) => (
                <button key={k} type="button" aria-pressed={chart === k} onClick={() => setChart(k)}>
                  {k === 'picked' ? m.chart.pickedShort : k === 'shortRate' ? m.chart.shortRateShort : m.chart.onTimeShort}
                </button>
              ))}
            </div>
          }
        >
          {chart === 'onTime' ? (
            <AreaChart title={m.chart.onTime(DAYS)} columns={onTimeCols} format={(v) => rateText(v)} testId="chart-on-time" fixedMax={1} />
          ) : chart === 'picked' ? (
            <AreaChart title={m.chart.picked(DAYS)} columns={pickedCols} format={(v) => m.lines(v)} testId="chart-picked" />
          ) : (
            <AreaChart title={m.chart.shortRate(DAYS)} columns={shortCols} format={(v) => rateText(v)} testId="chart-short-rate" />
          )}
          <SubList title={m.chart.topShort(DAYS)} q={bySku} link={{ to: centerPath(mfcId, 'inventory'), text: m.toInventory }}>
            {(bySku.data?.items ?? []).length === 0 ? (
              <p className="text-sm text-base-content/55">{m.noShort}</p>
            ) : (
              <BarList
                testId="top-short"
                rows={(bySku.data?.items ?? []).map((s) => ({ key: s.sku, label: s.productName ?? s.sku, value: s.shortLines, text: m.shortOf(s.shortLines, s.pickedLines) }))}
              />
            )}
          </SubList>
        </Panel>

        {/* 알림 피드 · 지금 작업과 인력 */}
        <Panel
          className="@4xl:col-span-6"
          title={m.feed.title}
          sub={m.feed.sub}
          q={feedState}
          flush
          aside={
            <Link to={centerPath(mfcId, 'ops')} className="link text-xs">
              {m.feed.toHome}
            </Link>
          }
        >
          {feedPartial && <p className="px-4 pb-2 text-xs text-warning">{m.feed.partial}</p>}
          {feed.length === 0 ? (
            <p className="px-4 pb-4 text-sm text-base-content/55">{m.feed.none}</p>
          ) : (
            <ul data-testid="alert-feed">
              {feed.slice(0, FEED_ROWS).map((f) => (
                <li key={f.key} className="grid min-h-12 grid-cols-[auto_minmax(0,1fr)_auto_auto] items-center gap-3 border-t border-base-300 px-4 py-1.5 transition-colors hover:bg-primary/5" data-testid="alert-feed-row">
                  <span className={`badge ${f.tone === 'error' ? 'badge-error' : 'badge-warning'}`}>{f.tone === 'error' ? m.feed.urgent : m.feed.caution}</span>
                  <div className="min-w-0">
                    <p className="truncate text-sm font-semibold">{f.title}</p>
                    <p className="truncate text-xs text-base-content/60">{f.where}</p>
                  </div>
                  <time className="pm-mono hidden text-xs text-base-content/55 @lg:block" dateTime={f.at ?? undefined} title={f.at ? formatSeoul(f.at) : undefined}>
                    {f.at ? shortAt(f.at, today) : ''}
                  </time>
                  <Link to={f.to} className="btn btn-xs pm-action">
                    {m.feed.action}
                  </Link>
                </li>
              ))}
            </ul>
          )}
          {feed.length > FEED_ROWS && <p className="border-t border-base-300 px-4 py-2 text-xs text-base-content/55">{m.feed.more(feed.length - FEED_ROWS)}</p>}
        </Panel>
        <Panel
          className="@4xl:col-span-6"
          title={m.chart.tasks}
          sub={m.chart.tasksSub}
          q={tasks}
          aside={
            <Link to={centerPath(mfcId, 'tasks')} className="link text-xs">
              {m.toTasks}
            </Link>
          }
        >
          <BarList testId="task-types" rows={typeRows} />
          {tasksMore && <p className="mt-2 text-xs text-warning">{m.tasksMore}</p>}
          <p className="mt-3 mb-2 flex items-baseline justify-between text-sm font-bold">
            {m.chart.people}
            <Link to={centerPath(mfcId, 'workers')} className="link text-xs font-normal">
              {m.toWorkers}
            </Link>
          </p>
          {workers.isError ? (
            <p role="alert" className="text-sm font-semibold text-error">
              {m.failed}
            </p>
          ) : (
            <dl className="grid grid-cols-2 gap-2 text-center @lg:grid-cols-4" data-testid="people">
              <Stat label={m.people.active} value={workers.data ? active.length : null} />
              <Stat label={m.people.working} value={workers.data ? working : null} />
              <Stat label={m.people.onBreak} value={workers.data ? onBreak : null} />
              <Stat label={m.people.idle} value={workers.data ? idle : null} />
            </dl>
          )}
          <SubList title={m.chart.deliveries} q={live} link={{ to: centerPath(mfcId, 'deliveries'), text: m.toDeliveries }}>
            {stateRows.length === 0 ? <p className="text-sm text-base-content/55">{m.noDeliveries}</p> : <BarList testId="delivery-states" rows={stateRows} />}
            {live.data?.truncated && <p className="mt-1 text-xs text-warning">{m.liveTruncated(LIVE_SIZE)}</p>}
          </SubList>

        </Panel>

      </div>
    </section>
  );
}

interface FeedItem {
  readonly key: string;
  readonly tone: 'error' | 'warning';
  readonly title: string;
  readonly where: string;
  readonly at: string | null;
  readonly to: string;
}

interface QueryLike {
  readonly isPending: boolean;
  readonly isError: boolean;
}

const icon = (d: string) => (
  <svg viewBox="0 0 24 24" className="h-4 w-4 fill-none stroke-current" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d={d} />
  </svg>
);
const ICON = {
  pick: icon('M4 7h16M4 12h16M4 17h10'),
  short: icon('M12 9v4M12 17h.01M10.3 3.9 2.4 18a2 2 0 0 0 1.7 3h15.8a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z'),
  clock: icon('M12 7v5l3 2M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z'),
  tasks: icon('M9 4h6M8 6H6v15h12V6h-2M9 12l2 2 4-4'),
};

function PriorityChip({ to, label, n, failed, tone }: { readonly to: string; readonly label: string; readonly n: number | undefined; readonly failed: boolean; readonly tone: 'error' | 'warning' }) {
  const has = (n ?? 0) > 0;
  const cls = failed || !has ? 'badge-ghost' : tone === 'error' ? 'badge-error' : 'badge-warning';
  return (
    <Link to={to} className="btn btn-sm gap-2 font-normal" data-testid="priority-chip">
      {label}
      <span className={`badge badge-sm pm-mono ${cls}`}>{failed ? m.failedShort : n === undefined ? '…' : m.count(n)}</span>
    </Link>
  );
}

/** 지표 칸 — 이름·아이콘 / 큰 숫자 / 아랫줄 / 미니 추이(14일) 또는 진행 막대(0~1) */
function Kpi({
  testId,
  label,
  icon: ic,
  value,
  foot,
  q,
  trend,
  track,
  trio,
  stack,
}: {
  readonly testId: string;
  readonly label: string;
  readonly icon: ReactNode;
  readonly value: string;
  readonly foot: string;
  readonly q: QueryLike;
  readonly trend?: readonly number[];
  readonly track?: number | null;
  /** 세 숫자(레퍼런스 "36 / 24 / 284") — 있으면 큰 숫자 대신. value 는 화면 읽기용 이름에 */
  readonly trio?: readonly [number, number, number];
  /** 세 숫자 비율 막대(대기·진행·막힘) */
  readonly stack?: readonly [number, number, number];
}) {
  const max = Math.max(0, ...(trend ?? []));
  // 숫자와 단위를 나눠 단위는 작게(레퍼런스 "428 UPH") — 글자 전체는 그대로
  const [, num = value, unit = ''] = /^([\d.,—-]+)(.*)$/.exec(value) ?? [];
  return (
    <article className="col-span-12 flex min-h-28 flex-col rounded-box border border-base-300 bg-base-100 px-4 pt-3 pb-3 @md:col-span-6 @5xl:col-span-3" data-testid={testId}>
      <p className="flex items-center justify-between gap-2 text-sm font-semibold text-base-content/80">
        <span className="truncate">{label}</span>
        <span className="grid h-8 w-8 place-items-center rounded-field border border-primary/25 bg-primary/15 text-primary">{ic}</span>
      </p>
      {q.isPending ? (
        <p className="mt-1 text-2xl font-bold text-base-content/40">…</p>
      ) : q.isError ? (
        <p className="mt-1 text-sm font-semibold text-error" data-state="error">
          {m.failed}
        </p>
      ) : (
        <>
          {trio ? (
            <p className="mt-1 flex items-baseline gap-2 text-[30px] leading-tight font-extrabold tracking-[-0.04em] tabular-nums" aria-label={value}>
              <span data-testid={`${testId}-value`} className="sr-only">
                {value}
              </span>
              {trio.map((v, i) => (
                <span key={i} className="flex items-baseline gap-2" aria-hidden="true">
                  {i > 0 && <span className="text-lg font-medium text-base-content/30">/</span>}
                  <span className={i === 2 && v > 0 ? 'text-error' : ''}>{v}</span>
                </span>
              ))}
            </p>
          ) : (
            <p data-testid={`${testId}-value`} className="mt-1 flex items-baseline gap-1.5 text-[31px] leading-tight font-extrabold tracking-[-0.045em] tabular-nums">
              {num}
              {unit && <span className="text-sm font-semibold tracking-normal text-base-content/55">{unit}</span>}
            </p>
          )}
          <p className="truncate text-xs text-base-content/60">{foot}</p>
          {trend && max > 0 && (
            <span className="mt-auto flex h-6 items-end gap-0.5 pt-1" aria-hidden="true">
              {trend.map((v, i) => (
                <i key={i} className={`max-w-3.5 flex-1 rounded-t-sm ${i === trend.length - 1 ? 'bg-primary shadow-[0_0_8px] shadow-primary/50' : 'bg-primary/35'}`} style={{ height: `${v > 0 ? Math.max(8, (v / max) * 100) : 0}%` }} />
              ))}
            </span>
          )}
          {stack && stack.some((v) => v > 0) && (
            <span className="mt-auto flex h-1.5 gap-0.5 overflow-hidden rounded-full" aria-hidden="true">
              <i className="bg-base-content/30" style={{ flexGrow: stack[0] }} />
              <i className="pm-meter-fill" style={{ flexGrow: stack[1] }} />
              <i className="bg-error" style={{ flexGrow: stack[2] }} />
            </span>
          )}
          {track !== undefined && track !== null && (
            <span className="pm-meter-track mt-auto block h-1.5 overflow-hidden rounded-full" aria-hidden="true">
              <b className="pm-meter-fill block h-full rounded-full" style={{ width: `${Math.round(Math.max(0, Math.min(1, track)) * 100)}%` }} />
            </span>
          )}
        </>
      )}
    </article>
  );
}

/** 패널 — 머리(제목·작은 설명·오른쪽 조작) + 본문. 기본은 12칸 전체, 넓으면 className 의 칸 수 */
function Panel({
  title,
  sub,
  aside,
  q,
  help,
  className = '',
  flush = false,
  children,
}: {
  readonly title: string;
  readonly sub?: string;
  /** 설명 전체(마우스를 올리면) — 머리에는 짧은 sub 만 */
  readonly help?: string;
  readonly aside?: ReactNode;
  readonly q: QueryLike;
  readonly className?: string;
  /** 본문 좌우 여백 없이(목록 줄이 패널 끝까지) */
  readonly flush?: boolean;
  readonly children: ReactNode;
}) {
  return (
    <section className={`col-span-12 min-w-0 rounded-box border border-base-300 bg-base-100 ${className}`} aria-label={title}>
      <header className="flex min-h-12 items-center justify-between gap-2 px-4 py-2">
        <div className="min-w-0">
          <h2 className="truncate text-base font-bold tracking-[-0.025em]">{title}</h2>
          {sub && (
            <p className="mt-0.5 truncate text-xs text-base-content/55" title={help ?? sub}>
              {sub}
            </p>
          )}
        </div>
        {aside && <div className="shrink-0">{aside}</div>}
      </header>
      <div className={flush ? 'pb-1' : 'px-4 pb-4'}>
        {q.isPending ? (
          <p className={`text-sm text-base-content/40 ${flush ? 'px-4 pb-3' : ''}`}>…</p>
        ) : q.isError ? (
          <p role="alert" className={`text-sm font-semibold text-error ${flush ? 'px-4 pb-3' : ''}`} data-state="error">
            {m.failed}
          </p>
        ) : (
          children
        )}
      </div>
    </section>
  );
}

function Stat({ label, value }: { readonly label: string; readonly value: number | null }) {
  return (
    <div className="rounded-box bg-base-200/60 px-2 py-3">
      <dt className="text-xs text-base-content/60">{label}</dt>
      <dd className="text-xl font-bold tabular-nums">{value === null ? m.failedShort : value}</dd>
    </div>
  );
}

/** 패널 안 아래 칸(레퍼런스 "구역 진행률"처럼 그림 밑) — 작은 제목·링크 + 자기 원천 상태 */
function SubList({ title, q, link, children }: { readonly title: string; readonly q: QueryLike; readonly link: { readonly to: string; readonly text: string }; readonly children: ReactNode }) {
  return (
    <div className="mt-3 border-t border-base-300 pt-3">
      <p className="mb-2 flex items-baseline justify-between text-sm font-bold">
        {title}
        <Link to={link.to} className="link text-xs font-normal">
          {link.text}
        </Link>
      </p>
      {q.isPending ? (
        <p className="text-sm text-base-content/40">…</p>
      ) : q.isError ? (
        <p role="alert" className="text-sm font-semibold text-error" data-state="error">
          {m.failed}
        </p>
      ) : (
        children
      )}
    </div>
  );
}
