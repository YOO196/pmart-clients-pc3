import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useState, type ReactNode } from 'react';
import { createBrowserRouter, createMemoryRouter, Link, Navigate, NavLink, Outlet, RouterProvider } from 'react-router';

import { ApprovalDetailPage } from '../features/approvals/ApprovalDetailPage';
import { ApprovalInboxPage } from '../features/approvals/ApprovalInboxPage';
import { ApprovalListPage } from '../features/approvals/ApprovalListPage';
import { AssistantProvider } from '../features/assistant/AssistantContext';
import { AssistantAnswerPage, AssistantPage } from '../features/assistant/AssistantPage';
import { createDraftAssistantMock } from '../features/assistant/draftMock';
import { notConnectedAssistant, type AssistantPort } from '../features/assistant/port';
import { CategoryTreePage } from '../features/categories/CategoryTreePage';
import { ContentDraftPage, NewContentDraftPage } from '../features/contents/ContentDraftPage';
import { ContentImportPage, NewContentImportPage } from '../features/contents/ContentImportPage';
import { SkuHandlingPage } from '../features/handlings/SkuHandlingPage';
import { NewPriceImportPage, PriceImportPage } from '../features/prices/PriceImportPage';
import { PricePage } from '../features/prices/PricePage';
import { ProductDetailPage } from '../features/products/ProductDetailPage';
import { NewProductDraftPage, ProductDraftPage } from '../features/products/ProductDraftPage';
import { NewProductImportPage, ProductImportPage } from '../features/products/ProductImportPage';
import { ProductListPage } from '../features/products/ProductListPage';
import { OperatorAccountsPage } from '../features/operators/OperatorAccountsPage';
import { LoginCallbackPage, LoginPage } from '../features/session/LoginPage';
import { SessionPage } from '../features/session/SessionPage';
import { messages as m } from '../shared/messages';
import { RequireSession, SessionProvider, useSession } from './SessionContext';

const isMock = import.meta.env.VITE_PMART_ENV !== 'local';

// 백엔드 handoff 2026-10-30 §5 메뉴 순서
const nav: ReadonlyArray<readonly [string, string]> = [
  ['/approvals', m.nav.approvals],
  ['/categories', m.nav.categories],
  ['/products/drafts/new', m.nav.productNew],
  ['/products/import', m.nav.productImport],
  ['/products', m.nav.products],
  ['/contents/drafts/new', m.nav.contentNew],
  ['/contents/import', m.nav.contentImport],
  ['/prices', m.nav.prices],
  ['/prices/import', m.nav.priceImport],
  ['/handlings', m.nav.handlings],
  ['/views/approval-inbox', m.nav.bffInbox],
  ['/operators', m.nav.operators],
  // 메뉴는 모두에게 보인다. 업무 도우미 권한은 서버가 판정한다(403·FORBIDDEN_SCOPE).
  ['/assistant', m.nav.assistant],
];

/** 업무 도우미: 목 모드만 계약 확정 전 목(BR-46), 실서버 모드는 연결하지 않는다. */
const defaultAssistantPort = (): AssistantPort =>
  import.meta.env.VITE_PMART_ENV === 'mock' ? createDraftAssistantMock({ delayMs: 400 }) : notConnectedAssistant;

/**
 * 운영자 계정 화면(auth-service 계정 API). employee-auth 로그인(lan)에서는 내린다 — 직원 역할·센터의 정본이
 * employee-auth-service 이고 직원 등록은 인사팀 화면(hr-service, ADR-0056 5단계)으로 간다(handoff 2026-11-12 §4, 사용자 결정 2026-11-12).
 */
function OperatorsRoute() {
  const { loginMode } = useSession();
  if (loginMode !== 'employee-auth') return <OperatorAccountsPage />;
  return (
    <section className="max-w-2xl space-y-4">
      <h1 className="text-xl font-bold">{m.operators.title}</h1>
      <p role="note" className="alert alert-info text-sm">
        {m.operators.movedNotice}
      </p>
    </section>
  );
}

