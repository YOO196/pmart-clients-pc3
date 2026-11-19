// 목록 공통 부품 — web/backoffice/src/shared/admin.tsx 의 StatCard·StatStrip·countCell·GuideBox·AllDone·SearchPanel(칩 접기)을 이 앱에 맞게 옮김
// (2026-11-19 PC 2 요청 "통합 백오피스 UI·UX 를 MFC 백오피스에도", 쿠팡 윙 참고).
// - 숫자 카드: 서버가 센 수만. 읽는 중 "…", 못 읽으면 "?"(0 이 아님), 한 쪽에 다 못 세면 "N건 이상".
// - 안내 상자: 화면이 이미 쓰는 업무 문구만(새 규칙을 만들지 않는다). 접은 것은 이 브라우저에 기억.
// - 다 끝났어요 띠: 서버가 0건이라고 확인했을 때만(읽는 중·실패에는 그리지 않는다 — 부르는 쪽이 성공일 때만).
// - 검색 조건: 조건을 건 뒤에는 한 줄 칩으로 접고 "검색 열기"로 펼친다. '/' 키는 이 칸의 첫 입력으로 간다(app/PageChrome).
import { type ReactNode, useState } from 'react';

import { messages } from './messages';
import { useStatChange } from './motion';

const m = messages.listParts;

/** 숫자 칸 글자 — 서버 개수(쪽이 더 있으면 "N건 이상"), 읽는 중 "…", 못 읽음 "?" */
export const countCell = (q: { readonly data?: { readonly n: number; readonly more: boolean } | undefined; readonly isError: boolean }): string =>
  q.data ? (q.data.more ? m.atLeast(q.data.n) : m.count(q.data.n)) : q.isError ? '?' : '…';

/** 숫자 카드 — 이름 + 큰 숫자 + 설명 한 줄. 누르면 그 상태로 거른다. 숫자가 방금 바뀌면 잠깐 빛남·▲▼(움직임 줄이기면 없음) */
export function StatCard({
  label,
  value,
  hint,
  tone,
  testId,
  active = false,
  onClick,
}: {
  readonly label: ReactNode;
  readonly value: string;
  readonly hint?: ReactNode;
  readonly tone?: 'warning' | 'error' | 'info' | 'success' | undefined;
  readonly testId?: string;
  readonly active?: boolean;
  readonly onClick?: () => void;
}) {
  const ch = useStatChange(value);
  const valueCls = tone === 'error' ? 'text-error' : tone === 'warning' ? 'text-warning' : tone === 'info' ? 'text-primary' : '';
  // 가로형(지침 2 "이름은 왼쪽, 큰 숫자는 오른쪽") — 왼쪽 색 띠 없이 숫자 색으로만 구분
  const body = (
    <span className="flex items-start justify-between gap-3">
      <span className="min-w-0">
        <span className="block text-sm font-semibold">{label}</span>
        {hint && <span className="mt-0.5 block text-[11px] text-base-content/50">{hint}</span>}
      </span>
      <span className={`shrink-0 text-3xl font-bold leading-none tabular-nums ${value === '?' ? 'text-base-content/40' : valueCls}`} data-testid={testId ? `${testId}-value` : undefined}>
        {value}
        {ch.badge}
      </span>
    </span>
  );
  const cls = `block min-h-20 w-full rounded-box border px-4 py-4 text-left ${active ? 'border-primary bg-primary/5' : 'border-base-300 bg-base-100'} ${ch.cls}`;
  return onClick ? (
    <button type="button" className={`${cls} transition hover:border-primary/60`} onClick={onClick} aria-pressed={active} data-testid={testId}>
      {body}
    </button>
  ) : (
    <div className={cls} data-testid={testId}>
      {body}
    </div>
  );
}

/** 숫자 띠(목록 맨 위 카드 한 줄) */
export function StatStrip({ children, label, testId }: { readonly children: ReactNode; readonly label: string; readonly testId?: string }) {
  return (
    <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-5" role="group" aria-label={label} data-testid={testId}>
      {children}
    </div>
  );
}

