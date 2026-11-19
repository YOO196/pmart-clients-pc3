import { UiTextProvider } from '@pmart/web-ui';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ComponentType, ReactNode } from 'react';
import { createBrowserRouter, createMemoryRouter, Link, Navigate, NavLink, Outlet, RouterProvider, useLocation, useParams } from 'react-router';

import { env } from '../env';
import { AssignmentsMenu } from '../features/assignments/AssignmentPages';
import { CenterSwitcher } from '../features/centers/centers';
import { CenterDeliveriesMenu, DispatchFailuresMenu } from '../features/delivery/CenterDeliveryPages';
import { PackingHandoverMenu } from '../features/delivery/PackingHandoverPage';
import { ReturnHandoversMenu } from '../features/delivery/ReturnHandoverPage';
import { InboundMenu } from '../features/inbound/InboundPages';
import { InventoryMenu } from '../features/inventory/InventoryPages';
import { LocationsMenu } from '../features/locations/LocationPages';
import { MovesMenu } from '../features/moves/MovePages';
import { OpsMenu } from '../features/ops/OpsBoard';
import { QualityMenu } from '../features/quality/QualityPages';
import { RestrictionsMenu } from '../features/restrictions/RestrictionPages';
import { TasksMenu } from '../features/tasks/TaskPages';
import { WorkersMenu } from '../features/workers/WorkerPages';
import { PreparingPage } from '../features/menus/PreparingPage';
import { LoginCallbackPage, LoginPage } from '../features/session/LoginPage';
import { SessionPage } from '../features/session/SessionPage';
import { MyInfoPage } from '../features/me/MyInfoPage';
import { messages as m } from '../shared/messages';
import { allMenus, centerPath, isWorkerOnly, navGroups, type MenuItem, type MenuKey } from './nav';
import { RequireSession, SessionProvider, useSession } from './SessionContext';

/** 주소의 센터(`/c/:mfcId/…`). 세션 centers(sessions/current)에 있을 때만 그 센터 */
function useCenter(): { readonly mfcId: string; readonly mine: boolean } | null {
  const { mfcId } = useParams();
  const { session } = useSession();
  if (!mfcId) return null;
  return { mfcId, mine: session?.centers.includes(mfcId) ?? false };
}

/** 위 바(앱 이름·센터·목 표시·내 정보) + 왼쪽 메뉴(홈·묶음별 메뉴) + 본문. 2026-11-19 다듬기 — PDA 와 같은 흰 바탕·보라 포인트. */
function Layout() {
  const { session } = useSession();
  const center = useCenter();
  const { pathname } = useLocation();
  const target = center?.mine ? center.mfcId : session?.centers[0];
  // 지금 메뉴(`/c/:mfcId/<segment>/…`) — 센터를 바꾸면 같은 메뉴로 간다
  const segment = pathname.split('/')[3] ?? allMenus[0]!.segment;
  const showMenus = !!target && !isWorkerOnly(session?.roles ?? []);
  return (
    <div className="flex min-h-screen flex-col bg-base-200">
      <header className="sticky top-0 z-10 flex h-14 items-center gap-4 border-b border-base-300 bg-base-100 px-4">
        <Link to="/" className="flex items-center gap-2 text-lg font-extrabold tracking-tight" aria-label={m.goHome}>
          <span className="inline-block size-6 rounded-md bg-primary" aria-hidden />
          {m.appTitle}
        </Link>
        {env.isMock && <span className="badge badge-outline badge-sm">{m.mockBadge}</span>}
        <div className="flex-1" />
        {session && center?.mine && <CenterSwitcher centers={session.centers} current={center.mfcId} segment={segment} />}
        <nav className="flex items-center gap-1 text-sm">
          {session && (
            <NavLink to="/me" className={({ isActive }) => `btn btn-ghost btn-sm ${isActive ? 'btn-active' : ''}`}>
              {m.nav.me}
            </NavLink>
          )}
          <NavLink to={session ? '/session' : '/login'} className={({ isActive }) => `btn btn-ghost btn-sm ${isActive ? 'btn-active' : ''}`}>
            {session ? m.nav.session : m.nav.login}
          </NavLink>
        </nav>
      </header>
      <div className="flex flex-1">
        {showMenus && (
          <aside className="w-56 shrink-0 border-r border-base-300 bg-base-100">
            <nav className="sticky top-14 space-y-4 p-3" aria-label={m.nav.menu}>
              {navGroups.map((g) => (
                <div key={g.key}>
                  {g.key !== 'overview' && <p className="px-3 pb-1 text-xs font-semibold text-base-content/50">{m.groups[g.key]}</p>}
                  <ul className="space-y-0.5">
                    {g.items.map((item) => (
                      <li key={item.key}>
                        <NavLink
                          to={centerPath(target, item.segment)}
                          className={({ isActive }) =>
                            `block rounded-field px-3 py-1.5 text-sm ${isActive ? 'bg-secondary font-bold text-secondary-content' : 'hover:bg-base-200'}`
                          }
                        >
                          {m.menus[item.key]}
                        </NavLink>
                      </li>
                    ))}
                  </ul>
                </div>
              ))}
            </nav>
          </aside>
        )}
        <main className="min-w-0 flex-1 space-y-4 p-6">
          <div className="mx-auto max-w-7xl space-y-4">
            <Outlet />
          </div>
        </main>
      </div>
    </div>
  );
}

