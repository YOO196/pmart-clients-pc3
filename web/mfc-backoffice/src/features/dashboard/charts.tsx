// 대시보드 그림 — 한 계열 세로 막대(날짜별)·가로 막대(항목별). 색은 daisyUI primary 하나(계열이 하나라 범례 없이 제목이 이름).
// - 얇은 막대·끝 둥글게(4px)·막대 사이 2px, 격자·축은 흐리게. 값 글자는 글자색(계열 색 아님).
// - 막대마다 마우스·키보드 초점에 말풍선(tip). 값이 없는 날(분모 0 — 비율을 낼 수 없음)은 막대 없이 "—" 표시(0 과 구분).
// - 그림 아래 "표로 보기"(같은 숫자 표).
import { useState } from 'react';

import { messages } from '../../shared/messages';

const m = messages.dashboard;

export interface Column {
  readonly key: string;
  /** 축 글자(예 11/21) */
  readonly label: string;
  /** null = 값을 낼 수 없음(0 이 아님) */
  readonly value: number | null;
  /** 말풍선·표 한 줄 */
  readonly tip: string;
}

export function ColumnChart({ title, columns, format, testId }: { readonly title: string; readonly columns: readonly Column[]; readonly format: (v: number) => string; readonly testId: string }) {
  const [hover, setHover] = useState<number | null>(null);
  const max = Math.max(0, ...columns.map((c) => c.value ?? 0));
  const shown = hover === null ? null : columns[hover];
  const ticks = new Set([0, Math.floor((columns.length - 1) / 2), columns.length - 1]);
  return (
    <figure className="space-y-2" data-testid={testId}>
      <div className="relative">
        <div className="flex items-baseline justify-between text-xs text-base-content/50">
          <span>{max > 0 ? m.maxLabel(format(max)) : ''}</span>
          <span className="min-h-4 text-base-content/80" aria-live="polite" data-testid={`${testId}-tip`}>
            {shown ? shown.tip : ''}
          </span>
        </div>
        <div className="mt-1 flex h-36 items-end gap-0.5 border-b border-base-content/20" role="img" aria-label={title} onMouseLeave={() => setHover(null)}>
          {columns.map((c, i) => {
            const pct = c.value === null || c.value === 0 || max === 0 ? 0 : Math.max(2, (c.value / max) * 100);
            return (
              <button
                key={c.key}
                type="button"
                className="group flex h-full min-w-0 flex-1 flex-col items-center justify-end focus:outline-none"
                aria-label={c.tip}
                onMouseEnter={() => setHover(i)}
                onFocus={() => setHover(i)}
                onBlur={() => setHover(null)}
                data-testid={`${testId}-col`}
              >
                {c.value === null ? (
                  <span className="mb-1 text-xs text-base-content/35">—</span>
                ) : (
                  <span
                    className={`w-full max-w-7 rounded-t bg-primary transition-opacity ${hover !== null && hover !== i ? 'opacity-45' : ''} group-focus-visible:ring-2 group-focus-visible:ring-primary/40`}
                    style={{ height: `${pct}%` }}
                  />
                )}
              </button>
            );
          })}
        </div>
        <div className="mt-1 flex gap-0.5 text-[11px] text-base-content/50">
          {columns.map((c, i) => (
            <span key={c.key} className="min-w-0 flex-1 text-center">
              {ticks.has(i) ? c.label : ''}
            </span>
          ))}
        </div>
      </div>
      <details className="text-xs">
        <summary className="cursor-pointer text-base-content/60">{m.asTable}</summary>
        <ul className="mt-1 space-y-0.5 text-base-content/75">
          {columns.map((c) => (
            <li key={c.key}>{c.tip}</li>
          ))}
        </ul>
      </details>
    </figure>
  );
}

export interface BarRow {
  readonly key: string;
  readonly label: string;
  readonly value: number;
  /** 값 옆 글자(예 "3건 · 막힘 1") */
  readonly text: string;
}

/** 가로 막대 목록 — 항목 이름 | 막대 | 숫자 */
export function BarList({ rows, testId }: { readonly rows: readonly BarRow[]; readonly testId: string }) {
  const max = Math.max(0, ...rows.map((r) => r.value));
  return (
    <ul className="space-y-1.5" data-testid={testId}>
      {rows.map((r) => (
        <li key={r.key} className="grid grid-cols-[7rem_1fr_auto] items-center gap-2 text-sm" data-testid={`${testId}-row`}>
          <span className="truncate text-base-content/75" title={r.label}>
            {r.label}
          </span>
          <span className="pm-meter-track h-2 overflow-hidden rounded-full">
            <span className="pm-meter-fill block h-full rounded-full" style={{ width: `${max === 0 || r.value === 0 ? 0 : Math.max(2, (r.value / max) * 100)}%` }} />
          </span>
          <span className="text-right text-xs tabular-nums">{r.text}</span>
        </li>
      ))}
    </ul>
  );
}

/**
 * 영역 그림(레퍼런스 "시간대별 처리량" — 보라 그라데이션 영역 + 선 + 마우스 십자선·말풍선). 한 계열·축 하나.
 * 값이 없는 날(null)은 선을 끊고 "—"(0 과 구분). 날짜 칸마다 단추(마우스·키보드 초점에 말풍선), 아래 "표로 보기".
 */
