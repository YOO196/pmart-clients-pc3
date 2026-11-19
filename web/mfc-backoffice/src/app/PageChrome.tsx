// 화면 틀 보탬 — web/backoffice/src/app/PageChrome.tsx·ShortcutHelp('/' 키)를 이 앱에 맞게 옮김(2026-11-19 PC 2 요청 "통합 백오피스 UI·UX 를 MFC 백오피스에도").
// 1) 브라우저 탭 제목: 지금 화면 이름 + 출하 약속을 넘긴 출고 수(운영판과 같은 서버 값·같은 조회) — 다른 탭에 있어도 급한 일이 보인다.
// 2) 인터넷 끊김 띠: 끊긴 동안 화면 숫자가 최신이 아님을 알린다. 다시 이어지면 잠깐 알리고 화면은 저절로 다시 읽는다.
// 3) '/' 키: 이 화면 검색 조건(SearchBar)의 첫 입력으로. 접혀 있으면 펼친다. 입력 칸에 있을 때는 가로채지 않는다.
import { useEffect, useState, useSyncExternalStore } from 'react';

import { useOverdueCount } from '../features/ops/opsQueries';
import { messages } from '../shared/messages';

const m = messages.chrome;
const BACK_MS = 4_000;

/** 탭 제목 — "(3) 작업 현황 · PMart MFC 백오피스". 숫자는 서버 값으로 판정한 약속 초과, 못 읽으면 숫자 없이 */
export function useDocumentTitle(screen: string | null, mfcId: string | null) {
  const urgent = useOverdueCount(mfcId);
  const count = urgent && urgent.n > 0 ? `(${urgent.more ? `${urgent.n}+` : urgent.n}) ` : '';
  const title = `${count}${screen ? `${screen} · ` : ''}${messages.appTitle}`;
  useEffect(() => {
    document.title = title;
  }, [title]);
  useEffect(
    () => () => {
      document.title = messages.appTitle;
    },
    [],
  );
}

const FIELD = ':is(input:not([type=hidden]):not([type=checkbox]):not([type=radio]), select, textarea):not([disabled])';

/** '/' → 검색 조건 첫 칸 */
export function useSlashToSearch() {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const t = e.target;
      if (t instanceof HTMLElement && (t.isContentEditable || ['INPUT', 'TEXTAREA', 'SELECT'].includes(t.tagName))) return;
      if (e.key !== '/' || e.ctrlKey || e.metaKey || e.altKey) return;
      const form = document.querySelector<HTMLFormElement>('main form[data-search]');
      if (!form) return;
      e.preventDefault();
      const focus = () => form.querySelector<HTMLElement>(FIELD)?.focus();
      if (form.hidden) {
        form.parentElement?.querySelector<HTMLButtonElement>('[data-testid="search-toggle"]')?.click();
        setTimeout(focus, 0);
      } else focus();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);
}

const subscribe = (cb: () => void) => {
  window.addEventListener('online', cb);
  window.addEventListener('offline', cb);
  return () => {
    window.removeEventListener('online', cb);
    window.removeEventListener('offline', cb);
  };
};

export function ConnectionBanner() {
  const online = useSyncExternalStore(
    subscribe,
    () => navigator.onLine,
    () => true,
  );
  const [wasOffline, setWasOffline] = useState(false);
  const [back, setBack] = useState(false);
  if (!online && !wasOffline) setWasOffline(true);
  if (online && wasOffline) {
    setWasOffline(false);
    setBack(true);
  }
  useEffect(() => {
    if (!back) return;
    const t = setTimeout(() => setBack(false), BACK_MS);
    return () => clearTimeout(t);
  }, [back]);
  if (!online)
    return (
      <div role="alert" className="flex items-center gap-2 border-b border-warning/40 bg-warning/15 px-6 py-2 text-sm" data-testid="offline-banner">
        <span className="breathe h-2 w-2 shrink-0 rounded-full bg-warning" aria-hidden="true" />
        <strong>{m.offline}</strong>
        <span className="text-base-content/70">{m.offlineHint}</span>
      </div>
    );
  if (back)
    return (
      <div role="status" className="border-b border-success/30 bg-success/10 px-6 py-2 text-sm text-success" data-testid="online-again">
        {m.onlineAgain}
      </div>
    );
  return null;
}
