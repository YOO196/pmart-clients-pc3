// 목록 한 틀 부품 — 공용 @pmart/web-ui/standard(PC2, 라이더 백오피스 simList 를 올린 것)를 그대로 쓴다(2026-11-25 2차: MFC 사본 지움).
// 이 앱에만 남긴 것: Caret(▸ 를 글자 대신 CSS 로 — 줄 글자에 섞이지 않게)·InlineFields(펼친 줄 안 이름/값 칸).
import type { ReactNode } from 'react';

export { expandRowProps, InlineDetail, ResultBar, SearchPanel, SearchRow, useInlineOpen } from '@pmart/web-ui/standard';

/** 줄 앞 ▸/▾ */
export function Caret({ open }: { readonly open: boolean }) {
  // 글자는 CSS(::before)로 — 줄 글자(textContent)에 ▸ 가 섞이지 않게(MFC 2026-11-25)
  return <span className="pm-caret" data-open={open ? '' : undefined} aria-hidden="true" />;
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