/** 센터 하나 아래 화면들. 권한 안내(막지 않음)·워커 전용 계정 차단·남의 센터 차단을 한 곳에서 */
function CenterScope({ menu }: { readonly menu: MenuItem }) {
  const { session } = useSession();
  const center = useCenter();
  if (!session || !center) return null;
  if (isWorkerOnly(session.roles)) return <WorkerOnly />;
  if (!center.mine) {
    return (
      <div className="space-y-3">
        <p role="alert" className="alert alert-warning text-sm">
          {session.centers.length === 0 ? m.center.none : m.center.notMine}
        </p>
        {session.centers.length > 0 && (
          <ul className="menu rounded-box bg-base-100 w-fit">
            {session.centers.map((c) => (
              <li key={c}>
                <Link to={centerPath(c, menu.segment)}>{c}</Link>
              </li>
            ))}
          </ul>
        )}
      </div>
    );
  }
  // 센터 표시·고르기는 위 바(Layout)에 있다.
  return (
    <>
      {!session.roles.includes('MFC_SUPERVISOR') && (
        <p role="note" className="alert alert-warning text-sm">
          {m.noSupervisor}
        </p>
      )}
      <MenuPage menu={menu} mfcId={center.mfcId} />
    </>
  );
}

/** 만든 메뉴 화면(nav.ts `ready`). 아직이면 "준비 중" */
const menuPages: Partial<Record<MenuKey, ComponentType<{ readonly mfcId: string }>>> = {
  ops: OpsMenu,
  locations: LocationsMenu,
  moves: MovesMenu,
  workers: WorkersMenu,
  tasks: TasksMenu,
  assignments: AssignmentsMenu,
  packingHandover: PackingHandoverMenu,
  deliveries: CenterDeliveriesMenu,
  dispatchFailures: DispatchFailuresMenu,
  returnHandovers: ReturnHandoversMenu,
  inbound: InboundMenu,
  inventory: InventoryMenu,
  quality: QualityMenu,
  restrictions: RestrictionsMenu,
};

function MenuPage({ menu, mfcId }: { readonly menu: MenuItem; readonly mfcId: string }) {
  const Page = menu.ready ? menuPages[menu.key] : undefined;
  return Page ? <Page mfcId={mfcId} /> : <PreparingPage menu={menu} />;
}

function WorkerOnly() {
  return (
    <p role="alert" className="alert alert-warning text-sm">
      {m.workerOnly}
    </p>
  );
}

/** 첫 화면: 맡은 첫 센터의 센터 운영판(첫 메뉴)으로. 센터가 없거나 워커 전용이면 안내 */
function Home() {
  const { session } = useSession();
  if (!session) return null;
  if (isWorkerOnly(session.roles)) return <WorkerOnly />;
  const first = session.centers[0];
  if (!first) {
    return (
      <p role="alert" className="alert alert-warning text-sm">
        {m.center.none}
      </p>
    );
  }
  return <Navigate to={centerPath(first)} replace />;
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
      { index: true, element: guarded(<Home />) },
      { path: 'session', element: guarded(<SessionPage />) },
      { path: 'me', element: guarded(<MyInfoPage />) },
      { path: 'c/:mfcId', element: guarded(<Home />) },
      // 메뉴 아래 화면(목록·상세·등록)은 메뉴 화면이 자기 Routes 로 나눈다
      ...allMenus.map((menu) => ({ path: `c/:mfcId/${menu.segment}/*`, element: guarded(<CenterScope menu={menu} />) })),
      { path: '*', element: <Navigate to="/" replace /> },
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
