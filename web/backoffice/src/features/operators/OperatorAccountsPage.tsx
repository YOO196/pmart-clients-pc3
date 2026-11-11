// 운영자 계정 관리(OPERATOR_ADMIN, ADR-0018 §4): 목록·생성·역할/센터/상태 수정(X-Expected-Version)·비밀번호 초기화.
// 권한 판정은 서버(403 → FORBIDDEN 화면). 바뀐 역할은 다음 로그인·토큰 갱신부터 반영된다.
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { useSearchParams } from 'react-router';

import type { OperatorAccount } from '../../api/auth';
import { commandParams } from '../../api/command';
import { PmartFailure } from '../../api/failure';
import { request, requestNoContent } from '../../api/pmartFetch';
import { useApi } from '../../app/ApiContext';
import { CommandFeedback, FailureAlert } from '../../shared/Feedback';
import { formatSeoul } from '../../shared/format';
import { messages as m } from '../../shared/messages';
import { MultiSelectDropdown } from '../../shared/MultiSelectDropdown';
import { QueryState } from '../../shared/QueryState';
import { toUiState } from '../../shared/toUiState';
import { useCommand } from '../../shared/useCommand';

const KEY = ['auth', 'operators'];

/**
 * 고를 수 있는 역할. 계약 `RoleName` 은 enum 이 아니고 역할 목록 API 도 없어, 계약 설명에 적힌 5개를 쓴다.
 * 계정이 이미 가진 다른 역할은 "(목록에 없음)"으로 남겨 저장 때 지워지지 않게 한다.
 */
const KNOWN_ROLES = ['MD', 'PRODUCT_APPROVER', 'DISPLAY_APPROVER', 'PRICE_APPROVER', 'OPERATOR_ADMIN'] as const;

/** 역할 선택(여러 개, 사용자 요청 2026-11-07: 쉼표 입력은 오타 위험 → 드롭다운) */
function RolePicker({ value, onChange }: { readonly value: readonly string[]; readonly onChange: (next: string[]) => void }) {
  const known = new Set<string>(KNOWN_ROLES);
  const label = (r: string) => (known.has(r) ? m.operators.roleLabel(r) : m.operators.rolesUnknown(r));
  const options = [
    ...value.filter((r) => !known.has(r)).map((r) => ({ value: r, label: m.operators.rolesUnknown(r) })),
    ...KNOWN_ROLES.map((r) => ({ value: r, label: m.operators.roleLabel(r) })),
  ];
  return (
    <div className="flex w-72 flex-col gap-1 text-sm">
      <MultiSelectDropdown
        label={m.operators.roles}
        options={options}
        value={value}
        onChange={onChange}
        placeholder={m.operators.rolesPick}
        selectedText={m.operators.rolesSelected}
      />
      {value.length > 0 && (
        <ul className="flex flex-wrap gap-1" aria-label={m.operators.roles}>
          {value.map((r) => (
            <li key={r} className="badge badge-outline gap-1">
              {label(r)}
              <button type="button" aria-label={`${label(r)} 빼기`} onClick={() => onChange(value.filter((x) => x !== r))}>
                ✕
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

/**
 * 센터 선택(여러 개). 목록은 center-master `GET /centers`. 목록 조회에 실패해도 계정 화면은 쓸 수 있게
 * 이미 고른 ID 는 "(목록에 없음)" 으로 남겨 두고 실패는 표시만 한다(사용자 요청 2026-11-03: 쉼표 입력 → 드롭다운).
 */
function CenterPicker({ value, onChange }: { readonly value: readonly string[]; readonly onChange: (next: string[]) => void }) {
  const api = useApi();
  const query = useQuery({
    queryKey: ['center', 'list'],
    queryFn: () => request('GET', api.center.GET('/centers', { params: { query: { size: 100 } } })),
  });
  const centers = query.data?.items ?? [];
  const known = new Set(centers.map((c) => c.centerId));
  const label = (id: string) => {
    const c = centers.find((x) => x.centerId === id);
    return c ? `${c.name ?? id} · ${id}` : m.operators.centersUnknown(id);
  };
  const options = [
    // 목록에 없는 값(예전 데이터)도 선택된 채로 보인다
    ...value.filter((id) => !known.has(id)).map((id) => ({ value: id, label: m.operators.centersUnknown(id) })),
    ...centers.map((c) => ({
      value: c.centerId ?? '',
      label: `${c.name ?? m.none} · ${c.centerId ?? ''}${c.type ? ` · ${c.type}` : ''}${c.state && c.state !== 'ACTIVE' ? ` · ${c.state}` : ''}`,
    })),
  ];
  return (
    <div className="flex w-72 flex-col gap-1 text-sm">
      <MultiSelectDropdown
        label={m.operators.centers}
        options={options}
        value={value}
        onChange={onChange}
        placeholder={query.isPending ? m.loading : m.operators.centersPick}
        selectedText={m.operators.centersSelected}
        disabled={query.isPending}
      />
      {value.length > 0 && (
        <ul className="flex flex-wrap gap-1" aria-label={m.operators.centers}>
          {value.map((id) => (
            <li key={id} className="badge badge-outline gap-1">
              {label(id)}
              <button type="button" aria-label={`${label(id)} 빼기`} onClick={() => onChange(value.filter((x) => x !== id))}>
                ✕
              </button>
            </li>
          ))}
        </ul>
      )}
      {query.error instanceof PmartFailure && <FailureAlert failure={query.error} />}
    </div>
  );
}

function CreateAccount() {
  const api = useApi();
  const queryClient = useQueryClient();
  const [v, setV] = useState({ loginId: '', displayName: '', initialPassword: '', roles: [] as string[], centers: [] as string[] });
  const cmd = useCommand(async (body: { loginId: string; displayName: string; initialPassword: string; roles: string[]; centers: string[] }, key) => {
    const a = await request('POST', api.auth.POST('/operator-accounts', { ...commandParams(key), body }));
    setV({ loginId: '', displayName: '', initialPassword: '', roles: [], centers: [] });
    await queryClient.invalidateQueries({ queryKey: KEY });
    return a;
  });
  const field = (k: 'loginId' | 'displayName' | 'initialPassword', label: string, type = 'text') => (
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
            roles: v.roles,
            centers: v.centers,
          });
      }}
    >
      <h2 className="font-bold">{m.operators.create}</h2>
      <div className="flex flex-wrap gap-2">
        {field('loginId', m.operators.loginId)}
        {field('displayName', m.operators.displayName)}
        {field('initialPassword', m.operators.initialPassword, 'password')}
        <RolePicker value={v.roles} onChange={(roles) => setV({ ...v, roles })} />
        <CenterPicker value={v.centers} onChange={(centers) => setV({ ...v, centers })} />
      </div>
      <p className="text-xs opacity-70">{m.password.rule}</p>
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
    roles: [...account.roles],
    centers: [...account.centers],
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
              <RolePicker value={v.roles} onChange={(roles) => setV({ ...v, roles })} />
              <CenterPicker value={v.centers} onChange={(centers) => setV({ ...v, centers })} />
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
                onClick={() => void save.run({ displayName: v.displayName.trim(), roles: v.roles, centers: v.centers, state: v.state })}
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
