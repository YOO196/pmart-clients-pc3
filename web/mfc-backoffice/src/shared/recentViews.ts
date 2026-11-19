// 최근 본 항목 — web/backoffice/src/shared/recentViews.ts 를 이 앱에 맞게 옮김(2026-11-19 PC 2 요청 "통합 백오피스 UI·UX 를 MFC 백오피스에도").
// 이 브라우저에만, 로그인한 직원마다 따로 8개까지. 저장하는 것: 종류·센터·시스템 ID·화면에 보인 표기·본 시각(이름·연락처 같은 개인정보 없음).
// 모든 화면이 센터 아래(`/c/:mfcId/…`)라 센터도 같이 남긴다 — 다른 센터에서 본 것은 "최근 봄"으로 보이지 않는다.
// 저장이 막힌 브라우저(사생활 보호 창 등)에서는 조용히 아무것도 남기지 않는다 — 화면은 그대로 동작.
import { useEffect, useState } from 'react';

import { centerPath } from '../app/nav';
import { useSession } from '../app/SessionContext';

export type RecentKind = 'task' | 'worker' | 'move' | 'inboundTask' | 'location';
export interface RecentEntry {
  readonly kind: RecentKind;
  readonly mfcId: string;
  readonly id: string;
  readonly label: string;
  readonly at: number;
}

const MAX = 8;
const EVENT = 'pmart:mfc-recent-views';
const keyOf = (subject: string) => `pmart.mfc-backoffice.recent.${subject}`;

export const recentPath: Readonly<Record<RecentKind, (mfcId: string, id: string) => string>> = {
  task: (mfcId, id) => centerPath(mfcId, `tasks/${encodeURIComponent(id)}`),
  worker: (mfcId, id) => centerPath(mfcId, `workers/${encodeURIComponent(id)}`),
  move: (mfcId, id) => centerPath(mfcId, `moves/${encodeURIComponent(id)}`),
  inboundTask: (mfcId, id) => centerPath(mfcId, `inbound/tasks/${encodeURIComponent(id)}`),
  location: (mfcId, id) => centerPath(mfcId, `locations/${encodeURIComponent(id)}`),
};

const KINDS = Object.keys(recentPath);

export function readRecent(subject: string): RecentEntry[] {
  try {
    const raw: unknown = JSON.parse(window.localStorage.getItem(keyOf(subject)) ?? '[]');
    if (!Array.isArray(raw)) return [];
    return raw.filter((e): e is RecentEntry => {
      if (typeof e !== 'object' || e === null) return false;
      const o = e as Record<string, unknown>;
      return KINDS.includes(o['kind'] as string) && typeof o['mfcId'] === 'string' && typeof o['id'] === 'string' && typeof o['label'] === 'string' && typeof o['at'] === 'number';
    });
  } catch {
    return [];
  }
}

function write(subject: string, list: readonly RecentEntry[]) {
  try {
    window.localStorage.setItem(keyOf(subject), JSON.stringify(list));
  } catch {
    /* 저장이 막힌 브라우저 — 남기지 않는다 */
  }
  window.dispatchEvent(new Event(EVENT));
}

/** 상세 화면에서 부른다 — label 이 정해지면(서버 응답 뒤) 한 번 남긴다 */
export function useRecordRecent(kind: RecentKind, mfcId: string, id: string, label: string | null | undefined) {
  const subject = useSession().session?.subject;
  useEffect(() => {
    if (!subject || !id || !label) return;
    const rest = readRecent(subject).filter((e) => !(e.kind === kind && e.mfcId === mfcId && e.id === id));
    write(subject, [{ kind, mfcId, id, label, at: Date.now() }, ...rest].slice(0, MAX));
  }, [subject, kind, mfcId, id, label]);
}

export function useRecentViews(): readonly RecentEntry[] {
  const subject = useSession().session?.subject ?? '';
  const [items, setItems] = useState(() => (subject ? readRecent(subject) : []));
  useEffect(() => {
    const sync = () => setItems(subject ? readRecent(subject) : []);
    sync();
    window.addEventListener(EVENT, sync);
    window.addEventListener('storage', sync);
    return () => {
      window.removeEventListener(EVENT, sync);
      window.removeEventListener('storage', sync);
    };
  }, [subject]);
  return items;
}

/** 이 센터·이 종류에서 최근 본 ID(목록 "최근 봄" 표시 — 여러 건을 차례로 처리할 때 어디까지 봤는지) */
export function useSeenIds(kind: RecentKind, mfcId: string): ReadonlySet<string> {
  const items = useRecentViews();
  return new Set(items.filter((e) => e.kind === kind && e.mfcId === mfcId).map((e) => e.id));
}
