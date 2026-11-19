// 사본: web/backoffice/src/shared/SeenMark.tsx (2026-11-19 PC 2 요청 "통합 백오피스 UI·UX 를 MFC 백오피스에도") — 이 앱에서 따로 고친다.
// 목록 줄의 "최근 봄" 표시(2026-11-19) — 이 브라우저에서 최근 열어 본 것(shared/recentViews, 8개까지). 서버 상태가 아니다
import { messages } from './messages';

export function SeenMark({ seen }: { readonly seen: boolean }) {
  if (!seen) return null;
  return (
    <span className="ml-1.5 inline-flex items-center gap-1 align-middle text-[11px] font-normal text-base-content/45" title={messages.chrome.seenTitle} data-testid="seen-mark">
      <svg viewBox="0 0 24 24" className="h-3 w-3 fill-none stroke-current" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        <path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12Z" />
        <circle cx="12" cy="12" r="3" />
      </svg>
      {messages.chrome.seen}
    </span>
  );
}
