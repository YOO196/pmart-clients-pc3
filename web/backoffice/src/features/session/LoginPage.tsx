// 운영자 로그인(아이디·비밀번호 → JWT, ADR-0018). 실패 사유는 code 로만 고른다(LOGIN_FAILED·ACCOUNT_LOCKED).
// 비밀번호는 상태에만 두고 로그·오류 문구에 남기지 않는다. 로그인 뒤 원래 가려던 화면으로 돌아간다.
import { useState } from 'react';
import { Navigate, useNavigate, useSearchParams } from 'react-router';

import { useSession } from '../../app/SessionContext';
import { mockAccounts } from '../../mocks/operators';
import { CommandFeedback } from '../../shared/Feedback';
import { messages as m } from '../../shared/messages';
import { useCommand } from '../../shared/useCommand';

const isMock = import.meta.env.VITE_PMART_ENV !== 'local';

/** 열린 리디렉트 방지: 앱 안 경로만 */
const safeFrom = (from: string | null) => (from && from.startsWith('/') && !from.startsWith('//') ? from : '/approvals');

export function LoginPage() {
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
        <CommandFeedback command={cmd} />
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
