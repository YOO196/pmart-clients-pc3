// 운영자 계정 관리(OPERATOR_ADMIN, ADR-0018 §4): 목록·생성·역할/센터/상태 수정(X-Expected-Version)·비밀번호 초기화.
// 권한 판정은 서버(403 → FORBIDDEN 화면). 바뀐 역할은 다음 로그인·토큰 갱신부터 반영된다.
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { useSearchParams } from 'react-router';

import type { OperatorAccount } from '../../api/auth';
import { commandParams } from '../../api/command';
import { request, requestNoContent } from '../../api/pmartFetch';
import { useApi } from '../../app/ApiContext';
import { CommandFeedback } from '../../shared/Feedback';
import { formatSeoul } from '../../shared/format';
import { messages as m } from '../../shared/messages';
import { QueryState } from '../../shared/QueryState';
import { toUiState } from '../../shared/toUiState';
import { useCommand } from '../../shared/useCommand';

const list = (s: string) =>
  s
    .split(',')
    .map((x) => x.trim())
    .filter(Boolean);

const KEY = ['auth', 'operators'];

function CreateAccount() {
  const api = useApi();
  const queryClient = useQueryClient();
  const [v, setV] = useState({ loginId: '', displayName: '', initialPassword: '', roles: '', centers: '' });
  const cmd = useCommand(async (body: { loginId: string; displayName: string; initialPassword: string; roles: string[]; centers: string[] }, key) => {
    const a = await request('POST', api.auth.POST('/operator-accounts', { ...commandParams(key), body }));
    setV({ loginId: '', displayName: '', initialPassword: '', roles: '', centers: '' });
    await queryClient.invalidateQueries({ queryKey: KEY });
    return a;
  });
  const field = (k: keyof typeof v, label: string, type = 'text') => (
    <label className="flex flex-col gap-1 text-sm">
      {label}
      <input
        className="input input-sm"
        type={type}
        autoComplete={type === 'password' ? 'new-password' : 'off'}
        value={v[k]}
        onChange={(e) => setV({ ...v, [k]: e.target.value })}
      />
    </label>
  );
  const ok = /^[a-z0-9][a-z0-9._-]{2,63}$/.test(v.loginId) && v.displayName.trim() && v.initialPassword;

  return (
    <form
      className="space-y-2 rounded-box bg-base-100 p-4"
      onSubmit={(e) => {
        e.preventDefault();
        if (ok)
          void cmd.run({
            loginId: v.loginId,
            displayName: v.displayName.trim(),
            initialPassword: v.initialPassword,
            roles: list(v.roles),
            centers: list(v.centers),
          });
      }}
    >
      <h2 className="font-bold">{m.operators.create}</h2>
      <div className="flex flex-wrap gap-2">
        {field('loginId', m.operators.loginId)}
        {field('displayName', m.operators.displayName)}
        {field('initialPassword', m.operators.initialPassword, 'password')}
        {field('roles', m.operators.roles)}
        {field('centers', m.operators.centers)}
      </div>
      <p className="text-xs opacity-70">{`${m.operators.knownRoles} · ${m.password.rule}`}</p>
      <button type="submit" className="btn btn-primary btn-sm" disabled={!ok || cmd.busy}>
        {m.operators.create}
      </button>
      <CommandFeedback command={cmd}>
        {(a) => (
          <p role="status" className="text-success text-sm">
            {m.operators.created(a.loginId)}
          </p>
        )}
      </CommandFeedback>
    </form>
  );
}

