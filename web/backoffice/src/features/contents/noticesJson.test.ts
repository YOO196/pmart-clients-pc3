import { describe, expect, it } from 'vitest';

import { NoticesJsonError, parseNoticesJson } from './noticesJson';

describe('고시 정보 JSON', () => {
  it('seed-v1 product.json 의 content.notices 와 콘텐츠 필드를 읽는다', () => {
    const r = parseNoticesJson(
      JSON.stringify({
        product: { seedProductId: 'bm-1' },
        content: {
          name: '서울우유 1L',
          description: 'OCR 초안',
          storageGuide: '냉장 보관',
          returnGuide: null,
          notices: ['식품의 유형: 우유', '원산지: 국산'],
        },
      }),
    );
    expect(r.notices).toEqual(['식품의 유형: 우유', '원산지: 국산']);
    expect(r.fields).toEqual({ name: '서울우유 1L', description: 'OCR 초안', storageGuide: '냉장 보관' });
  });

  it('문자열 배열·{label,value} 배열·객체를 모두 "항목: 값"으로 만든다', () => {
    expect(parseNoticesJson('["식품의 유형: 우유", " 원산지: 국산 ", ""]').notices).toEqual(['식품의 유형: 우유', '원산지: 국산']);
    expect(
      parseNoticesJson(JSON.stringify([{ label: '식품의 유형', value: '우유' }, { label: '용량', value: 1000 }])).notices,
    ).toEqual(['식품의 유형: 우유', '용량: 1000']);
    expect(parseNoticesJson(JSON.stringify({ '식품의 유형': '우유', 원산지: '국산' })).notices).toEqual([
      '식품의 유형: 우유',
      '원산지: 국산',
    ]);
    expect(parseNoticesJson(JSON.stringify({ notices: { 원산지: '국산' } })).notices).toEqual(['원산지: 국산']);
  });

  it('JSON 이 아니거나 항목이 없거나 500자를 넘으면 오류다', () => {
    expect(() => parseNoticesJson('not json')).toThrow(NoticesJsonError);
    expect(() => parseNoticesJson('[]')).toThrow(NoticesJsonError);
    expect(() => parseNoticesJson('{"notices": 3}')).toThrow(NoticesJsonError);
    expect(() => parseNoticesJson(JSON.stringify([`원산지: ${'가'.repeat(500)}`]))).toThrow(NoticesJsonError);
    expect(() => parseNoticesJson('[1]')).toThrow(NoticesJsonError);
  });
});
