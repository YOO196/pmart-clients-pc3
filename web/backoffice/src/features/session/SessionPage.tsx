// 내 세션: 토큰 클레임·서버 세션(GET /auth/sessions/current)·비밀번호 변경·로그아웃.
// Keycloak 로그인이면(handoff 2026-11-11 §4) /auth/sessions/current 는 401 이라 부르지 않고 토큰 값만 보인다.
// 비밀번호 변경도 auth-service API 라 Keycloak 계정 화면으로 안내한다.
import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router';

import { commandParams } from '../../api/command';
import { KEYCLOAK } from '../../api/keycloak';
import { request, requestNoContent } from '../../api/pmartFetch';
import { useApi } from '../../app/ApiContext';
import { useSession } from '../../app/SessionContext';
import { CommandFeedback } from '../../shared/Feedback';
import { formatSeoul } from '../../shared/format';
import { messages as m } from '../../shared/messages';
import { QueryState } from '../../shared/QueryState';
import { toUiState } from '../../shared/toUiState';
import { useCommand } from '../../shared/useCommand';

function PasswordChange({ required }: { readonly required: boolean }) {
  const api = useApi();
  const { passwordChanged } = useSession();
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [confirm, setConfirm] = useState('');
  const cmd = useCommand(async (v: { currentPassword: string; newPassword: string }, key) => {
    await requestNoContent('POST', api.auth.POST('/auth/password-changes', { ...commandParams(key), body: v }));
    setCurrent('');
    setNext('');
    setConfirm('');
    passwordChanged();
    return true;
  });
  const mismatch = next.length > 0 && confirm.length > 0 && next !== confirm;

  return (
    <form
      className="space-y-2 rounded-box bg-base-100 p-4"
      onSubmit={(e) => {
        e.preventDefault();
        if (current && next && next === confirm) void cmd.run({ currentPassword: current, newPassword: next });
      }}
    >
      <h2 className="font-bold">{m.password.title}</h2>
      {required && (
        <p role="alert" className="alert alert-warning text-sm">
          {m.login.passwordChangeRequired}
        </p>
      )}
      <p className="text-xs opacity-70">{m.password.rule}</p>
      {(
        [
          [m.password.current, current, setCurrent, 'current-password'],
          [m.password.next, next, setNext, 'new-password'],
          [m.password.confirm, confirm, setConfirm, 'new-password'],
        ] as const
      ).map(([label, value, set, autoComplete]) => (
        <label key={label} className="flex flex-col gap-1 text-sm">
          {label}
          <input
            type="password"
            className="input input-sm w-full max-w-xs"
            autoComplete={autoComplete}
            maxLength={128}
            value={value}
            onChange={(e) => set(e.target.value)}
          />
        </label>
      ))}
      {mismatch && <p className="text-error text-sm">{m.password.mismatch}</p>}
      <button type="submit" className="btn btn-sm btn-primary" disabled={cmd.busy || !current || !next || next !== confirm}>
        {m.password.submit}
      </button>
      <CommandFeedback command={cmd}>
        {() => (
          <p role="status" className="text-success text-sm">
            {m.password.changed}
          </p>
        )}
      </CommandFeedback>
    </form>
  );
}

export function SessionPage() {
  const api = useApi();
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const { session, operator, displayName, authTimeSeconds, loginMode, logout } = useSession();
  const keycloak = loginMode === 'keycloak';
  const current = useQuery({
    queryKey: ['auth', 'session', session?.subject],
    enabled: session !== null && !keycloak,
    queryFn: () => request('GET', api.auth.GET('/auth/sessions/current', {})),
  });
  const required = params.get('password') === 'required' || operator?.passwordChangeRequired === true;

  return (
    <section className="max-w-2xl space-y-4">
      <h1 className="text-xl font-bold">{m.session.title}</h1>
      {session && (
        <>
          <div className="card bg-base-100 shadow-sm">
            <div className="card-body">
              <dl className="grid grid-cols-[8rem_1fr] gap-1 text-sm">
                <dt>{m.session.subject}</dt>
                <dd>
                  {operator
                    ? `${operator.displayName} (${operator.loginId})`
                    : displayName
                      ? `${displayName} (${session.subject || m.none})`
                      : session.subject || m.none}
                </dd>
                <dt>{m.session.roles}</dt>
                <dd>{session.roles.join(', ') || m.none}</dd>
                <dt>{m.session.centers}</dt>
                <dd>{session.centers.join(', ') || m.none}</dd>
              </dl>
              {keycloak ? (
                <dl className="grid grid-cols-[8rem_1fr] gap-1 text-sm">
                  {authTimeSeconds !== null && (
                    <>
                      <dt>{m.keycloak.authTime}</dt>
                      <dd>{formatSeoul(new Date(authTimeSeconds * 1000).toISOString())}</dd>
                    </>
                  )}
                  <dt>{m.keycloak.tokenExpiresAt}</dt>
                  <dd>{session.expiresAtSeconds ? formatSeoul(new Date(session.expiresAtSeconds * 1000).toISOString()) : m.none}</dd>
                </dl>
              ) : (
                <>
                  <h2 className="mt-2 text-sm font-semibold">{m.session.current}</h2>
                  <QueryState state={toUiState(current)} onRetry={() => void current.refetch()}>
                    {(s) => (
                      <dl className="grid grid-cols-[8rem_1fr] gap-1 text-sm">
                        <dt>{m.session.sessionId}</dt>
                        <dd>{s.sessionId ?? m.none}</dd>
                        <dt>{m.session.roles}</dt>
                        <dd>{(s.roles ?? []).join(', ') || m.none}</dd>
                        <dt>{m.session.centers}</dt>
                        <dd>{(s.centerScope ?? []).join(', ') || m.none}</dd>
                        <dt>{m.session.expiresAt}</dt>
                        <dd>{s.expiresAt ? formatSeoul(s.expiresAt) : m.none}</dd>
                      </dl>
                    )}
                  </QueryState>
                </>
              )}
              <button
                type="button"
                className="btn btn-sm w-fit"
                onClick={() => void logout().finally(() => void navigate('/login', { replace: true }))}
              >
                {m.session.signOut}
              </button>
            </div>
          </div>
          {keycloak ? (
            <p className="rounded-box bg-base-100 p-4 text-sm">
              {m.keycloak.passwordNote}{' '}
              <a className="link" href={`${KEYCLOAK.issuer}/account`} target="_blank" rel="noreferrer">
                {m.keycloak.accountConsole}
              </a>
            </p>
          ) : (
            <PasswordChange required={required} />
          )}
        </>
      )}
    </section>
  );
}
