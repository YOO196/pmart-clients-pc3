// 목록 공통 부품(2026-11-19 PC 2 요청 "통합 백오피스 UI·UX 를 MFC 백오피스에도", 쿠팡 윙 참고).
// 2026-11-21: 화면 맨 위 안내 상자(GuideBox)는 실사용에 쓸모없어 뺐다(사용자). 2026-11-20: StatStrip·AllDone 은 공용 @pmart/web-ui 를 쓴다(알림 handoff/all/2026-11-19-notice-web-ui-shared-parts).
// 이 앱에 남긴 것: StatCard·countCell(공용 알림대로 앱 사본 — 이 앱은 주소 쿼리 대신 거르기 함수 onClick),
// SearchBar(이 앱 목록은 고르는 즉시 거른다 — 공용 SearchPanel 은 조회·초기화 단추가 늘 붙어 회신에서 "단추 없음"·startOpen 을 부탁함).
// - 숫자 카드: 서버가 센 수만. 읽는 중 "…", 못 읽으면 "?"(0 이 아님), 한 쪽에 다 못 세면 "N건 이상".
// - 안내 상자: 화면이 이미 쓰는 업무 문구만(새 규칙을 만들지 않는다). 접은 것은 이 브라우저에 기억.
// - 다 끝났어요 띠: 서버가 0건이라고 확인했을 때만(읽는 중·실패에는 그리지 않는다 — 부르는 쪽이 성공일 때만).
// - 검색 조건(2026-11-25 목록 한 틀): [필터 → 팝업(고르기)][건 조건 칩 ✕] 한 줄. '/' 키는 팝업을 열어 첫 입력으로 간다(app/PageChrome).
import { type ComponentProps, type ReactNode, useEffect, useId, useState } from 'react';

import { AllDone as UiAllDone } from '@pmart/web-ui';

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
  // 2026-11-20 공용 콘솔 모양: 색은 뜻만(경고·위험) — info 파랑 숫자는 글자색으로. 고른 칸은 띠가 아래 파란 줄(console.css)
  const valueCls = tone === 'error' ? 'text-error' : tone === 'warning' ? 'text-[color-mix(in_oklab,var(--color-warning)_60%,var(--color-base-content))]' : '';
  // 2026-11-25 백오피스 통일 2차(PC5 — 라이더 숫자 칸): 이름은 위쪽 한 줄 굵게(칸마다 같은 높이로 일직선), 숫자는 그 아래 크게. 설명은 맨 아래 작게
  const body = (
    <span className="flex h-full flex-col gap-1">
      <span className="block truncate text-sm font-semibold text-base-content">{label}</span>
      <span className={`pm-stat-value block text-[28px] font-semibold leading-tight tracking-tight ${value === '?' ? 'text-base-content/40' : valueCls}`} data-testid={testId ? `${testId}-value` : undefined}>
        {value}
        {ch.badge}
      </span>
      {hint && <span className="block truncate text-xs text-base-content/55">{hint}</span>}
    </span>
  );
  const cls = `pm-stat block min-h-20 w-full rounded-box border px-4 py-4 text-left ${active ? 'border-primary bg-primary/5' : 'border-base-300 bg-base-100'} ${ch.cls}`;
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

/** 숫자 띠 — 공용 콘솔(@pmart/web-ui/console StatStrip, 2026-11-20): 한 상자·칸 사이 머리카락 선, 고른 칸(aria-pressed)은 아래 파란 줄 */
export { StatStrip } from '@pmart/web-ui/console';

/** 다 끝났어요 띠 — 공용(@pmart/web-ui AllDone). 서버가 0건이라고 확인했을 때만 부른다. 제목 기본값만 이 앱 문구 */
export function AllDone({ title = m.allDone, ...rest }: Omit<ComponentProps<typeof UiAllDone>, 'title'> & { readonly title?: string }) {
  return <UiAllDone title={title} {...rest} />;
}

/** [이름, 값(빈 문자열 = 안 걸림)] 또는 [이름, 값, 풀기] — 풀기가 있으면 칩에 ✕ */
export type SearchSummary = readonly [string, string] | readonly [string, string, (() => void) | undefined];

/**
 * 검색 조건(2026-11-25 백오피스 UI 통일 — 라이더 백오피스 simList SearchPanel 모양): 한 줄 [필터 → 팝업(children 고르기)][건 조건 칩 ✕] … [extra].
 * 이 앱 목록은 고르는 즉시 거른다(조회 단추 없음). 팝업은 늘 닫힌 채 시작하고, 건 조건은 칩으로 늘 보인다(정보는 줄이지 않음).
 * 폼은 하나(aria-label=label, data-list-part="top") — '/' 키가 팝업을 열고 첫 칸으로(app/PageChrome).
 */
export function SearchBar({
  summary,
  children,
  label = m.search,
  extra,
}: {
  readonly summary: ReadonlyArray<SearchSummary>;
  readonly children: ReactNode;
  readonly label?: string;
  readonly extra?: ReactNode;
  /** 예전 이름 — 팝업은 늘 닫힌 채 시작한다(받기만 한다) */
  readonly startOpen?: boolean;
}) {
  const active = summary.filter(([, v]) => v !== '');
  // 필터 개수는 풀 수 있는(기본이 아닌) 조건만 — 기본값 칩("진행 중" 등)은 보이기만
  const set = active.filter(([, , clear]) => !!clear).length;
  const [open, setOpen] = useState(false);
  const popId = useId();
  useEffect(() => {
    if (!open) return;
    const onKey = (e: globalThis.KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open]);
  return (
    <div className="pm-fbar" data-testid="search-bar">
      <div className="pm-fwrap">
        <button
          type="button"
          className={`pm-funnel ${set > 0 ? 'on' : ''}`}
          aria-haspopup="dialog"
          aria-expanded={open}
          aria-controls={popId}
          aria-label={m.filterOpen(set)}
          title={label}
          onClick={() => setOpen((o) => !o)}
          data-testid="search-toggle"
        >
          <span aria-hidden="true">{m.filter}</span>
          {set > 0 && <span className="pm-funnel-n">{set}</span>}
        </button>
        {open && <div className="pm-pop-back" onClick={() => setOpen(false)} aria-hidden="true" />}
        <form id={popId} className="pm-pop" aria-label={label} data-list-part="top" data-testid="search-popup" hidden={!open} onSubmit={(e) => e.preventDefault()}>
          <div className="pm-pop-grid pm-pop-fields">{children}</div>
          <div className="pm-pop-foot">
            <button type="button" className="btn btn-sm" onClick={() => setOpen(false)}>
              {m.close}
            </button>
          </div>
        </form>
      </div>
      {active.map(([k, v, clear]) => (
        <span key={k} className={`pm-fchip ${clear ? '' : 'pm-fchip-def'}`} data-testid="search-chip">
          {/* 값만("상태 닫힘" 처럼 되풀이하지 않게) — 무슨 조건인지는 올려 보면(title)·읽기 도구 이름 */}
          <button type="button" className="pm-fchip-l" aria-label={m.change(k, v)} title={k} onClick={() => setOpen(true)}>
            {v}
          </button>
          {clear && (
            <button type="button" className="pm-fchip-x" aria-label={m.clear(k)} onClick={clear}>
              ✕
            </button>
          )}
        </span>
      ))}
      {extra && <span className="ml-auto flex items-center gap-2">{extra}</span>}
    </div>
  );
}
