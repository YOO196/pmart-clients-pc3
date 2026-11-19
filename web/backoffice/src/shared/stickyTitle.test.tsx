// 상세 제목 띠(2026-11-19) — 제목 카드가 위로 지나가면 띠, 돌아오면 사라짐. 단추는 띠에 복제하지 않는다
import { act, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { DetailHeader } from './admin';
import { DETAIL_BAR_SLOT } from './StickyTitle';

type Cb = (entries: Array<Partial<IntersectionObserverEntry>>) => void;
let fire: Cb = () => undefined;
afterEach(() => vi.unstubAllGlobals());

describe('상세 제목 띠', () => {
  it('카드가 화면 위로 나가면 제목·배지 띠, 다시 보이면 사라진다', () => {
    vi.stubGlobal(
      'IntersectionObserver',
      class {
        constructor(cb: Cb) {
          fire = cb;
        }
        observe() {}
        disconnect() {}
      },
    );
    render(
      <MemoryRouter>
        <div id={DETAIL_BAR_SLOT} />
        <DetailHeader back={{ to: '/cases', label: '목록' }} title="C-1119-0001" badges={<span>처리 중</span>} actions={<button type="button">맡기</button>} />
      </MemoryRouter>,
    );
    expect(screen.queryByTestId('sticky-title')).not.toBeInTheDocument();
    act(() => fire([{ isIntersecting: false, boundingClientRect: { top: -120 } as DOMRectReadOnly }]));
    const bar = screen.getByTestId('sticky-title');
    expect(within(bar).getByText('C-1119-0001')).toBeInTheDocument();
    expect(within(bar).getByText('처리 중')).toBeInTheDocument();
    expect(within(bar).queryByRole('button', { name: '맡기' })).not.toBeInTheDocument(); // 명령 단추는 복제하지 않는다
    expect(screen.getAllByRole('button', { name: '맡기' })).toHaveLength(1);
    act(() => fire([{ isIntersecting: true, boundingClientRect: { top: 10 } as DOMRectReadOnly }]));
    expect(screen.queryByTestId('sticky-title')).not.toBeInTheDocument();
  });

  it('아래쪽으로 벗어난 것(아직 안 내려옴)은 띠가 아니다', () => {
    vi.stubGlobal(
      'IntersectionObserver',
      class {
        constructor(cb: Cb) {
          fire = cb;
        }
        observe() {}
        disconnect() {}
      },
    );
    render(
      <MemoryRouter>
        <div id={DETAIL_BAR_SLOT} />
        <DetailHeader back={{ to: '/', label: '목록' }} title="T" />
      </MemoryRouter>,
    );
    act(() => fire([{ isIntersecting: false, boundingClientRect: { top: 900 } as DOMRectReadOnly }]));
    expect(screen.queryByTestId('sticky-title')).not.toBeInTheDocument();
  });
});
