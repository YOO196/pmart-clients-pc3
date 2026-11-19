// 움직임 효과 공통(2026-11-19 "다 넣어") — 처음 값·처음 목록은 바뀜이 아니고, 바뀐 것만 잠깐
import { act, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { StatCard } from './admin';
import { numberOf, useNewIds } from './motion';

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

describe('숫자 칸 바뀜', () => {
  it('처음 값은 표시 없음, 늘면 ▲ 와 빛남, 4초 뒤 사라짐', () => {
    const { rerender } = render(<StatCard label="미처리" value="3" testId="c" />);
    expect(screen.queryByTestId('stat-delta')).not.toBeInTheDocument();
    expect(screen.getByTestId('c')).not.toHaveClass('stat-changed');
    rerender(<StatCard label="미처리" value="5" testId="c" />);
    expect(screen.getByTestId('stat-delta')).toHaveTextContent('▲2');
    expect(screen.getByTestId('c')).toHaveClass('stat-changed');
    act(() => {
      vi.advanceTimersByTime(4_100);
    });
    expect(screen.queryByTestId('stat-delta')).not.toBeInTheDocument();
  });

  it('못 읽음(?)·읽는 중(…)은 바뀜으로 치지 않는다', () => {
    const { rerender } = render(<StatCard label="미처리" value="3" testId="c" />);
    rerender(<StatCard label="미처리" value="?" testId="c" />);
    expect(screen.queryByTestId('stat-delta')).not.toBeInTheDocument();
    expect(numberOf('50+')).toBe(50);
    expect(numberOf('1,234')).toBe(1234);
    expect(numberOf('…')).toBeUndefined();
  });
});

function Rows({ ids, scope }: { readonly ids: readonly string[] | undefined; readonly scope: string }) {
  const fresh = useNewIds(ids, scope);
  return <p data-testid="fresh">{[...fresh].join(',')}</p>;
}

describe('새로 들어온 줄', () => {
  it('처음 목록은 새것이 아니고, 다음에 들어온 것만 5초 동안', () => {
    const { rerender } = render(<Rows ids={['a', 'b']} scope="t1" />);
    expect(screen.getByTestId('fresh')).toHaveTextContent('');
    rerender(<Rows ids={['c', 'a', 'b']} scope="t1" />);
    expect(screen.getByTestId('fresh')).toHaveTextContent('c');
    act(() => {
      vi.advanceTimersByTime(5_100);
    });
    expect(screen.getByTestId('fresh')).toHaveTextContent('');
  });

  it('탭·거르기가 바뀌면 다시 센다(줄이 다 "새로"가 되지 않는다)', () => {
    const { rerender } = render(<Rows ids={['a']} scope="t1" />);
    rerender(<Rows ids={['x', 'y']} scope="t2" />);
    expect(screen.getByTestId('fresh')).toHaveTextContent('');
  });
});
