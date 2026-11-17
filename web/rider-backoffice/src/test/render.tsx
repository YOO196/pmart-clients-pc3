import { render } from '@testing-library/react';

import { mockOperatorToken } from '@pmart/web-core';
import { App } from '../app/App';
import { server } from './server';

const token = (sub: string, roles: readonly string[], centers: readonly string[] = []) => mockOperatorToken({ sub, roles, centers, exp: 4_000_000_000 });

export const as = {
  riderOps: token('OP-rops-1', ['RIDER_OPS']),
  admin: token('OP-admin-1', ['OPERATOR_ADMIN']),
  cs: token('OP-cs-1', ['CS_AGENT']),
};

/** 화면 + 보낸 요청 기록(헤더·본문 확인용) */
export function renderAt(path: string, accessToken: string | null = as.riderOps) {
  const sent: Request[] = [];
  const listener = ({ request }: { request: Request }) => {
    sent.push(request.clone());
  };
  server.events.on('request:start', listener);
  const view = render(<App memory initialPath={path} {...(accessToken ? { initialToken: accessToken } : {})} />);
  return {
    ...view,
    sent,
    gets: (pathPart: string) => sent.filter((r) => r.method === 'GET' && new URL(r.url).pathname.includes(pathPart)),
  };
}
