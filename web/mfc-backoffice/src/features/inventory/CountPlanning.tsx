// 재고 실사 시간대·순환 실사 시작 — 백엔드 지침 clients/all/2026-11-20-guide-count-windows-and-rotation.md
// (사용자 결정 2026-11-20 "하루 두 번 아침 7~8시·저녁 8~9시 기본, 바꿀 수 있게, 관리자가 시작, 20칸, 추천대로").
// - 시간대: mfc-capacity `GET·PUT /mfcs/{mfcId}/count-windows`(0.33.0) — 목록 통째로, X-Expected-Version = 받은 version. 서울 "HH:mm".
//   시간대가 돼도 실사는 저절로 열리지 않는다(그 시간엔 실사를 피킹보다 먼저 준다는 순서 규칙). 지금 시간대인지는 서버 `activeNow`.
// - 순환 실사: mfc-inventory `POST /mfcs/{mfcId}/count-plans` {rotationSize, assigneeId?, reason?}(0.42.0) — 서버가 오래 안 센 칸부터 고른다.
//   고른 칸은 실사가 끝날 때까지 피킹·이동·적치가 막힌다 → 시작 전 확인. 칸이 모자라면 있는 만큼(응답 sessions 수).
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';

import { request } from '@pmart/web-core';
import { CommandFeedback, formatSeoul, QueryState, toUiState, useCommand } from '@pmart/web-ui';
import { commandParams } from '../../api/command';
import type { components as Cap } from '../../api/generated/mfc-capacity';
import type { components as Inv } from '../../api/generated/mfc-inventory';
import { useApi } from '../../app/ApiContext';
import { useSession } from '../../app/SessionContext';
import { messages } from '../../shared/messages';
import { Who } from '../../shared/OperatorLabel';

const m = messages.inventory.countPlan;
type Window = Cap['schemas']['CountWindow'];
type CountPlan = Inv['schemas']['CountPlan'];

const MAX_WINDOWS = 6;
const HHMM = /^([01]\d|2[0-3]):[0-5]\d$/;

/** 저장 전 미리 검사(서버가 최종 판단 — 같은 규칙). 문제가 없으면 null */
export function windowProblem(rows: readonly Window[]): string | null {
  if (rows.length > MAX_WINDOWS) return m.tooManyWindows(MAX_WINDOWS);
  for (const r of rows) {
    if (!HHMM.test(r.startTime) || !HHMM.test(r.endTime)) return m.badTime;
    if (r.startTime >= r.endTime) return m.startBeforeEnd;
  }
  const sorted = [...rows].sort((a, b) => a.startTime.localeCompare(b.startTime));
  for (let i = 1; i < sorted.length; i++) if (sorted[i]!.startTime < sorted[i - 1]!.endTime) return m.overlap;
  return null;
}

