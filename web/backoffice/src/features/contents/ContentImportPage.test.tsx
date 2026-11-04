import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { describe, expect, it } from 'vitest';

import { API_BASE } from '../../api/client';
import { renderAt } from '../../test/render';
import { server } from '../../test/server';

const draft = (id: string, state: string, submittable: boolean, problems: { code: string; field?: string; detail?: string }[] = []) => ({
  draftId: id,
  state,
  version: 1,
  submittable,
  problems,
  input: { name: `이름-${id}` },
  images: [],
});

// 서버가 주는 값만으로 행 사유가 갈린다: 제출 가능 / 게시본과 같음 / 다른 제출로 승인 대기 / 고칠 것 있음
const batch = {
  batchId: 'cib-1',
  format: 'SEED_V1',
  sourceSystem: 'bmart-capture',
  state: 'UPLOADED',
  productCount: 4,
  items: [
    { sourceKey: 'k-ready', draftId: 'cd-ready', outcome: 'CREATED', draft: draft('cd-ready', 'DRAFT', true) },
    { sourceKey: 'k-pub', draftId: 'cd-pub', outcome: 'UNCHANGED', draft: draft('cd-pub', 'PUBLISHED', false) },
    { sourceKey: 'k-lock', draftId: 'cd-lock', outcome: 'LOCKED', draft: draft('cd-lock', 'SUBMITTED', false) },
    {
      sourceKey: 'k-bad',
      draftId: 'cd-bad',
      outcome: 'CREATED',
      draft: draft('cd-bad', 'DRAFT', false, [{ code: 'PRODUCT_NOT_LINKED', field: 'productId', detail: '원천 키로 연결된 상품이 없음' }]),
    },
  ],
};

describe('콘텐츠 일괄 등록 — 행마다 제출 여부·사유', () => {
  it('제출 가능·이미 게시됨·승인 대기·고칠 것(필드·상세 포함)을 구분하고, 제출 뒤 빠진 초안을 사유와 함께 보인다', async () => {
    server.use(
      http.get(`${API_BASE}/content-import-batches/cib-1`, () => HttpResponse.json(batch)),
      http.post(`${API_BASE}/content-import-batches/cib-1/submissions`, () =>
        HttpResponse.json({
          submittedDraftIds: ['cd-ready'],
          excludedDraftIds: ['cd-pub', 'cd-lock', 'cd-bad'],
          approvalRequest: {
            type: 'DISPLAY',
            targetService: 'product-content-service',
            targetRef: 'contentImportBatch:cib-1',
            allowedActions: ['PUBLISH'],
            summary: '콘텐츠 일괄 게시 1건',
          },
        }),
      ),
    );
    const user = userEvent.setup();
    renderAt('/contents/import/cib-1');

    expect(await screen.findByTestId('row-summary')).toHaveTextContent('제출 가능 1 · 이미 게시됨 1 · 승인 대기 1 · 고칠 것 있음 1');
    expect(screen.getByRole('columnheader', { name: '제출 여부·사유' })).toBeInTheDocument();
    const row = (key: string) => screen.getByRole('cell', { name: key }).closest('tr') as HTMLElement;
    expect(row('k-ready')).toHaveTextContent('제출 가능');
    expect(row('k-pub')).toHaveTextContent('이미 게시된 내용과 같아 제출하지 않아요');
    expect(row('k-lock')).toHaveTextContent('다른 제출로 승인 대기 중이라 이번에 바꾸지 않아요');
    expect(row('k-bad')).toHaveTextContent('고쳐야 제출할 수 있어요');
    expect(row('k-bad')).toHaveTextContent('상품 승인 전이에요 (productId) — 원천 키로 연결된 상품이 없음');

    await user.click(screen.getByRole('button', { name: '유효 행 제출 준비' }));
    const excluded = await screen.findByLabelText('제출에서 빠진 초안 3개');
    const lines = within(excluded).getAllByRole('listitem');
    expect(lines).toHaveLength(3);
    expect(lines[0]).toHaveTextContent('cd-pub (k-pub): 이미 게시된 내용과 같아 제출하지 않아요');
    expect(lines[2]).toHaveTextContent('cd-bad (k-bad): 고쳐야 제출할 수 있어요 · 상품 승인 전이에요 (productId) — 원천 키로 연결된 상품이 없음');
  });
});
