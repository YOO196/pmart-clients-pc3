// 콘텐츠 일괄 등록 행의 제출 여부·사유. 화면 판단 없이 서버 값(초안 상태·submittable·problems·outcome)을 그대로 풀어 쓴다.
import type { ContentImportBatch } from '../../api/models';
import { reasonText } from '../../shared/Feedback';
import { messages as m } from '../../shared/messages';

export type ImportItem = NonNullable<ContentImportBatch['items']>[number];
export type RowKind = 'ready' | 'problems' | 'published' | 'locked' | 'rejected' | 'none';

export interface RowStatus {
  readonly kind: RowKind;
  readonly text: string;
  /** 사유 목록(problems 의 code·field·detail) */
  readonly reasons: readonly string[];
}

const problemText = (p: { code: string; field?: string | null; detail?: string | null }) =>
  [reasonText(p.code), p.field ? `(${p.field})` : '', p.detail ? `— ${p.detail}` : ''].filter(Boolean).join(' ');

export function rowStatus(it: ImportItem): RowStatus {
  const d = it.draft;
  const reasons = (d?.problems ?? []).map(problemText);
  if (!d) return { kind: 'none', text: m.contents.rowStatus.noDraft, reasons };
  switch (d.state) {
    case 'PUBLISHED':
      return { kind: 'published', text: m.contents.rowStatus.published, reasons: [] };
    case 'SUBMITTED':
      return { kind: 'locked', text: it.outcome === 'LOCKED' ? m.contents.rowStatus.lockedOther : m.contents.rowStatus.submitted, reasons: [] };
    case 'REJECTED':
      return { kind: 'rejected', text: m.contents.rowStatus.rejected, reasons };
    default:
      if (d.submittable) {
        return { kind: 'ready', text: it.outcome === 'UNCHANGED' ? m.contents.rowStatus.readySame : m.contents.rowStatus.ready, reasons: [] };
      }
      return { kind: 'problems', text: m.contents.rowStatus.problems, reasons };
  }
}

export function rowSummary(items: readonly ImportItem[]): string {
  const c = { ready: 0, published: 0, locked: 0, problems: 0 };
  for (const it of items) {
    const k = rowStatus(it).kind;
    if (k === 'ready') c.ready += 1;
    else if (k === 'published') c.published += 1;
    else if (k === 'locked') c.locked += 1;
    else c.problems += 1;
  }
  return m.contents.rowSummary(c.ready, c.published, c.locked, c.problems);
}
