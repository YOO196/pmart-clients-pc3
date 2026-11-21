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
