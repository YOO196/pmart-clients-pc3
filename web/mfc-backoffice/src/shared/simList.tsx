// 목록 한 틀 부품(2026-11-25 백오피스 UI 통일, PC5 요청서 docs/operations/2026-11-25-notice-backoffice-ui-standard.md) —
// 정본 web/rider-backoffice/src/shared/simList.tsx 의 찾기 줄(SearchPanel·SearchRow)·줄 아래 펼침(useInlineOpen·expandRowProps·Caret·InlineDetail)을 옮겼다.
// 모양은 src/list.css. 공용 web/ui 로 올리는 일은 PC2 몫이라 그때 이 파일을 지운다.
import { type CSSProperties, type FormEvent, type KeyboardEvent, type MouseEvent, type ReactNode, useEffect, useId, useState } from 'react';
import { Link } from 'react-router';

const t = {
  funnel: '거르기 조건',
  filterWord: '필터',
  funnelOpen: (n: number) => (n > 0 ? `거르기 조건 열기 (${n}개 걸림)` : '거르기 조건 열기'),
  change: (k: string, v: string) => `${k} ${v} 조건 바꾸기`,
  clear: (k: string) => `${k} 조건 풀기`,
  close: '닫기',
  clearAll: '모두 지우기',
  info: 'ⓘ',
  infoLabel: (open: boolean) => (open ? '화면 설명 접기' : '화면 설명 보기'),
  full: '전체 상세 ›',
} as const;

/** [이름, 값(빈 문자열 = 안 걸림), 풀기] — 풀기가 있으면 칩에 ✕ */
export type SummaryEntry = readonly [string, string] | readonly [string, string, (() => void) | undefined];

/**
 * 검색 조건 — 시뮬레이터처럼 한 줄: [찾기 칸(search)][찾기][깔때기 → 팝업(children: 상태·종류 고르기)][건 조건 칩 ✕][초기화].
 * 공용 SearchPanel 과 같은 이름·속성(덮어 쓰기) — search 를 주지 않은 화면은 입력 칸까지 팝업 안에 있다.
 * 폼은 하나(aria-label=label, data-list-part="top" — '/' 키가 첫 칸으로). 팝업의 입력도 같은 폼이라 Enter 가 찾기다.
 */
