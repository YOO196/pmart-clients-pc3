// 센터 대시보드(사용자 2026-11-21) — 관제실 짜임(참고 corap/mfc-control-tower·mfc-admin): 우선 확인 줄 → 지표 칸 넷(미니 추이) →
// 추이 패널 → 알림 피드·지금 작업·인력 → 결품 상품·배송 상태. 12칸 격자를 본문 폭(컨테이너)으로 다시 놓는다(메뉴를 접거나 창이 좁아져도).
// 원천(모두 기존 계약 — 새 API 없음, 참고 화면의 로봇·UPH 같은 계약에 없는 지표는 넣지 않는다). 원천마다 따로 읽고 실패는 "조회 실패"(0 아님).
// - 피킹 줄·결품률 14일: mfc-fulfillment `GET /metrics/picking-lines`(0건 날짜 줄 없음 = 0줄). 결품률 = shortLines ÷ pickedLines, 분모 0 은 "—".
// - 결품 많은 상품: `/metrics/picking-lines/by-sku?sort=shortLines&limit=5`. 정시 배송률: delivery-dispatch `/metrics/on-time-deliveries`(onTime ÷ due).
// - 작업·인력: 홈과 같은 끝나지 않은 작업·작업자. 배송 상태: bff live-delivery 50건(넘으면 안내).
// - 추이 패널(그래프·결품 많은 상품)은 고른 기간(URL ?from=&to=, 기본 14일, 최대 92일 — 정시 배송은 31일씩 나눠 읽음). 지표 칸은 늘 오늘·14일.
//   칸 단위: 시간(7일까지)·일·주·월. 피킹 줄·결품은 서버가 그 단위로 센다(fulfillment 0.34.0 bucket — 시간 7일·일 92일씩 나눠, 주·월 1년 한 번에).
//   정시율은 날짜 칸만 있어(시간 칸 DD-6 대기) 일 합계를 더하고, 시간은 목 모드에서만 하루 곡선으로 나눠 그림. 최대 1년.
//   그래프를 끌면 그 구간으로 확대, Ctrl+Z 는 한 단계 넓게(1일 → 7일 → 30일 → 90일 → 1년, 지금 기간 가운데 중심).
// - 알림 피드·우선 확인: 홈 원천(useOps — 출하 약속·인계 확인·피킹 파손 사고)과 배차 지연(useDispatchDelays) — 같은 쿼리 키라 두 번 읽지 않는다.
import { useQuery } from '@tanstack/react-query';
import { useEffect, useState, type ReactNode } from 'react';
import { Link, useSearchParams } from 'react-router';

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
import { AreaChart, BarList, Heatmap, type Column, type StackSeries } from './charts';
import { SIM_CATEGORIES, SIM_PRODUCTS, simAt } from './orderSim';
import { FloorMap } from './FloorMap';
import { env } from '../../env';
import {
  addDays,
  buckets,
  presetFrom,
  zoomOut,
  chunks,
  DAYS,
  defaultUnit,
  hourShare,
  lastDays,
  MAX_RANGE,
  ON_TIME_CHUNK,
  PICKING_BUCKET,
  PICKING_CHUNK,
  PICKING_LIMIT,
  pickingKey,
  RANGE_PRESETS,
  rate,
  rateText,
  shortDate,
  spanDays,
  UNITS,
  unitsFor,
  validRange,
  type Bucket,
  type Range,
  type Unit,
} from './dashboardRules';

const m = messages.dashboard;
/** 결품 사유 색 — 범주 색 4개(index.css --pm-cat-1~4, 색약 구분 검사 통과), 상태색(빨강·초록)은 쓰지 않는다 */
const REASON_COLOR = {
  SHORT: 'var(--pm-cat-1)',
  DAMAGED: 'var(--pm-cat-2)',
  SPOILED: 'var(--pm-cat-3)',
  BLOCKED: 'var(--pm-cat-4)',
} as const;
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