/** 안내 상자 — ⓘ 제목 + 글머리 몇 줄, 접기(화면마다 storeKey 로 기억) */
export function GuideBox({ title, items, storeKey, testId = 'guide-box' }: { readonly title: string; readonly items: readonly ReactNode[]; readonly storeKey: string; readonly testId?: string }) {
  const k = `pmart.mfc-backoffice.guide.${storeKey}`;
  const [open, setOpen] = useState(() => {
    try {
      return window.localStorage.getItem(k) !== 'closed';
    } catch {
      return true;
    }
  });
  const toggle = () => {
    const next = !open;
    setOpen(next);
    try {
      window.localStorage.setItem(k, next ? 'open' : 'closed');
    } catch {
      // 저장이 막힌 브라우저 — 이번 화면에서만
    }
  };
  return (
    <div className="rounded-box border border-base-300 bg-base-200/50 px-5 py-3" data-testid={testId}>
      <button type="button" className="flex w-full items-center justify-between gap-2 text-left text-sm font-semibold" aria-expanded={open} onClick={toggle}>
        <span className="inline-flex items-center gap-2">
          <span className="flex h-5 w-5 items-center justify-center rounded-full border border-base-content/40 text-[11px] font-bold" aria-hidden="true">
            i
          </span>
          {title}
        </span>
        <span className="text-xs text-base-content/50" aria-hidden="true">
          {open ? '▴' : '▾'}
        </span>
      </button>
      {open && (
        <ul className="mt-2 list-inside list-disc space-y-1 text-sm text-base-content/70">
          {items.map((t, i) => (
            <li key={i}>{t}</li>
          ))}
        </ul>
      )}
    </div>
  );
}

/** 다 끝났어요 띠 — 서버가 0건이라고 확인했을 때만 */
export function AllDone({ title = m.allDone, body, testId = 'all-done' }: { readonly title?: string; readonly body?: string; readonly testId?: string }) {
  return (
    <div role="status" className="flex items-center gap-3 rounded-box border border-success/30 bg-success/10 px-5 py-3.5" data-testid={testId}>
      <span className="grid h-7 w-7 shrink-0 place-items-center rounded-full bg-success text-white" aria-hidden="true">
        <svg viewBox="0 0 24 24" className="h-4 w-4 fill-none stroke-current" strokeWidth={3} strokeLinecap="round" strokeLinejoin="round">
          <path d="M5 12.5l4.5 4.5L19 7.5" />
        </svg>
      </span>
      <span>
        <span className="block font-bold">{title}</span>
        {body && <span className="block text-sm text-base-content/65">{body}</span>}
      </span>
    </div>
  );
}

/**
 * 검색 조건 — 맨 위 연회색 띠에 [이름 값] 칩, 펼치면 아래 흰 칸에 입력들. 조건이 하나도 없으면 처음부터 펼친다(입력해야 하니까).
 * 이 앱 목록은 고르는 즉시 거른다(조회 단추 없음) — 접기·펼치기만 한다.
 */
export function SearchBar({
  summary,
  children,
  label = m.search,
  extra,
  startOpen,
}: {
  readonly summary: ReadonlyArray<readonly [string, string]>;
  readonly children: ReactNode;
  readonly label?: string;
  readonly extra?: ReactNode;
  /** 처음에 펼칠지 — 기본은 "건 조건이 없으면 펼침". 화면 기본값이 칩에 보이는 목록(예: 대기)은 부르는 쪽이 정한다 */
  readonly startOpen?: boolean;
}) {
  const active = summary.filter(([, v]) => v !== '');
  const [open, setOpen] = useState(startOpen ?? active.length === 0);
  return (
    <div data-testid="search-bar">
      <div className={`flex flex-wrap items-center gap-2 rounded-box border border-base-300 bg-base-200/60 px-4 py-2.5 ${open ? 'rounded-b-none' : ''}`}>
        <span className="inline-flex items-center gap-1.5 text-sm font-bold">
          <svg viewBox="0 0 24 24" className="h-4 w-4 fill-none stroke-current" strokeWidth={2} strokeLinecap="round" aria-hidden="true">
            <path d="M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14Zm9 2-4-4" />
          </svg>
          {label}
        </span>
        {summary.map(([k, v]) => (
          <button
            key={k}
            type="button"
            className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-xs ${v ? 'border-primary bg-base-100' : 'border-base-300 bg-base-100 text-base-content/60'}`}
            onClick={() => setOpen(true)}
            data-testid="search-chip"
          >
            <span className="font-semibold">{k}</span>
            <span className={v ? 'text-primary' : ''}>{v || m.all}</span>
            <span aria-hidden="true">▾</span>
          </button>
        ))}
        <span className="ml-auto flex items-center gap-2">
          {extra}
          <button type="button" className="btn btn-ghost btn-xs border border-base-300 bg-base-100" aria-expanded={open} onClick={() => setOpen((o) => !o)} data-testid="search-toggle">
            {open ? m.close : m.open}
          </button>
        </span>
      </div>
      <form
        className="flex flex-wrap items-end gap-x-5 gap-y-3 rounded-box rounded-t-none border border-t-0 border-base-300 bg-base-100 px-4 py-3.5 text-sm"
        onSubmit={(e) => e.preventDefault()}
        aria-label={label}
        data-search=""
        hidden={!open}
      >
        {children}
      </form>
    </div>
  );
}
