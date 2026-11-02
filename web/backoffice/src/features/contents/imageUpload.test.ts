// multipart 본문은 vitest+jsdom 의 fetch 가 보내지 못해(jsdom Blob 을 못 읽음) 가짜 API 객체로 호출만 본다.
import { describe, expect, it, vi } from 'vitest';

import type { Api } from '../../api/client';
import type { ContentImage } from '../../api/models';
import { toPending } from './ImagePicker';
import { uploadPendingImages } from './imageUpload';

const png = (name: string) => new File([new Uint8Array([137, 80, 78, 71])], name, { type: 'image/png' });

function fakeApi(fail: (call: number) => boolean = () => false) {
  let calls = 0;
  const POST = vi.fn(async (_path: string, opts: { params: { header: Record<string, string>; path: { draftId: string } }; body: { role: string; sortOrder: number }; bodySerializer: () => FormData }) => {
    calls += 1;
    if (fail(calls)) {
      return { error: { status: 503, code: 'DEPENDENCY_UNAVAILABLE' }, response: new Response(null, { status: 503 }) };
    }
    const form = opts.bodySerializer();
    const image: ContentImage = {
      imageId: `img-${calls}`,
      role: opts.body.role as ContentImage['role'],
      sortOrder: Number(form.get('sortOrder')),
    };
    return { data: image, response: new Response(null, { status: 201 }) };
  });
  return { api: { content: { POST } } as unknown as Api, POST };
}

describe('초안 이미지 올리기', () => {
  it('한 장씩 올리고, MAIN 은 0, 나머지는 이미 올라간 같은 역할 뒤에 이어 붙인다. 장마다 다른 멱등 키', async () => {
    const { api, POST } = fakeApi();
    const existing: ContentImage[] = [{ imageId: 'img-old', role: 'DESCRIPTION', sortOrder: 0 }];
    const pending = [
      ...toPending([png('main.png')], 'MAIN'),
      ...toPending([png('d1.png'), png('d2.png')], 'DESCRIPTION'),
      ...toPending([png('info.png')], 'DETAIL'),
    ];
    const progress: [number, number][] = [];

    const out = await uploadPendingImages(api, 'cd-1', pending, existing, (d, t) => progress.push([d, t]));

    expect(out.failed).toHaveLength(0);
    expect(out.uploaded.map((i) => [i.role, i.sortOrder])).toEqual([
      ['MAIN', 0],
      ['DESCRIPTION', 1],
      ['DESCRIPTION', 2],
      ['DETAIL', 0],
    ]);
    expect(POST).toHaveBeenCalledTimes(4);
    expect(POST.mock.calls.every(([path]) => path === '/content-drafts/{draftId}/images')).toBe(true);
    expect(POST.mock.calls.every(([, o]) => o.params.path.draftId === 'cd-1')).toBe(true);
    const keys = POST.mock.calls.map(([, o]) => o.params.header['Idempotency-Key']);
    expect(new Set(keys).size).toBe(4);
    // multipart 본문에 file·role·sortOrder 가 들어간다.
    const form = POST.mock.calls[1]![1].bodySerializer();
    expect((form.get('file') as File).name).toBe('d1.png');
    expect(form.get('role')).toBe('DESCRIPTION');
    expect(form.get('sortOrder')).toBe('1');
    expect(progress).toEqual([
      [0, 4],
      [1, 4],
      [2, 4],
      [3, 4],
      [4, 4],
    ]);
  });

  it('한 장이 실패해도 나머지는 계속 올리고, 실패한 장과 사유를 돌려준다', async () => {
    const { api } = fakeApi((call) => call === 2);
    const pending = [...toPending([png('main.png')], 'MAIN'), ...toPending([png('d1.png'), png('d2.png')], 'DESCRIPTION')];

    const out = await uploadPendingImages(api, 'cd-1', pending, []);

    expect(out.uploaded.map((i) => [i.role, i.sortOrder])).toEqual([
      ['MAIN', 0],
      ['DESCRIPTION', 1],
    ]);
    expect(out.failed.map((f) => f.image.file.name)).toEqual(['d1.png']);
    // 변경 요청의 5xx 는 실패 확정이 아니라 결과 불명이다(요청 규칙). 화면은 "다시 고르면 된다"로 안내한다.
    expect(out.failed[0]!.failure.message).toBe('UNKNOWN_RESULT');
  });
});
