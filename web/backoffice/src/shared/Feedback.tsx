// 명령 결과·거절 사유 표시. 문구는 Problem code 로만 고른다(title·detail 문자열 비교 금지).
import type { ReactNode } from 'react';

import {
  CommandRejectedFailure,
  type PmartFailure,
  ProblemFailure,
  SessionExpiredFailure,
} from '../api/failure';
import { messages as m } from './messages';
import type { Command } from './useCommand';

export function failureCode(failure: PmartFailure): string | undefined {
  if (failure instanceof ProblemFailure) return failure.problem.code;
  if (failure instanceof CommandRejectedFailure) return 'COMMAND_REJECTED';
  return undefined;
}

export const reasonText = (code: string | null | undefined) => (code ? (m.reason[code] ?? code) : m.none);

export function FailureAlert({ failure }: { readonly failure: PmartFailure }) {
  const code = failureCode(failure);
  const text =
    failure instanceof SessionExpiredFailure ? m.sessionExpired : code ? (m.problem[code] ?? m.rejectedTitle) : m.rejectedTitle;
  const details = failure instanceof ProblemFailure ? failure.problem.details : [];
  return (
    <div role="alert" data-state="rejected" data-code={code} className="alert alert-error flex-col items-start">
      <span className="font-bold">{text}</span>
      {code && <span className="text-xs opacity-70">{code}</span>}
      {details.length > 0 && (
        <ul className="list-disc pl-5 text-sm">
          {details.map((d, i) => (
            <li key={`${d.field ?? ''}-${i}`}>{`${d.field ?? ''} ${reasonText(d.reason)}`.trim()}</li>
          ))}
        </ul>
      )}
      {failure.requestId && <span className="text-xs opacity-70 select-all">{m.requestId(failure.requestId)}</span>}
    </div>
  );
}

/** 명령 진행·거절·불명 표시. 완료 표시는 화면이 children 으로 그린다(ACCEPTED 를 완료로 그리지 않게). */
export function CommandFeedback<V, T>({
  command,
  children,
}: {
  readonly command: Command<V, T>;
  readonly children?: (result: T) => ReactNode;
}) {
  const { phase } = command;
  switch (phase.kind) {
    case 'idle':
      return null;
    case 'running':
      return (
        <div role="status" className="flex items-center gap-2 text-sm">
          <span className="loading loading-spinner loading-sm" />
          {m.running}
        </div>
      );
    case 'done':
      return <>{children?.(phase.result)}</>;
    case 'rejected':
      return <FailureAlert failure={phase.failure} />;
    case 'unknown':
      return (
        <div role="alert" data-state="unknown" className="alert alert-info flex-col items-start">
          <span className="font-bold">{m.unknownTitle}</span>
          <span>{m.unknownBody}</span>
          {phase.failure.requestId && <span className="text-xs opacity-70">{m.requestId(phase.failure.requestId)}</span>}
          <button type="button" className="btn btn-sm btn-outline" onClick={() => void command.resend()}>
            {m.resend}
          </button>
        </div>
      );
  }
}
