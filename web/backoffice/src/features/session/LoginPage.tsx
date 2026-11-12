// 직원 로그인. LOGIN_MODE 가 employee-auth 면 게이트웨이 로그인 시작 주소로 보낸다(ADR-0056, handoff 2026-11-12) — Keycloak 화면에서 로그인하고 /auth/callback 으로 돌아온다.
// auth-service(아이디·비밀번호 → JWT, ADR-0018). 실패 사유는 code 로만 고른다(LOGIN_FAILED·ACCOUNT_LOCKED).
// 비밀번호는 상태에만 두고 로그·오류 문구에 남기지 않는다. 로그인 뒤 원래 가려던 화면으로 돌아간다.
import { useEffect, useState } from 'react';
import { Link, Navigate, useNavigate, useSearchParams } from 'react-router';

import { EmployeeLoginError, type EmployeeLoginErrorCode } from '../../api/employeeAuth';
import { useSession } from '../../app/SessionContext';
import { mockAccounts } from '../../mocks/operators';
import { CommandFeedback } from '../../shared/Feedback';
import { messages as m } from '../../shared/messages';
import { useCommand } from '../../shared/useCommand';

const isMock = import.meta.env.VITE_PMART_ENV !== 'local';

/** 열린 리디렉트 방지: 앱 안 경로만 */
const safeFrom = (from: string | null) => (from && from.startsWith('/') && !from.startsWith('//') ? from : '/approvals');

export function LoginPage() {
  const { loginMode } = useSession();
  return loginMode === 'employee-auth' ? <EmployeeLoginPage /> : <PasswordLoginPage />;
}

/** employee-auth: 버튼 → 게이트웨이 로그인 시작(→ Keycloak 로그인 화면). 돌아오면 /auth/callback 이 티켓을 토큰으로 바꾼다 */
function EmployeeLoginPage() {
  const { session, startEmployeeLogin, signOutUnconfirmed } = useSession();
  const [params] = useSearchParams();
  const from = safeFrom(params.get('from'));
  const [phase, setPhase] = useState<'idle' | 'starting' | 'failed'>('idle');

  if (session) return <Navigate to={from} replace />;

  return (
    <section className="mx-auto max-w-sm space-y-4 pt-10">
      <h1 className="text-xl font-bold">{m.login.title}</h1>
      <div className="space-y-3 rounded-box bg-base-100 p-6 shadow-sm">
        <button
          type="button"
          className="btn btn-primary w-full"
          disabled={phase === 'starting'}
          onClick={() => {
            setPhase('starting');
            startEmployeeLogin(from).catch(() => setPhase('failed'));
          }}
        >
          {phase === 'starting' ? m.employeeLogin.starting : m.employeeLogin.start}
        </button>
        {phase === 'failed' && (
          <p role="alert" className="alert alert-error text-sm">
            {m.employeeLogin.startFailed}
          </p>
        )}
        {signOutUnconfirmed && (
          <p role="alert" className="alert alert-warning text-sm">
            {m.employeeLogin.signOutUnconfirmed}
          </p>
        )}
        <p className="text-xs opacity-70">{m.employeeLogin.note}</p>
      </div>
    </section>
  );
}

/** 로그인 뒤 돌아오는 곳(복귀 주소 ?ticket= 또는 ?error=). 티켓을 토큰으로 바꾸고 원래 가려던 화면으로 */
export function LoginCallbackPage() {
  const { completeEmployeeLogin } = useSession();
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const [error, setError] = useState<EmployeeLoginErrorCode | null>(null);

  useEffect(() => {
    let live = true;
    completeEmployeeLogin(params)
      .then((from) => {
        // 주소창에서 ticket 을 지운다(replace)
        if (live) void navigate(safeFrom(from), { replace: true });
      })
      .catch((e: unknown) => {
        if (live) setError(e instanceof EmployeeLoginError ? e.code : 'NETWORK');
      });
    return () => {
      live = false;
    };
  }, [completeEmployeeLogin, navigate, params]);

  return (
    <section className="mx-auto max-w-sm space-y-4 pt-10">
      <h1 className="text-xl font-bold">{m.login.title}</h1>
      <div className="space-y-3 rounded-box bg-base-100 p-6 shadow-sm">
        {error === null ? (
          <p role="status" className="text-sm opacity-70">
            {m.employeeLogin.completing}
          </p>
        ) : (
          <>
            <p role="alert" className="alert alert-error text-sm">
              {m.employeeLogin.errors[error]}
            </p>
            <Link to="/login" replace className="btn btn-primary w-full">
              {m.employeeLogin.retry}
            </Link>
          </>
        )}
      </div>
    </section>
  );
}

/** auth-service: 아이디·비밀번호(mock·local 빌드) */
function PasswordLoginPage() {
  const { session, login } = useSession();
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const from = safeFrom(params.get('from'));
  const [loginId, setLoginId] = useState('');
  const [password, setPassword] = useState('');

  const cmd = useCommand(async (credentials: { loginId: string; password: string }) => {
    const account = await login(credentials);
    setPassword('');
    void navigate(account.passwordChangeRequired ? '/session?password=required' : from, { replace: true });
    return account;
  });

  if (session && cmd.phase.kind === 'idle') return <Navigate to={from} replace />;

  return (
    <section className="mx-auto max-w-sm space-y-4 pt-10">
      <h1 className="text-xl font-bold">{m.login.title}</h1>
      <form
        className="space-y-3 rounded-box bg-base-100 p-6 shadow-sm"
        onSubmit={(e) => {
          e.preventDefault();
          // 로그인은 상태를 남기지 않아 결과 불명이어도 새로 시도해도 된다.
          if (cmd.phase.kind === 'unknown' || cmd.phase.kind === 'rejected') cmd.reset();
          if (loginId.trim() && password) void cmd.run({ loginId: loginId.trim(), password });
        }}
      >
        <label className="flex flex-col gap-1 text-sm">
          {m.login.loginId}
          <input className="input w-full" autoComplete="username" maxLength={64} value={loginId} onChange={(e) => setLoginId(e.target.value)} />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          {m.login.password}
          <input
            className="input w-full"
            type="password"
            autoComplete="current-password"
            maxLength={128}
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
        </label>
        <button type="submit" className="btn btn-primary w-full" disabled={cmd.phase.kind === 'running' || !loginId.trim() || !password}>
          {m.login.submit}
        </button>
        {/* 로그인은 상태를 남기지 않으므로 결과 불명이어도 "같은 요청으로 결과 확인" 대신 다시 로그인하면 된다. */}
        <CommandFeedback command={cmd} unknown={{ body: m.login.unknownBody, resend: false }} />
        <p className="text-xs opacity-70">{m.login.memoryNote}</p>
      </form>
      {isMock && (
        <div className="rounded-box bg-base-100 p-4 text-sm">
          <p className="mb-2 font-semibold">{m.login.mockAccounts}</p>
          <div className="flex flex-wrap gap-2">
            {mockAccounts.map((a) => (
              <button
                key={a.loginId}
                type="button"
                className="btn btn-xs"
                onClick={() => {
                  setLoginId(a.loginId);
                  setPassword(a.password);
                }}
              >
                {`${a.loginId} · ${a.roles.join(', ') || a.centers.join(', ')}`}
              </button>
            ))}
          </div>
        </div>
      )}
    </section>
  );
}
