// 내 정보 — hr-service GET /hr/employees/me(목).
import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { describe, expect, it } from 'vitest';

import { API_BASE } from '../../api/client';
import { as, renderAt } from '../../test/render';
import { server } from '../../test/server';

describe('내 정보', () => {
  it('왼쪽 메뉴 "내 정보" → 본인 인사 정보(서버 값 그대로), 바꾸기는 준비 중 안내만(요청을 보내지 않음)', async () => {
    const view = renderAt('/session');
    await userEvent.click(await screen.findByRole('link', { name: '내 정보' }));
    const profile = await screen.findByTestId('me-profile');
    expect(within(profile).getByText('정관리')).toBeInTheDocument();
    expect(within(profile).getByText('E-2026-0101')).toBeInTheDocument();
    expect(within(profile).getByText('sup1@pmart.test')).toBeInTheDocument();
    expect(within(profile).getByText('정규직')).toBeInTheDocument();
    expect(within(profile).getByText('센터 MFC-BSN-01')).toBeInTheDocument();
    expect(within(profile).getByText('재직')).toBeInTheDocument();
    expect(screen.getByText('회사 메일은 로그인 ID 이자 사서함이라 인사팀만 바꿔요.')).toBeInTheDocument();
    expect(within(screen.getByTestId('me-password')).getByText(/^준비 중이에요/)).toBeInTheDocument();
    expect(within(screen.getByTestId('me-contact')).getByText(/^준비 중이에요/)).toBeInTheDocument();
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument();
    expect(view.sent.filter((r) => r.method !== 'GET' && new URL(r.url).pathname.includes('/hr/'))).toHaveLength(0);
  });

  it('본부 소속이면 본사 부서로', async () => {
    renderAt('/me', as.sup2);
    expect(await within(await screen.findByTestId('me-profile')).findByText('본사 부서 1004')).toBeInTheDocument();
  });

  it('인사 기록이 없으면(404) 오류가 아니라 "기록 없음"', async () => {
    renderAt('/me', as.worker);
    expect(await screen.findByText('인사 기록이 없는 계정이에요. 인사팀에 확인해 주세요.')).toBeInTheDocument();
  });

  it('조회 실패는 오류(빈 화면으로 두지 않음)', async () => {
    server.use(http.get(`${API_BASE}/hr/employees/me`, () => new HttpResponse(null, { status: 500 })));
    renderAt('/me');
    expect(await screen.findByRole('alert')).toHaveAttribute('data-state', 'error');
  });
});
