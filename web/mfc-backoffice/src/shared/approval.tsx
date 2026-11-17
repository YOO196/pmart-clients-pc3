// 본사 승인 번호(AP-1, inventory 0.22.0·quality 0.3.0·capacity 0.16.0 — 백엔드 공지 clients/mfc-backoffice/2026-11-17-notice-mfc-approval-ref-and-new-fields.md §1).
// - 승인 번호(approvalRef)는 선택. 기준(한 건 손실 10만 원 이상 또는 한 SKU 20개 이상, 운영 제한 해제는 늘)이면 서버가 422 APPROVAL_REQUIRED.
// - 그 거절의 details: field=threshold → 걸린 기준 문장(보여 준다), field=approvalRequest → approval-service 변경 요청 본문(JSON 문자열 — 화면에 쏟지 않는다),
//   field=approvalRef → 번호가 왜 안 되는지(NOT_APPROVED·ALREADY_USED·EXPIRED·NOT_YET_EFFECTIVE·SELF_APPROVAL·TARGET_MISMATCH·OUT_OF_SCOPE).
// - 본사 승인 요청 보내기(approval-service `POST /change-requests` → submissions)는 approval 타입이 생긴 뒤(PC 2 요청 2026-11-17). 지금은 안내만.
import type { ReactNode } from 'react';

import { type PmartFailure, ProblemFailure } from '@pmart/web-core';
import { type Command, CommandFeedback } from '@pmart/web-ui';
import { messages } from './messages';

const a = messages.approval;

export interface ApprovalRequired {
  readonly thresholds: readonly string[];
  /** approval-service 변경 요청 본문(파싱 전 JSON 문자열) — 승인 요청 보내기에 그대로 쓴다 */
  readonly request: string | null;
  /** 넣은 승인 번호가 안 되는 이유(코드) */
  readonly refReasons: readonly string[];
}

export function approvalRequired(failure: PmartFailure): ApprovalRequired | null {
  if (!(failure instanceof ProblemFailure) || failure.problem.code !== 'APPROVAL_REQUIRED') return null;
  const details = failure.problem.details ?? [];
  const of = (field: string) => details.filter((d) => d.field === field).map((d) => d.reason ?? '').filter(Boolean);
  return { thresholds: of('threshold'), request: of('approvalRequest')[0] ?? null, refReasons: of('approvalRef') };
}

export function ApprovalRequiredNotice({ info }: { readonly info: ApprovalRequired }) {
  return (
    <div role="alert" data-state="approval-required" className="alert alert-warning flex-col items-start text-sm">
      <span className="font-bold">{a.required}</span>
      {info.thresholds.length > 0 && (
        <ul className="list-disc pl-5" aria-label={a.thresholds}>
          {info.thresholds.map((t) => (
            <li key={t}>{t}</li>
          ))}
        </ul>
      )}
      {info.refReasons.map((r) => (
        <span key={r} className="text-error" data-testid="approval-ref-reason">
          {a.refReason[r] ?? r}
        </span>
      ))}
      <span>{a.howTo}</span>
      <span className="text-xs opacity-70">{a.requestPending}</span>
    </div>
  );
}

/** CommandFeedback 과 같고, 422 APPROVAL_REQUIRED 만 승인 안내로 바꿔 그린다. */
export function ApprovalAwareFeedback<V, T>({ command, children }: { readonly command: Command<V, T>; readonly children?: (result: T) => ReactNode }) {
  const info = command.phase.kind === 'rejected' ? approvalRequired(command.phase.failure) : null;
  if (info) return <ApprovalRequiredNotice info={info} />;
  return children ? <CommandFeedback command={command}>{children}</CommandFeedback> : <CommandFeedback command={command} />;
}

export function ApprovalRefInput({ value, onChange, hint = a.refHint }: { readonly value: string; readonly onChange: (v: string) => void; readonly hint?: string }) {
  return (
    <label className="flex flex-col gap-1">
      {a.ref}
      <input className="input input-sm w-56 font-mono" maxLength={128} value={value} onChange={(e) => onChange(e.target.value)} />
      <span className="text-xs opacity-70">{hint}</span>
    </label>
  );
}
