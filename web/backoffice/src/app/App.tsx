import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { createMemoryRouter, createBrowserRouter, Outlet, RouterProvider } from 'react-router';

import { ApprovalInboxPage } from '../features/approvals/ApprovalInboxPage';
import { messages as m } from '../shared/messages';

const isMock = import.meta.env.VITE_PMART_ENV !== 'local';

function Layout() {
  return (
    <div className="min-h-screen bg-base-200">
      <header className="navbar bg-base-100 shadow-sm">
        <span className="text-lg font-bold">{m.appTitle}</span>
        {isMock && <span className="badge badge-outline ml-3">{m.mockBadge}</span>}
      </header>
      <main className="p-6">
        <Outlet />
      </main>
    </div>
  );
}

const routes = [{ path: '/', element: <Layout />, children: [{ index: true, element: <ApprovalInboxPage /> }] }];

/** 재시도는 pmartFetch(429·retryable) 규칙만 따른다. TanStack Query 의 자동 재시도는 끈다. */
export function createQueryClient() {
  return new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
}

export function App({
  queryClient = createQueryClient(),
  memory = false,
}: {
  readonly queryClient?: QueryClient;
  readonly memory?: boolean;
}) {
  const router = memory ? createMemoryRouter(routes) : createBrowserRouter(routes);
  return (
    <QueryClientProvider client={queryClient}>
      <RouterProvider router={router} />
    </QueryClientProvider>
  );
}
