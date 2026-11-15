// 본사 부서(hr 0.3.0) — 목록·이름 붙이기·새 부서, 소속 입력의 목록 고르기.
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http } from 'msw';
import { describe, expect, it } from 'vitest';

import { API_BASE } from '../../api/client';
import { db } from '../../mocks/db';
import { problem } from '../../mocks/support';
import { renderAt } from '../../test/render';
import { server } from '../../test/server';

describe('본사 부서', () => {
  it('목록: 코드 순, 이름, 퇴사 아닌 소속 직원 수', async () => {
    renderAt('/departments');
    const rows = await screen.findAllByTestId('department-row');
    expect(rows.map((r) => within(r).getAllByRole('cell')[0]!.textContent)).toEqual(['CS', 'HR', 'MD']);
    expect(within(rows[1]!).getByLabelText('HR 부서 이름')).toHaveValue('인사팀');
  });

  it('이름 저장은 PUT /hr/departments/{code} — Idempotency-Key·X-Source-System', async () => {
    const view = renderAt('/departments');
    const input = await screen.findByLabelText('MD 부서 이름');
    await userEvent.type(input, '상품기획팀');
    await userEvent.click(within(input.closest('form')!).getByRole('button', { name: '저장' }));
    await waitFor(() => expect(db.departments.get('MD')?.name).toBe('상품기획팀'));
    const put = view.sent.find((r) => r.method === 'PUT' && r.url.includes('/hr/departments/MD'))!;
    expect(put.headers.get('Idempotency-Key')).toBeTruthy();
    expect(put.headers.get('X-Source-System')).toBe('hr-backoffice-web');
    expect(await put.json()).toEqual({ name: '상품기획팀' });
  });

  it('새 부서 추가(코드 형식 검사) → 목록에 생긴다', async () => {
    renderAt('/departments');
    const form = await screen.findByRole('form', { name: '부서 추가' });
    await userEvent.type(within(form).getByLabelText('부서 코드'), '1004');
    await userEvent.type(within(form).getByLabelText('부서 이름'), '물류기획팀');
    await userEvent.click(within(form).getByRole('button', { name: '부서 추가' }));
    expect(await screen.findByLabelText('1004 부서 이름')).toHaveValue('물류기획팀');
  });

  it('목록을 못 불러오면 빈 목록이 아니라 오류', async () => {
    server.use(http.get(`${API_BASE}/hr/departments`, () => problem(500, 'INTERNAL_ERROR')));
    renderAt('/departments');
    expect(await screen.findByText('정보를 불러오지 못했어요')).toBeInTheDocument();
    expect(screen.queryByText('아직 부서가 없어요.')).not.toBeInTheDocument();
  });

  it('직원 등록의 본사 부서: 목록 코드면 이름을, 처음 보는 코드면 새 부서라고 보인다', async () => {
    renderAt('/employees/new');
    const input = await screen.findByLabelText('부서 코드');
    await userEvent.type(input, 'HR');
    expect(await screen.findByTestId('department-name')).toHaveTextContent('인사팀');
    await userEvent.clear(input);
    await userEvent.type(input, 'NEW-1');
    expect(await screen.findByText(/목록에 없는 새 부서 코드/)).toBeInTheDocument();
  });
});