export function SearchPanel({
  onSubmit,
  onReset,
  children,
  submitLabel = '조회',
  submitDisabled = false,
  label = '검색 조건',
  summary,
  submit = true,
  search,
  filters,
  testId,
}: {
  readonly onSubmit: (e: FormEvent) => void;
  readonly onReset: () => void;
  readonly children?: ReactNode;
  readonly submitLabel?: string;
  /** 공용과 맞춘 이름 — 이 모양은 늘 "모두 지우기"(2026-11-21 사용자 "지우기 버튼 굳이") */
  readonly resetLabel?: string;
  readonly submitDisabled?: boolean;
  readonly label?: string;
  readonly summary?: ReadonlyArray<SummaryEntry>;
  /** false = 찾기 단추 없음(고르는 즉시 거르는 목록) */
  readonly submit?: boolean;
  /** 공용과 맞춘 이름 — 이 모양에서는 팝업이 늘 닫힌 채 시작한다 */
  readonly startOpen?: boolean;
  /** 왼쪽 찾기 칸(번호·전화 등 글자 입력) — 늘 보인다 */
  readonly search?: ReactNode;
  /** 늘 보이는 거르기(고르기 하나뿐인 화면 — 예: 상담함 구분). 찾기 단추와 떨어진 자리에 이름을 붙여 둔다 */
  readonly filters?: ReactNode;
  /** 칩이 없어도 거르기가 걸렸는지(filters 쪽) — "모두 지우기" 보이기 */
  readonly active?: boolean;
  readonly testId?: string;
}) {
  const [open, setOpen] = useState(false);
  const popId = useId();
  const active = (summary ?? []).filter(([, v]) => v !== '');
  useEffect(() => {
    if (!open) return;
    const onKey = (e: globalThis.KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open]);
  const submitBtn = submit && (
    <button type="submit" className="btn btn-sm btn-primary" disabled={submitDisabled}>
      {submitLabel}
    </button>
  );
  return (
    <form
      className="pm-fbar"
      aria-label={label}
      data-list-part="top"
      data-search=""
      data-testid={testId}
      onSubmit={(e) => {
        onSubmit(e);
        setOpen(false);
      }}
    >
      {search && <div className="pm-fbar-q">{search}</div>}
      {search && submitBtn}
      {filters && <div className="pm-fbar-filters">{filters}</div>}
      {children !== undefined && children !== null && children !== false && (
        <div className="pm-fwrap">
          <button
            type="button"
            className={`pm-funnel ${active.length > 0 ? 'on' : ''}`}
            aria-haspopup="dialog"
            aria-expanded={open}
            aria-controls={open ? popId : undefined}
            aria-label={t.funnelOpen(active.length)}
            title={t.funnel}
            onClick={() => setOpen((o) => !o)}
            data-testid="search-toggle"
          >
            {/* 깔때기 그림 대신 글자(2026-11-24 사용자 "깔때기 모양 말고 필터라고 적어") */}
            <span aria-hidden="true">{t.filterWord}</span>
            {active.length > 0 && <span className="pm-funnel-n">{active.length}</span>}
          </button>
          {open && (
            <>
              <div className="pm-pop-back" onClick={() => setOpen(false)} aria-hidden="true" />
              <div className="pm-pop" id={popId} role="group" aria-label={t.funnel} data-testid="search-popup">
                <div className="pm-pop-grid">{children}</div>
                <div className="pm-pop-foot">
                  <button type="button" className="btn btn-sm btn-ghost" onClick={onReset}>
                    {t.clearAll}
                  </button>
                  {!search && submitBtn}
                  <button type="button" className="btn btn-sm" onClick={() => setOpen(false)}>
                    {t.close}
                  </button>
                </div>
              </div>
            </>
          )}
        </div>
      )}
      {!search && children == null && submitBtn}
      {active.map(([k, v, clear]) => (
        <span key={k} className="pm-fchip" data-testid="search-chip">
          {/* 값만("운행 운행 중" 처럼 되풀이하지 않게) — 무슨 조건인지는 올려 보면(title)·읽기 도구 이름 */}
          <button type="button" className="pm-fchip-l" aria-label={t.change(k, v)} title={k} onClick={() => setOpen(true)}>
            {v}
          </button>
          {clear && (
            <button type="button" className="pm-fchip-x" aria-label={t.clear(k)} onClick={clear}>
              ✕
            </button>
          )}
        </span>
      ))}
      {/* 칩 줄 끝 "모두 지우기"는 뺐다(2026-11-24 사용자 "터치한 거 한번 더 터치하면 필터 풀리는 걸로 하고 모두 지우기 버튼은 없애자")
          — 칩마다 ✕, 고르기 단추는 다시 누르면 풀린다. 깔때기 팝업 안의 "모두 지우기"는 그대로. */}
    </form>
  );
}

/** 팝업 안 한 묶음(공용 SearchRow 와 같은 속성) — 작은 회색 머리 + 고르기 목록 */
export function SearchRow({ label, children }: { readonly label: ReactNode; readonly children: ReactNode }) {
  return (
    <div className="pm-pop-sec">
      <div className="pm-pop-h">{label}</div>
      <div className="pm-pop-body">{children}</div>
    </div>
  );
}

/** 줄 펼침 — 한 번에 한 줄만(시뮬레이터처럼). 상태는 화면 안에만(주소는 거르기·쪽만) */
export function useInlineOpen() {
  const [openKey, setOpenKey] = useState<string | null>(null);
  return {
    isOpen: (k: string) => openKey === k,
    toggle: (k: string) => setOpenKey((o) => (o === k ? null : k)),
  };
}

const interactive = (el: EventTarget | null) => el instanceof Element && !!el.closest('a, button, input, select, textarea, label, summary, [role="radio"]');

/** 펼치는 줄에 붙일 속성 — 줄을 누르거나 Enter·Space 로 펼친다(줄 안 링크·단추는 그대로) */
export function expandRowProps(open: boolean, onToggle: () => void) {
  return {
    'aria-expanded': open,
    tabIndex: 0,
    'data-open': open ? '' : undefined,
    onClick: (e: MouseEvent<HTMLTableRowElement>) => {
      if (interactive(e.target)) return;
      onToggle();
    },
    onKeyDown: (e: KeyboardEvent<HTMLTableRowElement>) => {
      if (e.target !== e.currentTarget) return;
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        onToggle();
      }
    },
  } as const;
}

