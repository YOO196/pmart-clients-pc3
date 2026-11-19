// 접수 건 한 칸 — 화면 번호(C-1119-0042)만(ADR-0070 덧붙임 2026-11-19). 시스템 ID 는 글자로 보이지 않는다.
// 읽는 중 "…", 못 읽음 "번호 확인 불가", 번호 없음(옛 기록) "번호 없음".
import { messages } from './messages';
import { useCaseNumber } from './numberLookups';

export function CaseNumber({ caseId }: { readonly caseId: string }) {
  const q = useCaseNumber(caseId);
  if (q.isPending) return <span>…</span>;
  if (q.isError) return <span className="text-warning">{messages.displayNumber.failed}</span>;
  return q.data ? <span className="font-mono">{q.data}</span> : <span className="text-base-content/50">{messages.displayNumber.missing}</span>;
}
