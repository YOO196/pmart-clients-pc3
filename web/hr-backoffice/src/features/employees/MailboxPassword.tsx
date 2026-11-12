// 사서함(웹메일) 초기 비밀번호 발급(POST …/mailbox-password-resets).
// - 응답의 initialPassword 는 이 컴포넌트의 상태에만 둔다: 저장·로그·클립보드 자동 복사를 하지 않고, 닫거나 화면을 떠나면 사라진다.
// - 서버는 같은 Idempotency-Key 재전송도 재생하지 않고 새로 발급한다 → 결과를 못 받았을 때 자동으로 다시 보내지 않는다(사람이 다시 누른다).
// - 서버 캐시(TanStack Query)에 넣지 않는다.
import { useState } from 'react';

import { IdempotencyKey, NetworkFailure, PmartFailure, request, UnknownResultFailure } from '@pmart/web-core';
import { FailureAlert } from '@pmart/web-ui';
import { commandParams } from '../../api/command';
import { useApi } from '../../app/ApiContext';
import { messages as m } from '../../shared/messages';

type Phase =
  | { readonly kind: 'idle' }
  | { readonly kind: 'running' }
  | { readonly kind: 'issued'; readonly mailAddress: string; readonly initialPassword: string }
  | { readonly kind: 'rejected'; readonly failure: PmartFailure }
  | { readonly kind: 'unknown' };

export function MailboxPassword({ operatorId }: { readonly operatorId: string }) {
  const api = useApi();
  const [phase, setPhase] = useState<Phase>({ kind: 'idle' });

  const issue = async () => {
    setPhase({ kind: 'running' });
    try {
      const result = await request(
        'POST',
        api.hr.POST('/hr/employees/{operatorId}/mailbox-password-resets', commandParams(IdempotencyKey.generate(), { path: { operatorId } })),
      );
      setPhase({ kind: 'issued', mailAddress: result.mailAddress, initialPassword: result.initialPassword });
    } catch (e) {
      const failure = e instanceof PmartFailure ? e : new PmartFailure('UNEXPECTED');
      setPhase(failure instanceof UnknownResultFailure || failure instanceof NetworkFailure ? { kind: 'unknown' } : { kind: 'rejected', failure });
    }
  };

  return (
    <div className="space-y-2 border-t border-base-300 pt-3">
      <h3 className="text-sm font-semibold">{m.mailbox.title}</h3>
      <p className="text-xs opacity-70">{m.mailbox.note}</p>
      {phase.kind === 'issued' ? (
        <div role="alert" className="alert alert-warning flex-col items-start text-sm">
          <p>{m.mailbox.once}</p>
          <dl className="grid grid-cols-[8rem_1fr] gap-1">
            <dt>{m.fields.mailAddress}</dt>
            <dd>{phase.mailAddress}</dd>
            <dt>{m.mailbox.password}</dt>
            <dd>
              <code data-testid="initial-password" className="select-all">
                {phase.initialPassword}
              </code>
            </dd>
          </dl>
          <button type="button" className="btn btn-sm" onClick={() => setPhase({ kind: 'idle' })}>
            {m.mailbox.hide}
          </button>
        </div>
      ) : (
        <>
          <p className="text-xs opacity-70">{m.mailbox.issueWarning}</p>
          <button type="button" className="btn btn-sm" disabled={phase.kind === 'running'} onClick={() => void issue()}>
            {m.mailbox.issue}
          </button>
          {phase.kind === 'running' && (
            <p role="status" className="text-sm">
              {m.running}
            </p>
          )}
          {phase.kind === 'unknown' && (
            <p role="alert" data-state="unknown" className="alert alert-info text-sm">
              {m.mailbox.unknown}
            </p>
          )}
          {phase.kind === 'rejected' && <FailureAlert failure={phase.failure} />}
        </>
      )}
    </div>
  );
}
