// 센터 대시보드 계산 — 날짜 목록·비율(표시만, 판정은 서버 지표 정의 그대로).

/** 추이 기간(일) — 지표 원천 상한(결품 92일·정시 배송 31일) 안 */
export const DAYS = 14;

/** today(YYYY-MM-DD, 한국 날짜)까지 n 일 — 오래된 날 먼저 */
export function lastDays(today: string, n: number): string[] {
  const base = Date.parse(`${today}T00:00:00Z`);
  return Array.from({ length: n }, (_, i) => new Date(base - (n - 1 - i) * 86_400_000).toISOString().slice(0, 10));
}

/** 분모 0 이면 null(N/A — 0% 가 아니다) */
export const rate = (num: number, den: number): number | null => (den > 0 ? num / den : null);

export const rateText = (v: number | null) => (v === null ? '—' : `${(Math.round(v * 1000) / 10).toFixed(1)}%`);

/** 2026-11-21 → 11/21 */
export const shortDate = (d: string) => `${Number(d.slice(5, 7))}/${Number(d.slice(8, 10))}`;

/** 추이 기간 상한(일) — 1년. 서버 상한(피킹 92일·정시 배송 31일)은 나눠 읽어 합친다 */
export const MAX_RANGE = 366;
export const PICKING_CHUNK = 92;
/** 피킹 지표 칸 단위(mfc-fulfillment 0.34.0 bucket)와 단위마다 한 번에 읽는 기간 상한(HOUR 7일·DAY 92일·WEEK·MONTH 366일) */
export const PICKING_BUCKET = { hour: 'HOUR', day: 'DAY', week: 'WEEK', month: 'MONTH' } as const;
export const PICKING_LIMIT: Readonly<Record<Unit, number>> = { hour: 7, day: PICKING_CHUNK, week: 366, month: 366 };

/** 피킹 지표 줄 → 그 단위 칸 key(buckets 의 key 와 같은 모양). HOUR 는 hour(+09:00 시작 시각)의 "YYYY-MM-DDTHH", 주는 월요일, 달은 YYYY-MM */
export function pickingKey(row: { readonly date: string; readonly hour?: string | null }, unit: Unit): string {
  if (unit === 'hour') return row.hour ? row.hour.slice(0, 13) : `${row.date}T00`;
  if (unit === 'month') return row.date.slice(0, 7);
  return row.date;
}
export const ON_TIME_CHUNK = 31;
/** 기간 바 빠른 단추(일) — 1년 = 365 */
export const RANGE_PRESETS = [1, 7, 30, 90, 365] as const;

export interface Range {
  readonly from: string;
  readonly to: string;
}

/** 날짜 + n 일 */
export const addDays = (d: string, n: number) => new Date(Date.parse(`${d}T00:00:00Z`) + n * 86_400_000).toISOString().slice(0, 10);

/** from~to(포함) 날짜 목록 */
export function daysIn(r: Range): string[] {
  const out: string[] = [];
  for (let d = r.from; d <= r.to; d = addDays(d, 1)) out.push(d);
  return out;
}

export const spanDays = (r: Range) => daysIn(r).length;

/** 날짜 형식·순서·오늘 이후·상한을 본 기간, 맞지 않으면 null */
export function validRange(from: string | null, to: string | null, today: string): Range | null {
  const iso = /^\d{4}-\d{2}-\d{2}$/;
  if (!from || !to || !iso.test(from) || !iso.test(to) || Number.isNaN(Date.parse(from)) || Number.isNaN(Date.parse(to))) return null;
  if (from > to || to > today) return null;
  if (spanDays({ from, to }) > MAX_RANGE) return null;
  return { from, to };
}

/** n 일씩 나눈 조각(정시 배송 31일 상한) */
export function chunks(r: Range, n: number): Range[] {
  const out: Range[] = [];
  for (let f = r.from; f <= r.to; f = addDays(f, n)) {
    const t = addDays(f, n - 1);
    out.push({ from: f, to: t < r.to ? t : r.to });
  }
  return out;
}

/** 그래프 한 칸의 단위 */
export type Unit = 'hour' | 'day' | 'week' | 'month';
export const UNITS: readonly Unit[] = ['hour', 'day', 'week', 'month'];

/** 기간 길이에 쓸 수 있는 단위 — 시간은 7일까지, 주는 14일부터, 월은 60일부터. hourOk = 그 지표에 시간 칸이 있는가(정시율은 아직 없음 — 목에서만) */
export function unitsFor(span: number, hourOk: boolean): Unit[] {
  return UNITS.filter((u) => (u === 'hour' ? hourOk && span <= 7 : u === 'week' ? span >= 14 : u === 'month' ? span >= 60 : true));
}

/** 기간 길이의 기본 단위 — 1일 시간, 31일까지 일, 그 위 주(2026-11-24 사용자 — 90일 일별은 요일 톱니가 심함), 1년 가까이 월. 단위는 바꿀 수 있다 */
export function defaultUnit(span: number, hourOk: boolean): Unit {
  if (span <= 1) return hourOk ? 'hour' : 'day';
  if (span <= 31) return 'day';
  return span >= 300 ? 'month' : 'week';
}

