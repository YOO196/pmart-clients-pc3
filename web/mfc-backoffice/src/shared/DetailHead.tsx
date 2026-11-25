// 상세 화면 머리(2026-11-25 백오피스 UI 통일 — PC5 요청서 §5-1, 정본 web/rider-backoffice/src/shared/admin.tsx DetailHeader·BackButton·useGoBack).
// [‹][제목][상태] … 오른쪽 위 이전·n/N·다음. 제목 위 "목록" 글자 링크는 없앴다 — 둥근 ‹ 단추가 방금 보던 화면으로(찾기 조건·스크롤 유지).
import type { ReactNode } from 'react';
import { useLocation, useNavigate } from 'react-router';

/**
 * 뒤로 — 앱 안에서 넘어왔으면 뒤로(목록의 거르기·스크롤·펼친 줄이 그대로), 주소로 바로 열었으면 그 목록으로.
 * 첫 화면의 location.key 는 'default'(React Router) — 라이더의 history.state.idx 와 같은 뜻이고 메모리 라우터(시험)에서도 맞다.
 */
export function useGoBack(fallback: string): () => void {
  const navigate = useNavigate();
  const { key } = useLocation();
  return () => {
    if (key !== 'default') void navigate(-1);
    else void navigate(fallback);
  };
}

/** 제목 왼쪽 둥근 ‹ 단추(이름은 읽기 도구·마우스 올리면 — "작업자 목록" 등) */
export function BackButton({ onClick, label, small = false }: { readonly onClick: () => void; readonly label: string; readonly small?: boolean }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      title={label}
      data-testid="detail-back"
      className={`btn btn-circle shrink-0 border-base-300 bg-base-100 ${small ? 'btn-xs text-base' : 'btn-sm text-xl'} leading-none`}
    >
      <span aria-hidden className="-mt-0.5">
        ‹
      </span>
    </button>
  );
}

/** 머리 줄 — 왼쪽 [‹][제목(children)], 오른쪽 위 이전·다음(nav). 제목은 읽은 뒤에만 children 으로 온다(읽는 중·실패에도 ‹ 는 보인다) */
export function DetailTop({ onBack, backLabel, nav, children }: { readonly onBack: () => void; readonly backLabel: string; readonly nav?: ReactNode; readonly children?: ReactNode }) {
  return (
    <div className="flex flex-wrap items-start justify-between gap-3" data-testid="detail-top">
      <div className="flex min-w-0 flex-wrap items-center gap-2">
        <BackButton onClick={onBack} label={backLabel} />
        {children}
      </div>
      {nav && <div className="ml-auto">{nav}</div>}
    </div>
  );
}
