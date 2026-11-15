// 내 세션: 역할·센터(sessions/current 0.6.0 응답), 서버 세션(GET /employee-auth/sessions/current), 내 인사 정보(GET /hr/employees/me — 모든 직원), 로그아웃.
// 비밀번호는 Keycloak 이 관리해 이 앱에서 바꾸지 않는다.
import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router';

import { centerDisplayName, request } from '@pmart/web-core';
import { formatSeoul, QueryState, toUiState } from '@pmart/web-ui';
import { useApi } from '../../app/ApiContext';
import { useSession } from '../../app/SessionContext';
import { messages as m } from '../../shared/messages';
import { affiliationText } from '../employees/labels';
import { useMe } from './useMe';

export function SessionPage() {
  const api = useApi();
  const navigate = useNavigate();
  const { session, logout } = useSession();
  const current = useQuery({
    queryKey: ['employee-auth', 'session', session?.subject],
    enabled: session !== null,
    queryFn: () => request('GET', api.employeeAuth.GET('/employee-auth/sessions/current', {})),
  });
  const me = useMe();

  if (!session) return null;
  return (
    <section className="max-w-2xl space-y-4">
      <h1 className="text-xl font-bold">{m.session.title}</h1>
      <div className="card bg-base-100 shadow-sm">
        <div className="card-body">
          <h2 className="text-sm font-semibold">{m.session.me}</h2>
          <QueryState state={toUiState(me)} onRetry={() => void me.refetch()}>
            {(e) =>
              e === null ? (
                <p className="text-sm opacity-70">{m.session.meMissing}</p>
              ) : (
                <dl className="grid grid-cols-[8rem_1fr] gap-1 text-sm">
                  <dt>{m.fields.name}</dt>
                  <dd>{e.name}</dd>
                  <dt>{m.fields.employeeNo}</dt>
                  <dd>{e.employeeNo}</dd>
                  <dt>{m.fields.mailAddress}</dt>
                  <dd>{e.mailAddress}</dd>
                  <dt>{m.fields.employmentType}</dt>
                  <dd>{m.employmentType[e.employmentType]}</dd>
                  <dt>{m.fields.affiliation}</dt>
                  <dd>{affiliationText(e.affiliation)}</dd>
                  <dt>{m.fields.status}</dt>
                  <dd>{m.employmentStatus[e.status]}</dd>
                </dl>
              )
            }
          </QueryState>

          <h2 className="mt-2 text-sm font-semibold">{m.session.title}</h2>
          <dl className="grid grid-cols-[8rem_1fr] gap-1 text-sm">
            <dt>{m.session.subject}</dt>
            <dd>{session.subject || m.none}</dd>
            <dt>{m.session.roles}</dt>
            <dd>{session.roles.join(', ') || m.none}</dd>
            <dt>{m.session.centers}</dt>
            <dd>{session.centers.map((c) => centerDisplayName(session, c)).join(', ') || m.none}</dd>
          </dl>
          {session.roles.length === 0 && (
            <p role="alert" className="alert alert-warning text-sm">
              {m.employeeLogin.noRoles}
            </p>
          )}

          <h2 className="mt-2 text-sm font-semibold">{m.session.current}</h2>
          <QueryState state={toUiState(current)} onRetry={() => void current.refetch()}>
            {(s) => (
              <dl className="grid grid-cols-[8rem_1fr] gap-1 text-sm">
                <dt>{m.session.sessionId}</dt>
                <dd>{s.sessionId}</dd>
                <dt>{m.employeeLogin.app}</dt>
                <dd>{s.app}</dd>
                <dt>{m.employeeLogin.issuedAt}</dt>
                <dd>{formatSeoul(s.issuedAt)}</dd>
                <dt>{m.employeeLogin.tokenExpiresAt}</dt>
                <dd>{formatSeoul(s.expiresAt)}</dd>
              </dl>
            )}
          </QueryState>
          <button
            type="button"
            className="btn btn-sm w-fit"
            onClick={() =>
              void logout().then((result) => {
                // 'redirecting' 이면 브라우저가 Keycloak 로그아웃 주소로 떠난다(→ /login 으로 돌아온다).
                if (result !== 'redirecting') void navigate('/login', { replace: true });
              })
            }
          >
            {m.session.signOut}
          </button>
        </div>
      </div>
      <div className="space-y-1 rounded-box bg-base-100 p-4 text-sm">
        <p>{m.employeeLogin.passwordNote}</p>
        <p>{m.employeeLogin.sharedPcNote}</p>
        <p>{m.session.ssoNote}</p>
      </div>
    </section>
  );
}
