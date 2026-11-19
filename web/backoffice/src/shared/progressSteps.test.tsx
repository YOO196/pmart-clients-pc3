// 진행 단계 막대(2026-11-19 사용자 "주문 완료인데 막대가 끝까지 안 간다") — 닿은 단계로 들어오는 선은 초록
import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';

import { ProgressSteps } from './ProgressSteps';

const STEPS = ['결제', '주문 확정', '상품 준비', '배송 중', '전달 완료'];
/** 단계마다 [왼쪽 반 선, 오른쪽 반 선] 색 — 첫 단계는 왼쪽, 끝 단계는 오른쪽 선이 없다 */
const lines = () =>
  screen.getAllByRole('listitem').map((li) => [...li.querySelectorAll('span[aria-hidden="true"].h-0\\.5')].map((s) => (s.className.includes('bg-success') ? 'green' : 'gray')));

describe('진행 단계 막대', () => {
  it('끝 단계까지 끝났으면(전달 완료) 선이 모두 초록 — 마지막 단계 앞 반쪽도', () => {
    render(<ProgressSteps steps={STEPS} place={{ step: 4, done: true }} label="주문 진행" testId="p" endedTestId="e" />);
    expect(lines().flat().every((c) => c === 'green')).toBe(true);
  });

  it('중간 단계(배송 중)면 그 단계까지 초록, 그 뒤는 회색', () => {
    render(<ProgressSteps steps={STEPS} place={{ step: 3, done: false }} label="주문 진행" testId="p" endedTestId="e" />);
    const l = lines();
    expect(l[3]).toEqual(['green', 'gray']); // 배송 중: 들어오는 선 초록, 나가는 선 회색
    expect(l[4]).toEqual(['gray']); // 전달 완료로 들어오는 선 회색
  });
});
