import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { describe, expect, it } from 'vitest';

import { API_BASE } from '../../api/client';
import { renderAt } from '../../test/render';
import { server } from '../../test/server';

describe('콘텐츠 등록 — 승인된 상품 고르기', () => {
  it('입력란에 커서를 두면 승인된 상품 목록이 열리고, 검색해서 고르면 상품 ID 가 채워진다', async () => {
    const user = userEvent.setup();
    renderAt('/contents/drafts/new');
    const input = screen.getByRole('combobox', { name: '상품 ID(승인된 상품)' });

    await user.click(input);
    const list = await screen.findByRole('listbox', { name: '승인된 상품' });
    expect(within(list).getAllByRole('option')).toHaveLength(2);

    await user.type(input, '미역');
    expect(within(list).getAllByRole('option')).toHaveLength(1);
    await user.click(within(list).getByRole('option', { name: /소고기 미역국/ }));

    expect(input).toHaveValue('P-00000002');
    expect(screen.queryByRole('listbox')).not.toBeInTheDocument();
  });

  it('키보드로도 고를 수 있다', async () => {
    const user = userEvent.setup();
    renderAt('/contents/drafts/new');
    const input = screen.getByRole('combobox', { name: '상품 ID(승인된 상품)' });

    await user.click(input);
    await screen.findByRole('listbox');
    await user.keyboard('{ArrowDown}{Enter}');

    expect(input).toHaveValue('P-00000002');
  });

  it('목록 조회 실패는 "없음"이 아니라 오류로 보인다', async () => {
    server.use(
      http.get(`${API_BASE}/products`, () =>
        HttpResponse.json({ status: 503, code: 'DEPENDENCY_UNAVAILABLE', retryable: false }, { status: 503 }),
      ),
    );
    const user = userEvent.setup();
    renderAt('/contents/drafts/new');

    await user.click(screen.getByRole('combobox', { name: '상품 ID(승인된 상품)' }));

    expect(await screen.findByRole('alert')).toBeInTheDocument();
    expect(screen.queryByText('찾는 상품이 없어요')).not.toBeInTheDocument();
  });

  it('다 불러오지 않은 상태에서 못 찾으면 없다고 단정하지 않고 더 불러오게 한다', async () => {
    server.use(
      http.get(`${API_BASE}/products`, ({ request }) => {
        const cursor = new URL(request.url).searchParams.get('cursor');
        return HttpResponse.json(
          cursor
            ? { items: [{ productId: 'P-00000099', internalName: '귤 3kg', saleState: 'ON_SALE', version: 1 }], page: { nextCursor: null, size: 1 } }
            : { items: [{ productId: 'P-00000001', internalName: '사과 1.5kg', saleState: 'ON_SALE', version: 1 }], page: { nextCursor: 'c2', size: 1 } },
        );
      }),
    );
    const user = userEvent.setup();
    renderAt('/contents/drafts/new');
    const input = screen.getByRole('combobox', { name: '상품 ID(승인된 상품)' });

    await user.click(input);
    await screen.findByRole('listbox');
    await user.type(input, '귤');
    expect(screen.getByText('불러온 1개 안에는 없어요. 더 불러와서 찾아 보세요')).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: '더 불러오기(지금 1개)' }));
    await user.click(await screen.findByRole('option', { name: /귤 3kg/ }));
    expect(input).toHaveValue('P-00000099');
  });
});