/** 줄 앞 ▸/▾ */
export function Caret({ open }: { readonly open: boolean }) {
  // 글자는 CSS(::before)로 — 줄 글자(textContent)에 ▸ 가 섞이지 않게(MFC 2026-11-25)
  return <span className="pm-caret" data-open={open ? '' : undefined} aria-hidden="true" />;
}

/**
 * 펼친 칸 위 버튼 색(2026-11-24 사용자 "점선 밑에 있으니까 눈에 더 안들어와. 아까처럼 이 라이더의 배송은 그대로 하양, 전체 상세는 파랑으로").
 * 표의 첫 칸 링크 규칙(DataTable — 이름 점선 밑줄)이 펼친 줄의 첫 칸 안 버튼에도 걸려 밑줄을 끈다. 앱 전체 `a { color: inherit }` 때문에
 * 글자색도 직접 준다(btn-primary 클래스만으로는 글자가 바탕색과 같아 보이지 않았다).
 */
export const inlineMainButton: CSSProperties = { backgroundColor: 'var(--color-primary)', color: 'var(--color-primary-content)', textDecoration: 'none' };
export const inlineSubButton: CSSProperties = { backgroundColor: 'var(--color-base-100)', color: 'var(--color-base-content)', borderColor: 'var(--color-base-300)', textDecoration: 'none' };

/** 줄 바로 아래 펼친 상세(.md-inline) — 오른쪽 위 "전체 상세 ›" 링크 */
/**
 * 줄 아래 펼친 상세. "전체 상세 ›"(와 [actions])는 위쪽 오른쪽 한 줄에 같은 크기 버튼으로 모은다.
 * 2026-11-24 사용자:
 * - "이 라이더의 배송 UI랑 버튼 위치가 좀 애매" — 작은 버튼이 왼쪽 정보 밑에, 상세 링크는 오른쪽 칸 위에 떨어져 있었다.
 * - "전체 상세 버튼이랑 그래프 UI 겹치네" — 오른쪽 위에 띄워 둔(float) 링크가 배송 단계 그래프 위에 겹쳤다.
 */
export function InlineDetail({
  colSpan,
  to,
  linkLabel = t.full,
  actions,
  children,
  testId = 'inline-detail',
}: {
  readonly colSpan: number;
  readonly to?: string;
  readonly linkLabel?: string;
  readonly actions?: ReactNode;
  readonly children: ReactNode;
  readonly testId?: string;
}) {
  return (
    <tr className="pm-inline-row">
      <td colSpan={colSpan}>
        <div className="pm-inline" data-testid={testId}>
          {(actions || to) && (
            <div className="pm-inline-bar">
              {actions}
              {to && (
                <Link className="btn btn-sm border-0" style={inlineMainButton} to={to}>
                  {linkLabel}
                </Link>
              )}
            </div>
          )}
          {children}
        </div>
      </td>
    </tr>
  );
}

/** 펼친 줄 안 이름/값 칸(서버 값만) — 넓이에 맞춰 여러 칸, 이름은 작은 보조 글(list.css .pm-inline dt) */
export function InlineFields({ rows }: { readonly rows: ReadonlyArray<readonly [string, ReactNode]> }) {
  return (
    <dl className="grid grid-cols-[repeat(auto-fill,minmax(11rem,1fr))] gap-x-6 gap-y-3 text-sm">
      {rows.map(([k, v]) => (
        <div key={k} className="min-w-0">
          <dt>{k}</dt>
          <dd className="min-w-0 break-words font-medium">{v}</dd>
        </div>
      ))}
    </dl>
  );
}
