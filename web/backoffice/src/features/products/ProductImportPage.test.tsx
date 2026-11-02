import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';

import type { ImportBatch, ProductDraft } from '../../api/models';
import { db } from '../../mocks/db';
import { renderAt } from '../../test/render';

describe('상품 일괄 등록', () => {
  it('INVALID 초안의 중량·보관 방식을 배치 화면에서 채워 저장하면 다시 검증돼 VALID 가 된다', async () => {
    const draft: ProductDraft = {
      draftId: 'pd-seed-invalid',
      batchId: 'pib-seed-2',
      sourceSystem: 'bmart-capture',
      sourceKey: 'bm-1',
      state: 'DRAFT',
      input: { product: { internalName: '부사 사과 1kg', primaryCategoryId: 'p01-c01-l01' }, skus: [{ unitType: 'E', unitsPerSku: 1, volumeMl: 1000 }] },
      validationState: 'INVALID',
      problems: [
        { code: 'WEIGHT_REQUIRED', field: 'skus[0].weightG' },
        { code: 'STORAGE_TYPE_REQUIRED', field: 'skus[0].storageType' },
      ],
      draftHash: null,
      approvalId: null,
      resultProductId: null,
      resultSkus: [],
      version: 0,
      updatedAt: '2026-11-02T00:00:00Z',
    };
    db.productDrafts.set(draft.draftId, draft);
    const batch: ImportBatch = {
      batchId: 'pib-seed-2',
      format: 'SEED_V1',
      sourceSystem: 'bmart-capture',
      state: 'VALIDATED',
      productCount: 1,
      validCount: 0,
      invalidCount: 1,
      drafts: [draft],
      createdAt: '2026-11-02T00:00:00Z',
    };
    db.importBatches.set(batch.batchId, batch);
    const user = userEvent.setup();
    const view = renderAt('/products/import/pib-seed-2');

    const fill = await screen.findByLabelText('빠진 값 채우기 부사 사과 1kg');
    expect(within(fill).getByText('용량 1000mL')).toBeInTheDocument();
    // 값을 미리 채우지 않는다
    expect(within(fill).getByLabelText('중량(g)')).toHaveValue('');
    await user.type(within(fill).getByLabelText('중량(g)'), '1000');
    await user.selectOptions(within(fill).getByLabelText('보관 방식'), 'CHILLED');
    await user.click(within(fill).getByRole('button', { name: '저장·재검증' }));

    await waitFor(() => expect(screen.getByText('VALID')).toBeInTheDocument());
    expect(screen.queryByLabelText('빠진 값 채우기 부사 사과 1kg')).not.toBeInTheDocument();
    const put = view.mutations('/product-drafts/pd-seed-invalid')[0]!;
    expect(put.method).toBe('PUT');
    expect(put.headers.get('X-Expected-Version')).toBe('0');
    const body = (await put.json()) as { skus: { weightG?: number; storageType?: string; volumeMl?: number }[] };
    expect(body.skus[0]).toMatchObject({ weightG: 1000, storageType: 'CHILLED', volumeMl: 1000 });
    view.stop();
  });

  it('업로드·검증 뒤 배치 화면에서 바로 다른 파일을 올릴 수 있다(다른 메뉴로 갔다 올 필요 없음)', async () => {
    const batch: ImportBatch = {
      batchId: 'pib-seed-1',
      format: 'SEED_V1',
      sourceSystem: 'bmart-capture',
      state: 'VALIDATED',
      productCount: 0,
      validCount: 0,
      invalidCount: 0,
      drafts: [],
      createdAt: '2026-11-02T00:00:00Z',
    };
    db.importBatches.set(batch.batchId, batch);
    renderAt('/products/import/pib-seed-1');

    expect(await screen.findByRole('heading', { name: '배치 pib-seed-1' })).toBeInTheDocument();
    const another = screen.getByRole('heading', { name: '다른 파일 올리기' }).parentElement!;
    expect(within(another).getByLabelText('seed-v1.zip')).toBeInTheDocument();
    // 파일을 고르기 전에는 올릴 수 없다
    expect(within(another).getByRole('button', { name: '업로드·검증' })).toBeDisabled();
  });
});
