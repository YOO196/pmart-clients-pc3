import { render, screen } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { describe, expect, it } from 'vitest';

import { API_BASE } from '../../api/client';
import { App } from '../../app/App';
import { as } from '../../test/render';
import { server } from '../../test/server';

describe('승인 상세 (목 모드, MSW)', () => {
  it('금액 없는 행(requestedAmount: null)도 화면이 깨지지 않고 승인 버튼이 보인다', async () => {
    server.use(
      http.get(`${API_BASE}/approvals/:id`, () =>
        HttpResponse.json({
          approvalId: 'AP-null-amount',
          type: 'PRODUCT',
          requesterId: 'OP-someone-else',
          reviewState: 'REVIEW_PENDING',
          executionState: 'NOT_REQUESTED',
          version: 1,
          lines: [{ lineKey: 'P-1', requestedAmount: null, attributes: { registration: 'NEW', internalName: '사과' } }],
          decisions: [],
        }),
      ),
    );
    render(<App memory initialPath="/approvals/AP-null-amount" initialToken={as.md} />);

    expect(await screen.findByText('P-1')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: '승인' })).toBeInTheDocument();
  });

  it('승인 뒤 반영이 같은 상태로 머물면 "확인 중"을 끝내고 다시 확인 안내를 보인다', async () => {
    let decided = false;
    const detail = () => ({
      approvalId: 'AP-stuck',
      type: 'PRODUCT',
      requesterId: 'OP-someone-else',
      reviewState: decided ? 'APPROVED' : 'REVIEW_PENDING',
      executionState: decided ? 'ACCEPTED' : 'NOT_REQUESTED',
      version: decided ? 2 : 1,
      lines: [{ lineKey: 'P-1' }],
      decisions: [],
    });
    server.use(
      http.get(`${API_BASE}/approvals/:id`, () => HttpResponse.json(detail())),
      http.post(`${API_BASE}/approvals/:id/decisions`, () => {
        decided = true;
        return HttpResponse.json({ status: 'APPLIED', requestId: 'req-1', occurredAt: '2026-11-04T01:00:00Z' });
      }),
    );
    render(<App memory initialPath="/approvals/AP-stuck" initialToken={as.md} />);

    (await screen.findByRole('button', { name: '승인' })).click();

    expect(await screen.findByText('아직 정본 반영이 확인되지 않았어요. 잠시 후 다시 확인해 주세요.')).toBeInTheDocument();
    expect(screen.queryByText('정본 반영을 확인하고 있어요')).not.toBeInTheDocument();
  });
});
