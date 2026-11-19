// 센터 휴게 번호(mfc-capacity 0.20.0) `GET·PUT /mfcs/{mfcId}/break-pin` — 작업자가 PDA 로 휴게를 켤 때 넣는 4자리.
// 서버는 번호를 돌려주지 않는다(정했는지·언제·누가만). 바꾸기는 그 센터 MFC_SUPERVISOR — 작업자 목록 위와 "내 정보"에서 같은 카드(작업자는 보기만).
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';

import { request } from '@pmart/web-core';
import { CommandFeedback, formatSeoul, QueryState, toUiState, useCommand } from '@pmart/web-ui';
import { commandParams } from '../../api/command';
import { useApi } from '../../app/ApiContext';
import { messages } from '../../shared/messages';
import { Who } from '../../shared/OperatorLabel';

const m = messages.workers;

/** 작업자가 PDA 로 휴게를 켤 때 넣는 4자리. 서버는 정했는지·언제만 준다 — 번호는 화면에도 다시 보이지 않는다. */
export function BreakPinCard({ mfcId, canEdit = true }: { readonly mfcId: string; readonly canEdit?: boolean }) {
  const api = useApi();
  const queryClient = useQueryClient();
  const bp = m.breakPin;
  const query = useQuery({
    queryKey: ['break-pin', mfcId],
    queryFn: () => request('GET', api.capacity.GET('/mfcs/{mfcId}/break-pin', { params: { path: { mfcId } } })),
  });
  const [pin, setPin] = useState('');
  const [again, setAgain] = useState('');
  const digits = (v: string) => v.replace(/\D/g, '').slice(0, 4);
  const valid = /^\d{4}$/.test(pin) && pin === again;
  const save = useCommand(async (value: string, key) => {
    const r = await request('PUT', api.capacity.PUT('/mfcs/{mfcId}/break-pin', { ...commandParams(key, { path: { mfcId } }), body: { pin: value } }));
    setPin('');
    setAgain('');
    await queryClient.invalidateQueries({ queryKey: ['break-pin', mfcId] });
    return r;
  });
  return (
    <div className="space-y-2 rounded-box bg-base-100 p-3 text-sm" data-testid="break-pin">
      <h2 className="font-bold">{bp.title}</h2>
      <p className="text-xs opacity-70">{bp.intro}</p>
      <QueryState state={toUiState(query)} onRetry={() => void query.refetch()}>
        {(s) => (
          <p data-testid="break-pin-status">
            {s.set ? (
              <>
                {`${bp.set} · `}
                <Who id={s.updatedBy} />
                {` · ${s.updatedAt ? formatSeoul(s.updatedAt) : messages.none}`}
              </>
            ) : (
              bp.notSet
            )}
          </p>
        )}
      </QueryState>
      {canEdit ? (
        <>
          <form
            className="flex flex-wrap items-end gap-2"
            aria-label={bp.save}
            onSubmit={(e) => {
              e.preventDefault();
              if (!valid) return;
              if (save.phase.kind === 'rejected' || save.phase.kind === 'done') save.reset();
              void save.run(pin);
            }}
          >
            <label className="flex flex-col gap-1">
              {bp.newPin}
              <input
                className="input input-sm w-28 text-center tracking-widest"
                type="password"
                inputMode="numeric"
                autoComplete="off"
                maxLength={4}
                value={pin}
                onChange={(e) => setPin(digits(e.target.value))}
              />
            </label>
            <label className="flex flex-col gap-1">
              {bp.confirmPin}
              <input
                className="input input-sm w-28 text-center tracking-widest"
                type="password"
                inputMode="numeric"
                autoComplete="off"
                maxLength={4}
                value={again}
                onChange={(e) => setAgain(digits(e.target.value))}
              />
            </label>
            <button type="submit" className="btn btn-sm btn-primary" disabled={!valid || save.busy}>
              {bp.save}
            </button>
            {pin.length === 4 && again.length === 4 && pin !== again && (
              <p role="alert" className="w-full text-xs text-error">
                {bp.mismatch}
              </p>
            )}
          </form>
          <p className="text-xs opacity-70">{bp.lockNote}</p>
          <CommandFeedback command={save}>{() => <p role="status">{bp.saved}</p>}</CommandFeedback>
        </>
      ) : (
        <p className="text-xs opacity-70">{bp.supervisorOnly}</p>
      )}
    </div>
  );
}
