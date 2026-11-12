// 초안 이미지 올리기(`POST /content-drafts/{draftId}/images`, multipart). 한 장씩, 장마다 새 멱등 키.
// sortOrder: MAIN 은 0(다시 올리면 바꾼다), 그 밖은 이미 올라간 같은 역할 뒤에 이어 붙인다.
import type { Api } from '../../api/client';
import { commandParams, IdempotencyKey } from '../../api/command';
import { PmartFailure } from '@pmart/web-core';
import type { ContentImage } from '../../api/models';
import { request } from '@pmart/web-core';
import { multipart } from '../products/ProductImportPage';
import type { PendingImage } from './ImagePicker';

export interface UploadOutcome {
  readonly uploaded: readonly ContentImage[];
  readonly failed: readonly { readonly image: PendingImage; readonly failure: PmartFailure }[];
}

export async function uploadPendingImages(
  api: Api,
  draftId: string,
  pending: readonly PendingImage[],
  existing: readonly ContentImage[],
  onProgress?: (done: number, total: number) => void,
): Promise<UploadOutcome> {
  const nextOrder: Record<string, number> = {};
  for (const img of existing) {
    nextOrder[img.role] = Math.max(nextOrder[img.role] ?? 0, img.sortOrder + 1);
  }
  const uploaded: ContentImage[] = [];
  const failed: { image: PendingImage; failure: PmartFailure }[] = [];
  let done = 0;
  onProgress?.(done, pending.length);
  for (const p of pending) {
    const sortOrder = p.role === 'MAIN' ? 0 : (nextOrder[p.role] ?? 0);
    if (p.role !== 'MAIN') nextOrder[p.role] = sortOrder + 1;
    const key = IdempotencyKey.generate();
    try {
      const img = await request(
        'POST',
        api.content.POST('/content-drafts/{draftId}/images', {
          ...commandParams(key, { path: { draftId } }),
          body: { file: '', role: p.role, sortOrder },
          ...multipart({ file: p.file, role: p.role, sortOrder: String(sortOrder) }),
        }),
      );
      uploaded.push(img);
    } catch (e) {
      // 한 장이 실패해도 나머지는 계속 올린다. 실패한 장은 초안 화면에서 다시 고른다.
      failed.push({ image: p, failure: e instanceof PmartFailure ? e : new PmartFailure(String(e)) });
    }
    done += 1;
    onProgress?.(done, pending.length);
  }
  return { uploaded, failed };
}
