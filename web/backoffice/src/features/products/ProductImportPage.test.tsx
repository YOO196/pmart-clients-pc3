import { screen, within } from '@testing-library/react';
import { describe, expect, it } from 'vitest';

import type { ImportBatch } from '../../api/models';
import { db } from '../../mocks/db';
import { renderAt } from '../../test/render';

describe('상품 일괄 등록', () => {
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
