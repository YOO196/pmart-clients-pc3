import { UiTextProvider } from '@pmart/web-ui';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';
import { createBrowserRouter, createMemoryRouter, Link, Navigate, NavLink, Outlet, RouterProvider } from 'react-router';

import { env } from '../env';
import { DepartmentsPage } from '../features/departments/departments';
import { PermissionDetailPage, PermissionsPage } from '../features/permissions/PermissionsPage';
import { EmployeeDetailPage } from '../features/employees/EmployeeDetailPage';
import { EmployeeListPage } from '../features/employees/EmployeeListPage';
import { EmployeeRegisterPage } from '../features/employees/EmployeeRegisterPage';
import { LoginCallbackPage, LoginPage } from '../features/session/LoginPage';
import { SessionPage } from '../features/session/SessionPage';
import { useMe } from '../features/session/useMe';
import { messages as m } from '../shared/messages';
import { RequireSession, SessionProvider, useSession } from './SessionContext';

const nav: ReadonlyArray<readonly [string, string]> = [
  ['/employees', m.nav.employees],
  ['/employees/new', m.nav.register],
  ['/departments', m.nav.departments],
  ['/permissions', m.nav.permissions],
];

function Layout() {
  const { session } = useSession();
  // 메뉴에는 이름을 보인다(운영자 ID 는 길다). 이름을 아직 못 받았거나 인사 기록이 없으면 "내 세션"만.
  const me = useMe();
  const myName = me.data?.name;
  return (
    <div className="flex min-h-screen bg-base-200">
      <aside className="w-52 shrink-0 bg-base-100 shadow-sm">
        <div className="p-4">
          <Link to="/" className="text-lg font-bold" aria-label={m.goHome}>
            {m.appTitle}
          </Link>
          {env.isMock && <span className="badge badge-outline ml-2">{m.mockBadge}</span>}
        </div>
        <ul className="menu w-full">
          <li>
            <NavLink to={session ? '/session' : '/login'}>{session ? (myName ? `${m.nav.session}: ${myName}` : m.nav.session) : m.nav.login}</NavLink>
          </li>
          {nav.map(([to, label]) => (
            <li key={to}>
              <NavLink to={to} end>
                {label}
              </NavLink>
            </li>
          ))}
        </ul>
      </aside>
      <main className="min-w-0 flex-1 space-y-4 p-6">
        {/* 안내만 한다 — 화면을 막지 않고, 판정은 서버(403 → 이용할 수 없는 화면) */}
        {session && !session.roles.includes('HR_ADMIN') && (
          <p role="note" className="alert alert-warning text-sm">
            {m.noHrRole}
          </p>
        )}
        <Outlet />
      </main>
    </div>
  );
}

const guarded = (element: ReactNode) => <RequireSession>{element}</RequireSession>;

const routes = [
  { path: '/login', element: <LoginPage /> },
  // employee-auth 복귀 주소(백엔드 허용 목록의 <출처>/auth/callback)
  { path: '/auth/callback', element: <LoginCallbackPage /> },
  {
    path: '/',
    element: <Layout />,
    children: [
      { index: true, element: <Navigate to="/employees" replace /> },
      { path: 'session', element: guarded(<SessionPage />) },
      { path: 'employees', element: guarded(<EmployeeListPage />) },
      { path: 'employees/new', element: guarded(<EmployeeRegisterPage />) },
      { path: 'employees/:operatorId', element: guarded(<EmployeeDetailPage />) },
      { path: 'departments', element: guarded(<DepartmentsPage />) },
      { path: 'permissions', element: guarded(<PermissionsPage />) },
      { path: 'permissions/:operatorId', element: guarded(<PermissionDetailPage />) },
    ],
  },
];

/** 재시도는 pmartFetch(429·retryable) 규칙만 따른다. TanStack Query 의 자동 재시도는 끈다. */
export function createQueryClient() {
  return new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
}

export function App({
  queryClient = createQueryClient(),
  memory = false,
  initialPath = '/',
  initialToken,
}: {
  readonly queryClient?: QueryClient;
  readonly memory?: boolean;
  readonly initialPath?: string;
  /** 테스트에서 바로 세션을 시작한다. */
  readonly initialToken?: string;
}) {
  const router = memory ? createMemoryRouter(routes, { initialEntries: [initialPath] }) : createBrowserRouter(routes);
  return (
    <QueryClientProvider client={queryClient}>
      <UiTextProvider problem={m.problem} reason={m.reason}>
        <SessionProvider {...(initialToken ? { initialToken } : {})}>
          <RouterProvider router={router} />
        </SessionProvider>
      </UiTextProvider>
    </QueryClientProvider>
  );
}