function AccountRow({ account }: { readonly account: OperatorAccount }) {
  const api = useApi();
  const queryClient = useQueryClient();
  const [editing, setEditing] = useState(false);
  const [v, setV] = useState({
    displayName: account.displayName,
    roles: account.roles.join(', '),
    centers: account.centers.join(', '),
    state: account.state,
  });
  const [temp, setTemp] = useState('');
  const operatorId = account.operatorId;

  const save = useCommand(async (body: { displayName: string; roles: string[]; centers: string[]; state: 'ACTIVE' | 'DISABLED' }, key) => {
    const a = await request(
      'PUT',
      api.auth.PUT('/operator-accounts/{operatorId}', { ...commandParams(key, { path: { operatorId }, version: account.version }), body }),
    );
    await queryClient.invalidateQueries({ queryKey: KEY });
    return a;
  });
  const reset = useCommand(async (temporaryPassword: string, key) => {
    await requestNoContent(
      'POST',
      api.auth.POST('/operator-accounts/{operatorId}/password-resets', {
        ...commandParams(key, { path: { operatorId } }),
        body: { temporaryPassword },
      }),
    );
    setTemp('');
    await queryClient.invalidateQueries({ queryKey: KEY });
    return true;
  });

  return (
    <>
      <tr>
        <td>{account.loginId}</td>
        <td>{account.displayName}</td>
        <td>{account.roles.join(', ') || m.none}</td>
        <td>{account.centers.join(', ') || m.none}</td>
        <td>
          {m.operators.stateName[account.state]}
          {account.locked && <span className="badge badge-warning badge-sm ml-1">{m.operators.locked}</span>}
          {account.passwordChangeRequired && <span className="badge badge-ghost badge-sm ml-1">{m.operators.passwordChangeRequired}</span>}
        </td>
        <td>{account.lastLoginAt ? formatSeoul(account.lastLoginAt) : m.none}</td>
        <td>
          <button type="button" className="btn btn-xs" onClick={() => setEditing(!editing)}>
            {m.operators.edit}
          </button>
        </td>
      </tr>
      {editing && (
        <tr>
          <td colSpan={7} className="space-y-2 bg-base-200">
            <div className="flex flex-wrap items-end gap-2">
              <label className="flex flex-col text-sm">
                {m.operators.displayName}
                <input className="input input-sm" value={v.displayName} onChange={(e) => setV({ ...v, displayName: e.target.value })} />
              </label>
              <label className="flex flex-col text-sm">
                {m.operators.roles}
                <input className="input input-sm w-72" value={v.roles} onChange={(e) => setV({ ...v, roles: e.target.value })} />
              </label>
              <label className="flex flex-col text-sm">
                {m.operators.centers}
                <input className="input input-sm" value={v.centers} onChange={(e) => setV({ ...v, centers: e.target.value })} />
              </label>
              <label className="flex flex-col text-sm">
                {m.operators.state}
                <select
                  className="select select-sm"
                  value={v.state}
                  onChange={(e) => setV({ ...v, state: e.target.value === 'DISABLED' ? 'DISABLED' : 'ACTIVE' })}
                >
                  <option value="ACTIVE">{m.operators.stateName.ACTIVE}</option>
                  <option value="DISABLED">{m.operators.stateName.DISABLED}</option>
                </select>
              </label>
              <button
                type="button"
                className="btn btn-primary btn-sm"
                disabled={save.busy || !v.displayName.trim()}
                onClick={() => void save.run({ displayName: v.displayName.trim(), roles: list(v.roles), centers: list(v.centers), state: v.state })}
              >
                {m.operators.save}
              </button>
            </div>
            <CommandFeedback command={save}>
              {() => (
                <p role="status" className="text-success text-sm">
                  {m.operators.saved}
                </p>
              )}
            </CommandFeedback>
            <div className="flex flex-wrap items-end gap-2">
              <label className="flex flex-col text-sm">
                {m.operators.temporaryPassword}
                <input className="input input-sm" type="password" autoComplete="new-password" value={temp} onChange={(e) => setTemp(e.target.value)} />
              </label>
              <button type="button" className="btn btn-sm" disabled={reset.busy || !temp} onClick={() => void reset.run(temp)}>
                {m.operators.reset}
              </button>
            </div>
            <CommandFeedback command={reset}>
              {() => (
                <p role="status" className="text-success text-sm">
                  {m.operators.resetDone}
                </p>
              )}
            </CommandFeedback>
          </td>
        </tr>
      )}
    </>
  );
}

export function OperatorAccountsPage() {
  const api = useApi();
  const [params, setParams] = useSearchParams();
  const cursor = params.get('cursor') ?? undefined;
  const query = useQuery({
    queryKey: [...KEY, cursor],
    queryFn: () => request('GET', api.auth.GET('/operator-accounts', { params: { query: { size: 100, ...(cursor ? { cursor } : {}) } } })),
  });

  return (
    <section className="space-y-4">
      <h1 className="text-xl font-bold">{m.operators.title}</h1>
      <p className="text-xs opacity-70">{m.operators.adminOnly}</p>
      <QueryState state={toUiState(query, (d) => (d.items?.length ?? 0) === 0)} onRetry={() => void query.refetch()}>
        {(d) => (
          <>
            <CreateAccount />
            <table className="table table-sm bg-base-100">
              <thead>
                <tr>
                  <th>{m.operators.loginId}</th>
                  <th>{m.operators.displayName}</th>
                  <th>{m.operators.roles}</th>
                  <th>{m.operators.centers}</th>
                  <th>{m.operators.state}</th>
                  <th>{m.operators.lastLoginAt}</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {(d.items ?? []).map((a) => (
                  <AccountRow key={a.operatorId} account={a} />
                ))}
              </tbody>
            </table>
            {d.page?.nextCursor && (
              <button type="button" className="btn btn-sm" onClick={() => setParams({ cursor: d.page?.nextCursor ?? '' })}>
                {m.more}
              </button>
            )}
          </>
        )}
      </QueryState>
    </section>
  );
}