type Api = ReturnType<typeof useApi>;
/** 정시 배송 — 계약 상한 31일이라 나눠 읽고 합친다(asOf 는 가장 이른 것) */
async function fetchOnTime(api: Api, mfcId: string, r: Range) {
  const parts = await Promise.all(
    chunks(r, ON_TIME_CHUNK).map((c) => request('GET', api.dispatch.GET('/metrics/on-time-deliveries', { params: { query: { from: c.from, to: c.to, mfcId } } }))),
  );
  return { items: parts.flatMap((x) => x.items ?? []), asOf: parts.map((x) => x.asOf).sort()[0] };
}

/** 피킹 줄 — 서버가 단위(bucket)로 센다. 단위마다 기간 상한(시간 7일·일 92일·주·월 366일)이 있어 넘으면 나눠 읽고 합친다 */
async function fetchPicking(api: Api, mfcId: string, r: Range, unit: Unit) {
  const bucket = PICKING_BUCKET[unit];
  const parts = await Promise.all(
    chunks(r, PICKING_LIMIT[unit]).map((c) => request('GET', api.fulfillment.GET('/metrics/picking-lines', { params: { query: { from: c.from, to: c.to, mfcId, bucket } } }))),
  );
  return { items: parts.flatMap((x) => x.items ?? []), asOf: parts.map((x) => x.asOf).sort()[0] };
}

/** 결품 많은 상품은 기간을 나눠 합칠 수 없다(상위 5 가 조각마다 다름) — 92일을 넘으면 끝날까지 최근 92일 */
const skuRangeOf = (r: Range): Range => (spanDays(r) > PICKING_CHUNK ? { from: addDays(r.to, -(PICKING_CHUNK - 1)), to: r.to } : r);

/** 추이 패널 — 고른 기간 */
function useTrend(mfcId: string, r: Range, unit: Unit) {
  const api = useApi();
  const common = { refetchInterval: OPS_REFRESH_MS } as const;
  const picking = useQuery({ ...common, queryKey: ['dashboard', mfcId, 'picking-lines', r.from, r.to, unit], queryFn: () => fetchPicking(api, mfcId, r, unit) });
  const sr = skuRangeOf(r);
  const bySku = useQuery({
    ...common,
    queryKey: ['dashboard', mfcId, 'by-sku', sr.from, sr.to],
    queryFn: () => request('GET', api.fulfillment.GET('/metrics/picking-lines/by-sku', { params: { query: { from: sr.from, to: sr.to, mfcId, sort: 'shortLines', limit: 5 } } })),
  });
  const onTime = useQuery({ ...common, queryKey: ['dashboard', mfcId, 'on-time', r.from, r.to], queryFn: () => fetchOnTime(api, mfcId, r) });
  return { picking, bySku, onTime };
}

function useDashboard(mfcId: string) {
  const api = useApi();
  // 날짜는 1분마다 다시 본다(자정을 넘기면 기간이 하루 밀린다) — 렌더 중 시계를 직접 읽지 않는다
  const nowMs = useNow(OPS_REFRESH_MS);
  const today = seoulToday(nowMs);
  const days = lastDays(today, DAYS);
  const from = days[0] ?? today;
  const common = { refetchInterval: OPS_REFRESH_MS } as const;
  const picking = useQuery({ ...common, queryKey: ['dashboard', mfcId, 'picking-lines', from, today, 'day'], queryFn: () => fetchPicking(api, mfcId, { from, to: today }, 'day') });
  const onTime = useQuery({ ...common, queryKey: ['dashboard', mfcId, 'on-time', from, today], queryFn: () => fetchOnTime(api, mfcId, { from, to: today }) });
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
  return { nowMs, today, days, picking, onTime, workers, live, ops, delays };
}

export function DashboardMenu({ mfcId }: { readonly mfcId: string }) {
  return <Dashboard key={mfcId} mfcId={mfcId} />;
}

type ChartKind = 'orders' | 'sales' | 'picked' | 'shortRate' | 'onTime';
const KINDS: readonly ChartKind[] = ['orders', 'sales', 'picked', 'shortRate', 'onTime'];

