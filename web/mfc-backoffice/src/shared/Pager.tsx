// 쪽 넘김 — 화면에서 받은 목록을 쪽으로 나눠 보인다(서버가 쪽 나눔 없이 전부 주는 목록 — 예 작업자).
// 쪽 번호는 URL 쿼리 `page`(1부터, 표 필터·정렬·페이지는 URL 에 — react-web 규칙). 목록 위·아래에 같은 단추를 둔다.
import { useSearchParams } from 'react-router';

import { messages } from './messages';

const m = messages.pager;

/** 지금 쪽(1부터, 범위 밖이면 끝 쪽으로)과 바꾸기. 거르기가 바뀌면 부르는 쪽이 `page` 를 지워 1쪽으로 돌린다. */
export function usePage(total: number, size: number) {
  const [params, setParams] = useSearchParams();
  const pageCount = Math.max(1, Math.ceil(total / size));
  const raw = Number(params.get('page') ?? '1');
  const page = Number.isInteger(raw) && raw >= 1 ? Math.min(raw, pageCount) : 1;
  const set = (p: number) => {
    const next = new URLSearchParams(params);
    if (p <= 1) next.delete('page');
    else next.set('page', String(p));
    setParams(next, { replace: true });
  };
  return { page, pageCount, set, from: (page - 1) * size, to: Math.min(page * size, total) };
}

export function Pager({
  page,
  pageCount,
  total,
  from,
  to,
  onChange,
  testId,
}: {
  readonly page: number;
  readonly pageCount: number;
  readonly total: number;
  readonly from: number;
  readonly to: number;
  readonly onChange: (page: number) => void;
  readonly testId: string;
}) {
  return (
    <nav className="flex flex-wrap items-center justify-between gap-2 text-sm" aria-label={m.label} data-testid={testId}>
      <span className="text-xs text-base-content/60">{total === 0 ? m.none : m.range(from + 1, to, total)}</span>
      <div className="join">
        <button type="button" className="btn btn-sm join-item" disabled={page <= 1} onClick={() => onChange(page - 1)}>
          {`‹ ${m.prev}`}
        </button>
        {Array.from({ length: pageCount }, (_, i) => i + 1).map((p) => (
          <button
            key={p}
            type="button"
            className={`btn btn-sm join-item ${p === page ? 'btn-primary' : ''}`}
            aria-current={p === page ? 'page' : undefined}
            aria-label={m.goTo(p)}
            onClick={() => onChange(p)}
          >
            {p}
          </button>
        ))}
        <button type="button" className="btn btn-sm join-item" disabled={page >= pageCount} onClick={() => onChange(page + 1)}>
          {`${m.next} ›`}
        </button>
      </div>
    </nav>
  );
}
