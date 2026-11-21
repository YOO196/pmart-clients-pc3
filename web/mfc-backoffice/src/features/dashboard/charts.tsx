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
          <span className="h-2.5 rounded-full bg-base-200">
            <span className="block h-full rounded-full bg-primary" style={{ width: `${max === 0 || r.value === 0 ? 0 : Math.max(2, (r.value / max) * 100)}%` }} />
          </span>
          <span className="text-right tabular-nums">{r.text}</span>
        </li>
      ))}
    </ul>
  );
}
