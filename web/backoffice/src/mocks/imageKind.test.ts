// 목 사진 형식 판정 — 실서버처럼 파일 앞부분으로(2026-11-24 "목업 서버에서는 아무 사진이나 다 올라가는데")
import { describe, expect, it } from 'vitest';

import { imageKindOf } from './support';

const blob = (bytes: number[] | string, type = 'image/png') => new Blob([typeof bytes === 'string' ? bytes : new Uint8Array(bytes)], { type });

describe('imageKindOf', () => {
  it('JPEG·PNG·WEBP 는 앞부분으로 알아본다', async () => {
    expect(await imageKindOf(blob([0xff, 0xd8, 0xff, 0xe0]))).toBe('image/jpeg');
    expect(await imageKindOf(blob([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a]))).toBe('image/png');
    expect(await imageKindOf(blob('RIFF\u0000\u0000\u0000\u0000WEBPVP8 '))).toBe('image/webp');
  });
  it('이름표(MIME)가 image/png 여도 내용이 그림이 아니면 null', async () => {
    expect(await imageKindOf(blob('this is not an image'))).toBeNull();
    expect(await imageKindOf(blob([71, 73, 70, 56]))).toBeNull(); // GIF
  });
});
