// 본사 승인 번호(AP-1, inventory 0.22.0·quality 0.3.0·capacity 0.16.0 — 백엔드 공지 clients/mfc-backoffice/2026-11-17-notice-mfc-approval-ref-and-new-fields.md §1).
// - 승인 번호(approvalRef)는 선택. 기준(한 건 손실 10만 원 이상 또는 한 SKU 20개 이상, 운영 제한 해제는 늘)이면 서버가 422 APPROVAL_REQUIRED.
// - 그 거절의 details: field=threshold → 걸린 기준 문장(보여 준다), field=approvalRequest → approval-service 변경 요청 본문(JSON 문자열 — 화면에 쏟지 않는다),
//   field=approvalRef → 번호가 왜 안 되는지(NOT_APPROVED·ALREADY_USED·EXPIRED·NOT_YET_EFFECTIVE·SELF_APPROVAL·TARGET_MISMATCH·OUT_OF_SCOPE).
// - 본사 승인 요청 보내기: 그 요청 본문으로 approval-service `POST /change-requests`(초안) → `POST …/{id}/submissions`(제출, 202 resultId = approvalId).
//   받은 승인 번호를 화면의 번호 칸에 넣어 둔다 — 본사(백오피스 승인함)가 승인하면 작업자가 같은 내용으로 다시 보낸다(자동으로 다시 보내지 않는다).
//   결과 불명이면 같은 키로만 다시(초안을 이미 만들었으면 제출만). 409 DUPLICATE_APPROVAL = 같은 대상의 열린 승인이 이미 있다.
// - 승인 상태 확인: `GET /approvals/{approvalId}` 의 reviewState(승인 대기·승인·반려·만료 …) — 보기만.
import { useQuery } from '@tanstack/react-query';
import { type ReactNode, useRef, useState } from 'react';

import { IdempotencyKey, type PmartFailure, ProblemFailure, request } from '@pmart/web-core';
import { type Command, CommandFeedback, useCommand } from '@pmart/web-ui';
import { commandParams } from '../api/command';
import type { components as ApprovalC } from '../api/generated/approval';
import { useApi } from '../app/ApiContext';
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

type ChangeRequestBody = ApprovalC['schemas']['ChangeRequestBody'];

/** details 의 요청 본문(JSON 문자열) → 변경 요청 본문. 모양이 아니면 null(요청 단추를 숨긴다). */
export function parseApprovalRequest(raw: string | null): ChangeRequestBody | null {
  if (!raw) return null;
  try {
    const v = JSON.parse(raw) as Partial<ChangeRequestBody> | null;
    return v && typeof v === 'object' && typeof v.targetRef === 'string' && typeof v.type === 'string' ? (v as ChangeRequestBody) : null;
  } catch {
    return null;
  }
}

/** 본사 승인 요청 보내기 — 초안 만들기 → 제출. 받은 승인 번호를 [onApprovalId] 로 넘긴다. */
function RequestApproval({ body, onApprovalId }: { readonly body: ChangeRequestBody; readonly onApprovalId?: ((id: string) => void) | undefined }) {
  const api = useApi();
  const draft = useRef<{ id: string; version: number | undefined } | null>(null);
  const submitKey = useRef<IdempotencyKey | null>(null);
  const [approvalId, setApprovalId] = useState<string | null>(null);
  const send = useCommand(async (_: null, key) => {
    if (!draft.current) {
      const cr = await request('POST', api.approval.POST('/change-requests', { ...commandParams(key), body }));
      draft.current = { id: cr.changeRequestId ?? '', version: cr.version ?? undefined };
    }
    submitKey.current ??= IdempotencyKey.generate();
    const { id, version } = draft.current;
    const r = await request(
      'POST',
      api.approval.POST('/change-requests/{changeRequestId}/submissions', { ...commandParams(submitKey.current, { path: { changeRequestId: id }, version }) }),
    );
    const issued = r.resultId ?? '';
    setApprovalId(issued);
    if (issued) onApprovalId?.(issued);
    return issued;
  });
  if (approvalId) {
    return (
      <div className="space-y-1" data-testid="approval-requested">
        <p className="font-semibold">{a.requested(approvalId)}</p>
        <ApprovalStatus approvalId={approvalId} />
      </div>
    );
  }
  const duplicate = send.phase.kind === 'rejected' && send.phase.failure instanceof ProblemFailure && send.phase.failure.problem.code === 'DUPLICATE_APPROVAL';
  return (
    <div className="space-y-1">
      <button type="button" className="btn btn-sm btn-warning" disabled={send.busy} onClick={() => void send.run(null)}>
        {a.requestButton}
      </button>
      {duplicate ? <p className="font-semibold">{a.duplicate}</p> : <CommandFeedback command={send} />}
    </div>
  );
}

/** 승인 상태(보기만) — 누를 때 다시 읽는다. */
function ApprovalStatus({ approvalId }: { readonly approvalId: string }) {
  const api = useApi();
  const query = useQuery({
    queryKey: ['approval', approvalId],
    enabled: false,
    queryFn: () => request('GET', api.approval.GET('/approvals/{approvalId}', { params: { path: { approvalId } } })),
  });
  const state = query.data?.reviewState;
  return (
    <div className="flex flex-wrap items-center gap-2">
      <button type="button" className="btn btn-xs" disabled={query.isFetching} onClick={() => void query.refetch()}>
        {a.checkStatus}
      </button>
      {state && (
        <span data-testid="approval-review-state" className={state === 'APPROVED' ? 'font-semibold text-success' : ''}>
          {a.reviewState[state] ?? state}
        </span>
      )}
      {query.isError && <span>{a.statusFailed}</span>}
    </div>
  );
}

export function ApprovalRequiredNotice({ info, onApprovalId }: { readonly info: ApprovalRequired; readonly onApprovalId?: ((id: string) => void) | undefined }) {
  const body = parseApprovalRequest(info.request);
  return (
    // daisyUI alert 는 넓은 화면에서 자식을 가로 칸으로 나눈다 — 내용을 한 덩어리로 묶어 위아래로 쌓는다.
    <div role="alert" data-state="approval-required" className="alert alert-warning text-sm">
      <div className="w-full space-y-1">
        <p className="font-bold">{a.required}</p>
        {info.thresholds.length > 0 && (
          <ul className="list-disc pl-5" aria-label={a.thresholds}>
            {info.thresholds.map((t) => (
              <li key={t}>{t}</li>
            ))}
          </ul>
        )}
        {info.refReasons.map((r) => (
          <p key={r} className="font-semibold" data-testid="approval-ref-reason">
            {a.refReason[r] ?? r}
          </p>
        ))}
        {body ? <RequestApproval body={body} onApprovalId={onApprovalId} /> : info.refReasons.length === 0 && <p className="text-xs opacity-70">{a.noRequestBody}</p>}
        <p>{a.howTo}</p>
      </div>
    </div>
  );
}

/** CommandFeedback 과 같고, 422 APPROVAL_REQUIRED 만 승인 안내로 바꿔 그린다. */
export function ApprovalAwareFeedback<V, T>({
  command,
  children,
  onApprovalId,
}: {
  readonly command: Command<V, T>;
  readonly children?: (result: T) => ReactNode;
  /** 본사 승인 요청으로 받은 번호 — 화면의 번호 칸에 넣는다 */
  readonly onApprovalId?: ((id: string) => void) | undefined;
}) {
  const info = command.phase.kind === 'rejected' ? approvalRequired(command.phase.failure) : null;
  if (info) return <ApprovalRequiredNotice info={info} onApprovalId={onApprovalId} />;
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
