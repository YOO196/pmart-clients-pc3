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
/**
 * [compact] 면(작업자 목록 위) 정해 두었을 때 카드 대신 작은 "관리자 번호 변경" 단추만 — 누르면 입력 칸(사용자 2026-11-20).
 * 아직 안 정했으면 어느 쪽이든 카드 전체.
 */
export function BreakPinCard({ mfcId, canEdit = true, compact = false }: { readonly mfcId: string; readonly canEdit?: boolean; readonly compact?: boolean }) {
  const api = useApi();
  const queryClient = useQueryClient();
  const bp = m.breakPin;
  const query = useQuery({
    queryKey: ['break-pin', mfcId],
    queryFn: () => request('GET', api.capacity.GET('/mfcs/{mfcId}/break-pin', { params: { path: { mfcId } } })),
  });
  // 번호를 한 번 정하면 카드는 한 줄 + 작은 "바꾸기" 단추만(사용자 2026-11-20). 누르면 입력 칸이 열린다.
  const [editing, setEditing] = useState(false);
  const [pin, setPin] = useState('');
  const [again, setAgain] = useState('');
  const digits = (v: string) => v.replace(/\D/g, '').slice(0, 4);
  const valid = /^\d{4}$/.test(pin) && pin === again;
  const save = useCommand(async (value: string, key) => {
    const r = await request('PUT', api.capacity.PUT('/mfcs/{mfcId}/break-pin', { ...commandParams(key, { path: { mfcId } }), body: { pin: value } }));
    setPin('');
    setAgain('');
    setEditing(false);
    await queryClient.invalidateQueries({ queryKey: ['break-pin', mfcId] });
    return r;
  });
  const isSet = query.data?.set === true;
  // 아직 안 정했으면(또는 조회 전·실패) 입력 칸을 그대로 보인다 — 정해 두었을 때만 접는다.
  const showForm = canEdit && (!isSet || editing);
  if (compact && isSet && canEdit && !editing)
    return (
      <div className="flex items-center gap-2" data-testid="break-pin">
        <button
          type="button"
          className="btn btn-xs"
          onClick={() => {
            setEditing(true);
            if (save.phase.kind !== 'idle' && save.phase.kind !== 'running') save.reset();
          }}
        >
          {bp.adminChange}
        </button>
        <CommandFeedback command={save}>
          {() => (
            <p role="status" className="text-xs">
              {bp.saved}
            </p>
          )}
        </CommandFeedback>
      </div>
    );
  return (
    <div className="space-y-2 rounded-box bg-base-100 p-3 text-sm" data-testid="break-pin">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
        <h2 className="font-bold">{bp.title}</h2>
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
        {canEdit && isSet && (
          <button
            type="button"
            className="btn btn-xs"
            aria-expanded={editing}
            onClick={() => {
              setEditing((v) => !v);
              setPin('');
              setAgain('');
              if (save.phase.kind !== 'idle' && save.phase.kind !== 'running') save.reset();
            }}
          >
            {editing ? bp.cancelChange : bp.change}
          </button>
        )}
      </div>
      {showForm && (
        <>
          <p className="text-xs opacity-70">{bp.intro}</p>
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
              {isSet ? bp.saveChange : bp.save}
            </button>
            {pin.length === 4 && again.length === 4 && pin !== again && (
              <p role="alert" className="w-full text-xs text-error">
                {bp.mismatch}
              </p>
            )}
          </form>
          <p className="text-xs opacity-70">{bp.lockNote}</p>
        </>
      )}
      {canEdit && <CommandFeedback command={save}>{() => <p role="status">{bp.saved}</p>}</CommandFeedback>}
      {!canEdit && !isSet && <p className="text-xs opacity-70">{bp.supervisorOnly}</p>}
    </div>
  );
}
