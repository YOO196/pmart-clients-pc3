import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { UiTextProvider } from '@pmart/web-ui';
import { useState, type ReactNode } from 'react';
import { createBrowserRouter, createMemoryRouter, Link, Navigate, NavLink, Outlet, RouterProvider } from 'react-router';

import { ApprovalDetailPage } from '../features/approvals/ApprovalDetailPage';
import { ApprovalInboxPage } from '../features/approvals/ApprovalInboxPage';
import { ApprovalListPage } from '../features/approvals/ApprovalListPage';
import { AssistantProvider } from '../features/assistant/AssistantContext';
import { AssistantAnswerPage, AssistantPage } from '../features/assistant/AssistantPage';
import { createDraftAssistantMock } from '../features/assistant/draftMock';
import { createHttpAssistant } from '../features/assistant/httpAssistant';
import type { AssistantPort } from '../features/assistant/port';
import { CategoryTreePage } from '../features/categories/CategoryTreePage';
import { ContentDraftPage, NewContentDraftPage } from '../features/contents/ContentDraftPage';
import { ContentImportPage, NewContentImportPage } from '../features/contents/ContentImportPage';
import { SkuHandlingPage } from '../features/handlings/SkuHandlingPage';
import { InquiryDetailPage, InquiryListPage } from '../features/inquiries/InquiryPages';
import { NewPriceImportPage, PriceImportPage } from '../features/prices/PriceImportPage';
import { PricePage } from '../features/prices/PricePage';
import { ProductDetailPage } from '../features/products/ProductDetailPage';
import { NewProductDraftPage, ProductDraftPage } from '../features/products/ProductDraftPage';
import { NewProductImportPage, ProductImportPage } from '../features/products/ProductImportPage';
import { ProductListPage } from '../features/products/ProductListPage';
import { LoginCallbackPage, LoginPage } from '../features/session/LoginPage';
import { SessionPage } from '../features/session/SessionPage';
import type { Api } from '../api/client';
import { env } from '../env';
import { messages as m } from '../shared/messages';
import { useApi } from './ApiContext';
import { RequireSession, SessionProvider, useSession } from './SessionContext';

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
  // 고객센터 문의(상담원 CS_AGENT). 메뉴는 모두에게 보이고 권한은 서버가 판정한다(403).
  ['/inquiries', m.nav.inquiries],
  // 메뉴는 모두에게 보인다. 업무 도우미 권한은 서버가 판정한다(403·FORBIDDEN_SCOPE).
  ['/assistant', m.nav.assistant],
];

/** 업무 도우미: 목 모드만 계약 확정 전 목(BR-46), 실서버 모드는 연결하지 않는다. */
// 목 모드는 draftMock(계약 모양), 실서버 모드(local·lan)는 게이트웨이의 ai-assistant-service(2026-11-09 LAN 배포).
const defaultAssistantPort = (api: Api): AssistantPort =>
  import.meta.env.VITE_PMART_ENV === 'mock' ? createDraftAssistantMock({ delayMs: 400 }) : createHttpAssistant(api);

function Layout() {
  const { session } = useSession();
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
            <NavLink to={session ? '/session' : '/login'}>
              {session ? `${m.nav.session}: ${session.subject}` : m.nav.login}
            </NavLink>
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
      <main className="min-w-0 flex-1 p-6">
        <Outlet />
      </main>
    </div>
  );
}

const guarded = (element: ReactNode) => <RequireSession>{element}</RequireSession>;

const routes = [
  { path: '/login', element: <LoginPage /> },
  // 직원 로그인 복귀 주소(handoff 2026-11-12 §3 — 백엔드 허용 목록의 <출처>/auth/callback)
  { path: '/auth/callback', element: <LoginCallbackPage /> },
  {
    path: '/',
    element: <Layout />,
    children: [
      { index: true, element: <Navigate to="/approvals" replace /> },
      { path: 'session', element: guarded(<SessionPage />) },
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
      { path: 'inquiries', element: guarded(<InquiryListPage />) },
      { path: 'inquiries/:inquiryId', element: guarded(<InquiryDetailPage />) },
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
  const api = useApi();
  const [port] = useState(() => assistantPort ?? defaultAssistantPort(api));
  return (
    <QueryClientProvider client={queryClient}>
      <UiTextProvider problem={m.problem} reason={m.reason}>
        <SessionProvider {...(initialToken ? { initialToken } : {})}>
          <AssistantProvider port={port}>
            <RouterProvider router={router} />
          </AssistantProvider>
        </SessionProvider>
      </UiTextProvider>
    </QueryClientProvider>
  );
}