/** 주·월 칸이 기간 끝에 잘려 며칠만 들었나 — { days, full }, 다 들었거나 일·시간 칸이면 null */
export function partialOf(b: { readonly from: string; readonly to: string; readonly hour?: number }, unit: Unit): { readonly days: number; readonly full: number } | null {
  if (unit !== 'week' && unit !== 'month') return null;
  const days = daysIn(b).length;
  const full = unit === 'week' ? 7 : new Date(Date.UTC(Number(b.from.slice(0, 4)), Number(b.from.slice(5, 7)), 0)).getUTCDate();
  return days < full ? { days, full } : null;
}

export interface Bucket {
  readonly key: string;
  /** 포함 날짜(기간 밖은 잘라 낸다) */
  readonly from: string;
  readonly to: string;
  readonly label: string;
  /** 시간 단위일 때 시(0–23) */
  readonly hour?: number;
}

const weekday = (d: string) => (new Date(`${d}T00:00:00Z`).getUTCDay() + 6) % 7; // 월요일 0

/** 기간을 단위 칸으로 나눈다(오래된 칸 먼저). 시간 단위는 오늘이면 지금 시각까지만 */
export function buckets(r: Range, unit: Unit, today: string, nowHour: number): Bucket[] {
  const days = daysIn(r);
  const multiYear = r.from.slice(0, 4) !== r.to.slice(0, 4);
  if (unit === 'hour') {
    const single = days.length === 1;
    return days.flatMap((d) =>
      Array.from({ length: d === today ? nowHour + 1 : 24 }, (_, h) => ({
        key: `${d}T${String(h).padStart(2, '0')}`,
        from: d,
        to: d,
        hour: h,
        label: single ? `${h}시` : `${shortDate(d)} ${h}시`,
      })),
    );
  }
  if (unit === 'day') return days.map((d) => ({ key: d, from: d, to: d, label: shortDate(d) }));
  const out: Bucket[] = [];
  for (const d of days) {
    const key = unit === 'week' ? addDays(d, -weekday(d)) : d.slice(0, 7);
    const last = out.at(-1);
    if (last?.key === key) out[out.length - 1] = { ...last, to: d };
    else {
      const [y, mo] = [Number(d.slice(0, 4)), Number(d.slice(5, 7))];
      const label = unit === 'week' ? `${shortDate(key)}주` : multiYear ? `${y % 100}년 ${mo}월` : `${mo}월`;
      out.push({ key, from: d, to: d, label });
    }
  }
  return out;
}

/** 목 모드 시간대별(정시 배송은 서버 시간 칸이 없음 DD-6, 피킹 목도 같은 곡선) — 그날 합계를 하루 수요 곡선으로 나눈다. 시간 합 = 그날 합 */
const HOUR_WEIGHT = [0, 0, 0, 0, 0, 0, 1, 3, 5, 6, 7, 9, 10, 8, 6, 6, 7, 9, 11, 12, 10, 7, 4, 1];
export function hourShare(total: number, hour: number, lastHour: number): number {
  if (total === 0) return 0;
  const w = HOUR_WEIGHT.slice(0, lastHour + 1);
  const sum = w.reduce((a, b) => a + b, 0);
  // 새벽(곡선이 아직 0)이면 합계를 지금 시각 칸에 — 버리면 시간 합 ≠ 그날 합
  if (sum === 0) return hour === lastHour ? total : 0;
  // 가장 큰 나머지 방식 — 정수로 나눠도 합이 total
  const raw = w.map((x) => (total * x) / sum);
  const base = raw.map(Math.floor);
  let left = total - base.reduce((a, b) => a + b, 0);
  const order = raw.map((x, i) => [x - Math.floor(x), i] as const).sort((a, b) => b[0] - a[0] || a[1] - b[1]);
  for (const [, i] of order) {
    if (left <= 0) break;
    base[i]! += 1;
    left -= 1;
  }
  return base[hour] ?? 0;
}

/** 빠른 단추의 시작일 — n 일 전부터, 1년은 11달 전 1일부터(월별 첫 칸이 반 토막 나지 않게, 이번 달만 지금까지) */
export function presetFrom(n: number, today: string): string {
  if (n !== 365) return addDays(today, -(n - 1));
  const y = Number(today.slice(0, 4));
  const mo = Number(today.slice(5, 7)) - 11;
  const [yy, mm] = mo <= 0 ? [y - 1, mo + 12] : [y, mo];
  return `${yy}-${String(mm).padStart(2, '0')}-01`;
}

/**
 * 한 단계 넓게(Ctrl+Z) — 지금 기간보다 큰 다음 단계(1일 → 7일 → 30일 → 90일 → 1년), 지금 기간 가운데를 중심으로.
 * 끝이 오늘을 넘으면 오늘에 붙인다(1년이 오늘에 붙으면 빠른 단추 1년과 같게). 이미 1년 단추만큼 넓으면 null.
 */
export function zoomOut(r: Range, today: string): Range | null {
  // 1년 단추(11달 전 1일부터 ≈ 334~365일)보다 길면 끝
  if (spanDays(r) >= spanDays({ from: presetFrom(365, today), to: today })) return null;
  const n = RANGE_PRESETS.find((p) => p > spanDays(r)) ?? 365;
  const mid = addDays(r.from, Math.floor((spanDays(r) - 1) / 2));
  let from = addDays(mid, -Math.floor((n - 1) / 2));
  let to = addDays(from, n - 1);
  if (to >= today) {
    to = today;
    from = presetFrom(n, today);
  }
  return { from, to };
}