export function AreaChart({
  title,
  columns,
  format,
  testId,
  fixedMax,
}: {
  readonly title: string;
  readonly columns: readonly Column[];
  readonly format: (v: number) => string;
  readonly testId: string;
  /** 비율처럼 축 끝이 정해진 값(예 1 = 100%) */
  readonly fixedMax?: number;
}) {
  const [hover, setHover] = useState<number | null>(null);
  const n = columns.length;
  const max = Math.max(0, ...columns.map((c) => c.value ?? 0));
  // 눈금 끝은 보기 좋은 수(1·2·2.5·5 × 10ⁿ)로 올림 — 비율은 fixedMax(1 = 100%)
  const nice = (v: number) => {
    const p = 10 ** Math.floor(Math.log10(v));
    return ([1, 2, 2.5, 5, 10].find((k) => k * p >= v) ?? 10) * p;
  };
  const top = fixedMax ?? (max > 0 ? nice(max * 1.08) : 1);
  const W = 600;
  const H = 180;
  const x = (i: number) => ((i + 0.5) / n) * W;
  const y = (v: number) => H - (v / top) * H;
  // null 에서 끊긴 조각들
  const segs: Array<Array<readonly [number, number]>> = [[]];
  columns.forEach((c, i) => {
    if (c.value === null) segs.push([]);
    else segs[segs.length - 1]!.push([x(i), y(c.value)]);
  });
  const parts = segs.filter((p) => p.length > 0);
  const line = (p: ReadonlyArray<readonly [number, number]>) => p.map(([px, py], k) => `${k ? 'L' : 'M'}${px.toFixed(1)},${py.toFixed(1)}`).join('');
  const area = (p: ReadonlyArray<readonly [number, number]>) => (p.length > 1 ? `${line(p)}L${p[p.length - 1]![0].toFixed(1)},${H}L${p[0]![0].toFixed(1)},${H}Z` : '');
  const shown = hover === null ? null : columns[hover];
  const gid = `pm-area-${testId}`;
  const ticks = new Set([0, Math.floor((n - 1) / 2), n - 1]);
  return (
    <figure className="space-y-2" data-testid={testId}>
      <div className="flex items-baseline justify-end text-xs text-base-content/55">
        <span className="min-h-4 tabular-nums text-base-content/85" aria-live="polite" data-testid={`${testId}-tip`}>
          {shown ? shown.tip : ''}
        </span>
      </div>
      <div className="relative ml-12 h-40" onMouseLeave={() => setHover(null)}>
        {/* 세로 눈금(0 · 중간 · 끝) */}
        {[0, 0.5, 1].map((g) => (
          <span key={g} className="pm-mono pointer-events-none absolute -left-12 w-11 -translate-y-1/2 truncate text-right text-[10.5px] text-base-content/45" style={{ top: `${(1 - g) * 100}%` }}>
            {format(top * g)}
          </span>
        ))}
        <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" className="absolute inset-0 h-full w-full overflow-visible text-primary" role="img" aria-label={title}>
          <defs>
            <linearGradient id={gid} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0" stopColor="currentColor" stopOpacity="0.5" />
              <stop offset="1" stopColor="currentColor" stopOpacity="0" />
            </linearGradient>
          </defs>
          {[0, 0.5].map((g) => (
            <line key={g} x1="0" x2={W} y1={H * g} y2={H * g} className="stroke-base-content/10" strokeWidth="1" vectorEffect="non-scaling-stroke" />
          ))}
          <line x1="0" x2={W} y1={H} y2={H} className="stroke-base-content/25" strokeWidth="1" vectorEffect="non-scaling-stroke" />
          {parts.map((p, k) => (
            <path key={`a${k}`} d={area(p)} fill={`url(#${gid})`} />
          ))}
          {parts.map((p, k) => (
            <path key={`g${k}`} d={line(p)} fill="none" stroke="currentColor" strokeOpacity="0.3" strokeWidth="6" vectorEffect="non-scaling-stroke" />
          ))}
          {parts.map((p, k) => (
            <path key={`l${k}`} d={line(p)} fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinejoin="round" vectorEffect="non-scaling-stroke" />
          ))}
        </svg>
        {/* 십자선·점(HTML — 늘어난 SVG 위에서도 둥글게) */}
        {shown && shown.value !== null && hover !== null && (
          <>
            <span className="pointer-events-none absolute inset-y-0 w-px border-l border-dashed border-primary/60" style={{ left: `${((hover + 0.5) / n) * 100}%` }} />
            <span
              className="pointer-events-none absolute h-2.5 w-2.5 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-base-100 bg-primary shadow-[0_0_10px] shadow-primary/60"
              style={{ left: `${((hover + 0.5) / n) * 100}%`, top: `${(y(shown.value) / H) * 100}%` }}
            />
          </>
        )}
        <div className="absolute inset-0 flex">
          {columns.map((c, i) => (
            <button
              key={c.key}
              type="button"
              className="flex min-w-0 flex-1 items-end justify-center pb-1 focus:outline-none"
              aria-label={c.tip}
              onMouseEnter={() => setHover(i)}
              onFocus={() => setHover(i)}
              onBlur={() => setHover(null)}
              data-testid={`${testId}-col`}
            >
              {c.value === null && <span className="text-xs text-base-content/35">—</span>}
            </button>
          ))}
        </div>
      </div>
      <div className="pm-mono ml-12 flex text-[11px] text-base-content/50">
        {columns.map((c, i) => (
          <span key={c.key} className="min-w-0 flex-1 text-center">
            {ticks.has(i) ? c.label : ''}
          </span>
        ))}
      </div>
      <details className="text-xs">
        <summary className="cursor-pointer text-base-content/60">{m.asTable}</summary>
        <ul className="mt-1 space-y-0.5 tabular-nums text-base-content/75">
          {columns.map((c) => (
            <li key={c.key}>{c.tip}</li>
          ))}
        </ul>
      </details>
    </figure>
  );
}
