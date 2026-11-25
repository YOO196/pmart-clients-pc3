import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

import { mockOperatorToken } from '@pmart/web-core';
import { App } from '../app/App';
import { server } from './server';

const token = (sub: string, roles: readonly string[], centers: readonly string[]) => mockOperatorToken({ sub, roles, centers, exp: 4_000_000_000 });

export const as = {
  sup: token('OP-sup-1', ['MFC_SUPERVISOR'], ['MFC-BJG-01']),
  sup2: token('OP-sup-2', ['MFC_SUPERVISOR'], ['MFC-BJG-01', 'MFC-MOKPO-01']),
  worker: token('OP-wkr-1', ['MFC_WORKER'], ['MFC-BJG-01']),
  admin: token('OP-admin-1', ['OPERATOR_ADMIN'], []),
  adminWithCenter: token('OP-admin-2', ['OPERATOR_ADMIN'], ['MFC-BJG-01']),
};

/** 화면 + 보낸 요청 기록(헤더·본문 확인용) */
export function renderAt(path: string, accessToken: string | null = as.sup) {
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

/** 목록 찾기 줄의 "필터" 팝업을 연다(이미 열렸으면 그대로) — 고르기 칸은 팝업 안에 있다(2026-11-25 목록 한 틀) */
export async function openFilter() {
  const toggle = await screen.findByTestId('search-toggle');
  if (toggle.getAttribute('aria-expanded') !== 'true') await userEvent.click(toggle);
}
