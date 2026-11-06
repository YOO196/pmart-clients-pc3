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

  it('재고 승인 행의 숫자는 "원"이 아니라 수량(개)으로, 가격 승인만 원으로 보인다', async () => {
    const detail = (id: string, type: string, lines: unknown[]) => ({
      approvalId: id,
      type,
      requesterId: 'OP-someone-else',
      reviewState: 'REVIEW_PENDING',
      executionState: 'NOT_REQUESTED',
      version: 1,
      lines,
      decisions: [],
    });
    server.use(
      http.get(`${API_BASE}/approvals/AP-stock`, () =>
        HttpResponse.json(
          detail('AP-stock', 'INITIAL_STOCK', [
            { lineKey: 'L-1', requestedAmount: 10, attributes: { mfcId: 'MFC-BSN-01', sku: 'E-00000001', qty: 10 } },
            { lineKey: 'L-2', requestedQty: 1200, attributes: { mfcId: 'MFC-BSN-01', sku: 'E-00000002' } },
          ]),
        ),
      ),
      http.get(`${API_BASE}/approvals/AP-price`, () =>
        HttpResponse.json(detail('AP-price', 'PRICE', [{ lineKey: 'E-00000002', requestedAmount: 3900, attributes: { basePrice: 3900 } }])),
      ),
    );
    const view = render(<App memory initialPath="/approvals/AP-stock" initialToken={as.md} />);
    expect(await screen.findByText('L-1')).toBeInTheDocument();
    const qty = screen.getAllByTestId('line-qty').map((e) => e.textContent);
    const amount = screen.getAllByTestId('line-amount').map((e) => e.textContent);
    expect(qty).toEqual(['10개', '1,200개']);
    expect(amount).toEqual(['', '']);
    expect(screen.queryByText(/원$/)).toBeNull();
    view.unmount();

    render(<App memory initialPath="/approvals/AP-price" initialToken={as.md} />);
    expect(await screen.findByText('E-00000002')).toBeInTheDocument();
    expect(screen.getByTestId('line-amount')).toHaveTextContent('3,900원');
    expect(screen.getByTestId('line-qty')).toHaveTextContent('');
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

    expect(await screen.findByText('반영 결과는 해당 등록 화면(상품·가격·콘텐츠 일괄 등록)에서 확인해 주세요. 이 화면의 반영 상태는 아직 바로 바뀌지 않아요.')).toBeInTheDocument();
    expect(screen.queryByText('정본 반영을 확인하고 있어요')).not.toBeInTheDocument();
  });
  it('콘텐츠 게시 승인 행(BR-44): 기존 게시 갱신이면 지금 게시본 버전을 보이고, 상품용 "기존 상품 갱신"으로 쓰지 않는다', async () => {
    server.use(
      http.get(`${API_BASE}/approvals/AP-content`, () =>
        HttpResponse.json({
          approvalId: 'AP-content',
          type: 'DISPLAY',
          targetService: 'product-content-service',
          targetRef: 'contentImportBatch:cib-1',
          requesterId: 'OP-someone-else',
          reviewState: 'REVIEW_PENDING',
          executionState: 'NOT_REQUESTED',
          version: 1,
          lines: [
            { lineKey: 'cd-new', attributes: { draftId: 'cd-new', name: '사과', registration: 'NEW' } },
            { lineKey: 'cd-upd', attributes: { draftId: 'cd-upd', name: '배', registration: 'UPDATE', publishedContentVersion: 3 } },
          ],
          decisions: [],
        }),
      ),
    );
    render(<App memory initialPath="/approvals/AP-content" initialToken={as.md} />);
    expect(await screen.findByText('cd-new')).toBeInTheDocument();
    const marks = screen.getAllByTestId('content-registration');
    expect(marks[0]).toHaveTextContent('새 콘텐츠');
    expect(marks[1]).toHaveTextContent('기존 게시 갱신');
    expect(marks[1]).toHaveTextContent('지금 게시본 v3');
    expect(screen.queryByText('기존 상품 갱신')).not.toBeInTheDocument();
    expect(screen.queryByText(/새 상품/)).not.toBeInTheDocument();
  });
});