function Dashboard({ mfcId }: { readonly mfcId: string }) {
  const { nowMs, today, days, picking, onTime, workers, live, ops, delays } = useDashboard(mfcId);
  const { tasks, damages, handovers } = ops;
  // 주문·매출은 목에서만(시뮬레이션) — 실서버 기본은 피킹 줄
  const [chart, setChart] = useState<ChartKind>(env.isMock ? 'orders' : 'picked');

  // 추이 기간·칸 단위 — URL(?from=&to=&unit=), 맞지 않으면 기본 14일·일. 바꿀 때마다 앞 상태를 쌓아 Ctrl+Z 로 되돌린다
  const [params, setParams] = useSearchParams();
  // 시간 칸 — 피킹 줄·결품은 서버(0.34.0), 정시율·주문·매출은 목에서만(정시 시간 칸 DD-6 대기, 주문 지표 O-11 대기)
  const hourOk = env.isMock || chart === 'picked' || chart === 'shortRate';
  const range: Range = validRange(params.get('from'), params.get('to'), today) ?? { from: days[0] ?? today, to: today };
  const span = spanDays(range);
  const allowed = unitsFor(span, hourOk);
  const askedUnit = params.get('unit') as Unit | null;
  const unit: Unit = askedUnit && allowed.includes(askedUnit) ? askedUnit : defaultUnit(span, hourOk);
  type View = Range & { readonly unit: Unit };
  const setRange = (next: View) =>
    setParams(
      (p) => {
        const q = new URLSearchParams(p);
        q.set('from', next.from);
        q.set('to', next.to);
        q.set('unit', next.unit);
        return q;
      },
      { replace: true },
    );
  /** 기간을 바꾸면 단위는 그 길이의 기본으로(1일 → 시간, 1년 → 월). 단위만 바꿀 때는 unit 을 준다 */
  const applyRange = (r: Range, u?: Unit) => {
    const next: View = { ...r, unit: u ?? defaultUnit(spanDays(r), hourOk) };
    if (next.from === range.from && next.to === range.to && next.unit === unit) return;
    setRange(next);
  };
  // 한 단계 넓게(1일 → 7일 → 30일 → 90일 → 1년, 지금 기간 가운데 중심) — 앞 상태로 되돌리기가 아니다(사용자 2026-11-21)
  const wider = zoomOut(range, today);
  const widen = () => {
    if (wider) applyRange(wider);
  };
  // Ctrl+Z(⌘Z) = 한 단계 넓게 — 입력칸에서 누른 것은 입력칸 되돌리기로 둔다
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!(e.ctrlKey || e.metaKey) || e.shiftKey || e.key.toLowerCase() !== 'z') return;
      const t = e.target as HTMLElement | null;
      if (t && (t.isContentEditable || ['INPUT', 'TEXTAREA', 'SELECT'].includes(t.tagName))) return;
      if (!wider) return;
      e.preventDefault();
      widen();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });
  const trend = useTrend(mfcId, range, unit);
  const nowHour = Number(new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Seoul', hour: '2-digit', hourCycle: 'h23' }).format(nowMs));
  const tBuckets = buckets(range, unit, today, nowHour);
  // 피킹은 서버가 센 칸(bucket) 그대로 — key 가 칸 key 와 같다
  const tPick = new Map((trend.picking.data?.items ?? []).filter((i) => i.mfcId === mfcId).map((i) => [pickingKey(i, unit), i]));
  const tOnTime = new Map((trend.onTime.data?.items ?? []).filter((i) => i.mfcId === mfcId).map((i) => [i.date, i]));

  // 날짜별 — 피킹은 줄이 없으면 0줄(계약), 정시 배송은 줄이 없으면 due 0(비율 "—")
  const pickRow = new Map((picking.data?.items ?? []).filter((i) => i.mfcId === mfcId).map((i) => [i.date, i]));
  const onTimeRow = new Map((onTime.data?.items ?? []).filter((i) => i.mfcId === mfcId).map((i) => [i.date, i]));
  const pickedCols: Column[] = days.map((d) => {
    const r = pickRow.get(d);
    return { key: d, label: shortDate(d), value: r?.pickedLines ?? 0, tip: m.pickTip(shortDate(d), r?.pickedLines ?? 0, r?.shortLines ?? 0) };
  });
  const shortKpi = days.map((d) => {
    const r = pickRow.get(d);
    return rate(r?.shortLines ?? 0, r?.pickedLines ?? 0) ?? 0;
  });
  // 칸마다 합 — 피킹은 서버 칸 값(줄 없으면 0줄), 정시 배송은 서버 일 합계를 더하고 시간은(목만) 그날 합계를 시간 곡선으로 나눈다
  const sumOf = (b: Bucket) => {
    const p = tPick.get(b.key);
    const acc = { picked: p?.pickedLines ?? 0, short: p?.shortLines ?? 0, onTime: 0, due: 0, late: 0, days: 0 };
    for (let d = b.from; d <= b.to; d = addDays(d, 1)) {
      const o = tOnTime.get(d);
      const last = d === today ? nowHour : 23;
      const part = (v: number) => (b.hour === undefined ? v : hourShare(v, b.hour, last));
      acc.onTime += part(o?.onTime ?? 0);
      acc.due += part(o?.due ?? 0);
      acc.late += part(o?.late ?? 0);
      acc.days += 1;
    }
    return acc;
  };
  const sums = tBuckets.map((b) => ({ b, t: sumOf(b) }));
  const tipLabel = (b: Bucket) => (b.hour !== undefined ? `${shortDate(b.from)} ${b.hour}시` : b.from === b.to ? shortDate(b.from) : `${b.label} (${shortDate(b.from)}–${shortDate(b.to)})`);
  const tPickedCols: Column[] = sums.map(({ b, t }) => ({ key: b.key, label: b.label, value: t.picked, tip: m.pickTip(tipLabel(b), t.picked, t.short) }));
  // 결품 — 사유별 쌓은 막대(드문 사건이라 비율 선보다 "몇 줄·왜"). 사유 합은 결품 줄보다 클 수 있다(계약)
  const REASONS = ['SHORT', 'DAMAGED', 'SPOILED', 'BLOCKED'] as const;
  const reasonSeries: StackSeries[] = REASONS.map((k) => ({ key: k, name: m.chart.reason[k], color: REASON_COLOR[k] }));
  const reasonVals = tBuckets.map((b) => REASONS.map((k) => tPick.get(b.key)?.shortLinesByReason[k] ?? 0));
  const shortBarCols: Column[] = tBuckets.map((b, i) => {
    const vals = reasonVals[i]!;
    const total = vals.reduce((a, c) => a + c, 0);
    const parts = REASONS.map((k, j) => (vals[j]! > 0 ? `${m.chart.reason[k]} ${vals[j]}` : '')).filter(Boolean).join(' · ');
    return { key: b.key, label: b.label, value: total, tip: m.chart.shortBarTip(tipLabel(b), parts, total) };
  });
  const periodShort = sums.reduce((a, { t }) => ({ s: a.s + t.short, p: a.p + t.picked }), { s: 0, p: 0 });

  // 주문·매출(목 시뮬레이션) — 카테고리·상품 거르기는 URL(?cat=&sku=)
  const cat = params.get('cat');
  const sku = params.get('sku');
  const product = SIM_PRODUCTS.find((x) => x.sku === sku) ?? null;
  const filter = { category: product ? null : cat, sku: product?.sku ?? null };
  const setFilter = (next: { readonly cat?: string | null; readonly sku?: string | null }) =>
    setParams(
      (p) => {
        const q = new URLSearchParams(p);
        for (const [k, v] of Object.entries(next)) {
          if (v) q.set(k, v);
          else q.delete(k);
        }
        return q;
      },
      { replace: true },
    );
  const ordersView = chart === 'orders' || chart === 'sales';
  const simOn = hourOk && ordersView;
  const simSum = (b: Bucket) => {
    const acc = { orders: 0, amount: 0 };
    for (let d = b.from; d <= b.to; d = addDays(d, 1)) {
      const hours = b.hour !== undefined ? [b.hour] : Array.from({ length: d === today ? nowHour + 1 : 24 }, (_, h) => h);
      for (const h of hours) {
        const v = simAt(d, h, filter);
        acc.orders += v.orders;
        acc.amount += v.amount;
      }
    }
    return acc;
  };
  const simCols: Column[] = simOn
    ? tBuckets.map((b) => {
        const v = simSum(b);
        return chart === 'sales'
          ? { key: b.key, label: b.label, value: v.amount, tip: m.chart.salesTip(tipLabel(b), v.amount) }
          : { key: b.key, label: b.label, value: v.orders, tip: product ? m.chart.qtyTip(tipLabel(b), v.orders) : m.chart.orderTip(tipLabel(b), v.orders) };
      })
    : [];
  // 요일 × 시간 평균(그 기간에 그 요일이 몇 번 있었나로 나눔)
  const heat = (() => {
    if (!simOn) return null;
    const sum = Array.from({ length: 7 }, () => Array.from({ length: 24 }, () => 0));
    const seen = Array.from({ length: 7 }, () => Array.from({ length: 24 }, () => 0));
    for (let d = range.from; d <= range.to; d = addDays(d, 1)) {
      const wd = (new Date(`${d}T00:00:00Z`).getUTCDay() + 6) % 7;
      for (let h = 0; h < (d === today ? nowHour + 1 : 24); h++) {
        const v = simAt(d, h, filter);
        sum[wd]![h]! += chart === 'sales' ? v.amount : v.orders;
        seen[wd]![h]! += 1;
      }
    }
    return sum.map((row, wd) => row.map((v, h) => (seen[wd]![h]! > 0 ? Math.round(v / seen[wd]![h]!) : 0)));
  })();
  const topSold = simOn
    ? SIM_PRODUCTS.filter((x) => !cat || x.category === cat)
        .map((x) => {
          let qty = 0;
          let amount = 0;
          for (let d = range.from; d <= range.to; d = addDays(d, 1))
            for (let h = 0; h < (d === today ? nowHour + 1 : 24); h++) {
              const v = simAt(d, h, { sku: x.sku });
              qty += v.orders;
              amount += v.amount;
            }
          return { x, qty, amount };
        })
        .sort((a, b) => (chart === 'sales' ? b.amount - a.amount : b.qty - a.qty))
        .slice(0, 5)
    : [];
  const won = (v: number) => (v >= 10_000 ? `${Math.round(v / 10_000).toLocaleString('ko-KR')}만원` : `${v.toLocaleString('ko-KR')}원`);

  const onTimeCols: Column[] = sums.map(({ b, t }) => {
    const v = rate(t.onTime, t.due);
    return { key: b.key, label: b.label, value: v, tip: m.onTimeTip(tipLabel(b), rateText(v), t.onTime, t.due, t.late) };
  });

  // 끌어서 고른 칸 → 첫 칸 시작일 ~ 끝 칸 끝날(시간 칸이면 그날). 하루 안이면 그날 시간대별로
  const zoom = (fromKey: string, toKey: string) => {
    const a = tBuckets.find((b) => b.key === fromKey);
    const z = tBuckets.find((b) => b.key === toKey);
    if (a && z) applyRange({ from: a.from, to: z.to });
  };

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
  const refetchAll = () => [picking, trend.picking, trend.bySku, trend.onTime, onTime, workers, live, tasks, damages, handovers, delays].forEach((q) => void q.refetch());

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
          trend={shortKpi}
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
          title={m.chart.trend(shortDate(range.from), shortDate(range.to), span, m.range.unit[unit])}
          sub={
            chart === 'onTime'
              ? m.chart.onTimeNote
              : ordersView
                ? m.chart.ordersSub
                : chart === 'shortRate'
                  ? m.chart.shortSub(rateText(rate(periodShort.s, periodShort.p)))
                  : m.chart.pickSub
          }
          {...(chart === 'onTime' ? { help: m.chart.onTimeHelp } : {})}
          q={chart === 'onTime' ? trend.onTime : ordersView ? { isPending: false, isError: false } : trend.picking}
          toolbar={
            <RangeBar range={range} unit={unit} units={allowed} hourOk={hourOk} today={today} canBack={wider !== null} onChange={applyRange} onBack={widen} />
          }
          aside={
            <div className="pm-seg" role="group" aria-label={m.chart.pickToggle}>
              {KINDS.map((k) => (
                <button key={k} type="button" aria-pressed={chart === k} onClick={() => setChart(k)}>
                  {
                    {
                      orders: m.chart.ordersShort,
                      sales: m.chart.salesShort,
                      picked: m.chart.pickedShort,
                      shortRate: m.chart.shortRateShort,
                      onTime: m.chart.onTimeShort,
                    }[k]
                  }
                </button>
              ))}
            </div>
          }
        >
          {/* key 에 기간 — 기간이 바뀌면 새로 그려 가로축에서 다시 차오른다 */}
          {ordersView ? (
            !simOn ? (
              <p role="status" className="rounded-field border border-dashed border-base-300 p-4 text-sm text-base-content/65" data-testid="orders-no-api">
                {m.chart.ordersNoApi}
              </p>
            ) : (
              <>
                <div className="mb-2 flex flex-wrap items-center gap-1.5" data-testid="orders-filter">
                  <span className="badge badge-accent badge-sm">{m.chart.simBadge}</span>
                  <select
                    className="select select-xs w-auto"
                    aria-label={m.chart.category}
                    value={product ? product.category : (cat ?? '')}
                    onChange={(e) => setFilter({ cat: e.target.value || null, sku: null })}
                  >
                    <option value="">{m.chart.allCategories}</option>
                    {SIM_CATEGORIES.map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.name}
                      </option>
                    ))}
                  </select>
                  <select className="select select-xs w-auto max-w-[11rem]" aria-label={m.chart.product} value={sku ?? ''} onChange={(e) => setFilter({ sku: e.target.value || null })}>
                    <option value="">{m.chart.allProducts}</option>
                    {SIM_PRODUCTS.filter((x) => !(product ? product.category : cat) || x.category === (product ? product.category : cat)).map((x) => (
                      <option key={x.sku} value={x.sku}>
                        {x.name}
                      </option>
                    ))}
                  </select>
                </div>
                <AreaChart
                  key={`${chart}-${range.from}-${range.to}-${unit}-${cat ?? ''}-${sku ?? ''}`}
                  title={chart === 'sales' ? m.chart.sales(span) : m.chart.orders(span)}
                  columns={simCols}
                  format={(v) => (chart === 'sales' ? won(v) : product ? `${v.toLocaleString('ko-KR')}개` : m.count(v))}
                  testId={chart === 'sales' ? 'chart-sales' : 'chart-orders'}
                  onRange={zoom}
                />
              </>
            )
          ) : chart === 'onTime' ? (
            <AreaChart key={`o-${range.from}-${range.to}-${unit}`} title={m.chart.onTime(span)} columns={onTimeCols} format={(v) => rateText(v)} testId="chart-on-time" fixedMax={1} onRange={zoom} />
          ) : chart === 'picked' ? (
            <AreaChart key={`p-${range.from}-${range.to}-${unit}`} title={m.chart.picked(span)} columns={tPickedCols} format={(v) => m.lines(v)} testId="chart-picked" onRange={zoom} />
          ) : (
            <AreaChart
              key={`s-${range.from}-${range.to}-${unit}`}
              title={m.chart.shortBars(span)}
              columns={shortBarCols}
              format={(v) => m.lines(Math.round(v))}
              testId="chart-short"
              onRange={zoom}
              stack={{ series: reasonSeries, values: reasonVals }}
            />
          )}
          {ordersView ? (
            heat && (
              <div className="mt-4 space-y-4 border-t border-base-300 pt-3">
                <Heatmap title={m.chart.heatTitle(chart === 'sales' ? m.chart.salesShort : m.chart.ordersShort)} cells={heat} format={(v) => (chart === 'sales' ? won(v) : m.count(v))} testId="order-heat" />
                <div>
                  <p className="mb-1.5 flex items-baseline justify-between text-xs">
                    <span className="font-semibold text-base-content/80">{m.chart.topSold(span)}</span>
                    <span className="text-base-content/45">{m.chart.topSoldHint}</span>
                  </p>
                  <ul className="space-y-1" data-testid="top-sold">
                    {topSold.map(({ x, qty, amount }) => (
                      <li key={x.sku}>
                        <button
                          type="button"
                          className={`grid w-full grid-cols-[1fr_auto] items-center gap-2 rounded-field px-1.5 py-0.5 text-left text-sm transition-colors hover:bg-primary/8 ${sku === x.sku ? 'bg-primary/12' : ''}`}
                          aria-pressed={sku === x.sku}
                          onClick={() => setFilter({ sku: sku === x.sku ? null : x.sku, cat: null })}
                          data-testid="top-sold-row"
                        >
                          <span className="truncate">{x.name}</span>
                          <span className="pm-mono text-xs text-base-content/70">
                            {qty.toLocaleString('ko-KR')}개 · {won(amount)}
                          </span>
                        </button>
                      </li>
                    ))}
                  </ul>
                </div>
              </div>
            )
          ) : (
          <SubList title={m.chart.topShort(spanDays(skuRangeOf(range)))} q={trend.bySku} link={{ to: centerPath(mfcId, 'inventory'), text: m.toInventory }}>
            {(trend.bySku.data?.items ?? []).length === 0 ? (
              <p className="text-sm text-base-content/55">{m.noShort}</p>
            ) : (
              <BarList
                testId="top-short"
                rows={(trend.bySku.data?.items ?? []).map((s) => ({ key: s.sku, label: s.productName ?? s.sku, value: s.shortLines, text: m.shortOf(s.shortLines, s.pickedLines) }))}
              />
            )}
          </SubList>
          )}
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
/** 추이 기간 바 — 빠른 단추(오늘까지 n일)·시작일·끝일·이전 기간 */
function RangeBar({
  range,
  unit,
  units,
  hourOk,
  today,
  canBack,
  onChange,
  onBack,
}: {
  readonly range: Range;
  readonly unit: Unit;
  readonly units: readonly Unit[];
  readonly hourOk: boolean;
  readonly today: string;
  readonly canBack: boolean;
  readonly onChange: (r: Range, u?: Unit) => void;
  readonly onBack: () => void;
}) {
  const r = m.range;
  const [error, setError] = useState<string | null>(null);
  const pick = (from: string, to: string) => {
    const ok = validRange(from, to, today);
    if (!ok) {
      setError(from && to && from <= to && to <= today ? r.tooLong(MAX_RANGE) : r.bad);
      return;
    }
    setError(null);
    onChange(ok);
  };
  return (
    <div className="mb-2 space-y-1" data-testid="range-bar">
      <div className="flex flex-wrap items-center gap-1.5">
        <div className="pm-seg" role="group" aria-label={r.label}>
          {RANGE_PRESETS.map((n) => (
            <button key={n} type="button" aria-pressed={range.to === today && range.from === presetFrom(n, today)} onClick={() => pick(presetFrom(n, today), today)}>
              {n === 365 ? r.year : r.days(n)}
            </button>
          ))}
        </div>
        <div className="pm-seg" role="group" aria-label={r.unitLabel}>
          {UNITS.map((u) => (
            <button
              key={u}
              type="button"
              aria-pressed={unit === u}
              disabled={!units.includes(u)}
              title={u === 'hour' && !hourOk ? r.hourNoApi : !units.includes(u) ? r.unitNotFit : undefined}
              className="disabled:cursor-not-allowed disabled:opacity-35"
              onClick={() => onChange(range, u)}
            >
              {r.unit[u]}
            </button>
          ))}
        </div>
        <input
          type="date"
          className="input input-xs pm-mono w-[8.6rem]"
          aria-label={r.from}
          value={range.from}
          max={range.to}
          onChange={(e) => {
            if (e.target.value) pick(e.target.value, range.to);
          }}
        />
        <span className="text-xs text-base-content/45">–</span>
        <input
          type="date"
          className="input input-xs pm-mono w-[8.6rem]"
          aria-label={r.to}
          value={range.to}
          min={range.from}
          max={today}
          onChange={(e) => {
            if (e.target.value) pick(range.from, e.target.value);
          }}
        />
      </div>
      <div className="flex min-h-6 items-center justify-between gap-2">
        {error ? (
          <p role="alert" className="text-xs text-error">
            {error}
          </p>
        ) : (
          <p className="truncate text-[11px] text-base-content/45">{r.hint}</p>
        )}
        <button type="button" className="btn btn-xs btn-ghost shrink-0" disabled={!canBack} onClick={onBack} title={r.backHint} data-testid="range-back">
          ⤢ {r.back}
        </button>
      </div>
    </div>
  );
}

function Panel({
  title,
  sub,
  aside,
  q,
  help,
  className = '',
  flush = false,
  toolbar,
  children,
}: {
  /** 머리 아래, 읽는 중·실패와 상관없이 늘 보이는 줄(예: 기간 바) */
  readonly toolbar?: ReactNode;
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
      {toolbar && <div className="px-4">{toolbar}</div>}
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