function Layout() {
  const { session, displayName, loginMode } = useSession();
  const items = loginMode === 'employee-auth' ? nav.filter(([to]) => to !== '/operators') : nav;
  return (
    <div className="flex min-h-screen bg-base-200">
      <aside className="w-52 shrink-0 bg-base-100 shadow-sm">
        <div className="p-4">
          <Link to="/" className="text-lg font-bold" aria-label={m.goHome}>
            {m.appTitle}
          </Link>
          {isMock && <span className="badge badge-outline ml-2">{m.mockBadge}</span>}
        </div>
        <ul className="menu w-full">
          <li>
            <NavLink to={session ? '/session' : '/login'}>
              {session ? `${m.nav.session}: ${displayName ?? session.subject}` : m.nav.login}
            </NavLink>
          </li>
          {items.map(([to, label]) => (
            <li key={to}>
              <NavLink to={to} end>
                {label}
              </NavLink>
            </li>
          ))}
        </ul>
      </aside>
      <main className="min-w-0 flex-1 p-6">
        <Outlet />
      </main>
    </div>
  );
}

const guarded = (element: ReactNode) => <RequireSession>{element}</RequireSession>;

const routes = [
  { path: '/login', element: <LoginPage /> },
  // employee-auth 복귀 주소(handoff 2026-11-12 §3 — 백엔드 허용 목록의 <출처>/auth/callback)
  { path: '/auth/callback', element: <LoginCallbackPage /> },
  {
    path: '/',
    element: <Layout />,
    children: [
      { index: true, element: <Navigate to="/approvals" replace /> },
      { path: 'session', element: guarded(<SessionPage />) },
      { path: 'operators', element: guarded(<OperatorsRoute />) },
      { path: 'approvals', element: guarded(<ApprovalListPage />) },
      { path: 'approvals/:approvalId', element: guarded(<ApprovalDetailPage />) },
      { path: 'views/approval-inbox', element: guarded(<ApprovalInboxPage />) },
      { path: 'categories', element: guarded(<CategoryTreePage />) },
      { path: 'products', element: guarded(<ProductListPage />) },
      { path: 'products/drafts/new', element: guarded(<NewProductDraftPage />) },
      { path: 'products/drafts/:draftId', element: guarded(<ProductDraftPage />) },
      { path: 'products/import', element: guarded(<NewProductImportPage />) },
      { path: 'products/import/:batchId', element: guarded(<ProductImportPage />) },
      { path: 'products/:productId', element: guarded(<ProductDetailPage />) },
      { path: 'contents/drafts/new', element: guarded(<NewContentDraftPage />) },
      { path: 'contents/drafts/:draftId', element: guarded(<ContentDraftPage />) },
      { path: 'contents/import', element: guarded(<NewContentImportPage />) },
      { path: 'contents/import/:batchId', element: guarded(<ContentImportPage />) },
      { path: 'prices', element: guarded(<PricePage />) },
      { path: 'prices/import', element: guarded(<NewPriceImportPage />) },
      { path: 'prices/import/:batchId', element: guarded(<PriceImportPage />) },
      { path: 'handlings', element: guarded(<SkuHandlingPage />) },
      { path: 'assistant', element: guarded(<AssistantPage />) },
      { path: 'assistant/answers/:answerId', element: guarded(<AssistantAnswerPage />) },
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
  assistantPort,
}: {
  readonly queryClient?: QueryClient;
  readonly memory?: boolean;
  readonly initialPath?: string;
  /** 테스트·목 모드에서 바로 세션을 시작한다. */
  readonly initialToken?: string;
  /** 테스트에서 업무 도우미 목 시나리오를 주입한다. */
  readonly assistantPort?: AssistantPort;
}) {
  const router = memory ? createMemoryRouter(routes, { initialEntries: [initialPath] }) : createBrowserRouter(routes);
  const [port] = useState(() => assistantPort ?? defaultAssistantPort());
  return (
    <QueryClientProvider client={queryClient}>
      <SessionProvider {...(initialToken ? { initialToken } : {})}>
        <AssistantProvider port={port}>
          <RouterProvider router={router} />
        </AssistantProvider>
      </SessionProvider>
    </QueryClientProvider>
  );
}