/** 재고 실사 시간대 카드 — 보기는 센터 직원 누구나, 바꾸기는 센터 관리자 */
export function CountWindowsCard({ mfcId }: { readonly mfcId: string }) {
  const api = useApi();
  const queryClient = useQueryClient();
  const { session } = useSession();
  const supervisor = session?.roles.includes('MFC_SUPERVISOR') ?? false;
  const query = useQuery({
    queryKey: ['count-windows', mfcId],
    queryFn: () => request('GET', api.capacity.GET('/mfcs/{mfcId}/count-windows', { params: { path: { mfcId } } })),
  });
  const [draft, setDraft] = useState<Window[] | null>(null);
  const save = useCommand(async (rows: readonly Window[], key) => {
    const version = query.data?.version ?? 0;
    try {
      const r = await request('PUT', api.capacity.PUT('/mfcs/{mfcId}/count-windows', { ...commandParams(key, { path: { mfcId }, version }), body: { windows: [...rows] } }));
      queryClient.setQueryData(['count-windows', mfcId], r);
      setDraft(null);
      return r;
    } catch (e) {
      // 409 VERSION_CONFLICT 등 — 다시 읽어 지금 값을 보인다
      await queryClient.invalidateQueries({ queryKey: ['count-windows', mfcId] });
      throw e;
    }
  });
  const problem = draft ? windowProblem(draft) : null;
  const setRow = (i: number, patch: Partial<Window>) => setDraft((d) => (d ? d.map((r, j) => (j === i ? { ...r, ...patch } : r)) : d));
  return (
    <section className="space-y-2 rounded-box bg-base-100 p-4" aria-label={m.windowsTitle} data-testid="count-windows">
      <QueryState state={toUiState(query)} onRetry={() => void query.refetch()}>
        {(w) => (
          <>
            <div className="flex flex-wrap items-center gap-2">
              <h2 className="font-bold">{m.windowsTitle}</h2>
              {w.source === 'DEFAULT' && <span className="badge badge-sm">{m.defaultTag}</span>}
              {w.activeNow && <span className="badge badge-sm badge-success" data-testid="count-window-active">{m.activeNow}</span>}
              {supervisor && !draft && (
                <button type="button" className="btn btn-xs ml-auto" onClick={() => setDraft(w.windows.map((r) => ({ ...r })))}>
                  {m.edit}
                </button>
              )}
            </div>
            {!draft ? (
              <p data-testid="count-windows-text">
                {w.windows.length === 0 ? m.none : w.windows.map((r) => `${r.startTime}–${r.endTime}`).join(' · ')}
                {w.updatedAt && (
                  <span className="ml-2 text-xs text-base-content/60">
                    {`${m.changed} `}
                    <Who id={w.updatedBy} />
                    {` · ${formatSeoul(w.updatedAt)}`}
                  </span>
                )}
              </p>
            ) : (
              <form
                className="space-y-2"
                aria-label={m.save}
                onSubmit={(e) => {
                  e.preventDefault();
                  if (problem) return;
                  if (save.phase.kind === 'rejected' || save.phase.kind === 'done') save.reset();
                  void save.run(draft);
                }}
              >
                {draft.map((r, i) => (
                  <div key={i} className="flex flex-wrap items-center gap-2" data-testid="count-window-row">
                    <input type="time" step={600} className="input input-sm w-32" aria-label={m.start(i + 1)} value={r.startTime} onChange={(e) => setRow(i, { startTime: e.target.value })} />
                    <span>–</span>
                    <input type="time" step={600} className="input input-sm w-32" aria-label={m.end(i + 1)} value={r.endTime} onChange={(e) => setRow(i, { endTime: e.target.value })} />
                    <button type="button" className="btn btn-ghost btn-xs" onClick={() => setDraft((d) => (d ? d.filter((_, j) => j !== i) : d))}>
                      {m.remove}
                    </button>
                  </div>
                ))}
                {draft.length === 0 && <p className="text-xs text-base-content/60">{m.emptyMeans}</p>}
                <div className="flex flex-wrap items-center gap-2">
                  <button
                    type="button"
                    className="btn btn-xs"
                    disabled={draft.length >= MAX_WINDOWS}
                    onClick={() => setDraft((d) => (d ? [...d, { startTime: '12:00', endTime: '13:00' }] : d))}
                  >
                    {m.add}
                  </button>
                  <button type="button" className="btn btn-xs" onClick={() => setDraft([{ startTime: '07:00', endTime: '08:00' }, { startTime: '20:00', endTime: '21:00' }])}>
                    {m.restoreDefault}
                  </button>
                </div>
                {problem && (
                  <p role="alert" className="text-xs text-error">
                    {problem}
                  </p>
                )}
                <div className="flex gap-2">
                  <button type="submit" className="btn btn-sm btn-primary" disabled={!!problem || save.busy}>
                    {m.save}
                  </button>
                  <button type="button" className="btn btn-sm btn-ghost" onClick={() => setDraft(null)} disabled={save.busy}>
                    {m.cancel}
                  </button>
                </div>
              </form>
            )}
            <p className="text-xs text-base-content/60">{m.windowsNote}</p>
          </>
        )}
      </QueryState>
      <CommandFeedback command={save}>{() => <p role="status">{m.saved}</p>}</CommandFeedback>
    </section>
  );
}

