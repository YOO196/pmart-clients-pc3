import { describe, expect, it } from 'vitest';

import { humanizeCodes } from './codeText';

describe('humanizeCodes — 서버 글 속 상태 코드를 화면 말로', () => {
  it('조치 결과·수행료 메모', () => {
    expect(humanizeCodes('DISPATCH_RESTRICTED→NORMAL')).toBe('신규배차 제한 → 정상');
    expect(humanizeCodes('CANCELLED_BEFORE_PICKUP — 실패·취소 수행료 기준 없음(지원센터 조정)')).toBe('픽업 전 취소 — 실패·취소 수행료 기준 없음(지원센터 조정)');
  });
  it('모르는 코드·일반 글은 그대로', () => {
    expect(humanizeCodes('NEW_THING 확인')).toBe('NEW_THING 확인');
    expect(humanizeCodes('LAN 시험(자동)')).toBe('LAN 시험(자동)');
  });
});
