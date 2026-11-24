// 대시보드 그림 — 한 계열 세로 막대(날짜별)·가로 막대(항목별). 색은 daisyUI primary 하나(계열이 하나라 범례 없이 제목이 이름).
// - 얇은 막대·끝 둥글게(4px)·막대 사이 2px, 격자·축은 흐리게. 값 글자는 글자색(계열 색 아님).
// - 막대마다 마우스·키보드 초점에 말풍선(tip). 값이 없는 날(분모 0 — 비율을 낼 수 없음)은 막대 없이 "—" 표시(0 과 구분).
// - 그림 아래 "표로 보기"(같은 숫자 표).
import { Fragment, useState, type PointerEvent } from 'react';

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
  /** 기간 끝이 잘려 며칠만 든 칸(주·월) — 막대를 옅게(2026-11-24 사용자) */
  readonly partial?: boolean;
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
export function BarList({ rows, testId, cols = 1 }: { readonly rows: readonly BarRow[]; readonly testId: string; readonly cols?: 1 | 2 }) {
  const max = Math.max(0, ...rows.map((r) => r.value));
  return (
    <ul className={cols === 2 ? 'grid gap-x-6 gap-y-1.5 @lg:grid-cols-2' : 'space-y-1.5'} data-testid={testId}>
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
/** 세로 눈금 글자 — 만 넘는 수는 "1.2만줄"처럼 줄여 칸에서 잘리지 않게(말풍선·표는 원래 숫자) */
const compact = new Intl.NumberFormat('ko-KR', { notation: 'compact', maximumFractionDigits: 1 });
function axisText(format: (v: number) => string, v: number) {
  const full = format(v);
  // 이미 줄인 글자(예 매출 "50만원")는 그대로 — 다시 줄이면 "50만만원"
  if (v < 10_000 || /[\d.]\s*[만억]/.test(full)) return full;
  return full.replace(/[\d,.]+/, compact.format(v));
}

/** 쌓은 막대 계열(예: 결품 사유) — 색은 테마 변수, 범례를 늘 함께 */
export interface StackSeries {
  readonly key: string;
  readonly name: string;
  readonly color: string;
}

export function AreaChart({
  title,
  columns,
  format,
  testId,
  fixedMax,
  onRange,
  stack,
  rate,
  compare,
}: {
  readonly title: string;
  readonly columns: readonly Column[];
  readonly format: (v: number) => string;
  readonly testId: string;
  /** 비율처럼 축 끝이 정해진 값(예 1 = 100%) */
  readonly fixedMax?: number;
  /** 끌어서 고른 구간(첫·끝 칸의 key) — 주면 그래프를 끌어 확대할 수 있다 */
  readonly onRange?: (fromKey: string, toKey: string) => void;
  /** 주면 영역 대신 쌓은 막대(칸마다 계열 값, 합 = column.value) — 드문 사건(결품)처럼 선보다 "몇 건"이 읽히는 값 */
  readonly stack?: { readonly series: readonly StackSeries[]; readonly values: readonly (readonly number[])[] };
  /**
   * 비율 모양(정시율, 2026-11-24 사용자 "정시율 그래프 저게 최선?") — 면 없이 선·점, 세로축은 값 근처~100%로 좁히고,
   * 기간 평균을 점선으로. 값이 없는 칸(셀 배송 없음)은 바닥 "—" 대신 그 칸을 옅게 칠한다
   */
  readonly rate?: { readonly avg: number | null; readonly avgLabel: string };
  /** 지난 기간(바로 앞 같은 길이) — 칸 순서대로 맞춘 값, 옅은 점선(2026-11-24 사용자 "비교 기준") */
  readonly compare?: { readonly values: readonly (number | null)[]; readonly label: string };
}) {
  const [hover, setHover] = useState<number | null>(null);
  // 끌기: 누른 자리(a)부터 지금 자리(b)까지 — 판 폭 비율(0–1)로 따라가 띠가 픽셀 단위로 부드럽게 움직이고, 놓을 때 칸에 맞춘다
  const [drag, setDrag] = useState<{ readonly a: number; readonly b: number; readonly px: number } | null>(null);
  const n = columns.length;
  const canDrag = !!onRange && n > 1;
  const fracAt = (e: PointerEvent<HTMLElement>) => {
    const r = e.currentTarget.getBoundingClientRect();
    return { f: Math.min(1, Math.max(0, (e.clientX - r.left) / (r.width || 1))), w: r.width || 1 };
  };
  const colOf = (f: number) => Math.min(n - 1, Math.max(0, Math.floor(f * n)));
  const fLo = drag ? Math.min(drag.a, drag.b) : 0;
  const fHi = drag ? Math.max(drag.a, drag.b) : 0;
  const lo = colOf(fLo);
  const hi = colOf(fHi);
  // 6px 넘게 끌어야 고르기(그냥 누름과 구분). 한 칸 안이어도 끌었으면 그 칸 하나(예: 하루 → 그날 시간별)
  const dragging = drag !== null && (fHi - fLo) * drag.px > 6;
  const max = Math.max(0, ...columns.map((c) => c.value ?? 0), ...(compare?.values ?? []).map((v) => v ?? 0));
  // 건수는 칸이 적으면(31칸까지) 막대 — 하루하루 따로 떨어진 값. 많으면 면 없는 선(2026-11-24 사용자 "등고선 그래프가 최선이니?")
  const asBars = !rate && !stack && n <= 31;

  // 눈금 끝은 보기 좋은 수(1·2·2.5·5 × 10ⁿ)로 올림 — 비율은 fixedMax(1 = 100%)
  const nice = (v: number) => {
    const p = 10 ** Math.floor(Math.log10(v));
    return ([1, 2, 2.5, 5, 10].find((k) => k * p >= v) ?? 10) * p;
  };
  const top = rate ? 1 : (fixedMax ?? (max > 0 ? nice(max * 1.08) : 1));
  // 비율 모양: 바닥 = 가장 낮은 값(평균 포함)보다 조금 아래를 5% 단위로 내림
  const rateVals = columns.flatMap((c) => (c.value === null ? [] : [c.value]));
  const bottom = rate && rateVals.length > 0 ? Math.max(0, Math.floor((Math.min(...rateVals, rate.avg ?? 1) - 0.03) * 20) / 20) : 0;
  const W = 600;
  const H = 180;
  const x = (i: number) => ((i + 0.5) / n) * W;
  const y = (v: number) => H - ((v - bottom) / (top - bottom || 1)) * H;
  // null 에서 끊긴 조각들
  const segs: Array<Array<readonly [number, number]>> = [[]];
  columns.forEach((c, i) => {
    if (c.value === null) segs.push([]);
    else segs[segs.length - 1]!.push([x(i), y(c.value)]);
  });
  const parts = segs.filter((p) => p.length > 0);
  const line = (p: ReadonlyArray<readonly [number, number]>) => p.map(([px, py], k) => `${k ? 'L' : 'M'}${px.toFixed(1)},${py.toFixed(1)}`).join('');
  // 지난 기간 — null 에서 끊긴 조각
  const cSegs: Array<Array<readonly [number, number]>> = [[]];
  (compare?.values ?? []).forEach((v, i) => {
    if (i >= n) return;
    if (v === null) cSegs.push([]);
    else cSegs[cSegs.length - 1]!.push([x(i), y(v)]);
  });
  const cParts = cSegs.filter((p) => p.length > 0);
  const shown = hover === null ? null : columns[hover];
  const shownPrev = hover === null ? undefined : compare?.values[hover];
  const ticks = new Set([0, Math.floor((n - 1) / 2), n - 1]);
  return (
    <figure className="space-y-2" data-testid={testId}>
      <div className="flex items-baseline justify-between gap-2 text-xs text-base-content/55">
        {stack ? (
          <span className="flex flex-wrap gap-x-3 gap-y-0.5" data-testid={`${testId}-legend`}>
            {stack.series.map((sr) => (
              <span key={sr.key} className="inline-flex items-center gap-1">
                <span className="h-2 w-2 rounded-[2px]" style={{ background: sr.color }} aria-hidden="true" />
                {sr.name}
              </span>
            ))}
          </span>
        ) : compare ? (
          <span className="flex flex-wrap gap-x-3 gap-y-0.5" data-testid={`${testId}-legend`}>
            <span className="inline-flex items-center gap-1">
              <span className="h-2 w-2 rounded-[2px] bg-primary" aria-hidden="true" />
              {m.thisPeriod}
            </span>
            <span className="inline-flex items-center gap-1">
              <span className="w-3 border-t border-dashed border-base-content/50" aria-hidden="true" />
              {compare.label}
            </span>
          </span>
        ) : (
          <span />
        )}
        <span className="min-h-4 tabular-nums text-base-content/85" aria-live="polite" data-testid={`${testId}-tip`}>
          {dragging
            ? lo === hi
              ? m.zoomOne(columns[lo]!.label)
              : m.zoomTip(columns[lo]!.label, columns[hi]!.label, hi - lo + 1)
            : shown
              ? `${shown.tip}${compare && shownPrev !== undefined && shownPrev !== null ? ` · ${m.prevShort} ${format(shownPrev)}` : ''}`
              : ''}
        </span>
      </div>
      <div
        className={`relative ml-12 h-32 ${canDrag ? 'cursor-crosshair touch-none select-none' : ''}`}
        onMouseLeave={() => setHover(null)}
        {...(canDrag
          ? {
              onPointerDown: (e: PointerEvent<HTMLDivElement>) => {
                if (e.button !== 0) return;
                e.currentTarget.setPointerCapture(e.pointerId);
                const { f, w } = fracAt(e);
                setDrag({ a: f, b: f, px: w });
              },
              onPointerMove: (e: PointerEvent<HTMLDivElement>) => {
                if (!drag) return;
                const { f } = fracAt(e);
                setHover(colOf(f));
                setDrag({ ...drag, b: f });
              },
              onPointerUp: () => {
                if (dragging) onRange?.(columns[lo]!.key, columns[hi]!.key);
                setDrag(null);
              },
              onPointerCancel: () => setDrag(null),
            }
          : {})}
        data-testid={`${testId}-plot`}
      >
        {/* 세로 눈금(0 · 중간 · 끝) */}
        {[0, 0.5, 1].map((g) => (
          <span key={g} className="pm-mono pointer-events-none absolute -left-12 w-11 -translate-y-1/2 truncate text-right text-[10.5px] text-base-content/45" style={{ top: `${(1 - g) * 100}%` }}>
            {axisText(format, bottom + (top - bottom) * g)}
          </span>
        ))}
        <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" className="absolute inset-0 h-full w-full overflow-visible text-primary" role="img" aria-label={title}>
          {[0, 0.5].map((g) => (
            <line key={g} x1="0" x2={W} y1={H * g} y2={H * g} className="stroke-base-content/10" strokeWidth="1" vectorEffect="non-scaling-stroke" />
          ))}
          <line x1="0" x2={W} y1={H} y2={H} className="stroke-base-content/25" strokeWidth="1" vectorEffect="non-scaling-stroke" />
          {/* 처음 그릴 때·기간을 바꿀 때: 가로축에 납작하게 붙었다가 위로 차오른다(움직임 줄이기면 바로) */}
          <g className="pm-chart-rise">
          {stack &&
            stack.values.map((vals, i) => {
              const slot = W / n;
              const gap = Math.min(slot * 0.18, 4);
              let acc = 0;
              return (
                <g key={`b${i}`} opacity={(columns[i]?.partial ? 0.45 : 1) * (hover !== null && hover !== i ? 0.5 : 1)}>
                  {vals.map((v, k) => {
                    if (v <= 0) return null;
                    const y0 = y(acc);
                    acc += v;
                    return <rect
                        key={k}
                        x={i * slot + gap / 2}
                        width={slot - gap}
                        y={y(acc)}
                        height={Math.max(0, y0 - y(acc))}
                        style={{ fill: stack.series[k]?.color }}
                        className="stroke-base-100"
                        strokeWidth="1.5"
                        vectorEffect="non-scaling-stroke"
                      />;
                  })}
                </g>
              );
            })}
          {asBars &&
            columns.map((c, i) => {
              if (c.value === null || c.value <= 0) return null;
              const slot = W / n;
              const gap = Math.min(slot * 0.3, 10);
              return (
                <rect
                  key={`v${i}`}
                  x={i * slot + gap / 2}
                  width={slot - gap}
                  y={y(c.value)}
                  height={Math.max(0, H - y(c.value))}
                  fill="currentColor"
                  opacity={(c.partial ? 0.4 : 0.9) * (hover !== null && hover !== i ? 0.5 : 1)}
                  {...(c.partial ? { 'data-partial': true } : {})}
                  data-testid={`${testId}-bar`}
                />
              );
            })}
          {/* 기간 평균(점선) */}
          {rate && rate.avg !== null && (
            <line x1="0" x2={W} y1={y(rate.avg)} y2={y(rate.avg)} className="stroke-base-content/45" strokeWidth="1" strokeDasharray="4 4" vectorEffect="non-scaling-stroke" data-testid={`${testId}-avg`} />
          )}
          {!stack && !asBars && parts.map((p, k) => (
            <path key={`g${k}`} d={line(p)} fill="none" stroke="currentColor" strokeOpacity="0.3" strokeWidth="6" vectorEffect="non-scaling-stroke" />
          ))}
          {!stack && !asBars && parts.map((p, k) => (
            <path key={`l${k}`} d={line(p)} fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinejoin="round" vectorEffect="non-scaling-stroke" />
          ))}
          {/* 지난 기간(옅은 점선) */}
          {cParts.map((p, k) =>
            p.length > 1 ? (
              <path key={`c${k}`} d={line(p)} fill="none" className="stroke-base-content/45" strokeWidth="1.5" strokeDasharray="5 4" strokeLinejoin="round" vectorEffect="non-scaling-stroke" data-testid={`${testId}-prev`} />
            ) : null,
          )}
          </g>
        </svg>
        {/* 비율 모양: 값이 없는 칸은 옅게, 값마다 점, 평균 글 */}
        {rate &&
          columns.map((c, i) =>
            c.value === null ? (
              <span key={`n${i}`} className="pointer-events-none absolute inset-y-0 bg-base-content/[0.04]" style={{ left: `${(i / n) * 100}%`, width: `${100 / n}%` }} data-testid={`${testId}-gap`} />
            ) : (
              <span
                key={`d${i}`}
                className="pointer-events-none absolute h-1.5 w-1.5 -translate-x-1/2 -translate-y-1/2 rounded-full bg-primary"
                style={{ left: `${((i + 0.5) / n) * 100}%`, top: `${(y(c.value) / H) * 100}%` }}
              />
            ),
          )}
        {rate && rate.avg !== null && (
          <span className="pm-mono pointer-events-none absolute right-0 -translate-y-full rounded bg-base-100/80 px-1 text-[10.5px] text-base-content/65" style={{ top: `${(y(rate.avg) / H) * 100}%` }}>
            {rate.avgLabel}
          </span>
        )}
        {/* 끌어서 고르는 구간 */}
        {dragging && (
          <>
            {/* 맞춰질 칸(옅게) + 손을 따라가는 띠(진하게) */}
            <span
              className="pm-brush-snap pointer-events-none absolute inset-y-0 bg-primary/8"
              style={{ left: `${(lo / n) * 100}%`, width: `${((hi - lo + 1) / n) * 100}%` }}
            />
            <span
              className="pointer-events-none absolute inset-y-0 border-x border-primary/80 bg-primary/18 shadow-[0_0_16px] shadow-primary/25"
              style={{ left: `${fLo * 100}%`, width: `${(fHi - fLo) * 100}%` }}
              data-testid={`${testId}-brush`}
            />
          </>
        )}
        {/* 십자선·점(HTML — 늘어난 SVG 위에서도 둥글게) */}
        {!stack && !asBars && !dragging && shown && shown.value !== null && hover !== null && (
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
              {c.value === null && !rate && <span className="text-xs text-base-content/35">—</span>}
            </button>
          ))}
        </div>
      </div>
      <div className="pm-mono relative ml-12 h-4 text-[11px] text-base-content/50">
        {[...ticks].map((i) => (
          <span
            key={i}
            className={`absolute top-0 whitespace-nowrap ${i === 0 ? '' : i === n - 1 ? '-translate-x-full' : '-translate-x-1/2'}`}
            style={{ left: i === 0 ? 0 : i === n - 1 ? '100%' : `${((i + 0.5) / n) * 100}%` }}
          >
            {columns[i]?.label}
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

/**
 * 요일 × 시간 열지도(7 × 24) — "언제 잘 팔리나". 한 색(primary)의 진하기 = 값(밝은 쪽 = 적음).
 * 칸마다 마우스·키보드 초점에 말풍선, 가장 많은 때를 글로, 아래 "표로 보기".
 */
export function Heatmap({
  title,
  cells,
  format,
  testId,
}: {
  readonly title: string;
  /** [요일 월0…일6][시 0…23] */
  readonly cells: readonly (readonly number[])[];
  readonly format: (v: number) => string;
  readonly testId: string;
}) {
  const [hover, setHover] = useState<readonly [number, number] | null>(null);
  const max = Math.max(0, ...cells.flat());
  let peak: readonly [number, number] = [0, 0];
  cells.forEach((row, d) => row.forEach((v, h) => (v > (cells[peak[0]]?.[peak[1]] ?? 0) ? (peak = [d, h]) : null)));
  const tip = (d: number, h: number) => m.heat.tip(m.heat.days[d]!, h, format(cells[d]?.[h] ?? 0));
  return (
    <figure className="space-y-1.5" data-testid={testId}>
      <div className="flex items-baseline justify-between gap-2 text-xs">
        <span className="font-semibold text-base-content/80">{title}</span>
        <span className="min-h-4 tabular-nums text-base-content/75" aria-live="polite" data-testid={`${testId}-tip`}>
          {hover ? tip(hover[0], hover[1]) : max > 0 ? m.heat.peak(m.heat.days[peak[0]]!, peak[1]) : ''}
        </span>
      </div>
      <div className="grid grid-cols-[1.5rem_repeat(24,minmax(0,1fr))] gap-[2px]" role="img" aria-label={title} onMouseLeave={() => setHover(null)}>
        {cells.map((row, d) => (
          <Fragment key={d}>
            <span className="pr-1 text-right text-[10.5px] leading-[14px] text-base-content/50">{m.heat.days[d]}</span>
            {row.map((v, h) => (
              <button
                key={h}
                type="button"
                aria-label={tip(d, h)}
                className="pm-heat-cell h-3.5 rounded-[3px] focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
                style={{ background: `color-mix(in oklab, var(--color-primary) ${max > 0 ? Math.round((v / max) * 88) : 0}%, var(--color-base-200))` }}
                onMouseEnter={() => setHover([d, h])}
                onFocus={() => setHover([d, h])}
                data-testid={`${testId}-cell`}
              />
            ))}
          </Fragment>
        ))}
        <span />
        {Array.from({ length: 24 }, (_, h) => (
          <span key={h} className="pm-mono text-center text-[10px] text-base-content/45">
            {h % 6 === 0 ? h : ''}
          </span>
        ))}
      </div>
      <details className="text-xs">
        <summary className="cursor-pointer text-base-content/60">{m.asTable}</summary>
        <ul className="mt-1 space-y-0.5 tabular-nums text-base-content/75">
          {cells.map((row, d) => (
            <li key={d}>
              {m.heat.days[d]} · {row.map((v, h) => `${h}시 ${format(v)}`).join(' · ')}
            </li>
          ))}
        </ul>
      </details>
    </figure>
  );
}

export interface PieSlice {
  readonly key: string;
  readonly label: string;
  readonly value: number;
  /** 부가 글(수량·금액 등) */
  readonly sub: string;
  /** 누를 수 있나(그 밖 묶음은 못 누름) */
  readonly pickable: boolean;
}

/** 범주 색 — dataviz 팔레트 1~5(index.css --pm-cat-*), "그 밖"은 회색 */
const PIE_COLOR = ['var(--pm-cat-1)', 'var(--pm-cat-2)', 'var(--pm-cat-3)', 'var(--pm-cat-4)', 'var(--pm-cat-5)'];
const OTHER_COLOR = 'color-mix(in oklab, var(--color-base-content) 28%, var(--color-base-200))';

/**
 * 원 그래프(도넛) — 많이 팔린 상품 비중(2026-11-24 사용자 "원 그래프로, 로딩될 때 시계방향으로 부채 펼쳐지듯").
 * 3시에서 시계방향으로 조각을 놓고, 처음 그릴 때 가림막(굵은 원 테두리)이 시계방향으로 그려지며 조각이 드러난다(.pm-pie-sweep, 움직임 줄이기면 바로).
 * 조각·범례 줄에 마우스·초점이면 말풍선, 누르면 onPick, 아래 "표로 보기".
 */
export function PieChart({
  title,
  slices,
  picked,
  onPick,
  testId,
}: {
  readonly title: string;
  readonly slices: readonly PieSlice[];
  readonly picked: string | null;
  readonly onPick: (key: string) => void;
  readonly testId: string;
}) {
  const [hover, setHover] = useState<string | null>(null);
  const total = slices.reduce((n, x) => n + x.value, 0);
  const pct = (v: number) => (total > 0 ? `${((v / total) * 100).toFixed(1)}%` : '0%');
  const color = (i: number, x: PieSlice) => (x.pickable ? (PIE_COLOR[i % PIE_COLOR.length] ?? OTHER_COLOR) : OTHER_COLOR);
  const R = 46;
  const r0 = 27;
  // 앞 조각들의 합 → 시작·끝 각도
  const starts = slices.map((_, i) => slices.slice(0, i).reduce((n, x) => n + x.value, 0));
  const angle = (v: number) => (v / Math.max(1, total)) * Math.PI * 2;
  const arcs = slices.map((x, i) => ({ x, i, a0: angle(starts[i]!), a1: angle(starts[i]! + x.value) }));
  // 3시에서 시계방향(2026-11-24 사용자 "3시부터", 화면 y 는 아래) — 각도 a 의 점 = (cos a, sin a)
  const pt = (rad: number, a: number) => `${(50 + rad * Math.cos(a)).toFixed(3)} ${(50 + rad * Math.sin(a)).toFixed(3)}`;
  const path = (a0: number, a1: number) => {
    if (a1 - a0 >= Math.PI * 2 - 1e-6) return `M ${pt(R, 0)} A ${R} ${R} 0 1 1 ${pt(R, Math.PI)} A ${R} ${R} 0 1 1 ${pt(R, 0)} M ${pt(r0, 0)} A ${r0} ${r0} 0 1 0 ${pt(r0, Math.PI)} A ${r0} ${r0} 0 1 0 ${pt(r0, 0)} Z`;
    const big = a1 - a0 > Math.PI ? 1 : 0;
    return `M ${pt(R, a0)} A ${R} ${R} 0 ${big} 1 ${pt(R, a1)} L ${pt(r0, a1)} A ${r0} ${r0} 0 ${big} 0 ${pt(r0, a0)} Z`;
  };
  const focus = hover ?? picked;
  const shown = slices.find((x) => x.key === focus);
  // 가림막 — 반지름 (R+r0)/2 원 테두리(굵기 R−r0+2)를 3시에서 시계방향으로 그려 펼친다(원 테두리는 3시에서 시작)
  const mr = (R + r0) / 2;
  const C = 2 * Math.PI * mr;
  const maskId = `${testId}-sweep`;
  return (
    <figure className="space-y-2" data-testid={testId}>
      <div className="flex items-baseline justify-between gap-2 text-xs">
        <span className="font-semibold text-base-content/80">{title}</span>
        <span className="min-h-4 truncate tabular-nums text-base-content/75" aria-live="polite" data-testid={`${testId}-tip`}>
          {shown ? `${shown.label} · ${pct(shown.value)} · ${shown.sub}` : m.pie.hint}
        </span>
      </div>
      <div className="grid grid-cols-[minmax(0,15rem)_minmax(0,1fr)] items-center gap-4">
        <svg viewBox="0 0 100 100" className="aspect-square w-full" role="img" aria-label={title} onMouseLeave={() => setHover(null)}>
          <defs>
            <mask id={maskId}>
              <circle
                cx="50"
                cy="50"
                r={mr}
                fill="none"
                stroke="#fff"
                strokeWidth={R - r0 + 2}
                strokeDasharray={`${C} ${C}`}
                className="pm-pie-sweep"
                style={{ ['--pm-pie-c' as string]: `${C}` }}
              />
            </mask>
          </defs>
          <g mask={`url(#${maskId})`}>
            {arcs.map(({ x, i, a0, a1 }) =>
              x.value > 0 ? (
                <path
                  key={x.key}
                  d={path(a0, a1)}
                  style={{ fill: color(i, x) }}
                  className={`stroke-base-100 transition-opacity ${x.pickable ? 'cursor-pointer' : ''}`}
                  strokeWidth="0.8"
                  opacity={focus && focus !== x.key ? 0.45 : 1}
                  onMouseEnter={() => setHover(x.key)}
                  onClick={() => (x.pickable ? onPick(x.key) : undefined)}
                  data-testid={`${testId}-slice`}
                >
                  <title>{`${x.label} · ${pct(x.value)}`}</title>
                </path>
              ) : null,
            )}
          </g>
          {/* 가운데 위 줄 — 평소 "상품", 조각·범례에 마우스를 올리면 그 상품 이름(2026-11-24 사용자). 도넛 안에 들게 길면 글씨를 줄이고 9자 넘으면 줄임표 */}
          <text
            x="50"
            y="47"
            textAnchor="middle"
            className={shown ? 'fill-base-content' : 'fill-base-content/55'}
            style={{ fontSize: shown ? ([...shown.label].length > 6 ? 5.4 : 6.6) : 7, fontWeight: shown ? 700 : 400 }}
            data-testid={`${testId}-center`}
          >
            {shown ? ([...shown.label].length > 9 ? `${[...shown.label].slice(0, 8).join('')}…` : shown.label) : m.pie.center}
          </text>
          <text x="50" y="58" textAnchor="middle" className="fill-base-content" style={{ fontSize: 10, fontWeight: 800 }}>
            {shown ? pct(shown.value) : slices.filter((x) => x.pickable).length}
          </text>
        </svg>
        <ul className="space-y-0.5" data-testid="top-sold">
          {arcs.map(({ x, i }) => (
            <li key={x.key}>
              <button
                type="button"
                disabled={!x.pickable}
                className={`grid w-full grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-2 rounded-field px-1.5 py-1 text-left text-sm transition-colors enabled:hover:bg-primary/8 disabled:cursor-default ${picked === x.key ? 'bg-primary/12' : ''}`}
                {...(x.pickable ? { 'aria-pressed': picked === x.key } : {})}
                onMouseEnter={() => setHover(x.key)}
                onMouseLeave={() => setHover(null)}
                onFocus={() => setHover(x.key)}
                onBlur={() => setHover(null)}
                onClick={() => (x.pickable ? onPick(x.key) : undefined)}
                data-testid={x.pickable ? 'top-sold-row' : 'top-sold-other'}
              >
                <i className="inline-block h-2.5 w-2.5 rounded-sm" style={{ background: color(i, x) }} aria-hidden="true" />
                <span className="truncate">{x.label}</span>
                <span className="pm-mono text-xs text-base-content/70">{pct(x.value)}</span>
              </button>
            </li>
          ))}
        </ul>
      </div>
      <details className="text-xs">
        <summary className="cursor-pointer text-base-content/60">{m.asTable}</summary>
        <table className="mt-1 w-full tabular-nums text-base-content/75">
          <tbody>
            {slices.map((x) => (
              <tr key={x.key}>
                <td className="py-0.5 pr-2">{x.label}</td>
                <td className="pr-2 text-right">{pct(x.value)}</td>
                <td className="text-right">{x.sub}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </details>
    </figure>
  );
}
