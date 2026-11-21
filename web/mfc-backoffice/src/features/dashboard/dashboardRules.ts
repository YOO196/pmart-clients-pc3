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

/** 추이 기간 상한(일) — 피킹 지표 92일. 정시 배송(31일)은 31일씩 나눠 읽는다 */
export const MAX_RANGE = 92;
export const ON_TIME_CHUNK = 31;
/** 기간 바 빠른 단추 */
export const RANGE_PRESETS = [7, 14, 30, 90] as const;

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