/** 순환 실사 시작 — 서버가 오래 안 센 칸부터 고른다(센터 관리자) */
export function RotationCountStart({ mfcId }: { readonly mfcId: string }) {
  const api = useApi();
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [size, setSize] = useState('20');
  const [assignee, setAssignee] = useState('');
  const [reason, setReason] = useState('');
  const n = Number(size);
  const validSize = Number.isInteger(n) && n >= 1 && n <= 200;
  const workers = useQuery({
    queryKey: ['workers', mfcId, 'ACTIVE'],
    enabled: open,
    queryFn: async () => (await request('GET', api.capacity.GET('/mfcs/{mfcId}/workers', { params: { path: { mfcId }, query: { state: 'ACTIVE' } } }))).items ?? [],
  });
  const start = useCommand(async (_: null, key): Promise<CountPlan> => {
    const plan = await request(
      'POST',
      api.inventory.POST('/mfcs/{mfcId}/count-plans', {
        ...commandParams(key, { path: { mfcId } }),
        body: { rotationSize: n, ...(assignee ? { assigneeId: assignee } : {}), ...(reason.trim() ? { reason: reason.trim() } : {}) },
      }),
    );
    setConfirming(false);
    await queryClient.invalidateQueries({ queryKey: ['list', 'count-sessions', mfcId] });
    return plan;
  });
  return (
    <section className="space-y-2 rounded-box bg-base-100 p-4" aria-label={m.rotationTitle} data-testid="rotation-count">
      <div className="flex flex-wrap items-center gap-2">
        <h2 className="font-bold">{m.rotationTitle}</h2>
        <span className="text-xs text-base-content/60">{m.rotationHint}</span>
        {!open && (
          <button type="button" className="btn btn-sm btn-primary ml-auto" onClick={() => setOpen(true)}>
            {m.rotationStart}
          </button>
        )}
      </div>
      {open && (
        <form
          className="space-y-2"
          aria-label={m.rotationStart}
          onSubmit={(e) => {
            e.preventDefault();
            if (!validSize) return;
            if (!confirming) {
              setConfirming(true);
              return;
            }
            if (start.phase.kind === 'rejected' || start.phase.kind === 'done') start.reset();
            void start.run(null);
          }}
        >
          <div className="flex flex-wrap items-end gap-2">
            <label className="flex flex-col gap-1">
              {m.size}
              <input
                className="input input-sm w-24"
                inputMode="numeric"
                value={size}
                onChange={(e) => {
                  setSize(e.target.value.replace(/\D/g, '').slice(0, 3));
                  setConfirming(false);
                }}
              />
            </label>
            <label className="flex flex-col gap-1">
              {m.assignee}
              <select className="select select-sm w-56" value={assignee} onChange={(e) => setAssignee(e.target.value)}>
                <option value="">{m.anyone}</option>
                {(workers.data ?? []).map((w) => (
                  <option key={w.workerId} value={w.workerId}>
                    {[w.name ?? w.displayName ?? m.noName, w.employeeNo].filter(Boolean).join(' · ')}
                  </option>
                ))}
              </select>
            </label>
            <label className="flex flex-col gap-1">
              {m.reason}
              <input className="input input-sm w-56" maxLength={200} placeholder={m.reasonPlaceholder} value={reason} onChange={(e) => setReason(e.target.value)} />
            </label>
          </div>
          {!validSize && <p className="text-xs text-error">{m.badSize}</p>}
          {confirming && (
            <p role="alert" className="alert alert-warning py-2 text-sm" data-testid="rotation-confirm">
              {m.lockWarning(n)}
            </p>
          )}
          <div className="flex gap-2">
            <button type="submit" className={`btn btn-sm ${confirming ? 'btn-warning' : 'btn-primary'}`} disabled={!validSize || start.busy}>
              {confirming ? m.confirmStart : m.next}
            </button>
            <button
              type="button"
              className="btn btn-sm btn-ghost"
              disabled={start.busy}
              onClick={() => {
                setOpen(false);
                setConfirming(false);
              }}
            >
              {m.cancel}
            </button>
          </div>
        </form>
      )}
      <CommandFeedback command={start}>
        {(plan: CountPlan) => {
          const codes = (plan.sessions ?? []).map((s) => s.locationCode ?? '').filter(Boolean);
          return (
            <div role="status" className="space-y-1 text-sm" data-testid="rotation-result">
              <p className="font-semibold">{m.opened(codes.length, n)}</p>
              <p className="font-mono text-xs">{codes.join(' · ')}</p>
            </div>
          );
        }}
      </CommandFeedback>
    </section>
  );
}
